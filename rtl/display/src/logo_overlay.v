// -----------------------------------------------------------------------------
// Fixed bitmap logo / watermark overlay.
//
// The 64x64 logo lives in logo_rom (one BRAM read port).  The ROM exports the
// transparent key colour it was generated with, so regeneration cannot leave a
// stale key here.  Pixels equal to that key are transparent; everything else
// replaces the video.  The ROM output is registered, so this module reads one
// pixel ahead (x+1) and delays the valid flag by one clock to keep the logo
// pixel-aligned with the video.
//
// The overlay is drawn after brightness/contrast, fade and subtitles, so the
// logo stays at full brightness during a fade (TV-station style bug).
// -----------------------------------------------------------------------------
module logo_overlay #(
    parameter integer LOGO_X = 568,   // 640 - 64 - 8
    parameter integer LOGO_Y = 8,
    parameter integer LOGO_W = 64,
    parameter integer LOGO_H = 64
)(
    input  wire        clk,
    input  wire        de,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [23:0] rgb_in,
    output wire [23:0] rgb_out
);

    // one-pixel lookahead for the registered ROM output
    wire [9:0] lx = x + 10'd1;
    wire in_next = de &&
                   (lx >= LOGO_X) && (lx < LOGO_X + LOGO_W) &&
                   (y  >= LOGO_Y) && (y  < LOGO_Y + LOGO_H);

    wire [11:0] addr = in_next ? ((y - LOGO_Y) * LOGO_W + (lx - LOGO_X))
                               : 12'd0;

    wire [23:0] rom_data;
    wire [23:0] rom_key;
    reg         valid_d;

    logo_rom u_rom (
        .clk  (clk),
        .addr (addr),
        .data (rom_data),
        .key  (rom_key)
    );

    always @(posedge clk)
        valid_d <= in_next;

    // rom_data at cycle t holds mem[addr(t-1)], i.e. pixel x(t): already aligned.
    assign rgb_out = (valid_d && rom_data != rom_key) ? rom_data : rgb_in;

endmodule
