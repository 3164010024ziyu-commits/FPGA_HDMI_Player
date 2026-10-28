// Dump the 128x32 audio waveform box of hdmi_demo_top as ASCII art.
// Uses the behavioural stubs for the PLL/read_RAM/OSD/FIFO/HDMI-TX.
`timescale 1ns/1ps

module tb_wave;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [6:0] key_in = 7'h7F;

    always #10 clk = ~clk;   // 50 MHz, stub PLL passes it to the pixel domain

    hdmi_demo_top #(
        .AUDIO_FS(48000), .AUDIO_EN(1), .SUBTITLE_EN(1), .WAVE_ZOOM(4)
    ) u_top (
        .sys_clk(clk), .sys_rst_n(rst_n), .key_in(key_in),
        .HDMI_CLK_P(), .HDMI_D2_P(), .HDMI_D1_P(), .HDMI_D0_P()
    );

    reg dump = 1'b0;
    integer dbg = 0;

    always @(posedge clk) begin
        if (u_top.audio_valid_r && dbg < 6) begin
            $display("DBG t=%0t sample=%0d amp_hold=%0d col=%0d",
                     $time, $signed(u_top.sample_r), $signed(u_top.amp_hold), u_top.wave_col);
            dbg <= dbg + 1;
        end
        if (dump && u_top.sv >= 10'd8 && u_top.sv < 10'd40) begin
            if (u_top.sh >= 10'd512 && u_top.sh < 10'd640)
                $write("%s", (u_top.src_rgb == 24'h00FF00) ? "#" : ".");
            if (u_top.sh == 10'd639)
                $write("\n");
        end
        if (dump && u_top.sv == 10'd39 && u_top.sh == 10'd639) begin
            dump <= 1'b0;
            $display("WAVE-END");
        end
    end

    integer c;
    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        #6_000_000;                       // let the scope fill (> 512 samples)
        wait (u_top.sv == 10'd0 && u_top.sh == 10'd0);
        @(posedge clk);
        dump = 1'b1;
        wait (!dump);
        // report the captured amplitudes for a sanity check
        for (c = 0; c < 128; c = c + 1)
            $write("%0d ", $signed(u_top.wave_mem[c]));
        $write("\n");
        $display("DONE");
        $finish;
    end

endmodule
