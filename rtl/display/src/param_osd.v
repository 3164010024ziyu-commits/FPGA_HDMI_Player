// -----------------------------------------------------------------------------
// Right-side parameter bar (Windows-10 style) for brightness / contrast / volume.
//
// A single bar is drawn at x = 600..623, y = 160..319 (right edge, vertically
// centred).  Above it, a 5x7 ASCII string ("B 100%", "C  50%", "V  75%") is
// rendered at 2x scale.  Only one parameter is shown at a time; the caller
// supplies sel/val and the visible strobe (3 s timer).
//
// The 5x7 font is local (no BRAM, no GB2312 ROM) so the bar works whether or
// not the subtitle OSD / font ROM is enabled.
// -----------------------------------------------------------------------------
module param_osd (
    input  wire        clk,
    input  wire        reset,       // active high
    input  wire        de,
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [23:0] rgb_in,
    output reg  [23:0] rgb_out,
    input  wire [1:0]  sel,         // 0 = brightness, 1 = contrast, 2 = volume
    input  wire [4:0]  val,         // brightness/contrast 0..20, volume 0..19
    input  wire        visible
);

    localparam integer BAR_X = 600;
    localparam integer BAR_Y = 160;
    localparam integer BAR_W = 24;
    localparam integer BAR_H = 160;
    localparam integer TXT_X = 570;
    localparam integer TXT_Y = 136;
    localparam integer CH_W  = 10;   // 5x7 glyph at 2x

    // ------------------------------------------------------------- percentage
    // brightness/contrast: 21 levels -> 0..100%, volume: 20 levels -> 0..100%
    // Exact floor(level*100/19), without a long combinational divider.
    function [6:0] volume_percent;
        input [4:0] level;
        begin
            case(level)
                5'd0: volume_percent=7'd0;
                5'd1: volume_percent=7'd5;
                5'd2: volume_percent=7'd10;
                5'd3: volume_percent=7'd15;
                5'd4: volume_percent=7'd21;
                5'd5: volume_percent=7'd26;
                5'd6: volume_percent=7'd31;
                5'd7: volume_percent=7'd36;
                5'd8: volume_percent=7'd42;
                5'd9: volume_percent=7'd47;
                5'd10: volume_percent=7'd52;
                5'd11: volume_percent=7'd57;
                5'd12: volume_percent=7'd63;
                5'd13: volume_percent=7'd68;
                5'd14: volume_percent=7'd73;
                5'd15: volume_percent=7'd78;
                5'd16: volume_percent=7'd84;
                5'd17: volume_percent=7'd89;
                5'd18: volume_percent=7'd94;
                5'd19: volume_percent=7'd100;
                default: volume_percent=7'd100;
            endcase
        end
    endfunction
    wire [6:0] vol_pct=volume_percent(val);
    wire [6:0] pct_raw = (sel == 2'd2) ? vol_pct
                                       : ({2'b0, val} * 7'd5);
    // Parameter metadata may settle one clock later; RGB and timing remain
    // combinational pass-through. This cuts the percentage->font/bar path.
    reg [6:0] pct;
    always @(posedge clk or posedge reset)begin
        if(reset)pct<=0;
        else pct<=(pct_raw > 7'd100)?7'd100:pct_raw;
    end

    wire [3:0] d_h = pct / 7'd100;
    wire [3:0] d_t = (pct / 7'd10) % 4'd10;
    wire [3:0] d_o = pct % 4'd10;

    // 6 characters: letter, space, hundreds, tens, ones, '%'
    reg [3:0] chars [0:5];
    always @* begin
        chars[0] = (sel == 2'd0) ? 4'd12 : (sel == 2'd1) ? 4'd13 : 4'd14;
        chars[1] = 4'd0;
        chars[2] = (pct >= 7'd100) ? (d_h + 4'd1) : 4'd0;
        chars[3] = (pct >= 7'd10)  ? (d_t + 4'd1) : 4'd0;
        chars[4] = d_o + 4'd1;
        chars[5] = 4'd11;
    end

    // ------------------------------------------------------------- 5x7 font
    function [4:0] glyph_row;
        input [3:0] ch;
        input [2:0] r;
        begin
            case (ch)
            4'd1: case (r) 3'd0: glyph_row=5'b01110; 3'd1: glyph_row=5'b10001; 3'd2: glyph_row=5'b10011; 3'd3: glyph_row=5'b10101; 3'd4: glyph_row=5'b11001; 3'd5: glyph_row=5'b10001; default: glyph_row=5'b01110; endcase
            4'd2: case (r) 3'd0: glyph_row=5'b00100; 3'd1: glyph_row=5'b01100; 3'd2: glyph_row=5'b00100; 3'd3: glyph_row=5'b00100; 3'd4: glyph_row=5'b00100; 3'd5: glyph_row=5'b00100; default: glyph_row=5'b01110; endcase
            4'd3: case (r) 3'd0: glyph_row=5'b01110; 3'd1: glyph_row=5'b10001; 3'd2: glyph_row=5'b00001; 3'd3: glyph_row=5'b00010; 3'd4: glyph_row=5'b00100; 3'd5: glyph_row=5'b01000; default: glyph_row=5'b11111; endcase
            4'd4: case (r) 3'd0: glyph_row=5'b11111; 3'd1: glyph_row=5'b00010; 3'd2: glyph_row=5'b00100; 3'd3: glyph_row=5'b00010; 3'd4: glyph_row=5'b00001; 3'd5: glyph_row=5'b10001; default: glyph_row=5'b01110; endcase
            4'd5: case (r) 3'd0: glyph_row=5'b00010; 3'd1: glyph_row=5'b00110; 3'd2: glyph_row=5'b01010; 3'd3: glyph_row=5'b10010; 3'd4: glyph_row=5'b11111; 3'd5: glyph_row=5'b00010; default: glyph_row=5'b00010; endcase
            4'd6: case (r) 3'd0: glyph_row=5'b11111; 3'd1: glyph_row=5'b10000; 3'd2: glyph_row=5'b11110; 3'd3: glyph_row=5'b00001; 3'd4: glyph_row=5'b00001; 3'd5: glyph_row=5'b10001; default: glyph_row=5'b01110; endcase
            4'd7: case (r) 3'd0: glyph_row=5'b00110; 3'd1: glyph_row=5'b01000; 3'd2: glyph_row=5'b10000; 3'd3: glyph_row=5'b11110; 3'd4: glyph_row=5'b10001; 3'd5: glyph_row=5'b10001; default: glyph_row=5'b01110; endcase
            4'd8: case (r) 3'd0: glyph_row=5'b11111; 3'd1: glyph_row=5'b00001; 3'd2: glyph_row=5'b00010; 3'd3: glyph_row=5'b00100; 3'd4: glyph_row=5'b01000; 3'd5: glyph_row=5'b01000; default: glyph_row=5'b01000; endcase
            4'd9: case (r) 3'd0: glyph_row=5'b01110; 3'd1: glyph_row=5'b10001; 3'd2: glyph_row=5'b10001; 3'd3: glyph_row=5'b01110; 3'd4: glyph_row=5'b10001; 3'd5: glyph_row=5'b10001; default: glyph_row=5'b01110; endcase
            4'd10: case (r) 3'd0: glyph_row=5'b01110; 3'd1: glyph_row=5'b10001; 3'd2: glyph_row=5'b10001; 3'd3: glyph_row=5'b01111; 3'd4: glyph_row=5'b00001; 3'd5: glyph_row=5'b00010; default: glyph_row=5'b01100; endcase
            4'd11: case (r) 3'd0: glyph_row=5'b11001; 3'd1: glyph_row=5'b11010; 3'd2: glyph_row=5'b00010; 3'd3: glyph_row=5'b00100; 3'd4: glyph_row=5'b01000; 3'd5: glyph_row=5'b01011; default: glyph_row=5'b10011; endcase
            4'd12: case (r) 3'd0: glyph_row=5'b11110; 3'd1: glyph_row=5'b10001; 3'd2: glyph_row=5'b10001; 3'd3: glyph_row=5'b11110; 3'd4: glyph_row=5'b10001; 3'd5: glyph_row=5'b10001; default: glyph_row=5'b11110; endcase
            4'd13: case (r) 3'd0: glyph_row=5'b01110; 3'd1: glyph_row=5'b10001; 3'd2: glyph_row=5'b10000; 3'd3: glyph_row=5'b10000; 3'd4: glyph_row=5'b10000; 3'd5: glyph_row=5'b10001; default: glyph_row=5'b01110; endcase
            4'd14: case (r) 3'd0: glyph_row=5'b10001; 3'd1: glyph_row=5'b10001; 3'd2: glyph_row=5'b10001; 3'd3: glyph_row=5'b10001; 3'd4: glyph_row=5'b10001; 3'd5: glyph_row=5'b01010; default: glyph_row=5'b00100; endcase
            default: glyph_row = 5'b00000;
            endcase
        end
    endfunction

    // ------------------------------------------------------------- text pixel
    wire [9:0] tx = x - TXT_X;
    wire [9:0] ty = y - TXT_Y;
    wire in_txt = de && visible &&
                  (x >= TXT_X) && (x < TXT_X + 6*CH_W) &&
                  (y >= TXT_Y) && (y < TXT_Y + 14);

    wire [2:0] ci  = in_txt ? (tx / CH_W) : 3'd0;      // 0..5
    wire [3:0] cx  = in_txt ? (tx % CH_W) : 4'd0;
    wire [3:0] cy  = ty;
    wire [2:0] col = (cx[3:1] > 3'd4) ? 3'd4 : cx[3:1];
    wire [4:0] row = glyph_row(chars[ci], cy[3:1]);
    wire text_px   = in_txt && row[4 - col];

    // --------------------------------------------------------------- the bar
    wire in_bar = de && visible &&
                  (x >= BAR_X) && (x < BAR_X + BAR_W) &&
                  (y >= BAR_Y) && (y < BAR_Y + BAR_H);
    wire [13:0] fill_full = pct * 14'd158;             // 0..15800
    wire [7:0]  fill_h    = fill_full / 100;           // 0..158

    wire bar_border = (x == BAR_X) || (x == BAR_X + BAR_W - 1) ||
                      (y == BAR_Y) || (y == BAR_Y + BAR_H - 1);
    wire bar_fill   = (y >= BAR_Y + BAR_H - 1 - fill_h) &&
                      (y <  BAR_Y + BAR_H - 1) &&
                      (x >  BAR_X) && (x < BAR_X + BAR_W - 1);

    always @* begin
        rgb_out = rgb_in;
        if (in_txt) begin
            if (text_px)
                rgb_out = 24'hFFFFFF;
        end else if (in_bar) begin
            if (bar_border)    rgb_out = 24'h808080;
            else if (bar_fill) rgb_out = 24'hFFFFFF;
            else               rgb_out = 24'h303030;
        end
    end

endmodule
