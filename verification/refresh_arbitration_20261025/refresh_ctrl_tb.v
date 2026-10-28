`timescale 1ns/1ps
module refresh_ctrl_tb;
    reg Clk = 0;
    always #4 Clk = ~Clk;
    reg Reset_n = 0, initialized = 0, manual = 0;
    reg writing = 0, reading = 0, hold_busy = 0, respond = 1;
    reg active = 0;
    integer active_left = 0;
    wire pending, request, fault;
    integer requests = 0, cases = 0, before_count, n;
    reg completed = 0;
    sdram_refresh_ctrl #(.INTERVAL_CYCLES(128), .TIMEOUT_CYCLES(32)) dut (
        .Clk(Clk), .Reset_n(Reset_n), .Sdr_init_done(initialized),
        .Sdr_init_ref_vld(active), .Sdr_busy(hold_busy || active),
        .App_wr_en(writing), .App_rd_en(reading), .manual_refresh_req(manual),
        .refresh_pending(pending), .App_ref_req(request), .refresh_error(fault));

    always @(posedge Clk) begin
        if (!Reset_n) begin
            active <= 0;
            active_left <= 0;
        end else if (request) begin
            if (!initialized || writing || reading || hold_busy || active)
                $fatal(1, "UNIT_FAIL request without quiescence");
            requests = requests + 1;
            if (respond) begin active <= 1; active_left <= 8; end
        end else if (active_left > 0) begin
            active_left <= active_left - 1;
            if (active_left == 1) active <= 0;
        end
    end

    task cycles;
        input integer count;
        integer k;
        begin for (k = 0; k < count; k = k + 1) @(negedge Clk); end
    endtask
    task reset_case;
        begin
            Reset_n = 0; initialized = 0; manual = 0;
            writing = 0; reading = 0; hold_busy = 0; respond = 1;
            cycles(3); Reset_n = 1; cycles(1);
        end
    endtask
    task complete_case;
        begin cases = cases + 1; $display("REFRESH_UNIT_CASE_PASS %0d", cases); end
    endtask

    initial begin
        reset_case;
        before_count = requests;
        cycles(160);
        if (requests != before_count || pending || fault) $fatal(1, "UNIT_FAIL before initialization");
        complete_case;

        initialized = 1;
        cycles(127);
        if (pending) $fatal(1, "UNIT_FAIL early deadline");
        cycles(1);
        if (!pending) $fatal(1, "UNIT_FAIL missing deadline");
        cycles(20);
        if (requests != before_count + 1 || pending || fault) $fatal(1, "UNIT_FAIL periodic refresh");
        complete_case;

        reset_case; initialized = 1; before_count = requests;
        manual = 1; cycles(24);
        if (requests != before_count + 1 || pending || fault) $fatal(1, "UNIT_FAIL held manual request repeated");
        manual = 0; complete_case;

        reset_case; initialized = 1; before_count = requests;
        writing = 1; manual = 1; cycles(1); manual = 0; cycles(4);
        if (!pending || request || requests != before_count) $fatal(1, "UNIT_FAIL interrupted active writer");
        writing = 0; reading = 1; cycles(3);
        if (requests != before_count) $fatal(1, "UNIT_FAIL interrupted active reader");
        reading = 0; hold_busy = 1; cycles(3);
        if (requests != before_count) $fatal(1, "UNIT_FAIL did not drain downstream");
        hold_busy = 0; cycles(3);
        if (requests != before_count) $fatal(1, "UNIT_FAIL missing quiet guard");
        cycles(20);
        if (requests != before_count + 1 || pending || fault) $fatal(1, "UNIT_FAIL drain/service");
        complete_case;

        reset_case; initialized = 1; respond = 0; manual = 1;
        cycles(1); manual = 0; cycles(36);
        if (!fault || !pending) $fatal(1, "UNIT_FAIL missing timeout latch");
        cycles(8);
        if (!fault || !pending) $fatal(1, "UNIT_FAIL timeout not sticky");
        complete_case;

        reset_case;
        if (fault || pending || request) $fatal(1, "UNIT_FAIL reset did not clear fault");
        initialized = 1; manual = 1; hold_busy = 1; cycles(3);
        if (!pending) $fatal(1, "UNIT_FAIL reset test setup");
        reset_case;
        if (fault || pending || request) $fatal(1, "UNIT_FAIL reset while pending");
        complete_case;

        // A manual request just before the periodic deadline satisfies that
        // deadline; it must not be reported as a missed second interval.
        reset_case; initialized = 1; before_count = requests;
        cycles(126); manual = 1; cycles(1); manual = 0;
        cycles(22);
        if (fault || pending || requests != before_count + 1)
            $fatal(1, "UNIT_FAIL manual request adjacent to periodic deadline");
        complete_case;
        $display("REFRESH_UNIT_PASS cases=%0d", cases);
        completed = 1;
    end
    initial begin #30000; if (!completed) $fatal(1, "UNIT_FAIL timeout"); end
endmodule
