// Render the right-side parameter bar as ASCII to check geometry/percentages.
`timescale 1ns/1ps

module tb_param_osd;

    reg        clk = 1'b0;
    reg        de = 1'b1;
    reg [9:0]  x = 10'd0, y = 10'd0;
    reg [1:0]  sel = 2'd0;
    reg [4:0]  val = 5'd0;
    reg        visible = 1'b1;
    wire [23:0] rgb;

    param_osd dut (
        .clk(clk), .reset(1'b0), .de(de), .x(x), .y(y),
        .rgb_in(24'h000000), .rgb_out(rgb),
        .sel(sel), .val(val), .visible(visible)
    );

    task pix;
        begin
            #1;
            case (rgb)
                24'hFFFFFF: $write("#");
                24'h303030: $write("-");
                24'h808080: $write("|");
                default:   $write(".");
            endcase
        end
    endtask

    integer s, yy, xx;

    initial begin
        for (s = 0; s < 3; s = s + 1) begin
            sel = s[1:0];
            val = (s == 2) ? 5'd3 : 5'd10;

            $display("--- sel=%0d val=%0d : text row y=140 ---", sel, val);
            y = 10'd140;
            for (xx = 560; xx < 640; xx = xx + 1) begin
                x = xx[9:0]; pix;
            end
            $write("\n");

            $display("--- bar column x=610 (y=152..322, every 2) ---");
            x = 10'd610;
            for (yy = 152; yy < 324; yy = yy + 2) begin
                y = yy[9:0]; pix;
            end
            $write("\n");
        end
        sel = 2'd0; val = 5'd10;
        $display("--- full text block, sel=0 val=10 ---");
        for (yy = 136; yy < 150; yy = yy + 1) begin
            y = yy[9:0];
            for (xx = 570; xx < 630; xx = xx + 1) begin
                x = xx[9:0]; pix;
            end
            $write("\n");
        end
        $display("DONE");
        $finish;
    end

endmodule
