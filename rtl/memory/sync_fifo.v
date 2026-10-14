module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input                       Clk,
    input                       Reset_n,

    // Write interface
    input                       wr_en,
    input  [DATA_WIDTH-1:0]     wr_data,
    output                      full,

    // Read interface
    input                       rd_en,
    output reg [DATA_WIDTH-1:0] rd_data,
    output reg                  rd_valid,
    output                      empty
);

reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
reg [ADDR_WIDTH:0]wr_ptr;
reg [ADDR_WIDTH:0]rd_ptr;

wire wr_fire;
wire rd_fire;

assign full = ((wr_ptr[ADDR_WIDTH]!=rd_ptr[ADDR_WIDTH])&&(wr_ptr[ADDR_WIDTH-1:0]==rd_ptr[ADDR_WIDTH-1:0]));
assign empty = (wr_ptr==rd_ptr);
assign wr_fire = wr_en&&(!full);
assign rd_fire = rd_en&&(!empty);

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        wr_ptr <= 0;
    else if(wr_fire)
        wr_ptr <= wr_ptr + 1;
    else
        wr_ptr <= wr_ptr;

end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        rd_ptr <= 0;
    else if(rd_fire)
        rd_ptr <= rd_ptr + 1;
    else
        rd_ptr <= rd_ptr;

end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        rd_data <= 0;
    else if(rd_fire)
        rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
    else
        rd_data <= rd_data;

end

always @(posedge Clk) begin
    if(Reset_n && wr_fire)
        mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        rd_valid <= 0;
    else if(rd_fire)
        rd_valid <= 1;
    else
        rd_valid <= 0;

end


endmodule
