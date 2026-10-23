`timescale 1ns/1ps

// Integration simulation only. Original project RTL is instantiated unchanged.
module sdram_fifo_integration_tb;
  reg Clk = 1'b0;
  always #5 Clk = ~Clk;
  reg Reset_n = 1'b0;
  reg Sdr_init_done = 1'b0;
  reg Sdr_init_ref_vld = 1'b0;
  reg wr_en = 1'b0;
  reg [31:0] wr_data = 32'b0;
  wire full;
  wire fifo_rd_en;
  wire [31:0] fifo_rd_data;
  wire fifo_rd_valid;
  wire fifo_empty;
  wire App_wr_en;
  wire [20:0] App_wr_addr;
  wire [31:0] App_wr_din;
  wire [3:0] App_wr_dm;

  integer produced = 0;
  integer requested = 0;
  integer received = 0;
  integer written = 0;
  integer mid_refresh_writes = 0;
  integer burst_count = 0;
  integer run_length = 0;
  reg prev_wr_en = 1'b0;
  reg permit_refresh_overlap = 1'b0;

  sync_fifo #(.DATA_WIDTH(32), .ADDR_WIDTH(4)) input_fifo (
    .Clk(Clk), .Reset_n(Reset_n),
    .wr_en(wr_en), .wr_data(wr_data), .full(full),
    .rd_en(fifo_rd_en), .rd_data(fifo_rd_data),
    .rd_valid(fifo_rd_valid), .empty(fifo_empty)
  );
  sdram_write_ctrl dut (
    .Clk(Clk), .Reset_n(Reset_n),
    .Sdr_init_done(Sdr_init_done),
    .Sdr_init_ref_vld(Sdr_init_ref_vld),
    .fifo_rd_data(fifo_rd_data), .fifo_rd_valid(fifo_rd_valid),
    .fifo_empty(fifo_empty), .fifo_rd_en(fifo_rd_en),
    .App_wr_en(App_wr_en), .App_wr_addr(App_wr_addr),
    .App_wr_din(App_wr_din), .App_wr_dm(App_wr_dm)
  );

  function [31:0] expected_word;
    input integer index;
    begin
      expected_word = 32'hA5000000 ^ (32'h00010203 * index) ^ (index << 16);
    end
  endfunction

  // Sample the signals consumed by each block at the active clock edge,
  // before nonblocking assignments update registered outputs.
  always @(posedge Clk) begin
    if (Reset_n) begin
      if (wr_en && !full) produced = produced + 1;
      if (fifo_rd_en) begin
        if (fifo_empty !== 1'b0)
          $fatal(1, "INTEGRATION_FAIL: FIFO read request while empty/unknown");
        requested = requested + 1;
      end
      if (fifo_rd_valid) begin
        if (fifo_rd_data !== expected_word(received))
          $fatal(1, "INTEGRATION_FAIL: FIFO delivery %0d data=%08h expected=%08h",
                 received, fifo_rd_data, expected_word(received));
        received = received + 1;
      end
      if (App_wr_en === 1'b1) begin
        if (Sdr_init_done !== 1'b1)
          $fatal(1, "INTEGRATION_FAIL: write before initialization");
        if (Sdr_init_ref_vld && !prev_wr_en)
          $fatal(1, "INTEGRATION_FAIL: burst began during refresh flag");
        if (Sdr_init_ref_vld && !permit_refresh_overlap)
          $fatal(1, "INTEGRATION_FAIL: unexpected refresh/write overlap");
        if (App_wr_addr !== written[20:0])
          $fatal(1, "INTEGRATION_FAIL: write %0d address=%0d", written, App_wr_addr);
        if (App_wr_din !== expected_word(written))
          $fatal(1, "INTEGRATION_FAIL: write %0d data=%08h expected=%08h",
                 written, App_wr_din, expected_word(written));
        if (App_wr_dm !== 4'b0000)
          $fatal(1, "INTEGRATION_FAIL: unexpected byte mask");
        if (!prev_wr_en) begin
          burst_count = burst_count + 1;
          run_length = 0;
        end
        run_length = run_length + 1;
        if (run_length > 4)
          $fatal(1, "INTEGRATION_FAIL: burst exceeds four writes");
        if (Sdr_init_ref_vld) mid_refresh_writes = mid_refresh_writes + 1;
        $display("INTEGRATION_WRITE t=%0t word=%0d addr=%0d data=%08h refresh=%0b",
                 $time, written, App_wr_addr, App_wr_din, Sdr_init_ref_vld);
        written = written + 1;
      end else if (App_wr_en !== 1'b0) begin
        $fatal(1, "INTEGRATION_FAIL: unknown write enable");
      end else if (prev_wr_en && run_length != 4) begin
        $fatal(1, "INTEGRATION_FAIL: burst ended after %0d writes", run_length);
      end
      prev_wr_en = App_wr_en;
    end
  end

  task push_words;
    input integer count;
    integer k;
    begin
      for (k = 0; k < count; k = k + 1) begin
        @(negedge Clk);
        while (full) @(negedge Clk);
        wr_en = 1'b1;
        wr_data = expected_word(produced);
      end
      @(negedge Clk);
      wr_en = 1'b0;
    end
  endtask

  task hold_and_check_writes;
    input integer cycles;
    input integer expected_count;
    integer k;
    begin
      for (k = 0; k < cycles; k = k + 1) begin
        @(negedge Clk);
        if (written != expected_count)
          $fatal(1, "INTEGRATION_FAIL: expected writes=%0d, actual=%0d",
                 expected_count, written);
      end
    end
  endtask

  task wait_writes;
    input integer expected_count;
    integer timeout_cycles;
    begin
      timeout_cycles = 0;
      while (written < expected_count && timeout_cycles < 200) begin
        @(negedge Clk);
        timeout_cycles = timeout_cycles + 1;
      end
      if (written != expected_count)
        $fatal(1, "INTEGRATION_FAIL: timeout/extra writes, expected=%0d actual=%0d",
               expected_count, written);
    end
  endtask

  initial begin
    $dumpfile("integration.vcd");
    $dumpvars(0, sdram_fifo_integration_tb);
    repeat (4) @(negedge Clk);
    Reset_n = 1'b1;

    // Real FIFO can be prefetched, but initialization must block SDRAM output.
    push_words(8);
    hold_and_check_writes(16, 0);
    if (requested != 4 || received != 4)
      $fatal(1, "INTEGRATION_FAIL: initialization prefetch req=%0d recv=%0d",
             requested, received);
    $display("INTEGRATION_CHECK: initialization gate held after four real FIFO deliveries");

    Sdr_init_ref_vld = 1'b1;
    Sdr_init_done = 1'b1;
    hold_and_check_writes(12, 0);
    $display("INTEGRATION_CHECK: refresh before burst blocked all writes");
    Sdr_init_ref_vld = 1'b0;
    wait_writes(8);
    hold_and_check_writes(10, 8);

    // A partial group remains buffered across an empty FIFO interval.
    push_words(2);
    hold_and_check_writes(16, 8);
    if (requested != 10 || received != 10 || fifo_empty !== 1'b1)
      $fatal(1, "INTEGRATION_FAIL: partial group req=%0d recv=%0d empty=%0b",
             requested, received, fifo_empty);
    $display("INTEGRATION_CHECK: two-word starvation gap held data without partial burst");
    push_words(2);
    wait_writes(12);
    hold_and_check_writes(8, 12);

    // Probe documented behavior only: refresh gates burst entry, while an
    // already-started four-word burst continues. No SDRAM contract is assumed.
    push_words(4);
    wait_writes(13);
    permit_refresh_overlap = 1'b1;
    Sdr_init_ref_vld = 1'b1;
    wait_writes(16);
    if (mid_refresh_writes != 3)
      $fatal(1, "INTEGRATION_FAIL: expected three remaining probe writes, actual=%0d",
             mid_refresh_writes);
    $display("INTEGRATION_INFO: mid-burst refresh flag overlaps remaining three writes; interface arbitration is not modeled");
    push_words(4);
    hold_and_check_writes(16, 16);
    if (requested != 20 || received != 20)
      $fatal(1, "INTEGRATION_FAIL: next group prefetch req=%0d recv=%0d", requested, received);
    Sdr_init_ref_vld = 1'b0;
    permit_refresh_overlap = 1'b0;
    wait_writes(20);
    hold_and_check_writes(12, 20);
    if (produced != 20 || requested != 20 || received != 20 || burst_count != 5)
      $fatal(1, "INTEGRATION_FAIL: totals produced=%0d req=%0d recv=%0d writes=%0d bursts=%0d",
             produced, requested, received, written, burst_count);
    if (fifo_empty !== 1'b1)
      $fatal(1, "INTEGRATION_FAIL: input FIFO not empty at end");
    $display("INTEGRATION_PASS: real sync_fifo -> sdram_write_ctrl; 20 ordered words, 5 four-cycle bursts, addresses 0..19, dm=0, init/refresh start gates, starvation, refresh probe overlap=3");
    $finish;
  end

  initial begin
    #20000;
    $fatal(1, "INTEGRATION_FAIL: global timeout");
  end
endmodule
