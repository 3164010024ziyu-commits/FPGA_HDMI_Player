`timescale 1ns / 1ps

module pll_smoke_tb;
    reg refclk = 1'b0;
    reg reset = 1'b1;
    wire clk0_out;
    wire clk1_out;
    wire clk2_out;
    wire extlock;

    reg checks_active = 1'b0;
    reg test_passed = 1'b0;
    reg seen0 = 1'b0;
    reg seen1 = 1'b0;
    reg seen2 = 1'b0;
    integer periods0 = 0;
    integer periods1 = 0;
    integer periods2 = 0;
    integer phase_checks = 0;
    realtime previous0;
    realtime previous1;
    realtime previous2;
    realtime phase_start;

    clk_pll dut (
        .refclk(refclk),
        .reset(reset),
        .clk0_out(clk0_out),
        .clk1_out(clk1_out),
        .clk2_out(clk2_out),
        .extlock(extlock)
    );

    always #10 refclk = ~refclk; // 50 MHz input.

    task check_interval;
        input realtime actual;
        input realtime expected;
        input [8*24-1:0] label;
        begin
            if (actual < expected - 0.01 || actual > expected + 0.01)
                $fatal(1, "PLL_SMOKE_FAIL %0s actual=%0.3f ns expected=%0.3f ns",
                       label, actual, expected);
        end
    endtask

    initial begin
        #200 reset = 1'b0;
        wait (extlock === 1'b1);
        checks_active = 1'b1;
    end

    always @(extlock) begin
        if (checks_active && extlock !== 1'b1)
            $fatal(1, "PLL_SMOKE_FAIL lock was lost during measurements");
    end

    always @(posedge clk0_out) begin
        if (checks_active) begin
            if (seen0) begin
                check_interval($realtime - previous0, 10.0, "clk0 period");
                periods0 = periods0 + 1;
            end
            previous0 = $realtime;
            seen0 = 1'b1;
        end
    end

    always @(posedge clk1_out) begin
        if (checks_active) begin
            if (seen1) begin
                check_interval($realtime - previous1, 8.0, "clk1 period");
                periods1 = periods1 + 1;
            end
            previous1 = $realtime;
            seen1 = 1'b1;
        end
    end

    always @(posedge clk2_out) begin
        if (checks_active) begin
            if (seen2) begin
                check_interval($realtime - previous2, 8.0, "clk2 period");
                periods2 = periods2 + 1;
            end
            previous2 = $realtime;
            seen2 = 1'b1;
        end
    end

    initial begin
        wait (checks_active);
        while (!test_passed) begin
            @(posedge clk1_out);
            phase_start = $realtime;
            @(posedge clk2_out);
            check_interval($realtime - phase_start, 4.0, "clk1 to clk2 phase");
            phase_checks = phase_checks + 1;
        end
    end

    initial begin
        wait (checks_active);
        wait (periods0 >= 16 && periods1 >= 16 && periods2 >= 16 && phase_checks >= 16);
        if (extlock !== 1'b1)
            $fatal(1, "PLL_SMOKE_FAIL lock not asserted at completion");
        test_passed = 1'b1;
        checks_active = 1'b0;
        $display("PLL_SMOKE_PASS input=50MHz clk0=100MHz clk1=125MHz clk2=125MHz phase=180deg periods=%0d/%0d/%0d phase_checks=%0d time_ns=%0.3f",
                 periods0, periods1, periods2, phase_checks, $realtime);
        // The batch runner owns termination; avoid an interactive $finish stop.
    end

    initial begin
        #49000;
        if (!test_passed)
            $fatal(1, "PLL_SMOKE_FAIL timeout: lock=%b periods=%0d/%0d/%0d phase_checks=%0d",
                   extlock, periods0, periods1, periods2, phase_checks);
    end
endmodule
