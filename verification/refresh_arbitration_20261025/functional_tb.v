`timescale 1ns / 1ps

module functional_tb;
    reg SYS_CLK = 1'b0;
    reg wr_en = 1'b0;
    reg [31:0] wr_data = 32'd0;
    wire full, LED;
    reg rd_drive = 1'b0;
    reg [20:0] rd_address = 21'd0;
    reg manual_refresh = 1'b0;
    integer profile = 0;
    integer phase_diag = 0;
    integer phase_degrees = 90;
    wire diagnostic_shift_clock;
    reg diagnostic_shift_clock270 = 1'b0;
    assign #2 diagnostic_shift_clock = dut.Clk;
    // A delay greater than half a period needs transport-style scheduling;
    // a delayed continuous assignment would suppress the clock pulses.
    always @(dut.Clk) diagnostic_shift_clock270 <= #6 dut.Clk;
    integer submitted = 0;
    integer app_writes = 0;
    integer total_reads = 0;
    integer read_received = 0;
    integer read_base = 0;
    integer read_expected = 0;
    integer app_run = 0;
    integer physical_refreshes = 0;
    integer physical_writes = 0;
    integer physical_reads = 0;
    integer write_refresh_overlap = 0;
    integer cycle = 0;
    integer init_cycle = -1;
    integer events;
    integer case_id = 0;
    integer completed_cases = 0;
    integer data_errors = 0;
    integer coverage_errors = 0;
    integer storage_checks = 0;
    integer storage_errors = 0;
    integer mapped_bank [0:65535];
    integer mapped_index [0:65535];
    integer physical_row [0:3];
    integer physical_k;
    integer n, base, phase, ref_before;
    reg reading = 1'b0;
    reg suite_done = 1'b0;
    reg previous_refresh = 1'b0;
    reg [31:0] expected [0:65535];

    always #10 SYS_CLK = ~SYS_CLK;
    memory_top dut (.SYS_CLK(SYS_CLK), .wr_en(wr_en), .wr_data(wr_data), .full(full), .LED(LED));
    IS42s32200 dram (.Clk(dut.SDRAM_CLK), .Cke(1'b1), .Cs_n(1'b0),
        .Ras_n(dut.SDR_RAS), .Cas_n(dut.SDR_CAS), .We_n(dut.SDR_WE),
        .Ba(dut.SDR_BA), .Addr(dut.SDR_ADDR), .Dqm(dut.SDR_DM), .Dq(dut.SDR_DQ));

    initial begin
        if (!$value$plusargs("PROFILE=%d", profile)) profile = 0;
        if (!$value$plusargs("PHASE_DIAG=%d", phase_diag)) phase_diag = 0;
        if (!$value$plusargs("PHASE_DEGREES=%d", phase_degrees)) phase_degrees = 90;
        if (phase_diag != 0) begin
            // Explicit sensitivity experiment only. The project PLL is untouched.
            if (phase_degrees == 270) force dut.u2_ram.Sdr_clk_sft = diagnostic_shift_clock270;
            else force dut.u2_ram.Sdr_clk_sft = diagnostic_shift_clock;
            $display("DIAGNOSTIC_CLOCK_PHASE_OVERRIDE phase_deg=%0d project_PLL_unchanged=1", phase_degrees);
        end
        events = $fopen("events.csv", "w");
        $fdisplay(events, "time_ns,case,event,app_addr,data,ref_vld,manual_req,bank,physical_addr");
        force dut.App_rd_en = rd_drive;
        force dut.App_rd_addr = rd_address;
        force dut.manual_refresh_req = manual_refresh;
        // Same behavioral-model startup reset used by the earlier PLL test.
        force dut.u0_clk.reset = 1'b1;
        #200;
        release dut.u0_clk.reset;
    end

    function [31:0] pattern;
        input integer index;
        begin
            if (index < 4) pattern = (index + 1) * 32'h00000011;
            else pattern = 32'hb7e15163 ^ (index * 32'h10203041) ^ (index << 17);
        end
    endfunction

    // Expected storage contents come only from accepted upstream transfers.
    // All application transactions are sampled at the consumer's pre-NBA edge.
    always @(posedge dut.Clk) begin
        cycle = cycle + 1;
        if (!dut.Rst && dut.refresh_error) $fatal(1, "TB_FAIL refresh watchdog");
        if (!dut.Rst) begin
            if (wr_en && !full) begin
                expected[submitted] = wr_data;
                submitted = submitted + 1;
            end
            if (dut.App_wr_en) begin
                if (reading || rd_drive)
                    $fatal(1, "TB_FAIL simultaneous application read and write");
                if (app_writes >= submitted || dut.App_wr_addr !== app_writes ||
                    dut.App_wr_din !== expected[app_writes] || dut.App_wr_dm !== 4'b0000)
                    $fatal(1, "TB_FAIL app write index=%0d addr=%0d got=%h expected=%h submitted=%0d",
                           app_writes, dut.App_wr_addr, dut.App_wr_din, expected[app_writes], submitted);
                if (dut.Sdr_init_ref_vld) write_refresh_overlap = write_refresh_overlap + 1;
                $fdisplay(events, "%0.3f,%0d,APP_WRITE,%0d,%h,%b,%b,,", $realtime,
                    case_id, dut.App_wr_addr, dut.App_wr_din, dut.Sdr_init_ref_vld, manual_refresh);
                app_writes = app_writes + 1;
                app_run = app_run + 1;
                if (app_run > 4) $fatal(1, "TB_FAIL application burst longer than four words");
            end else if (app_run != 0) begin
                if (app_run != 4) $fatal(1, "TB_FAIL application burst length=%0d", app_run);
                app_run = 0;
            end
            if (dut.Sdr_rd_en) begin
                if (!reading || read_received >= read_expected)
                    $fatal(1, "TB_FAIL unexpected extra read response data=%h", dut.Sdr_rd_dout);
                $display("READ_RESULT case=%0d addr=%0d got=%h expected=%h time_ns=%0.3f",
                    case_id, read_base + read_received, dut.Sdr_rd_dout,
                    expected[read_base + read_received], $realtime);
                $fdisplay(events, "%0.3f,%0d,APP_READ_RETURN,%0d,%h,%b,%b,,", $realtime,
                    case_id, read_base + read_received, dut.Sdr_rd_dout, dut.Sdr_init_ref_vld, manual_refresh);
                if (dut.Sdr_rd_dout !== expected[read_base + read_received]) begin
                    data_errors = data_errors + 1;
                    if (profile == 0)
                        $fatal(1, "TB_FAIL readback case=%0d addr=%0d got=%h expected=%h",
                               case_id, read_base + read_received, dut.Sdr_rd_dout, expected[read_base + read_received]);
                    else
                        $display("TB_DATA_MISMATCH case=%0d addr=%0d got=%h expected=%h", case_id,
                                 read_base + read_received, dut.Sdr_rd_dout, expected[read_base + read_received]);
                end
                read_received = read_received + 1;
                total_reads = total_reads + 1;
            end
        end
        #0.001;
        if (dut.Sdr_init_done === 1'b1 && init_cycle == -1) init_cycle = cycle;
        if (dut.Sdr_init_ref_vld !== previous_refresh) begin
            $fdisplay(events, "%0.3f,%0d,REFRESH_VALID_CHANGE,,,%b,%b,,", $realtime,
                case_id, dut.Sdr_init_ref_vld, manual_refresh);
            previous_refresh = dut.Sdr_init_ref_vld;
        end
    end

    always @(posedge dut.SDRAM_CLK) begin
        if ({dut.SDR_RAS, dut.SDR_CAS, dut.SDR_WE} === 3'b011)
            physical_row[dut.SDR_BA] = dut.SDR_ADDR;
        if ({dut.SDR_RAS, dut.SDR_CAS, dut.SDR_WE} === 3'b001) begin
            physical_refreshes = physical_refreshes + 1;
            $fdisplay(events, "%0.3f,%0d,PHYSICAL_AUTO_REFRESH,,,%b,%b,%0d,%h", $realtime,
                case_id, dut.Sdr_init_ref_vld, manual_refresh, dut.SDR_BA, dut.SDR_ADDR);
        end
        if ({dut.SDR_RAS, dut.SDR_CAS, dut.SDR_WE} === 3'b100) begin
            for (physical_k = 0; physical_k < 4; physical_k = physical_k + 1) begin
                mapped_bank[physical_writes*4 + physical_k] = dut.SDR_BA;
                mapped_index[physical_writes*4 + physical_k] =
                    physical_row[dut.SDR_BA]*256 + dut.SDR_ADDR[7:0] + physical_k;
            end
            physical_writes = physical_writes + 1;
            $fdisplay(events, "%0.3f,%0d,PHYSICAL_WRITE,,%h,%b,%b,%0d,%h", $realtime,
                case_id, dut.SDR_DQ, dut.Sdr_init_ref_vld, manual_refresh, dut.SDR_BA, dut.SDR_ADDR);
        end
        if ({dut.SDR_RAS, dut.SDR_CAS, dut.SDR_WE} === 3'b101) begin
            physical_reads = physical_reads + 1;
            $fdisplay(events, "%0.3f,%0d,PHYSICAL_READ,,,%b,%b,%0d,%h", $realtime,
                case_id, dut.Sdr_init_ref_vld, manual_refresh, dut.SDR_BA, dut.SDR_ADDR);
        end
        if ({dut.SDR_RAS, dut.SDR_CAS, dut.SDR_WE} === 3'b000)
            $display("MODE_REGISTER value=%h time_ns=%0.3f", dut.SDR_ADDR, $realtime);
    end

    task idle_cycles;
        input integer amount;
        integer k;
        begin
            for (k = 0; k < amount; k = k + 1) @(negedge dut.Clk);
        end
    endtask

    task wait_quiet;
        integer watchdog;
        begin
            watchdog = 0;
            while (dut.fifo_empty !== 1'b1 || app_writes != submitted || dut.App_wr_en || dut.uut.state != 0) begin
                @(negedge dut.Clk);
                watchdog = watchdog + 1;
                if (watchdog > 2000) $fatal(1, "TB_FAIL writer did not drain submitted=%0d writes=%0d", submitted, app_writes);
            end
            idle_cycles(40);
            while (dut.Sdr_init_ref_vld !== 1'b0) @(negedge dut.Clk);
        end
    endtask

    task send_words;
        input integer count;
        integer k;
        begin
            for (k = 0; k < count; k = k + 1) begin
                @(negedge dut.Clk);
                while (full !== 1'b0) @(negedge dut.Clk);
                wr_en = 1'b1;
                wr_data = pattern(submitted);
            end
            @(negedge dut.Clk);
            wr_en = 1'b0;
            wr_data = 0;
        end
    endtask

    task read_group;
        input integer address;
        integer k, watchdog;
        reg [31:0] model_value;
        begin
            wait_quiet;
            // Diagnostic only: inspect model storage using the observed physical
            // ACT/WRITE addresses; do not assume an application address bit map.
            for (k = 0; k < 4; k = k + 1) begin
                case (mapped_bank[address+k])
                    0: model_value = dram.Bank0[mapped_index[address+k]];
                    1: model_value = dram.Bank1[mapped_index[address+k]];
                    2: model_value = dram.Bank2[mapped_index[address+k]];
                    3: model_value = dram.Bank3[mapped_index[address+k]];
                    default: model_value = 32'hxxxxxxxx;
                endcase
                storage_checks = storage_checks + 1;
                if (model_value !== expected[address+k]) begin
                    storage_errors = storage_errors + 1;
                    $display("MODEL_STORAGE_MISMATCH case=%0d app_addr=%0d bank=%0d index=%0d got=%h expected=%h",
                        case_id, address+k, mapped_bank[address+k], mapped_index[address+k], model_value, expected[address+k]);
                end
            end
            @(negedge dut.Clk);
            while (dut.refresh_pending || dut.Sdr_init_ref_vld || dut.Sdr_busy) @(negedge dut.Clk);
            reading = 1'b1;
            read_base = address;
            read_expected = 4;
            read_received = 0;
            for (k = 0; k < 4; k = k + 1) begin
                rd_drive = 1'b1;
                rd_address = address + k;
                @(negedge dut.Clk);
            end
            rd_drive = 1'b0;
            rd_address = 0;
            watchdog = 0;
            while (read_received < 4) begin
                @(negedge dut.Clk);
                watchdog = watchdog + 1;
                if (watchdog > 200) $fatal(1, "TB_FAIL missing read responses case=%0d base=%0d received=%0d",
                                          case_id, address, read_received);
            end
            idle_cycles(20);
            reading = 1'b0;
        end
    endtask

    task stream_manual_case;
        input integer beat;
        integer start, refresh_start, watchdog, errors_before, storage_before, g;
        begin
            case_id = 20 + beat;
            start = submitted;
            refresh_start = physical_refreshes;
            errors_before = data_errors;
            storage_before = storage_errors;
            $display("CASE_START stream_manual_beat_%0d base=%0d words=64", beat, start);
            fork
                send_words(64);
                begin
                    wait (dut.App_wr_en === 1'b1);
                    @(negedge dut.Clk);
                    idle_cycles(beat);
                    if (!dut.App_wr_en || dut.App_wr_addr !== start + beat)
                        $fatal(1, "TB_FAIL wrong stream injection phase");
                    manual_refresh = 1'b1;
                    $fdisplay(events, "%0.3f,%0d,MANUAL_REFRESH_REQUEST,%0d,,%b,1,,", $realtime,
                        case_id, dut.App_wr_addr, dut.Sdr_init_ref_vld);
                    @(negedge dut.Clk);
                    manual_refresh = 1'b0;
                end
            join
            wait_quiet;
            if (physical_refreshes == refresh_start) begin
                coverage_errors = coverage_errors + 1;
                $display("COVERAGE_MISS stream manual request did not refresh beat=%0d", beat);
            end
            for (g = start; g < start + 64; g = g + 4) read_group(g);
            completed_cases = completed_cases + 1;
            $display("CASE_RESULT stream_manual_beat_%0d refreshes=%0d storage_errors=%0d read_errors=%0d", beat,
                physical_refreshes-refresh_start, storage_errors-storage_before, data_errors-errors_before);
        end
    endtask

    task refresh_blocks_start_case;
        integer start, errors_before, storage_before;
        begin
            case_id = 30;
            start = submitted;
            errors_before = data_errors;
            storage_before = storage_errors;
            $display("CASE_START supply_during_real_refresh base=%0d", start);
            wait (dut.Sdr_init_ref_vld === 1'b1);
            fork
                send_words(4);
                begin
                    while (dut.Sdr_init_ref_vld === 1'b1) begin
                        @(posedge dut.Clk);
                        if (dut.Sdr_init_ref_vld && dut.App_wr_en)
                            $fatal(1, "TB_FAIL new group started while real refresh already active");
                    end
                end
            join
            wait_quiet;
            read_group(start);
            completed_cases = completed_cases + 1;
            $display("CASE_RESULT supply_during_real_refresh storage_errors=%0d read_errors=%0d",
                storage_errors-storage_before, data_errors-errors_before);
        end
    endtask

    task natural_stream_case;
        integer start, refresh_start, after_writes, errors_before, storage_before, g;
        begin
            case_id = 40;
            start = submitted;
            refresh_start = physical_refreshes;
            errors_before = data_errors;
            storage_before = storage_errors;
            $display("CASE_START natural_refresh_stream base=%0d words=4096", start);
            send_words(4096);
            wait_quiet;
            after_writes = physical_refreshes;
            if (after_writes-refresh_start < 2) begin
                coverage_errors = coverage_errors + 1;
                $display("COVERAGE_MISS natural stream covered fewer than two physical refreshes");
            end
            for (g = start; g < start+4096; g = g+4) read_group(g);
            completed_cases = completed_cases + 1;
            $display("CASE_RESULT natural_refresh_stream write_phase_refreshes=%0d total_refreshes=%0d storage_errors=%0d read_errors=%0d",
                after_writes-refresh_start, physical_refreshes-refresh_start, storage_errors-storage_before, data_errors-errors_before);
        end
    endtask

    task manual_case;
        input integer beat;
        integer start, refresh_start, watchdog, errors_before;
        begin
            case_id = 10 + beat;
            start = submitted;
            refresh_start = physical_refreshes;
            errors_before = data_errors;
            $display("CASE_START manual_request_beat_%0d base=%0d", beat, start);
            fork
                send_words(4);
                begin
                    wait (dut.App_wr_en === 1'b1);
                    @(negedge dut.Clk);
                    idle_cycles(beat);
                    if (!dut.App_wr_en || dut.App_wr_addr !== start + beat)
                        $fatal(1, "TB_FAIL wrong injection phase beat=%0d addr=%0d", beat, dut.App_wr_addr);
                    manual_refresh = 1'b1;
                    $fdisplay(events, "%0.3f,%0d,MANUAL_REFRESH_REQUEST,%0d,,%b,1,,", $realtime,
                        case_id, dut.App_wr_addr, dut.Sdr_init_ref_vld);
                    @(negedge dut.Clk);
                    manual_refresh = 1'b0;
                end
            join
            wait_quiet;
            watchdog = 0;
            while (physical_refreshes == refresh_start && watchdog <= 100) begin
                @(negedge dut.Clk);
                watchdog = watchdog + 1;
            end
            if (physical_refreshes == refresh_start) begin
                coverage_errors = coverage_errors + 1;
                $display("COVERAGE_MISS no physical refresh after manual request beat=%0d", beat);
            end
            read_group(start);
            completed_cases = completed_cases + 1;
            $display("CASE_RESULT manual_request_beat_%0d physical_refresh_delta=%0d read_errors=%0d", beat,
                     physical_refreshes-refresh_start, data_errors-errors_before);
        end
    endtask

    initial begin
        wait (dut.lock === 1'b1);
        wait (dut.Sdr_init_done === 1'b1 && dut.Sdr_init_ref_vld === 1'b0);
        idle_cycles(8);
        $display("INITIALIZED time_ns=%0.3f mode=%h profile=%0d", $realtime, dram.Mode_reg, profile);
        if (dram.Mode_reg !== 11'h032)
            $fatal(1, "TB_SETUP_FAIL SDRAM model mode register was not programmed as BL4 CL3");
        $dumpfile("functional.vcd");
        $dumpvars(0, dut.Clk, dut.SDRAM_CLK, dut.Sdr_init_done, dut.Sdr_init_ref_vld,
            dut.App_wr_en, dut.App_wr_addr, dut.App_wr_din, dut.App_rd_en, dut.App_rd_addr,
            dut.Sdr_rd_en, dut.Sdr_rd_dout, dut.SDR_RAS, dut.SDR_CAS, dut.SDR_WE,
            dut.SDR_BA, dut.SDR_ADDR, dut.SDR_DM, dut.SDR_DQ, manual_refresh, case_id);
        case_id = 1;
        $display("CASE_START baseline_four_words");
        send_words(4);
        wait_quiet;
        read_group(0);
        completed_cases = completed_cases + 1;
        $display("CASE_RESULT baseline_four_words read_errors=%0d", data_errors);
        if (profile >= 1) begin
            for (phase = 0; phase < 4; phase = phase + 1) manual_case(phase);
        end
        if (profile >= 2) begin
            for (phase = 0; phase < 4; phase = phase + 1) stream_manual_case(phase);
            refresh_blocks_start_case;
            natural_stream_case;
        end
        $display("SUITE_EXECUTED cases=%0d accepted=%0d app_writes=%0d reads=%0d physical_writes=%0d physical_reads=%0d physical_refreshes=%0d write_refresh_overlap=%0d data_errors=%0d storage_checks=%0d storage_errors=%0d coverage_errors=%0d time_ns=%0.3f",
            completed_cases, submitted, app_writes, total_reads, physical_writes, physical_reads,
            physical_refreshes, write_refresh_overlap, data_errors, storage_checks, storage_errors, coverage_errors, $realtime);
        if (data_errors == 0 && storage_errors == 0 && coverage_errors == 0) $display("FUNCTIONAL_SUITE_PASS");
        else $display("FUNCTIONAL_SUITE_FAIL");
        suite_done = 1'b1;
        $dumpflush;
        $dumpoff;
    end

    initial begin
        #1900000;
        if (!suite_done) $fatal(1, "TB_FAIL suite timeout lock=%b init=%b submitted=%0d writes=%0d reads=%0d",
            dut.lock, dut.Sdr_init_done, submitted, app_writes, total_reads);
    end
endmodule
