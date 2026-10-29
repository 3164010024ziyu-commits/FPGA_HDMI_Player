// -----------------------------------------------------------------------------
// HDMI display component: 640x480p60 video + audio + two-slot Chinese OSD.
//
// Video is always available; audio and subtitles can be disabled with the
// HDMI_AUDIO_EN / HDMI_SUBTITLE_EN parameters.  Runtime control comes from
// seven debounced keys.  Four are momentary push buttons (active low, pressed
// = 0, one action per press):
//
//   key_in[0]  VOL+      5-step volume, level 0..4  ->  0/64/128/192/255
//   key_in[1]  VOL-      (level 0 is digital silence, level 4 is 0 dB)
//   key_in[5]  SUB <-    move the normal subtitle one character (16 px) left
//   key_in[6]  SUB ->    move the normal subtitle one character (16 px) right
//
// Three are latching toggle switches, read as levels (SWITCH_ON_LOW=1 means
// the "on" position pulls the pin low):
//
//   key_in[2]  MUTE      mute on/off, the volume level is kept
//   key_in[3]  SUB ON    normal subtitle on/off
//   key_in[4]  TS ON     timestamp subtitle on/off (independent of SUB ON)
//
// All key processing runs in the pixel clock domain: two flip-flop
// synchroniser, ~10 ms debounce per key, then a one-cycle press strobe for
// the momentary keys.
// -----------------------------------------------------------------------------
module hdmi_tx_display #(
    parameter integer AUDIO_FS        = 48000,  // 44100 or 48000
    parameter integer HDMI_AUDIO_EN   = 1,
    parameter integer HDMI_SUBTITLE_EN = 1,
    parameter integer DVI_MODE        = 0,
    parameter integer TS_X            = 8,
    parameter integer TS_Y            = 448,
    parameter integer SUB_X_INIT      = 200,    // normal subtitle start column
    parameter integer KEY_ACTIVE_LOW  = 1,
    parameter integer SWITCH_ON_LOW   = 1
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    // video source interface
    input  wire [23:0] pix_rgb,
    input  wire        pix_valid,
    input  wire        frame_ready,
    input  wire        pix_underflow,

    output wire        pix_clk,
    output wire        pix_reset_n,
    output wire        pix_req,
    output wire        frame_sync,

    // audio source interface (asynchronous sample clock domain)
    input  wire        audio_clk,
    input  wire [31:0] audio_sample,   // {L[15:0], R[15:0]}
    input  wire        audio_valid,
    output wire        audio_ready,
    output wire [1:0]  audio_status,   // {overflow, underflow}
    output wire        audio_pkt,      // Audio Sample Packet activity

    // runtime key control (pixel clock domain, debounced internally)
    input  wire [6:0]  key_in,

    // OSD text write port (content is supplied by the top level)
    input  wire        osd_slot,
    input  wire [3:0]  osd_char_idx,
    input  wire [15:0] osd_char_code,  // GB2312
    input  wire        osd_char_we,
    input  wire [9:0]  osd_y,
    input  wire [23:0] osd_fg,

    output wire        HDMI_CLK_P,
    output wire        HDMI_D2_P,
    output wire        HDMI_D1_P,
    output wire        HDMI_D0_P
);

    wire        VGA_DE;
    wire [23:0] VGA_D;
    wire [23:0] OSD_D;
    wire        VGA_HS, VGA_VS;
    wire [9:0]  VGA_X;
    wire [9:0]  VGA_Y;

    wire pixel_clk;
