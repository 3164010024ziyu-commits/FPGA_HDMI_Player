module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input                       wr_clk,
    input                       rd_clk,
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

//用寄存器来保存空满，以防止出现组合环路
reg full_reg;
reg empty_reg;

assign full  = full_reg;
assign empty = empty_reg;

reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];
reg [ADDR_WIDTH:0]wr_bin_ptr;
reg [ADDR_WIDTH:0]rd_bin_ptr;
reg [ADDR_WIDTH:0]wr_gray_ptr;
reg [ADDR_WIDTH:0]rd_gray_ptr;

wire wr_fire;
wire rd_fire;

assign wr_fire = wr_en&&(!full);
assign rd_fire = rd_en&&(!empty);


wire [ADDR_WIDTH:0] wr_bin_next;
wire [ADDR_WIDTH:0] rd_bin_next;

assign wr_bin_next = wr_bin_ptr + wr_fire;
assign rd_bin_next = rd_bin_ptr + rd_fire;

wire [ADDR_WIDTH:0] wr_gray_next;
wire [ADDR_WIDTH:0] rd_gray_next;

assign wr_gray_next = wr_bin_next^(wr_bin_next>>1);
assign rd_gray_next = rd_bin_next^(rd_bin_next>>1);

always @(posedge wr_clk or negedge Reset_n) begin
    if(!Reset_n) begin
        wr_bin_ptr  <= 0;
        wr_gray_ptr <= 0;
    end
    else begin
        wr_bin_ptr  <= wr_bin_next;
        wr_gray_ptr <= wr_gray_next;
    end
end

always @(posedge rd_clk or negedge Reset_n) begin
    if(!Reset_n) begin
        rd_bin_ptr  <= 0;
        rd_gray_ptr <= 0;
    end
    else begin
        rd_bin_ptr  <= rd_bin_next;
        rd_gray_ptr <= rd_gray_next;
    end
end

//两级同步
reg [ADDR_WIDTH:0] wr_gray_sync1;
reg [ADDR_WIDTH:0] wr_gray_sync2;

reg [ADDR_WIDTH:0] rd_gray_sync1;
reg [ADDR_WIDTH:0] rd_gray_sync2;

always @(posedge rd_clk or negedge Reset_n) begin
    if (!Reset_n) begin
        wr_gray_sync1 <= 0;
        wr_gray_sync2 <= 0;
    end
    else begin
        wr_gray_sync1 <= wr_gray_ptr;
        wr_gray_sync2 <= wr_gray_sync1;
    end
end

always @(posedge wr_clk or negedge Reset_n) begin
    if (!Reset_n) begin
        rd_gray_sync1 <= 0;
        rd_gray_sync2 <= 0;
    end
    else begin
        rd_gray_sync1 <= rd_gray_ptr;
        rd_gray_sync2 <= rd_gray_sync1;
    end
end

//满空逻辑
wire full_next;
wire empty_next;

assign empty_next = (rd_gray_next == wr_gray_sync2);
assign full_next = (wr_gray_next == {~rd_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1],rd_gray_sync2[ADDR_WIDTH-2:0]});

always @(posedge wr_clk or negedge Reset_n) begin
    if (!Reset_n) begin
        full_reg <= 0;
    end
    else begin
        full_reg <= full_next;
    end
end

always @(posedge rd_clk or negedge Reset_n) begin
    if (!Reset_n) begin
        empty_reg <= 1;
    end
    else begin
        empty_reg <= empty_next;
    end
end

always @(posedge rd_clk or negedge Reset_n) begin
    if(!Reset_n)
        rd_data <= 0;
    else if(rd_fire)
        rd_data <= mem[rd_bin_ptr[ADDR_WIDTH-1:0]];
    else
        rd_data <= rd_data;

end

always @(posedge wr_clk) begin
    if(Reset_n && wr_fire)
        mem[wr_bin_ptr[ADDR_WIDTH-1:0]] <= wr_data;
end

always @(posedge rd_clk or negedge Reset_n) begin
    if(!Reset_n)
        rd_valid <= 0;
    else if(rd_fire)
        rd_valid <= 1;
    else
        rd_valid <= 0;

end

endmodule