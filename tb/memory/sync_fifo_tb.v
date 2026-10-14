`timescale 1ns/1ps

module sync_fifo_tb();

localparam DATA_WIDTH = 8;
localparam ADDR_WIDTH = 4;

    reg                       Clk;
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



sync_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) dut (
    .Clk(Clk),
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

initial Clk = 1;
always #10 Clk = ~Clk;

// initial begin
//     Reset_n = 0;
//     wr_en = 0;
//     rd_en = 0;
//     wr_data = 0;
//     #201;
//     Reset_n <= 1;

//     #199;

//     rd_en <= 1;
//     #20;

//     rd_en <= 0;
//     wr_en <= 1;
//     wr_data <= 8'b11111111;
//     #320;

//     wr_en <= 1;
//     wr_data <= 8'b11111111;
//     #20;

//     rd_en <= 1;
//     wr_en <= 1;
//     wr_data <= 8'b11111111;
//     #20;

//     rd_en <= 0;
//     wr_en <= 0;
//     #20;

//     $stop;



// end

initial begin
    Reset_n = 0;
    wr_en = 0;
    rd_en = 0;
    wr_data = 0;
    #201;
    Reset_n <= 1;

    #199;


    wr_en <= 1;
    wr_data <= 8'h11;
    #20;

    wr_en <= 1;
    wr_data <= 8'h22;
    #20;

    wr_en <= 1;
    wr_data <= 8'h33;
    #20;

    wr_en <= 0;

    rd_en <= 1;
    #60;

    rd_en <= 0;
    #21;



    $stop;



end



endmodule