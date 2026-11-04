// Render the 96x32 logo region as ASCII to check placement/transparency.
`timescale 1ns/1ps

module tb_logo;

    reg clk = 1'b0;
    always #20 clk = ~clk;          // 25 MHz

    reg [9:0] x = 10'd0, y = 10'd0;
    reg de = 1'b1;
    wire [23:0] rgb;

    logo_overlay #(.LOGO_X(568), .LOGO_Y(8)) dut (
        .clk(clk), .de(de), .x(x), .y(y),
        .rgb_in(24'h000000), .rgb_out(rgb)
    );

    integer yy, xx;

    // x advances every clock, exactly like the display's pixel counter
    always @(posedge clk) begin
        if (x == 10'd639) begin
            x <= 10'd0;
            y <= (y == 10'd479) ? 10'd0 : y + 10'd1;
        end else begin
            x <= x + 10'd1;
        end
    end

    initial begin
        // run to y=8, x=568, then dump rows 8..71, columns 560..639
        wait (y == 10'd8);
        for (yy = 8; yy < 72; yy = yy + 1) begin
            wait (y == yy && x == 10'd560);
            for (xx = 560; xx < 640; xx = xx + 1) begin
                @(negedge clk);
                if (rgb == 24'h000000)      $write(".");
                else if (rgb == 24'hE8E8E8) $write("T");
                else                        $write("#");
            end
            $write("\n");
        end
        $display("DONE");
        $finish;
    end

endmodule
