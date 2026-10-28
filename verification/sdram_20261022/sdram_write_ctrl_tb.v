`timescale 1ns/1ps

// Independent testbench; the project RTL is compiled without modification.
// The application interface is assumed to accept all four beats of a started
// burst. Actual SDRAM command timing/refresh arbitration is outside this model.
module sdram_write_ctrl_tb;
    reg Clk = 0;
    always #5 Clk = ~Clk;

    reg Reset_n = 0;
    reg Sdr_init_done = 1;
    reg Sdr_init_ref_vld = 0;
    wire [31:0] fifo_rd_data;
    wire fifo_rd_valid;
    wire fifo_empty;
    wire fifo_rd_en;
    wire App_wr_en;
    wire [20:0] App_wr_addr;
    wire [31:0] App_wr_din;
    wire [3:0] App_wr_dm;

    sdram_write_ctrl dut (
        .Clk(Clk), .Reset_n(Reset_n),
        .Sdr_init_done(Sdr_init_done),
        .Sdr_init_ref_vld(Sdr_init_ref_vld),
        .fifo_rd_data(fifo_rd_data), .fifo_rd_valid(fifo_rd_valid),
        .fifo_empty(fifo_empty), .fifo_rd_en(fifo_rd_en),
        .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr),
        .App_wr_din(App_wr_din), .App_wr_dm(App_wr_dm)
    );

    integer epoch = 0;
    integer available_words = 0;
    integer read_latency = 1;
    reg stall_fifo = 0;
    integer request_count = 0;
    integer response_count = 0;
    integer write_count = 0;
    integer clock_count = 0;
    integer last_write_cycle = -1;
    integer pass_count = 0;
    integer total_writes = 0;
    integer pipe_index;
    reg [7:0] response_valid_pipe = 0;
    reg [31:0] response_data_pipe [0:7];

    function [31:0] source_word;
        input integer epoch_value;
        input integer word_index;
        begin
            source_word = 32'h5a000000 ^ (epoch_value * 32'h00010000)
                          ^ (word_index * 32'h00001021);
        end
    endfunction

    assign fifo_empty = stall_fifo || (request_count >= available_words);
    assign fifo_rd_valid = response_valid_pipe[read_latency - 1];
    assign fifo_rd_data = response_data_pipe[read_latency - 1];

    // Latency 1 matches the existing registered-output sync_fifo interface.
    // Other latencies test that rd_valid, rather than a fixed delay, is used.
    always @(posedge Clk or negedge Reset_n) begin
        if (!Reset_n) begin
            request_count <= 0;
            response_valid_pipe <= 0;
            for (pipe_index = 0; pipe_index < 8; pipe_index = pipe_index + 1)
                response_data_pipe[pipe_index] <= 0;
        end else begin
            for (pipe_index = 7; pipe_index > 0; pipe_index = pipe_index - 1) begin
                response_valid_pipe[pipe_index] <= response_valid_pipe[pipe_index-1];
                response_data_pipe[pipe_index] <= response_data_pipe[pipe_index-1];
            end
            response_valid_pipe[0] <= fifo_rd_en && !fifo_empty;
            if (fifo_rd_en && !fifo_empty) begin
                response_data_pipe[0] <= source_word(epoch, request_count);
                request_count <= request_count + 1;
            end
        end
    end

    // Sample at the same rising edge a downstream synchronous receiver uses.
    always @(posedge Clk or negedge Reset_n) begin
        if (!Reset_n) begin
            response_count = 0;
            write_count = 0;
            clock_count = 0;
            last_write_cycle = -1;
        end else begin
            clock_count = clock_count + 1;
            if ((^{fifo_rd_en, App_wr_en, fifo_empty, fifo_rd_valid}) === 1'bx)
                $fatal(1, "FAIL: unknown control output rd_en=%b wr_en=%b empty=%b valid=%b",
                       fifo_rd_en, App_wr_en, fifo_empty, fifo_rd_valid);
            if (fifo_rd_en && fifo_empty)
                $fatal(1, "FAIL: FIFO read requested while empty");
            if (fifo_rd_valid)
                response_count = response_count + 1;
            if (App_wr_en) begin
                if (!Sdr_init_done || (Sdr_init_ref_vld && write_count % 4 == 0))
                    $fatal(1, "FAIL: write before initialization or burst started during refresh");
                if (write_count >= response_count)
                    $fatal(1, "FAIL: write without returned FIFO data");
                if (App_wr_addr !== write_count[20:0])
                    $fatal(1, "FAIL: address actual=%0d expected=%0d", App_wr_addr, write_count);
                if (App_wr_din !== source_word(epoch, write_count))
                    $fatal(1, "FAIL: data index=%0d actual=%08h expected=%08h",
                           write_count, App_wr_din, source_word(epoch, write_count));
                if (App_wr_dm !== 4'b0000)
                    $fatal(1, "FAIL: unexpected byte mask");
                if ((write_count % 4 != 0) && (clock_count != last_write_cycle + 1))
                    $fatal(1, "FAIL: gap inside four-word burst");
                last_write_cycle = clock_count;
                write_count = write_count + 1;
                total_writes = total_writes + 1;
            end
        end
    end

    task step;
        input integer cycles;
        begin
            repeat (cycles) @(negedge Clk);
        end
    endtask

    // Called at a falling edge; all stimulus changes avoid DUT sampling edges.
    task reset_case;
        input integer next_epoch;
        input integer latency;
        begin
            Reset_n = 0;
            available_words = 0;
            stall_fifo = 0;
            Sdr_init_done = 1;
            Sdr_init_ref_vld = 0;
            epoch = next_epoch;
            read_latency = latency;
            step(3);
            Reset_n = 1;
            step(2);
        end
    endtask

    task wait_requests;
        input integer target;
        input integer limit;
        integer cycles;
        begin
            cycles = 0;
            while (request_count < target && cycles < limit) begin
                step(1);
                cycles = cycles + 1;
            end
            if (request_count != target)
                $fatal(1, "FAIL: request timeout/overrun actual=%0d target=%0d", request_count, target);
        end
    endtask

    task wait_writes;
        input integer target;
        input integer limit;
        integer cycles;
        begin
            cycles = 0;
            while (write_count < target && cycles < limit) begin
                step(1);
                cycles = cycles + 1;
            end
            if (write_count != target)
                $fatal(1, "FAIL: write timeout/overrun actual=%0d target=%0d", write_count, target);
        end
    endtask

    task check_idle;
        input integer expected_count;
        begin
            step(6);
            if (request_count != expected_count || response_count != expected_count ||
                write_count != expected_count || App_wr_en !== 1'b0 || fifo_rd_en !== 1'b0)
                $fatal(1, "FAIL: final counts/read/write enable mismatch req=%0d resp=%0d wr=%0d",
                       request_count, response_count, write_count);
        end
    endtask

    task passed;
        input [639:0] name;
        begin
            pass_count = pass_count + 1;
            $display("CASE_PASS %0d: %0s (req=%0d resp=%0d writes=%0d)",
                     pass_count, name, request_count, response_count, write_count);
        end
    endtask

    integer stress_cycle;
    initial begin
        $dumpfile("sdram_write_ctrl.vcd");
        $dumpvars(0, sdram_write_ctrl_tb);
        @(negedge Clk);

        reset_case(1, 1);
        check_idle(0);
        if (dut.write_base_addr !== 21'd0)
            $fatal(1, "FAIL: reset address is not zero");
        passed("reset and empty FIFO stay idle");

        reset_case(2, 1);
        available_words = 4;
        wait_writes(4, 80);
        check_idle(4);
        if (dut.write_base_addr !== 21'd4)
            $fatal(1, "FAIL: base address does not advance by four");
        passed("one four-word burst, data/mask/address and base increment");

        reset_case(3, 1);
        available_words = 12;
        wait_writes(12, 160);
        check_idle(12);
        passed("three successive bursts, addresses 0 through 11");

        reset_case(4, 1);
        Sdr_init_done = 0;
        available_words = 4;
        wait_requests(4, 30);
        step(12);
        if (write_count != 0 || request_count != 4 || response_count != 4)
            $fatal(1, "FAIL: initialization gate/prefetch count");
        Sdr_init_done = 1;
        wait_writes(4, 40);
        check_idle(4);
        passed("prefetch allowed but write waits for initialization");

        reset_case(5, 1);
        Sdr_init_ref_vld = 1;
        available_words = 4;
        wait_requests(4, 30);
        step(12);
        if (write_count != 0 || request_count != 4 || response_count != 4)
            $fatal(1, "FAIL: refresh gate/prefetch count");
        Sdr_init_ref_vld = 0;
        wait_writes(4, 40);
        check_idle(4);
        passed("refresh before burst blocks writing until released");

        reset_case(6, 1);
        available_words = 2;
        step(20);
        if (request_count != 2 || response_count != 2 || write_count != 0)
            $fatal(1, "FAIL: partial prefetch must wait for four words");
        available_words = 4;
        wait_writes(4, 50);
        check_idle(4);
        passed("two-word starvation, then resume to complete burst");

        reset_case(7, 1);
        available_words = 4;
        stall_fifo = 1;
        step(8);
        if (request_count != 0) $fatal(1, "FAIL: read during forced empty");
        stall_fifo = 0;
        wait_requests(2, 20);
        stall_fifo = 1;
        step(10);
        if (request_count != 2 || write_count != 0)
            $fatal(1, "FAIL: FIFO empty gap handling");
        stall_fifo = 0;
        wait_writes(4, 50);
        check_idle(4);
        passed("FIFO empty gaps suppress requests and preserve data");

        reset_case(8, 4);
        available_words = 8;
        wait_writes(8, 160);
        check_idle(8);
        passed("four-cycle FIFO response latency and eight ordered writes");

        reset_case(9, 4);
        available_words = 2;
        wait_requests(2, 20);
        reset_case(10, 1);
        available_words = 4;
        wait_writes(4, 80);
        check_idle(4);
        passed("shared FIFO/controller reset during prefetch restarts cleanly");

        reset_case(11, 1);
        available_words = 8;
        wait_writes(2, 80);
        if (App_wr_en !== 1'b1)
            $fatal(1, "FAIL: reset stimulus did not interrupt active burst");
        reset_case(12, 1);
        available_words = 4;
        wait_writes(4, 80);
        check_idle(4);
        passed("reset during writing restarts data and address at zero");

        reset_case(13, 3);
        stress_cycle = 0;
        while (write_count < 256 && stress_cycle < 4000) begin
            if ((stress_cycle % 3 == 0) && available_words < 256)
                available_words = available_words + 1;
            stall_fifo = ((stress_cycle % 13 == 4) || (stress_cycle % 13 == 5));
            step(1);
            stress_cycle = stress_cycle + 1;
        end
        stall_fifo = 0;
        if (write_count != 256) $fatal(1, "FAIL: sustained traffic timeout");
        check_idle(256);
        passed("64 bursts with intermittent supply and delayed responses");

        if (pass_count != 11) $fatal(1, "FAIL: incomplete test suite");
        $display("SUITE_PASS cases=%0d total_checked_writes=%0d time_ns=%0d",
                 pass_count, total_writes, $time);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "FAIL: global simulation timeout");
    end
endmodule