wire pixel_clk_5x;
    wire pll_locked;
    wire reset_request = !sys_rst_n || !pll_locked;
    reg [1:0] pixel_release;
    always @(posedge pixel_clk or posedge reset_request) begin
        if(reset_request) pixel_release <= 0;
        else pixel_release <= {pixel_release[0],1'b1};
    end
    wire video_reset_n = pixel_release[1];
    assign pix_reset_n = video_reset_n;

    assign pix_clk = pixel_clk;

    // ------------------------------------------------------------------ PLL
    clk_wize u_clk_wize (
        .refclk   (sys_clk),
        .reset    (1'b0),
        .extlock  (pll_locked),
        .clk0_out (pixel_clk_5x),
        .clk1_out (pixel_clk)
    );

    // ------------------------------------------------------------- timing
    read_RAM u_read_RAM (
        .clk25M     (pixel_clk),
        .reset_n    (video_reset_n),
        .pix_rgb    (pix_rgb),
        .pix_valid  (pix_valid),

        .pix_req    (pix_req),
        .frame_sync (frame_sync),
        .HDMI_HSYNC (VGA_HS),
        .HDMI_VSYNC (VGA_VS),
        .HDMI_X     (VGA_X),
        .HDMI_Y     (VGA_Y),
        .HDMI_EN    (VGA_DE),
        .HDMI_D     (VGA_D)
    );

    // ------------------------------------------------------- key control
    localparam [2:0]  VOL_LEVEL_MAX = 3'd4;      // 0..4 -> five steps
    localparam [9:0]  SUB_STEP      = 10'd16;    // one 16-pixel character
    localparam [9:0]  SUB_X_START   = SUB_X_INIT[9:0];
    localparam [9:0]  SUB_X_MAX     = 10'd400;   // 640 - 15*16
    localparam [17:0] KEY_DB_MAX    = 18'h3FFFF; // ~10.5 ms at 25 MHz

    reg [6:0]  key_meta, key_sync, key_stable, key_stable_d;
    reg [17:0] key_timer [0:6];
    integer    ki;

    always @(posedge pixel_clk or negedge video_reset_n) begin
        if (!video_reset_n) begin
            key_meta     <= 7'd0;
            key_sync     <= 7'd0;
            key_stable   <= 7'h7F;   // all released / switches "off"
            key_stable_d <= 7'h7F;
            for (ki = 0; ki < 7; ki = ki + 1)
                key_timer[ki] <= 18'd0;
        end else begin
            key_meta     <= key_in;
            key_sync     <= key_meta;
            key_stable_d <= key_stable;

            for (ki = 0; ki < 7; ki = ki + 1) begin
                if (key_sync[ki] == key_stable[ki]) begin
                    key_timer[ki] <= 18'd0;
                end else if (key_timer[ki] == KEY_DB_MAX) begin
                    key_stable[ki] <= key_sync[ki];
                    key_timer[ki]  <= 18'd0;
                end else begin
                    key_timer[ki] <= key_timer[ki] + 18'd1;
                end
            end
        end
    end

    // one-cycle press strobe for the momentary keys (active low: pressed = 0)
    wire [6:0] key_press = (KEY_ACTIVE_LOW != 0)
                           ? (~key_stable &  key_stable_d)
                           : ( key_stable & ~key_stable_d);

    // latching switches: the debounced pin level *is* the state
    wire sw_mute = (SWITCH_ON_LOW != 0) ? ~key_stable[2] : key_stable[2];
    wire sw_sub  = (SWITCH_ON_LOW != 0) ? ~key_stable[3] : key_stable[3];
    wire sw_ts   = (SWITCH_ON_LOW != 0) ? ~key_stable[4] : key_stable[4];

    reg [2:0]  vol_level;
    reg [9:0]  sub_x;

    // 0, 64, 128, 192, 255 -> silence .. 0 dB
    function [7:0] vol_code;
        input [2:0] lvl;
        begin
            case (lvl)
                3'd0:    vol_code = 8'd0;
                3'd1:    vol_code = 8'd64;
                3'd2:    vol_code = 8'd128;
                3'd3:    vol_code = 8'd192;
                default: vol_code = 8'd255;
            endcase
        end
    endfunction

    always @(posedge pixel_clk or negedge video_reset_n) begin
        if (!video_reset_n) begin
            vol_level <= VOL_LEVEL_MAX;
            sub_x     <= SUB_X_START;
        end else begin
            if (key_press[0] && (vol_level != VOL_LEVEL_MAX))
                vol_level <= vol_level + 3'd1;
            if (key_press[1] && (vol_level != 3'd0))
                vol_level <= vol_level - 3'd1;
            if (key_press[5] && (sub_x >= SUB_STEP))
                sub_x <= sub_x - SUB_STEP;
            if (key_press[6] && (sub_x <= SUB_X_MAX - SUB_STEP))
                sub_x <= sub_x + SUB_STEP;
        end
    end

    wire [7:0] volume = sw_mute ? 8'd0 : vol_code(vol_level);
    wire [1:0] osd_en = (HDMI_SUBTITLE_EN != 0) ? {sw_ts, sw_sub} : 2'b00;

    // ---------------------------------------------------------------- OSD
    generate if(HDMI_SUBTITLE_EN != 0) begin : g_osd
    osd_overlay #(
        .OSD_EN (HDMI_SUBTITLE_EN),
        .TS_X   (TS_X),
        .TS_Y   (TS_Y)
    ) u_osd (
        .clk          (pixel_clk),
        .reset        (~video_reset_n),
        .de           (VGA_DE),
        .x            (VGA_X),
        .y            (VGA_Y),
        .rgb_in       (VGA_D),
        .rgb_out      (OSD_D),
        .osd_en       (osd_en),
        .osd_slot     (osd_slot),
        .char_idx     (osd_char_idx),
        .char_code    (osd_char_code),
        .char_we      (osd_char_we),
        .sub_x        (sub_x),
        .sub_y        (osd_y),
        .fg           (osd_fg)
    );

    end else begin : g_no_osd
        assign OSD_D = VGA_D;
    end endgenerate

    // -------------------------------------------------------------- audio
    wire [31:0] audio_rd_data;
    wire        audio_empty;
    wire        audio_full;
    wire        audio_overflow;
    wire        audio_pop;

    audio_fifo #(.AWIDTH(5)) u_audio_fifo (
        .wr_clk   (audio_clk),
        .wr_rst   (~video_reset_n),
        .wr_en    (audio_valid && HDMI_AUDIO_EN != 0),
        .wr_data  (audio_sample),
        .full     (audio_full),
        .overflow (audio_overflow),
        .rd_clk   (pixel_clk),
        .rd_rst   (~video_reset_n),
        .rd_en    (audio_pop),
        .rd_data  (audio_rd_data),
        .empty    (audio_empty)
    );

    assign audio_ready = !audio_full;

    // ------------------------------------------------------------- HDMI TX
    hdmi_tx #(
        .FAMILY  ("EG4"),
        .AUDIO_EN(HDMI_AUDIO_EN),
        .DVI_MODE(DVI_MODE),
        .AUDIO_FS(AUDIO_FS)
    ) u3_hdmi_tx (
        .PXLCLK_I    (pixel_clk),
        .PXLCLK_5X_I (pixel_clk_5x),
        .RST_N       (video_reset_n),

        .H_COUNT     (VGA_X),
        .V_COUNT     (VGA_Y),
        .VGA_HS      (VGA_HS),
        .VGA_VS      (VGA_VS),
        .VGA_RGB     (OSD_D),

        .AUDIO_I      (audio_rd_data),
        .AUDIO_VOL    (volume),
        .AUDIO_EMPTY  (audio_empty),
        .AUDIO_OVF    (audio_overflow),
        .AUDIO_POP    (audio_pop),
        .AUDIO_STATUS (audio_status),
        .AUDIO_PKT    (audio_pkt),

        .HDMI_CLK_P (HDMI_CLK_P),
        .HDMI_D2_P  (HDMI_D2_P),
        .HDMI_D1_P  (HDMI_D1_P),
        .HDMI_D0_P  (HDMI_D0_P)
    );

    // keep optional interface signals alive in the netlist
    wire unused = |{frame_ready, pix_underflow};

endmodule
