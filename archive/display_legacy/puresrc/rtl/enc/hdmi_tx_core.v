// -----------------------------------------------------------------------------
// HDMI 1.4a transmitter core (640x480p60, 8-bit RGB).
//
// Generates the three TMDS channels including control periods, video guard
// bands/preambles, data islands and the data island guard bands.  Packet
// scheduling is handled by packet_picker; ECC and the 9-bit data island stream
// by hdmi_packet_assembler.
//
// DVI_MODE=1 emits a pure DVI signal (no data islands, no audio).
// AUDIO_EN=0 keeps data islands (AVI InfoFrame) but never sends audio.
// -----------------------------------------------------------------------------
module hdmi_tx_core #(
    parameter integer AUDIO_EN   = 1,
    parameter integer DVI_MODE   = 0,
    parameter integer AUDIO_FS   = 48000,
    parameter integer IT_CONTENT = 1
) (
    input  wire        clk_pixel,
    input  wire        clk_pixel_x5,
    input  wire        reset,
    input  wire [9:0]  hcnt,
    input  wire [9:0]  vcnt,
    input  wire [23:0] rgb,
    input  wire        hs,
    input  wire        vs,
    input  wire [31:0] audio_sample,
    input  wire [7:0]  audio_vol,
    input  wire        audio_empty,
    input  wire        audio_overflow,
    output wire        audio_pop,
    output wire [1:0]  audio_status,
    output wire        audio_pkt,      // high while an Audio Sample Packet is sent
    output wire        HDMI_CLK_P,
    output wire        HDMI_D0_P,
    output wire        HDMI_D1_P,
    output wire        HDMI_D2_P
);

    localparam integer H_ACTIVE = 640;
    localparam integer V_ACTIVE = 480;
    localparam integer V_LAST   = 524;

    // ---------------------------------------------------------- timing flags
    wire in_active = (hcnt < H_ACTIVE) && (vcnt < V_ACTIVE);
    // Video guard bands/preambles are only emitted on lines that really carry
    // video (not on the last active line nor inside the vertical blanking).
    wire video_period_line = (vcnt < 479) || (vcnt == V_LAST);

    wire video_guard_now = (hcnt >= 798) && video_period_line;
    wire video_pre_now   = (hcnt >= 790) && (hcnt < 798) && video_period_line;
    wire island_now      = (hcnt >= 654) && (hcnt < 782);
    wire island_guard_now = ((hcnt >= 652) && (hcnt < 654)) ||
                            ((hcnt >= 782) && (hcnt < 784));
    wire island_pre_now  = (hcnt >= 644) && (hcnt < 652);

    wire frame_start = (hcnt == 799) && (vcnt == V_LAST);
    wire slot_pulse  = (hcnt == 653) || (hcnt == 685) ||
                       (hcnt == 717) || (hcnt == 749);

    // ------------------------------------------------------------ packet path
    wire [23:0] pkt_header;
    wire [55:0] pkt_sub0, pkt_sub1, pkt_sub2, pkt_sub3;
    wire [7:0]  pkt_type;
    wire [8:0]  pkt_data;

    assign audio_pkt = island_now && (pkt_type == 8'h02);

    packet_picker #(
        .AUDIO_FS  (AUDIO_FS),
        .AUDIO_EN  (AUDIO_EN),
        .IT_CONTENT(IT_CONTENT)
    ) u_picker (
        .clk           (clk_pixel),
        .reset         (reset),
        .frame_start   (frame_start),
        .slot_pulse    (slot_pulse),
        .audio_sample  (audio_sample),
        .audio_vol     (audio_vol),
        .audio_empty   (audio_empty),
        .audio_overflow(audio_overflow),
        .audio_pop     (audio_pop),
        .header        (pkt_header),
        .sub0          (pkt_sub0),
        .sub1          (pkt_sub1),
        .sub2          (pkt_sub2),
        .sub3          (pkt_sub3),
        .packet_type   (pkt_type),
        .audio_status  (audio_status)
    );

    hdmi_packet_assembler u_assembler (
        .clk         (clk_pixel),
        .reset       (reset),
        .in_island   (island_now),
        .slot_start  (slot_pulse),
        .header      (pkt_header),
        .sub0        (pkt_sub0),
        .sub1        (pkt_sub1),
        .sub2        (pkt_sub2),
        .sub3        (pkt_sub3),
        .packet_data (pkt_data)
    );

    // ------------------------------------------------------- stage 1 pipeline
    reg [2:0]  mode_r;
    reg [23:0] video_r;
    reg [5:0]  control_r;
    reg [11:0] island_r;

    always @(posedge clk_pixel or posedge reset) begin
        if (reset) begin
            mode_r    <= 3'd0;
            video_r   <= 24'd0;
            control_r <= 6'd0;
            island_r  <= 12'd0;
        end else begin
            video_r <= rgb;

            if (DVI_MODE != 0) begin
                mode_r    <= in_active ? 3'd1 : 3'd0;
                control_r <= {4'b0000, vs, hs};
                island_r  <= 12'd0;
            end else begin
                mode_r <= island_guard_now ? 3'd4 :
                          island_now       ? 3'd3 :
                          video_guard_now  ? 3'd2 :
                          in_active        ? 3'd1 : 3'd0;

                control_r <= {1'b0, island_pre_now, 1'b0,
                              (video_pre_now | island_pre_now), vs, hs};

                // 12 bits = channel2[11:8], channel1[7:4], channel0[3:0]
                island_r <= {pkt_data[8:5], pkt_data[4:1],
                             1'b1, pkt_data[0], vs, hs};
            end
        end
    end

    // ------------------------------------------------------------- TMDS code
    wire [9:0] tmds0, tmds1, tmds2;

    tmds_encoder #(.CHANNEL(0)) u_enc0 (
        .clk(clk_pixel), .reset(reset),
        .video_data(video_r[7:0]),
        .island_data(island_r[3:0]),
        .control_data(control_r[1:0]),
        .mode(mode_r), .tmds(tmds0));

    tmds_encoder #(.CHANNEL(1)) u_enc1 (
        .clk(clk_pixel), .reset(reset),
        .video_data(video_r[15:8]),
        .island_data(island_r[7:4]),
        .control_data(control_r[3:2]),
        .mode(mode_r), .tmds(tmds1));

    tmds_encoder #(.CHANNEL(2)) u_enc2 (
        .clk(clk_pixel), .reset(reset),
        .video_data(video_r[23:16]),
        .island_data(island_r[11:8]),
        .control_data(control_r[5:4]),
        .mode(mode_r), .tmds(tmds2));

    tmds_serializer u_serializer (
        .clk_pixel(clk_pixel),
        .clk_pixel_x5(clk_pixel_x5),
        .reset(reset),
        .tmds0(tmds0),
        .tmds1(tmds1),
        .tmds2(tmds2),
        .HDMI_CLK_P(HDMI_CLK_P),
        .HDMI_D0_P(HDMI_D0_P),
        .HDMI_D1_P(HDMI_D1_P),
        .HDMI_D2_P(HDMI_D2_P)
    );

endmodule
