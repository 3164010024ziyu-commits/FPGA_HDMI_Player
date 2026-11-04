`timescale 1ns/1ps

module async_fifo_tb;

localparam DATA_WIDTH = 8;
localparam ADDR_WIDTH = 4;

    reg wr_clk;
    reg rd_clk;

    reg                       Reset_n;

    // Write interface
    reg                       wr_en;
    reg  [DATA_WIDTH-1:0]     wr_data;
    wire                      full;

    // Read interface
    reg                       rd_en;
    wire [DATA_WIDTH-1:0] rd_data;
    wire                  rd_valid;
    wire                      empty;



async_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) dut (
    .wr_clk(wr_clk),
    .rd_clk(rd_clk),
    .Reset_n(Reset_n),

    // Write interface
    .wr_en(wr_en),
    .wr_data(wr_data),
    .full(full),

    // Read interface
    .rd_en(rd_en),
    .rd_data(rd_data),
    .rd_valid(rd_valid),
    .empty(empty)
);

    initial wr_clk = 0;
    always #10 wr_clk = ~wr_clk;       // 50 MHz

    initial rd_clk = 0;
    always #12.5 rd_clk = ~rd_clk;     // 40 MHz

    initial begin
        Reset_n = 0;
        wr_en = 0;
        rd_en = 0;
        wr_data = 8'h00;
        #100;
        Reset_n = 1;
        // full stays high until the write-clock reset release is complete.
        wait(!full);
        @(negedge wr_clk);
        wr_data = 8'h11;
        wr_en = 1;
        #20;
        wr_en = 0;
        #20;
        wr_data = 8'h22;
        wr_en = 1;
        #20;
        wr_en = 0;
        #20;
        wr_data = 8'h33;
        wr_en = 1;
        #20;
        wr_en = 0;
        #20;
        wr_data = 8'h44;
        wr_en = 1;
        #20;
        wr_en = 0;
        #20;
        // 在读时钟下降沿发出读请求
        @(negedge rd_clk);
        rd_en = 1'b1;

        // 连续读取 4 个数据
        repeat(4) @(negedge rd_clk);
        rd_en = 1'b0;

        // 再观察几个读时钟周期
        repeat(4) @(posedge rd_clk);
        #1;
        $stop;
    end
endmodule