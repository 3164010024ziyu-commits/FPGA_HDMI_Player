// -----------------------------------------------------------------------------
// HDMI auxiliary packet generator / scheduler.
//
// Produces the 24-bit packet header and four 56-bit subpackets for:
//   0x01 Audio Clock Regeneration
//   0x02 Audio Sample (LPCM, 16-bit, 2 channels)
//   0x82 AVI InfoFrame (RGB, IT content, VIC 1 = 640x480p)
//   0x84 Audio InfoFrame (2 channels, refer to stream header)
//   0x00 Null
//
// Packet layouts follow HDMI 1.4a sections 5.3.3, 5.3.4, 8.2.1, 8.2.2 and were
// cross-checked against hdl-util/hdmi (MIT OR Apache-2.0).
// -----------------------------------------------------------------------------
module packet_picker #(
    parameter integer AUDIO_FS  = 48000,   // 44100 or 48000
    parameter integer AUDIO_EN  = 1,
    parameter integer IT_CONTENT = 1
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        frame_start,      // one-cycle pulse at vcnt==0,hcnt==0
    input  wire        slot_pulse,       // pulse at each 32-clock packet slot
    input  wire [31:0] audio_sample,     // {L[15:0], R[15:0]}, pixel clock domain
    input  wire [7:0]  audio_vol,        // 0..255 linear volume (255 ~= 0 dB)
    input  wire        audio_empty,      // fifo empty, pixel clock domain
    input  wire        audio_overflow,   // fifo overflow, pixel clock domain
    output reg         audio_pop,        // pop one sample from the fifo
    output reg  [23:0] header,
    output reg  [55:0] sub0,
    output reg  [55:0] sub1,
    output reg  [55:0] sub2,
    output reg  [55:0] sub3,
    output reg  [7:0]  packet_type,
    output reg  [1:0]  audio_status     // {overflow, underflow}
);

    localparam [19:0] N_ACR        = (AUDIO_FS == 44100) ? 20'd6272 : 20'd6144;
    localparam integer ACR_SAMPLES = (AUDIO_FS == 44100) ? 49 : 48;
    localparam [3:0]  FS_CODE      = (AUDIO_FS == 44100) ? 4'b0000 : 4'b0010;

    // ---------------------------------------------------------------- audio
    reg [31:0] samp0, samp1, samp2, samp3;
    reg [2:0]  samp_cnt;
    reg [7:0]  frame_counter;           // IEC60958 frame, 0..191
    reg [19:0] pix_count;               // pixel clocks since last ACR packet
    reg [19:0] acr_cts;
    reg [23:0] cts_acc;                 // sum of 8 measured ACR periods
    reg [2:0]  cts_win;
    reg        cts_init;
    reg [31:0] acr_acc;                 // samples since last ACR
    reg        acr_due;

    wire sample_ready  = (samp_cnt == 3'd4);
    wire use_audio_now = slot_pulse && (AUDIO_EN != 0) && !acr_due && sample_ready;
    wire use_acr_now   = slot_pulse && (AUDIO_EN != 0) && acr_due;

    // IEC 60958 consumer channel status, 192 bits, LSB transmitted first.
    // 16-bit word length code = 4'b0010, channel 1 = left, channel 2 = right.
    localparam [191:0] CS_L = {152'd0, 4'b0000, 4'b0010, 2'b00, 2'b00,
                               FS_CODE, 4'd1, 4'd0, 8'd0, 2'b00, 3'b000,
                               1'b1, 1'b0, 1'b0};
    localparam [191:0] CS_R = {152'd0, 4'b0000, 4'b0010, 2'b00, 2'b00,
                               FS_CODE, 4'd2, 4'd0, 8'd0, 2'b00, 3'b000,
                               1'b1, 1'b0, 1'b0};

    // InfoFrame subpackets are transmitted PB0 (LSB) .. PB6 (MSB).
    // AVI VIC 1 = 640x480p: PB0..PB6 = E6 00 08 80 01 00 00
    localparam [55:0] AVI_S0 = {8'h00, 8'h00, 8'h01, 8'h80, 8'h08, 8'h00, 8'hE6};
    // Audio: PB0..PB6 = 70 01 00 00 00 00 00
    localparam [55:0] AIF_S0 = {8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h01, 8'h70};
    // Source Product Description InfoFrame (0x83, length 25)
    // vendor "Anlogic", product "FPGA Player", PB0 checksum = 0xFB
    localparam [55:0] SPD_S0 = {8'h69, 8'h67, 8'h6F, 8'h6C, 8'h6E, 8'h41, 8'hFB};
    localparam [55:0] SPD_S1 = {8'h20, 8'h41, 8'h47, 8'h50, 8'h46, 8'h00, 8'h63};
    localparam [55:0] SPD_S2 = {8'h00, 8'h72, 8'h65, 8'h79, 8'h61, 8'h6C, 8'h50};
    localparam [55:0] SPD_S3 = 56'd0;

    // Volume: sample * vol / 256 (255 ~= 0 dB, 0 = mute).
    wire signed [15:0] l_in = audio_sample[31:16];
    wire signed [15:0] r_in = audio_sample[15:0];
    wire signed [23:0] l_mul = l_in * $signed({1'b0, audio_vol});
    wire signed [23:0] r_mul = r_in * $signed({1'b0, audio_vol});
    wire [31:0] audio_scaled = {l_mul[23:8], r_mul[23:8]};

    reg avi_sent, aif_sent, spd_sent;

    // -------------------------------------------------------- sample staging
    always @(posedge clk) begin
        if (reset) begin
            samp_cnt <= 3'd0;
            samp0 <= 32'd0; samp1 <= 32'd0; samp2 <= 32'd0; samp3 <= 32'd0;
        end else if (use_audio_now) begin
            samp_cnt <= 3'd0;
        end else if (!audio_empty && samp_cnt < 3'd4) begin
            case (samp_cnt)
                3'd0: samp0 <= audio_scaled;
                3'd1: samp1 <= audio_scaled;
                3'd2: samp2 <= audio_scaled;
                default: samp3 <= audio_scaled;
            endcase
            samp_cnt <= samp_cnt + 3'd1;
        end
    end

    always @* begin
        audio_pop = (AUDIO_EN != 0) && !audio_empty && (samp_cnt < 3'd4);
    end

    // ------------------------------------------------- ACR + frame counter
    always @(posedge clk) begin
        if (reset) begin
            pix_count     <= 20'd0;
            acr_cts       <= 20'd0;
            cts_acc       <= 24'd0;
            cts_win       <= 3'd0;
            cts_init      <= 1'b0;
            acr_acc       <= 32'd0;
            acr_due       <= 1'b0;
            frame_counter <= 8'd0;
        end else begin
            pix_count <= pix_count + 20'd1;

            if (use_acr_now) begin
                acr_due <= 1'b0;
            end

            if (use_audio_now) begin
                // IEC 60958 channel-status block is exactly 192 frames.  The
                // counter must wrap at 192 (not at the 8-bit 256 boundary),
                // otherwise CS_L/CS_R[fc] is read out of range and the block
                // start flag is asserted every 256 frames.
                frame_counter <= (frame_counter == 8'd188) ? 8'd0
                                                           : frame_counter + 8'd4;
                if (acr_acc + 32'd4 >= ACR_SAMPLES) begin
                    acr_acc <= acr_acc + 32'd4 - ACR_SAMPLES;
                    acr_due <= 1'b1;
                    // The ACR packet can only leave at a data island slot, so
                    // a single measured interval is quantised by the packet
                    // scheduler (several hundred pixels).  Average eight
                    // intervals before publishing CTS to keep the recovered
                    // audio clock steady while still tracking slow drift.
                    if (!cts_init) begin
                        acr_cts  <= pix_count;
                        cts_init <= 1'b1;
                        cts_acc  <= 24'd0;
                        cts_win  <= 3'd0;
                    end else if (cts_win == 3'd7) begin
                        acr_cts <= (cts_acc + {4'd0, pix_count}) >> 3;
                        cts_acc <= 24'd0;
                        cts_win <= 3'd0;
                    end else begin
                        cts_acc <= cts_acc + {4'd0, pix_count};
                        cts_win <= cts_win + 3'd1;
                    end
                    pix_count <= 20'd0;
                end else begin
                    acr_acc <= acr_acc + 32'd4;
                end
            end
        end
    end

    // -------------------------------------------------------------- status
    always @(posedge clk) begin
        if (reset)
            audio_status <= 2'b00;
        else begin
            if (audio_overflow)
                audio_status[1] <= 1'b1;
            if (slot_pulse && (AUDIO_EN != 0) && !sample_ready && audio_empty)
                audio_status[0] <= 1'b1;
        end
    end

    // ------------------------------------------------------- packet payloads
    wire [7:0] fc0 = frame_counter;
    wire [7:0] fc1 = frame_counter + 8'd1;
    wire [7:0] fc2 = frame_counter + 8'd2;
    wire [7:0] fc3 = frame_counter + 8'd3;

    // audio_sample = {L[15:0], R[15:0]}; HDMI puts the left sample in
    // subpacket bits [23:0] and the right sample in bits [47:24].
    // Payload registers capture these staged samples on use_audio_now. An
    // extra pkt register here would transmit the preceding group of four.
    wire [23:0] l0 = {samp0[31:16], 8'h00};
    wire [23:0] r0 = {samp0[15:0],  8'h00};
    wire [23:0] l1 = {samp1[31:16], 8'h00};
    wire [23:0] r1 = {samp1[15:0],  8'h00};
    wire [23:0] l2 = {samp2[31:16], 8'h00};
    wire [23:0] r2 = {samp2[15:0],  8'h00};
    wire [23:0] l3 = {samp3[31:16], 8'h00};
    wire [23:0] r3 = {samp3[15:0],  8'h00};

    wire pl0 = ^{CS_L[fc0], l0};
    wire pr0 = ^{CS_R[fc0], r0};
    wire pl1 = ^{CS_L[fc1], l1};
    wire pr1 = ^{CS_R[fc1], r1};
    wire pl2 = ^{CS_L[fc2], l2};
    wire pr2 = ^{CS_R[fc2], r2};
    wire pl3 = ^{CS_L[fc3], l3};
    wire pr3 = ^{CS_R[fc3], r3};

    // HB2[7:4] = block-start flags, HB1[3:0] = sample-present flags
    wire [23:0] audio_header = {(fc3 == 8'd0), (fc2 == 8'd0), (fc1 == 8'd0),
                                (fc0 == 8'd0), 4'b0000, 3'b000, 1'b0, 4'b1111,
                                8'h02};

    wire [55:0] audio_s0 = {pr0, CS_R[fc0], 2'b00, pl0, CS_L[fc0], 2'b00, r0, l0};
    wire [55:0] audio_s1 = {pr1, CS_R[fc1], 2'b00, pl1, CS_L[fc1], 2'b00, r1, l1};
    wire [55:0] audio_s2 = {pr2, CS_R[fc2], 2'b00, pl2, CS_L[fc2], 2'b00, r2, l2};
    wire [55:0] audio_s3 = {pr3, CS_R[fc3], 2'b00, pl3, CS_L[fc3], 2'b00, r3, l3};

    wire [55:0] acr_sub = {N_ACR[7:0], N_ACR[15:8], 4'h0, N_ACR[19:16],
                           acr_cts[7:0], acr_cts[15:8], 4'h0, acr_cts[19:16],
                           8'h00};

    always @(posedge clk) begin
        if (reset) begin
            header      <= 24'h000000;
            sub0        <= 56'd0;
            sub1        <= 56'd0;
            sub2        <= 56'd0;
            sub3        <= 56'd0;
            packet_type <= 8'h00;
            avi_sent    <= 1'b0;
            aif_sent    <= 1'b0;
            spd_sent    <= 1'b0;
        end else begin
            if (frame_start) begin
                avi_sent <= 1'b0;
                aif_sent <= 1'b0;
                spd_sent <= 1'b0;
            end

            // The data-island scheduler must run even when audio is disabled:
            // AUDIO_EN only suppresses ACR/Audio Sample packets.  AVI/AIF/SPD
            // InfoFrames are still required for the sink to identify the
            // 640x480p RGB stream (without AVI many sinks stay blank).
            if (slot_pulse) begin
                if (acr_due) begin
                    header      <= {8'h00, 8'h00, 8'h01};
                    sub0        <= acr_sub;
                    sub1        <= acr_sub;
                    sub2        <= acr_sub;
                    sub3        <= acr_sub;
                    packet_type <= 8'h01;
                end else if (sample_ready) begin
                    header      <= audio_header;
                    sub0        <= audio_s0;
                    sub1        <= audio_s1;
                    sub2        <= audio_s2;
                    sub3        <= audio_s3;
                    packet_type <= 8'h02;
                end else if (!avi_sent) begin
                    header      <= {8'h0D, 8'h02, 8'h82};
                    sub0        <= AVI_S0;
                    sub1        <= 56'd0;
                    sub2        <= 56'd0;
                    sub3        <= 56'd0;
                    packet_type <= 8'h82;
                    avi_sent    <= 1'b1;
                end else if (!aif_sent) begin
                    header      <= {8'h0A, 8'h01, 8'h84};
                    sub0        <= AIF_S0;
                    sub1        <= 56'd0;
                    sub2        <= 56'd0;
                    sub3        <= 56'd0;
                    packet_type <= 8'h84;
                    aif_sent    <= 1'b1;
                end else if (!spd_sent) begin
                    header      <= {8'h19, 8'h01, 8'h83};
                    sub0        <= SPD_S0;
                    sub1        <= SPD_S1;
                    sub2        <= SPD_S2;
                    sub3        <= SPD_S3;
                    packet_type <= 8'h83;
                    spd_sent    <= 1'b1;
                end else begin
                    header      <= 24'h000000;
                    sub0        <= 56'd0;
                    sub1        <= 56'd0;
                    sub2        <= 56'd0;
                    sub3        <= 56'd0;
                    packet_type <= 8'h00;
                end
            end
        end
    end

endmodule
