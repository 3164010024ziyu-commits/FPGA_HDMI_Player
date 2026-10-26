module sdram_write_ctrl(
    input         Clk,
    input         Reset_n,

    input         Sdr_init_done,
    input         Sdr_init_ref_vld,
    input         Sdr_refresh_pending, // Finish an active group; defer the next group.

    // FIFO 读取侧
    input  [31:0] fifo_rd_data,
    input         fifo_rd_valid,
    input         fifo_empty,
    output        fifo_rd_en,

    // SDRAM 写入侧
    output        App_wr_en,
    output [20:0] App_wr_addr,
    output [31:0] App_wr_din,
    output [3:0]  App_wr_dm
);

reg [1:0] state;

localparam IDLE     = 2'd0;
localparam PREFETCH = 2'd1;
localparam WRITE    = 2'd2;
localparam DONE     = 2'd3;


reg [2:0] req_cnt;   // 已经向 FIFO 发出多少次有效读取请求
reg [2:0] recv_cnt;  // 已经收到多少个有效数据

reg [31:0] prefetch_buf [0:3];  //用于存储四个数据

reg [2:0] write_cnt;
reg [20:0] write_base_addr;

assign fifo_rd_en = (state == PREFETCH)
                 && (req_cnt < 3'd4)
                 && (!fifo_empty);

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        req_cnt <= 0;
    else if(state == IDLE)
        req_cnt <= 0;
    else if(fifo_rd_en)
        req_cnt <= req_cnt + 1'b1;
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        recv_cnt <= 0;
    else if(state == IDLE)
        recv_cnt <= 0;
    else if(state == PREFETCH && fifo_rd_valid && recv_cnt < 3'd4) begin
        prefetch_buf[recv_cnt] <= fifo_rd_data;
        recv_cnt <= recv_cnt + 1'b1;
    end
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        write_cnt <= 0;
    else if(state == IDLE)
        write_cnt <= 0;
    else if(state == WRITE && write_cnt < 3'd3)
        write_cnt <= write_cnt + 1'b1;
end

assign App_wr_en = (state == WRITE);
assign App_wr_din = prefetch_buf[write_cnt];
assign App_wr_addr = write_base_addr + write_cnt;
assign App_wr_dm = 4'b0000;

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        write_base_addr <= 0;
    else if(state == DONE)
        write_base_addr <= write_base_addr + 21'd4;
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        state <= IDLE;
    else begin
        case(state)
            IDLE:
                begin
                    if(!fifo_empty)
                        state <= PREFETCH;
                end
            PREFETCH:
                begin
                    if(recv_cnt == 3'd4 && Sdr_init_done && !Sdr_init_ref_vld && !Sdr_refresh_pending)//新增与sdram_refresh_ctrl配合的Sdr_refresh_pending
                        state <= WRITE;
                end
            WRITE:
                begin
                    if(write_cnt == 3'd3)
                        state <= DONE;
                end
            DONE:
                begin
                    state <= IDLE;
                end
            default: state <= IDLE;
        endcase
    end
end


endmodule