// -----------------------------------------------------------------------------
// HDMI display component: 640x480p60 video + audio + two-slot Chinese OSD.
//
// Video is always available; audio and subtitles can be disabled with the
// HDMI_AUDIO_EN / HDMI_SUBTITLE_EN parameters or at runtime through osd_en and
// AUDIO_FS=0? (audio is compile-time enabled only).
// -----------------------------------------------------------------------------
module hdmi_tx_display #(
    parameter integer AUDIO_FS        = 48000,  // 44100 or 48000
    parameter integer HDMI_AUDIO_EN   = 1,
    parameter integer HDMI_SUBTITLE_EN = 1,
    parameter integer DVI_MODE        = 0,
    parameter integer TS_X            = 8,
    parameter integer TS_Y            = 448
) (
    input  wire        sys_clk,
    input  wire        sys_rst_n,

    // video source interface
    input  wire [23:0] pix_rgb,
    input  wire        pix_valid,
    input  wire        frame_ready,
    input  wire        pix_underflow,

    output wire        pix_clk,
    output wire        pix_req,
    output wire        frame_sync,

    // audio source interface (asynchronous sample clock domain)
    input  wire        audio_clk,
    input  wire [31:0] audio_sample,   // {L[15:0], R[15:0]}
    input  wire        audio_valid,
    output wire        audio_ready,
    output wire [1:0]  audio_status,   // {overflow, underflow}
    output wire        audio_pkt,      // Audio Sample Packet activity

    // OSD / control
    input  wire [1:0]  osd_en,         // [1]=timestamp, [0]=subtitle
    input  wire        osd_slot,
    input  wire [3:0]  osd_char_idx,
    input  wire [15:0] osd_char_code,  // GB2312
    input  wire        osd_char_we,
    input  wire [9:0]  osd_x,
    input  wire [9:0]  osd_y,
    input  wire [23:0] osd_fg,
    input  wire [7:0]  cfg_volume,     // reserved, v1 passes audio unmodified
    input  wire [3:0]  key_in,         // reserved

    output wire        HDMI_CLK_P,
    output wire        HDMI_D2_P,
    output wire        HDMI_D1_P,
    output wire        HDMI_D0_P
);

    wire        VGA_DE;
    wire [23:0] VGA_D;
    wire [23:0] OSD_D;
    wire        VGA_HS, VGA_VS;
    wire [9:0] VGA_X;
    wire [9:0] VGA_Y;

    wire pixel_clk;
    wire pixel_clk_5x;

    assign pix_clk = pixel_clk;

    // ------------------------------------------------------------------ PLL
    clk_wize u_clk_wize (
        .refclk   (sys_clk),
        .reset    (1'b0),
        .clk0_out (pixel_clk_5x),
        .clk1_out (pixel_clk)
    );

    // ------------------------------------------------------------- timing
    read_RAM u_read_RAM (
        .clk25M     (pixel_clk),
        .reset_n    (sys_rst_n),
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

    // ---------------------------------------------------------------- OSD
    osd_overlay #(
        .OSD_EN (HDMI_SUBTITLE_EN),
        .TS_X   (TS_X),
        .TS_Y   (TS_Y)
    ) u_osd (
        .clk          (pixel_clk),
        .reset        (~sys_rst_n),
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
        .sub_x        (osd_x),
        .sub_y        (osd_y),
        .fg           (osd_fg)
    );

    // -------------------------------------------------------------- audio
    wire [31:0] audio_rd_data;
    wire        audio_empty;
    wire        audio_full;
    wire        audio_overflow;
    wire        audio_pop;

    audio_fifo #(.AWIDTH(5)) u_audio_fifo (
        .wr_clk   (audio_clk),
        .wr_rst   (~sys_rst_n),
        .wr_en    (audio_valid && HDMI_AUDIO_EN != 0),
        .wr_data  (audio_sample),
        .full     (audio_full),
        .overflow (audio_overflow),
        .rd_clk   (pixel_clk),
        .rd_rst   (~sys_rst_n),
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
        .RST_N       (sys_rst_n),

        .H_COUNT     (VGA_X),
        .V_COUNT     (VGA_Y),
        .VGA_HS      (VGA_HS),
        .VGA_VS      (VGA_VS),
        .VGA_RGB     (OSD_D),

        .AUDIO_I      (audio_rd_data),
        .AUDIO_VOL    (cfg_volume),
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
    wire unused = |{frame_ready, pix_underflow, cfg_volume, key_in};

endmodule
