// -----------------------------------------------------------------------------
// Hardware bring-up top for the display block:
//   * 640x480 colour gradient with an audio activity indicator
//   * 1 kHz L/R sine test tone at AUDIO_FS
//   * one Chinese subtitle slot + a fixed-position timestamp slot
// -----------------------------------------------------------------------------
module hdmi_demo_top #(
    parameter integer AUDIO_FS    = 48000,
    parameter integer AUDIO_EN    = 1,
    parameter integer SUBTITLE_EN = 1
) (
    input  wire sys_clk,
    input  wire sys_rst_n,
    output wire HDMI_CLK_P,
    output wire HDMI_D2_P,
    output wire HDMI_D1_P,
    output wire HDMI_D0_P
);

    localparam integer SYS_HZ   = 50_000_000;
    localparam integer PHASE_INC = (67_108_864 * 1000) / AUDIO_FS;

    wire        pix_clk, pix_req, frame_sync;
    wire [23:0] src_rgb;
    wire        src_valid;

    wire [31:0] audio_sample;
    wire        audio_valid, audio_ready;
    wire [1:0]  audio_status;
    wire        audio_pkt;

    wire [1:0]  osd_en;
    wire        osd_slot;
    wire [3:0]  osd_char_idx;
    wire [15:0] osd_char_code;
    wire        osd_char_we;

    // ------------------------------------------------------- video pattern
    reg [9:0]  sh;
    reg [9:0]  sv;

    always @(posedge pix_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            sh <= 10'd0;
            sv <= 10'd0;
        end else if (sh == 10'd799) begin
            sh <= 10'd0;
            sv <= (sv == 10'd524) ? 10'd0 : sv + 10'd1;
        end else begin
            sh <= sh + 10'd1;
        end
    end

    wire [7:0] grad_r = sh[6:0] + sv[6:0];
    wire [7:0] grad_g = sh[6:0];
    wire [7:0] grad_b = sv[6:0];

    // ---------------------------------------------------- audio activity LED
    // Top-right 32x32 square:
    //   blinking green = Audio Sample Packets are being transmitted
    //   red            = no audio packet for ~200 ms
    reg [23:0] audio_timeout;
    reg [23:0] blink_cnt;

    always @(posedge pix_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            audio_timeout <= 24'd0;
            blink_cnt     <= 24'd0;
        end else begin
            if (audio_pkt)
                audio_timeout <= 24'd0;
            else if (audio_timeout < 24'd6_000_000)
                audio_timeout <= audio_timeout + 24'd1;
            blink_cnt <= blink_cnt + 24'd1;
        end
    end

    wire audio_ok = (audio_timeout < 24'd5_000_000);   // ~200 ms at 25.175 MHz
    wire blink    = blink_cnt[23];                     // ~0.67 s period
    wire indicator = (sh >= 10'd600) && (sh < 10'd632) &&
                     (sv >= 10'd8)   && (sv < 10'd40);
    wire [23:0] indicator_color = audio_ok
                                  ? (blink ? 24'h00FF00 : 24'h004000)
                                  : 24'hFF0000;

    assign src_rgb   = indicator ? indicator_color : {grad_r, grad_g, grad_b};
    assign src_valid = (sh < 10'd640) && (sv < 10'd480);

    // -------------------------------------------------------- 1 kHz sine
    reg [25:0] phase;
    reg [31:0] fs_acc;
    reg        audio_valid_r;
    reg [15:0] sample_r;

    function [15:0] sine64;
        input [5:0] i;
        begin
            case (i)
                6'd0:  sine64 = 16'h0000;
                6'd1:  sine64 = 16'h0498;
                6'd2:  sine64 = 16'h0925;
                6'd3:  sine64 = 16'h0D9B;
                6'd4:  sine64 = 16'h11F0;
                6'd5:  sine64 = 16'h1619;
                6'd6:  sine64 = 16'h1A0B;
                6'd7:  sine64 = 16'h1DBD;
                6'd8:  sine64 = 16'h2125;
                6'd9:  sine64 = 16'h243C;
                6'd10: sine64 = 16'h26FA;
                6'd11: sine64 = 16'h2957;
                6'd12: sine64 = 16'h2B4F;
                6'd13: sine64 = 16'h2CDB;
                6'd14: sine64 = 16'h2DF9;
                6'd15: sine64 = 16'h2EA6;
                6'd16: sine64 = 16'h2EE0;
                6'd17: sine64 = 16'h2EA6;
                6'd18: sine64 = 16'h2DF9;
                6'd19: sine64 = 16'h2CDB;
                6'd20: sine64 = 16'h2B4F;
                6'd21: sine64 = 16'h2957;
                6'd22: sine64 = 16'h26FA;
                6'd23: sine64 = 16'h243C;
                6'd24: sine64 = 16'h2125;
                6'd25: sine64 = 16'h1DBD;
                6'd26: sine64 = 16'h1A0B;
                6'd27: sine64 = 16'h1619;
                6'd28: sine64 = 16'h11F0;
                6'd29: sine64 = 16'h0D9B;
                6'd30: sine64 = 16'h0925;
                6'd31: sine64 = 16'h0498;
                6'd32: sine64 = 16'h0000;
                6'd33: sine64 = 16'hFB68;
                6'd34: sine64 = 16'hF6DB;
                6'd35: sine64 = 16'hF265;
                6'd36: sine64 = 16'hEE10;
                6'd37: sine64 = 16'hE9E7;
                6'd38: sine64 = 16'hE5F5;
                6'd39: sine64 = 16'hE243;
                6'd40: sine64 = 16'hDEDB;
                6'd41: sine64 = 16'hDBC4;
                6'd42: sine64 = 16'hD906;
                6'd43: sine64 = 16'hD6A9;
                6'd44: sine64 = 16'hD4B1;
                6'd45: sine64 = 16'hD325;
                6'd46: sine64 = 16'hD207;
                6'd47: sine64 = 16'hD15A;
                6'd48: sine64 = 16'hD120;
                6'd49: sine64 = 16'hD15A;
                6'd50: sine64 = 16'hD207;
                6'd51: sine64 = 16'hD325;
                6'd52: sine64 = 16'hD4B1;
                6'd53: sine64 = 16'hD6A9;
                6'd54: sine64 = 16'hD906;
                6'd55: sine64 = 16'hDBC4;
                6'd56: sine64 = 16'hDEDB;
                6'd57: sine64 = 16'hE243;
                6'd58: sine64 = 16'hE5F5;
                6'd59: sine64 = 16'hE9E7;
                6'd60: sine64 = 16'hEE10;
                6'd61: sine64 = 16'hF265;
                6'd62: sine64 = 16'hF6DB;
                default: sine64 = 16'hFB68;
            endcase
        end
    endfunction

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            phase         <= 26'd0;
            fs_acc        <= 32'd0;
            audio_valid_r <= 1'b0;
            sample_r      <= 16'd0;
        end else begin
            audio_valid_r <= 1'b0;
            if (fs_acc + AUDIO_FS >= SYS_HZ) begin
                fs_acc <= fs_acc + AUDIO_FS - SYS_HZ;
                phase  <= phase + PHASE_INC;
                // table amplitude is 12000; double it to ~-2.7 dBFS so that
                // the test tone is clearly audible on TV speakers
                sample_r <= sine64(phase[25:20]) <<< 1;
                audio_valid_r <= 1'b1;
            end else begin
                fs_acc <= fs_acc + AUDIO_FS;
            end
        end
    end

    assign audio_sample = {sample_r, sample_r};   // L and R identical
    assign audio_valid  = audio_valid_r && (AUDIO_EN != 0);

    // ------------------------------------------------------ default text
    function [15:0] init_code;
        input [5:0] n;
        begin
            case (n)
                6'd0:  init_code = 16'hB4F3;  // da
                6'd1:  init_code = 16'hBCD2;  // jia
                6'd2:  init_code = 16'hBAC3;  // hao
                6'd15: init_code = 16'hA3B1;  // '1'
                6'd16: init_code = 16'hA3B2;  // '2'
                6'd17: init_code = 16'hA3BA;  // ':'
                6'd18: init_code = 16'hA3B3;  // '3'
                6'd19: init_code = 16'hA3B4;  // '4'
                6'd20: init_code = 16'hA3BA;  // ':'
                6'd21: init_code = 16'hA3B5;  // '5'
                6'd22: init_code = 16'hA3B6;  // '6'
                default: init_code = 16'h0000;
            endcase
        end
    endfunction

    reg [5:0]  init_cnt;
    reg [2:0]  init_div;
    wire       init_ts  = (init_cnt >= 6'd15);
    wire [3:0] init_idx = init_ts ? (init_cnt - 6'd15) : init_cnt[3:0];

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            init_cnt <= 6'd0;
            init_div <= 3'd0;
        end else if (init_cnt < 6'd30) begin
            if (init_div == 3'd7) begin
                init_div <= 3'd0;
                init_cnt <= init_cnt + 6'd1;
            end else begin
                init_div <= init_div + 3'd1;
            end
        end
    end

    // Hold the write strobe for 4 sys_clk cycles (80 ns) so that it is always
    // sampled by the slower 25 MHz pixel clock.
    assign osd_char_we   = (init_cnt < 6'd30) && (init_div < 3'd4);
    assign osd_slot      = init_ts;
    assign osd_char_idx  = init_idx;
    assign osd_char_code = init_code(init_cnt);
    assign osd_en        = SUBTITLE_EN ? {1'b1, 1'b1} : 2'b00;

    // --------------------------------------------------------- display
    hdmi_tx_display #(
        .AUDIO_FS         (AUDIO_FS),
        .HDMI_AUDIO_EN    (AUDIO_EN),
        .HDMI_SUBTITLE_EN (SUBTITLE_EN),
        .DVI_MODE         (0),
        .TS_X             (8),
        .TS_Y             (448)
    ) u_display (
        .sys_clk        (sys_clk),
        .sys_rst_n      (sys_rst_n),
        .pix_rgb        (src_rgb),
        .pix_valid      (src_valid),
        .frame_ready    (1'b1),
        .pix_underflow  (1'b0),
        .pix_clk        (pix_clk),
        .pix_req        (pix_req),
        .frame_sync     (frame_sync),
        .audio_clk      (sys_clk),
        .audio_sample   (audio_sample),
        .audio_valid    (audio_valid),
        .audio_ready    (audio_ready),
        .audio_status   (audio_status),
        .audio_pkt      (audio_pkt),
        .osd_en         (osd_en),
        .osd_slot       (osd_slot),
        .osd_char_idx   (osd_char_idx),
        .osd_char_code  (osd_char_code),
        .osd_char_we    (osd_char_we),
        .osd_x          (10'd200),
        .osd_y          (10'd420),
        .osd_fg         (24'hFFFFFF),
        .cfg_volume     (8'hFF),
        .key_in         (4'd0),
        .HDMI_CLK_P     (HDMI_CLK_P),
        .HDMI_D2_P      (HDMI_D2_P),
        .HDMI_D1_P      (HDMI_D1_P),
        .HDMI_D0_P      (HDMI_D0_P)
    );

    wire unused = |{pix_req, frame_sync, audio_ready, audio_status};

endmodule
