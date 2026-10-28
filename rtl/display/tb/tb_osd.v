// Render the first subtitle cells of osd_overlay with the real font data and
// print them as ASCII, to check what the OSD actually draws.
`timescale 1ns/1ps

module tb_osd;

    reg clk = 1'b0;
    always #20 clk = ~clk;        // 25 MHz

    reg reset = 1'b1;
    reg de = 1'b1;
    reg [9:0] x = 10'd0;
    reg [9:0] y = 10'd0;

    reg        char_we = 1'b0;
    reg        slot = 1'b0;
    reg [3:0]  cidx = 4'd0;
    reg [15:0] ccode = 16'd0;

    wire [23:0] rgb;

    osd_overlay #(.OSD_EN(1), .TS_X(8), .TS_Y(448)) dut (
        .clk(clk), .reset(reset), .de(de), .x(x), .y(y),
        .rgb_in(24'd0), .rgb_out(rgb),
        .osd_en(2'b01), .osd_slot(slot),
        .char_idx(cidx), .char_code(ccode), .char_we(char_we),
        .sub_x(10'd16), .sub_y(10'd0), .fg(24'hFFFFFF)
    );

    task put;
        input [3:0] i;
        input [15:0] c;
        begin
            cidx = i; ccode = c; char_we = 1'b1;
            @(posedge clk); @(posedge clk);
            char_we = 1'b0;
            @(posedge clk);
        end
    endtask

    integer px, py;

    initial begin
        repeat (4) @(posedge clk);
        reset = 1'b0;
        repeat (2) @(posedge clk);

        put(4'd0, 16'hB4F3);
        put(4'd1, 16'hBCD2);
        put(4'd2, 16'hBAC3);
        $display("TEXT %04h %04h %04h", dut.text_ram[0], dut.text_ram[1], dut.text_ram[2]);

        for (py = 0; py < 32; py = py + 1) begin
            for (px = 0; px < 64; px = px + 1) begin
                x = px[9:0]; y = py[9:0];
                @(posedge clk);
                #1;
                if (px >= 16)
                    $write("%s", (rgb != 24'd0) ? "#" : ".");
            end
            $write("\n");
            if (py == 15) $display("--- row 16 ---");
        end
        $display("DONE");
        $finish;
    end

endmodule
