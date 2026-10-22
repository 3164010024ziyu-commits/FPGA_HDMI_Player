// -----------------------------------------------------------------------------
// Hardware bring-up top for the display block:
//   * 640x480 colour gradient with a 128x32 audio waveform scope (top-right)
//   * 1 kHz L/R sine test tone at AUDIO_FS
//   * one Chinese subtitle slot + a fixed-position timestamp slot
//   * 7-key runtime control (volume / mute / subtitle on-off / subtitle x)
// -----------------------------------------------------------------------------
module hdmi_demo_top #(
    parameter integer AUDIO_FS    = 48000,
    parameter integer AUDIO_EN    = 1,
    parameter integer SUBTITLE_EN = 1,
    // samples per waveform column: 1, 2, 4, 8 or 16 (time-axis compression)
    parameter integer WAVE_ZOOM   = 4
) (
    input  wire sys_clk,
    input  wire sys_rst_n,
    // {sub_right, sub_left, ts_on, sub_on, mute, vol_dn, vol_up}
    // key_in[0..1,5,6]: momentary, pressed = 0
    // key_in[2..4]    : latching switches, "on" = 0
    input  wire [6:0] key_in,
    output wire HDMI_CLK_P,
    output wire HDMI_D2_P,
    output wire HDMI_D1_P,
    output wire HDMI_D0_P
);

    localparam integer SYS_HZ   = 50_000_000;
    // 2^26 * 1000 / AUDIO_FS: the product does not fit in 32 bits, so keep the
    // constant in 64 bits (a 32-bit division here produced ~33k -> ~24 Hz).
    localparam [63:0]  PHASE_INC = (64'd67_108_864 * 64'd1000) / AUDIO_FS;

    wire        pix_clk, pix_req, frame_sync;
    wire [23:0] src_rgb;
    wire        src_valid;

    wire [31:0] audio_sample;
    wire        audio_valid, audio_ready;
    wire [1:0]  audio_status;
    wire        audio_pkt;

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

    // The audio waveform scope sits in the top-right corner:
    //   x = 512..639 (128 px), y = 8..39 (32 px)
    // src_rgb is assembled after the sine generator, see "audio waveform scope".
    localparam integer WAVE_X = 512;
    localparam integer WAVE_Y = 8;

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

    // ------------------------------------------------- audio waveform scope
    // 128 columns x 32 rows in the top-right corner, one 1-pixel bar per
    // column.  One column is written every WAVE_ZOOM audio samples, so the time
    // axis is compressed by WAVE_ZOOM (1 = one sample per pixel):
    //   WAVE_ZOOM = 1 -> 128 samples  ( 2.7 ms,  2.7 cycles @ 1 kHz)
    //   WAVE_ZOOM = 2 -> 256 samples  ( 5.3 ms,  5.3 cycles)
    //   WAVE_ZOOM = 4 -> 512 samples  (10.7 ms, 10.7 cycles)
    //   WAVE_ZOOM = 8 -> 1024 samples (21.3 ms, 21.3 cycles)
    // A rising zero crossing of the decimated stream triggers the snapshot, so
    // the displayed wave keeps a fixed phase instead of jumping every frame.
    //
    // sample_r is generated in the sys_clk domain; a toggle mailbox carries a
    // 5-bit signed amplitude (sample / 2048, about +/-12) into the pixel domain.
    localparam integer ZOOM = (WAVE_ZOOM < 1)  ? 1  :
                              (WAVE_ZOOM > 16) ? 16 : WAVE_ZOOM;

    reg  [4:0] amp_hold;
    reg        amp_tog;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            amp_hold <= 5'sd0;
            amp_tog  <= 1'b0;
        end else if (audio_valid_r) begin
            amp_hold <= sample_r[15:11];
            amp_tog  <= ~amp_tog;
        end
    end

    reg  [4:0] wave_mem [0:127];  // circular capture buffer (decimated)
    reg  [4:0] disp_mem [0:127];  // triggered snapshot shown on screen
    reg  [6:0] wave_col;
    reg  [6:0] copy_idx;
    reg        copying;
    reg  [6:0] copy_base;
    reg  [3:0] dec_cnt;
    reg  [4:0] prev_amp;
    reg  [2:0] amp_tog_pix;
    reg  [4:0] amp_s1, amp_s2;
    integer    wi, di;

    wire sample_stb  = amp_tog_pix[2] ^ amp_tog_pix[1];
    wire dec_last    = (dec_cnt == (ZOOM - 1));
    // rising zero crossing (negative -> non-negative) is the scope trigger
    wire rising_zero = (amp_s2[4] == 1'b0) && (prev_amp[4] == 1'b1);

    always @(posedge pix_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wave_col    <= 7'd0;
            dec_cnt     <= 4'd0;
            amp_tog_pix <= 3'd0;
            amp_s1      <= 5'd0;
            amp_s2      <= 5'd0;
            prev_amp    <= 5'd0;
            copy_idx    <= 7'd0;
            copying     <= 1'b0;
            copy_base   <= 7'd0;
            for (wi = 0; wi < 128; wi = wi + 1)
                wave_mem[wi] <= 5'd0;
            for (di = 0; di < 128; di = di + 1)
                disp_mem[di] <= 5'd0;
        end else begin
            amp_tog_pix <= {amp_tog_pix[1:0], amp_tog};
            amp_s1      <= amp_hold;      // stable for ~20 us, 2FF is plenty
            amp_s2      <= amp_s1;

            if (sample_stb) begin
                if (dec_last) begin      // keep one sample per WAVE_ZOOM
                    dec_cnt <= 4'd0;
                    wave_mem[wave_col] <= amp_s2;
                    wave_col <= wave_col + 7'd1;
                    prev_amp <= amp_s2;

                    // trigger: snapshot the 128 columns ending at the zero
                    // crossing, so the displayed wave keeps a fixed phase
                    if (rising_zero) begin
                        copying   <= 1'b1;
                        copy_idx  <= 7'd0;
                        copy_base <= wave_col + 7'd1;
                    end
                end else begin
                    dec_cnt <= dec_cnt + 4'd1;
                end
            end

            if (copying) begin
                disp_mem[copy_idx] <= wave_mem[(copy_idx + copy_base) & 7'h7F];
                if (copy_idx == 7'd127)
                    copying <= 1'b0;
                copy_idx <= copy_idx + 7'd1;
            end
        end
    end

    // WAVE_X = 512 is 128-aligned, so sh[6:0] is the column inside the box.
    wire        in_wave  = (sh >= WAVE_X) && (sv >= WAVE_Y) && (sv < WAVE_Y + 32);
    wire [6:0]  wave_c   = sh[6:0];
    wire [5:0]  wave_y   = sv[5:0] - 6'd8;          // 0..31 inside the box
    wire [4:0]  wave_a   = disp_mem[wave_c];        // signed amplitude
    wire [4:0]  wave_mag = wave_a[4] ? (~wave_a + 5'd1) : wave_a;
    wire [5:0]  wave_t   = 6'd16 - (wave_a[4] ? 6'd0 : {1'b0, wave_mag});
    wire [5:0]  wave_b   = 6'd16 + (wave_a[4] ? {1'b0, wave_mag} : 6'd0);
    wire        wave_bar = (wave_y >= wave_t) && (wave_y <= wave_b);

    assign src_rgb = in_wave ? (wave_bar ? 24'h00FF00 : 24'h000000)
                             : {grad_r, grad_g, grad_b};

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
    // sampled by the slower 25 MHz pixel clock.  The strobe is delayed by two
    // sys_clk cycles after char_idx/char_code change, otherwise a pixel-clock
    // edge that lands on the sys_clk edge can sample a mixed code (one cell
    // was being written as a blank glyph because of this).
    assign osd_char_we   = (init_cnt < 6'd30) && (init_div >= 3'd2) && (init_div < 3'd6);
    assign osd_slot      = init_ts;
    assign osd_char_idx  = init_idx;
    assign osd_char_code = init_code(init_cnt);

    // --------------------------------------------------------- display
    hdmi_tx_display #(
        .AUDIO_FS         (AUDIO_FS),
        .HDMI_AUDIO_EN    (AUDIO_EN),
        .HDMI_SUBTITLE_EN (SUBTITLE_EN),
        .DVI_MODE         (0),
        .TS_X             (8),
        .TS_Y             (448),
        .SUB_X_INIT       (200),
        .KEY_ACTIVE_LOW   (1)
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
        .key_in         (key_in),
        .osd_slot       (osd_slot),
        .osd_char_idx   (osd_char_idx),
        .osd_char_code  (osd_char_code),
        .osd_char_we    (osd_char_we),
        .osd_y          (10'd420),
        .osd_fg         (24'hFFFFFF),
        .HDMI_CLK_P     (HDMI_CLK_P),
        .HDMI_D2_P      (HDMI_D2_P),
        .HDMI_D1_P      (HDMI_D1_P),
        .HDMI_D0_P      (HDMI_D0_P)
    );

    wire unused = |{pix_req, frame_sync, audio_ready, audio_status, audio_pkt};

endmodule
