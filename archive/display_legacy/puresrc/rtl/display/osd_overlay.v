// -----------------------------------------------------------------------------
// Two-slot Chinese text OSD (16x16 glyphs, GB2312 codes).
//
//   slot 0 : normal subtitle, up to 15 characters, position sub_x/sub_y
//   slot 1 : timestamp, up to 15 characters, fixed at (TS_X, TS_Y)
//
// The font ROM has one synchronous read port.  Each character cell pre-fetches
// its 16-bit glyph row three pixels before it is needed, so no row cache and no
// distributed RAM are required.  Text is white with a 1-pixel black shadow on
// the right-hand side of each stroke.
// -----------------------------------------------------------------------------
module osd_overlay #(
    parameter integer OSD_EN = 1,
    parameter integer TS_X   = 8,
    parameter integer TS_Y   = 448
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        de,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [23:0] rgb_in,
    output reg  [23:0] rgb_out,

    input  wire [1:0]  osd_en,       // [1]=timestamp, [0]=subtitle
    input  wire        osd_slot,     // text write target
    input  wire [3:0]  char_idx,     // 0..14
    input  wire [15:0] char_code,    // GB2312 code
    input  wire        char_we,
    input  wire [9:0]  sub_x,
    input  wire [9:0]  sub_y,
    input  wire [23:0] fg
);

    localparam integer NCH = 15;

    reg [15:0] text_ram [0:2*NCH-1];

    integer i;

    // ---------------------------------------------------- GB2312 -> ROM index
    function [11:0] gb_index;
        input [15:0] code;
        reg [7:0] qu, wei;
        reg [11:0] level_idx;
        begin
            qu  = code[15:8] - 8'hA0;
            wei = code[7:0]  - 8'hA0;
            if (qu == 8'd3 && wei >= 8'd1 && wei <= 8'd94)
                gb_index = {4'd0, wei};                 // 1..94
            else if (qu >= 8'd16 && qu <= 8'd55 && wei >= 8'd1 && wei <= 8'd94)
            begin
                level_idx = ({4'd0, qu} - 12'd16) * 12'd94 +
                            ({4'd0, wei} - 12'd1);
                if (level_idx < 12'd1905)
                    gb_index = 12'd95 + level_idx;      // 95..1999
                else
                    gb_index = 12'd0;
            end
            else
                gb_index = 12'd0;
        end
    endfunction

    initial begin
        for (i = 0; i < 2*NCH; i = i + 1) text_ram[i] = 16'd0;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 2*NCH; i = i + 1)
                text_ram[i] <= 16'd0;
        end else if (char_we && char_idx < NCH) begin
            text_ram[{osd_slot, 4'd0} + char_idx] <= char_code;
        end
    end

    // ------------------------------------------------------------- font ROM
    reg  [11:0] rom_idx;
    reg  [3:0]  rom_row;
    wire [15:0] rom_bits;

    font_16x16_rom u_font (
        .clk(clk), .idx(rom_idx), .row(rom_row), .bits(rom_bits)
    );

    // ------------------------------------------------------------ geometry
    wire [9:0] sx0 = x - sub_x;
    wire [9:0] sy0 = y - sub_y;
    wire in0 = de && osd_en[0] &&
               (x >= sub_x) && (x < sub_x + NCH*16) &&
               (y >= sub_y) && (y < sub_y + 16);

    wire [3:0] cell0 = sx0[7:4];
    wire [3:0] gc0   = sx0[3:0];
    wire [3:0] gr0   = sy0[3:0];

    wire [9:0] sx1 = x - TS_X;
    wire [9:0] sy1 = y - TS_Y;
    wire in1 = de && osd_en[1] &&
               (x >= TS_X) && (x < TS_X + NCH*16) &&
               (y >= TS_Y) && (y < TS_Y + 16);

    wire [3:0] cell1 = sx1[7:4];
    wire [3:0] gc1   = sx1[3:0];
    wire [3:0] gr1   = sy1[3:0];

    // ------------------------------------------------------ row pre-fetching
    // first0/first1 happen just before the box starts; next0/next1 at the end
    // of the previous cell.  The ROM returns data two clocks after the request.
    reg        issued0, issued1;
    reg [3:0]  last_cell0, last_cell1;
    reg        target0, target1;
    reg        tgt0_d1, tgt0_d2, tgt1_d1, tgt1_d2;
    reg [15:0] row0, row1;

    wire first0 = (x == sub_x - 10'd3) &&
                  (y >= sub_y) && (y < sub_y + 16);
    wire first1 = (x == TS_X - 10'd4) &&
                  (y >= TS_Y) && (y < TS_Y + 16);

    wire req0 = first0 ||
                (in0 && (cell0 != 4'd15) && (sx0[3:0] >= 4'd12) && !issued0);
    wire req1 = first1 ||
                (in1 && (cell1 != 4'd15) && (sx1[3:0] >= 4'd11) && !issued1);

    wire [3:0] next_cell0 = first0 ? 4'd0 : cell0 + 4'd1;
    wire [3:0] next_cell1 = first1 ? 4'd0 : cell1 + 4'd1;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rom_idx   <= 12'd0;
            rom_row   <= 4'd0;
            issued0   <= 1'b0;
            issued1   <= 1'b0;
            last_cell0<= 4'd0;
            last_cell1<= 4'd0;
            target0   <= 1'b0;
            target1   <= 1'b0;
            tgt0_d1   <= 1'b0;
            tgt0_d2   <= 1'b0;
            tgt1_d1   <= 1'b0;
            tgt1_d2   <= 1'b0;
            row0      <= 16'd0;
            row1      <= 16'd0;
        end else begin
            // clear the "already fetched this cell" flag on a cell change
            if (!in0) begin
                issued0 <= 1'b0;
                last_cell0 <= 4'd0;
            end else if (cell0 != last_cell0) begin
                last_cell0 <= cell0;
                issued0 <= 1'b0;
            end
            if (!in1) begin
                issued1 <= 1'b0;
                last_cell1 <= 4'd0;
            end else if (cell1 != last_cell1) begin
                last_cell1 <= cell1;
                issued1 <= 1'b0;
            end

            target0 <= 1'b0;
            target1 <= 1'b0;

            if (req0) begin
                rom_idx <= gb_index(text_ram[{1'b0, 4'd0} + next_cell0]);
                rom_row <= gr0;
                target0 <= 1'b1;
                if (!first0) issued0 <= 1'b1;
            end else if (req1) begin
                rom_idx <= gb_index(text_ram[{1'b1, 4'd0} + next_cell1]);
                rom_row <= gr1;
                target1 <= 1'b1;
                if (!first1) issued1 <= 1'b1;
            end

            // two-stage tag delay matches the synchronous ROM latency
            tgt0_d1 <= target0;
            tgt0_d2 <= tgt0_d1;
            tgt1_d1 <= target1;
            tgt1_d2 <= tgt1_d1;

            if (tgt0_d2) row0 <= rom_bits;
            if (tgt1_d2) row1 <= rom_bits;
        end
    end

    // ----------------------------------------------------------- composite
    wire glyph0  = row0[15 - gc0];
    wire shadow0 = (gc0 != 4'd0) && row0[15 - (gc0 - 4'd1)];
    wire glyph1  = row1[15 - gc1];
    wire shadow1 = (gc1 != 4'd0) && row1[15 - (gc1 - 4'd1)];

    always @* begin
        if (OSD_EN == 0)
            rgb_out = rgb_in;
        else if (in1 && (glyph1 || shadow1))
            rgb_out = glyph1 ? fg : 24'h000000;
        else if (in0 && (glyph0 || shadow0))
            rgb_out = glyph0 ? fg : 24'h000000;
        else
            rgb_out = rgb_in;
    end

endmodule
