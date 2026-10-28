module frame_desc_cdc (
    // 50 MHz 时钟域
    input  wire        src_clk,
    input  wire        src_rst_n,

    input  wire        src_valid,   //50 MHz 侧提出一份新帧描述
    output wire        src_ready,   //CDC 模块能够接受下一份描述

    input  wire [20:0] src_base_addr,
    input  wire [15:0] src_width,
    input  wire [15:0] src_height,
    input  wire        src_top_down,

    // 125 MHz 时钟域
    input  wire        dst_clk,
    input  wire        dst_rst_n,

    output reg         dst_valid,
    output reg  [20:0] dst_base_addr,
    output reg  [15:0] dst_width,
    output reg  [15:0] dst_height,
    output reg         dst_top_down

    input frame_write_done;
    output reg frame_write_done_sync;
);

wire src_fire;
assign src_fire = src_valid & src_ready;
reg req_toggle;
reg ack_toggle;
wire ack_sync;
assign src_ready = (req_toggle == ack_sync);

reg [20:0]base_addr_reg;
reg [15:0]width_reg;
reg [15:0]height_reg;
reg top_down_reg;

always @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
        req_toggle    <= 0;
        base_addr_reg <= 0;
        width_reg     <= 0;
        height_reg    <= 0;
        top_down_reg  <= 0;
    end
    else if (src_fire) begin
        base_addr_reg <= src_base_addr;
        width_reg     <= src_width;
        height_reg    <= src_height;
        top_down_reg  <= src_top_down;
        req_toggle <= ~req_toggle;
    end
end

//将req_toggle同步到125MHz侧
reg req_sync0;
reg req_sync1;

always @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
        req_sync0 <= 1'b0;
        req_sync1 <= 1'b0;
    end
    else begin
        req_sync0 <= req_toggle;
        req_sync1 <= req_sync0;
    end
end

wire req_sync = req_sync1;

//收到发送帧描述后，接收帧描述并发送确认
always @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
        dst_base_addr <= 0;
        dst_width <= 0;
        dst_height <= 0;
        dst_top_down <= 0;
        ack_toggle <= 0;
        dst_valid <= 0;
    end
    else if(req_sync^ack_toggle)begin
        dst_base_addr <= base_addr_reg;
        dst_width     <= width_reg;
        dst_height    <= height_reg;
        dst_top_down  <= top_down_reg;
        ack_toggle <= ~ack_toggle;
        dst_valid <= 1;
    end
    else dst_valid <= 0;
end

//将ack_toggle同步到50MHz侧
reg ack_sync0;
reg ack_sync1;

always @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
        ack_sync0 <= 1'b0;
        ack_sync1 <= 1'b0;
    end
    else begin
        ack_sync0 <= ack_toggle;
        ack_sync1 <= ack_sync0;
    end
end

assign ack_sync = ack_sync1;

reg frame_write_done_sync0;
reg frame_write_done_sync1;

always @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
        ack_sync0 <= 1'b0;
        ack_sync1 <= 1'b0;
    end
    else begin
        frame_write_done_sync0 <= frame_write_done;
        frame_write_done_sync1 <= frame_write_done_sync0;
    end
end

assign frame_write_done_sync = frame_write_done_sync1;
endmodule