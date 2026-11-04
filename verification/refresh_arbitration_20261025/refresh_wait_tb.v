`timescale 1ns / 1ps

module refresh_wait_tb;
    reg SYS_CLK = 1'b0;
    reg wr_en = 1'b0;
    reg [31:0] wr_data = 32'd0;
    wire full, LED;
    integer scenario = 0; // 0=idle; 1=continuous; 2=8192 words then pause.
    integer events;
    integer accepted = 0;
    integer app_writes = 0;
    integer app_run = 0;
    integer physical_writes = 0;
    integer physical_refreshes = 0;
    reg feed_enable = 1'b0;
    reg observing = 1'b0;
    reg probe_bound = 1'b0;
    reg completed = 1'b0;
    reg previous_write = 1'b0;
    realtime origin = 0.0;

    always #10 SYS_CLK = ~SYS_CLK;
    memory_top dut (.SYS_CLK(SYS_CLK), .wr_en(wr_en), .wr_data(wr_data), .full(full), .LED(LED));
    IS42s32200 dram (.Clk(dut.SDRAM_CLK), .Cke(1'b1), .Cs_n(1'b0),
        .Ras_n(dut.SDR_RAS), .Cas_n(dut.SDR_CAS), .We_n(dut.SDR_WE),
        .Ba(dut.SDR_BA), .Addr(dut.SDR_ADDR), .Dqm(dut.SDR_DM), .Dq(dut.SDR_DQ));

    task log_event;
        input [8*40-1:0] kind;
        input integer value;
        begin
            if (observing)
                $fdisplay(events, "%0.3f,%0.3f,%0s,%0d", $realtime,
                          $realtime-origin, kind, value);
        end
    endtask

    always @(negedge dut.Clk) begin
        if (feed_enable && !(scenario == 2 && accepted >= 8192)) begin
            wr_en = 1'b1;
            wr_data = 32'h6a090000 ^ accepted;
        end else begin
            if (wr_en && observing) log_event("INPUT_PAUSE", accepted);
            if (scenario == 2 && accepted >= 8192) feed_enable = 1'b0;
            wr_en = 1'b0;
            wr_data = 32'd0;
        end
    end

    always @(posedge dut.Clk) begin
        if (observing && !dut.Rst) begin
            if (wr_en && !full) accepted = accepted + 1;
            if (dut.App_wr_en) begin
                if (dut.App_wr_addr !== app_writes || dut.App_wr_dm !== 4'b0000 || dut.App_wr_din !== (32'h6a090000 ^ app_writes))
                    $fatal(1, "WAIT_TEST_FAIL application write sequence");
                app_writes = app_writes + 1;
                app_run = app_run + 1;
                if (app_run > 4) $fatal(1, "WAIT_TEST_FAIL write burst longer than four");
                if (!previous_write) log_event("APP_BURST_START", app_writes-1);
            end else if (app_run != 0) begin
                if (app_run != 4) $fatal(1, "WAIT_TEST_FAIL incomplete write burst length=%0d", app_run);
                log_event("APP_BURST_END", app_writes-1);
                app_run = 0;
            end
            previous_write = dut.App_wr_en;
        end
    end

    always @(dut.Sdr_init_ref_vld) log_event("REFRESH_VALID", dut.Sdr_init_ref_vld);
    always @(dut.Sdr_busy) log_event("TOP_SDR_BUSY", dut.Sdr_busy);
`ifdef REFRESH_ARBITER
    always @(dut.refresh_pending) log_event("REFRESH_PENDING", dut.refresh_pending);
    always @(posedge dut.Clk)
        if (observing && dut.refresh_error) $fatal(1, "WAIT_TEST_FAIL refresh watchdog");
`endif
    always @(posedge dut.SDRAM_CLK) begin
        if (observing) begin
            if ({dut.SDR_RAS,dut.SDR_CAS,dut.SDR_WE} === 3'b001) begin
                physical_refreshes = physical_refreshes + 1;
                log_event("AUTO_REFRESH", physical_refreshes);
            end
            if ({dut.SDR_RAS,dut.SDR_CAS,dut.SDR_WE} === 3'b100)
                physical_writes = physical_writes + 1;
        end
    end

    initial begin
        if (!$value$plusargs("SCENARIO=%d", scenario)) scenario = 0;
        events = $fopen("events.csv", "w");
        $fdisplay(events, "absolute_ns,relative_ns,event,value");
        // Simulation startup input only; PLL source/configuration is unchanged.
        force dut.u0_clk.reset = 1'b1;
        #200;
        release dut.u0_clk.reset;
        wait (dut.lock === 1'b1);
        wait (dut.Sdr_init_done === 1'b1 && dut.Sdr_init_ref_vld === 1'b0);
        @(negedge dut.Clk);
        if (!probe_bound) $fatal(1, "WAIT_TEST_SETUP_FAIL internal observer did not bind");
        if (dram.Mode_reg !== 11'h032) $fatal(1, "WAIT_TEST_SETUP_FAIL model not initialized");
        origin = $realtime;
        observing = 1'b1;
        log_event("WINDOW_START", scenario);
        log_event("REFRESH_VALID_INITIAL", dut.Sdr_init_ref_vld);
        log_event("TOP_SDR_BUSY_INITIAL", dut.Sdr_busy);
        if (scenario != 0) feed_enable = 1'b1;
        #512000;
        log_event("WINDOW_END", scenario);
        $display("WAIT_TEST_COMPLETE scenario=%0d origin_ns=%0.3f end_ns=%0.3f accepted=%0d app_writes=%0d physical_writes=%0d physical_refreshes=%0d",
            scenario, origin, $realtime, accepted, app_writes, physical_writes, physical_refreshes);
        observing = 1'b0;
        completed = 1'b1;
        $fclose(events);
    end

    initial begin
        #1590000;
        if (!completed) $fatal(1, "WAIT_TEST_FAIL timeout");
    end
endmodule
