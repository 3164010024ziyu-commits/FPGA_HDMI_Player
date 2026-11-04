module sdram_write_ctrl(
    input         Clk,
    input         Reset_n,

    input         Sdr_init_done,
    input         Sdr_init_ref_vld,
    input         Sdr_refresh_pending, // Finish an active group; defer the next group.
    input         Sdr_busy,

    //帧描述信息
    input  dst_valid,     
    input  [20:0]dst_base_addr,  
    input  [15:0]dst_width,      
    input  [15:0]dst_height,     
    input  dst_top_down,   

    output reg frame_write_done,

    // FIFO 读取侧
    input  [31:0] fifo_rd_data,
    input         fifo_rd_valid,
    input         fifo_empty,
    output        fifo_rd_en,

    // SDRAM 写入侧
    output        App_wr_en,
    output        write_request,
    output [20:0] App_wr_addr,
    output [31:0] App_wr_din,
    output [3:0]  App_wr_dm
);

reg [1:0] state;
reg frame_active;   //确实存在一张需要完成写入的有效图片。


localparam IDLE     = 2'd0;
localparam PREFETCH = 2'd1;
localparam WRITE    = 2'd2;
localparam DONE     = 2'd3;


reg [2:0] req_cnt;   // 已经向 FIFO 发出多少次有效读取请求
reg [2:0] recv_cnt;  // 已经收到多少个有效数据

reg [31:0] prefetch_buf [0:3];  //用于存储四个数据

reg [2:0] write_cnt;
reg [20:0] write_base_addr;

// Prepare the first row in separate cycles. The running write address then
// needs only an increment, or one row-step addition at an end-of-line beat.
reg [15:0] first_row, frame_width_latched, last_column;
reg [20:0] first_row_offset, row_step, row_base_addr, current_addr;
reg [1:0] address_init_phase;
reg address_ready;

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
// Independent of the grant (carried by Sdr_refresh_pending) to avoid a loop.
assign write_request = frame_active && address_ready && state == PREFETCH && recv_cnt == 4 &&
                       Sdr_init_done && !Sdr_init_ref_vld;
assign App_wr_din = prefetch_buf[write_cnt];
assign App_wr_dm = 4'b0000;

//增加frame_drsc_cdc后修改的地址逻辑
reg [15:0]pixel_x_cnt;
reg [15:0]pixel_y_cnt;
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)begin
        pixel_x_cnt <= 0;
        pixel_y_cnt <= 0;
    end
    else begin
        if(dst_valid)begin
            pixel_x_cnt <= 0;
            pixel_y_cnt <= 0;
        end
        else if(state == WRITE && write_cnt <= 3'd3)begin
            if(pixel_x_cnt == last_column)begin
                pixel_x_cnt <= 0;
                pixel_y_cnt <= pixel_y_cnt + 1;
            end
        else
            pixel_x_cnt <= pixel_x_cnt + 1;
        end
    end
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) begin
        first_row <= 0;
        frame_width_latched <= 0;
        last_column <= 0;
        first_row_offset <= 0;
        row_step <= 0;
        row_base_addr <= 0;
        current_addr <= 0;
        address_init_phase <= 0;
        address_ready <= 0;
    end
    else if(dst_valid) begin
        first_row <= dst_top_down ? 16'd0 : dst_height - 16'd1;
        frame_width_latched <= dst_width;
        last_column <= dst_width - 16'd1;
        row_step <= dst_top_down ? {5'd0,dst_width} : 21'd0 - {5'd0,dst_width};
        address_init_phase <= 1;
        address_ready <= 0;
    end
    else if(address_init_phase == 1) begin
        first_row_offset <= first_row * frame_width_latched;
        address_init_phase <= 2;
    end
    else if(address_init_phase == 2) begin
        row_base_addr <= write_base_addr + first_row_offset;
        current_addr <= write_base_addr + first_row_offset;
        address_init_phase <= 0;
        address_ready <= 1;
    end
    else if(state == WRITE) begin
        if(pixel_x_cnt == last_column) begin
            row_base_addr <= row_base_addr + row_step;
            current_addr <= row_base_addr + row_step;
        end
        else current_addr <= current_addr + 21'd1;
    end
end

assign App_wr_addr = current_addr;

// A frame becomes complete only after its last word and downstream drain.
// Four quiet clocks match the existing refresh arbiter's pipeline guard.
reg [2:0] drain_quiet_count;    //下游写入通路已经连续空闲了多少个 125 MHz 时钟周期
always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n) begin
        frame_write_done <= 0;
        frame_active <= 0;
        drain_quiet_count <= 0;
    end
    else if(dst_valid) begin
        frame_write_done <= 0;
        frame_active <= (dst_width != 0) && (dst_height != 0);
        drain_quiet_count <= 0;
    end
    else if(frame_active) begin
        if((pixel_y_cnt == dst_height) && (pixel_x_cnt == 0) &&
           Sdr_init_done && !App_wr_en && !Sdr_busy && !Sdr_init_ref_vld &&
           fifo_empty && !fifo_rd_valid) begin
            if(drain_quiet_count == 3'd3) begin
                frame_write_done <= 1;
                frame_active <= 0;
                drain_quiet_count <= 0;
            end
            else drain_quiet_count <= drain_quiet_count + 1'b1;
        end
        else drain_quiet_count <= 0;
    end
end



always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        write_base_addr <= 0;
    else if(dst_valid)
        write_base_addr <= dst_base_addr;
end

always @(posedge Clk or negedge Reset_n) begin
    if(!Reset_n)
        state <= IDLE;
    else begin
        case(state)
            IDLE:
                begin
                    if(frame_active && !fifo_empty)
                        state <= PREFETCH;
                end
            PREFETCH:
                begin
                    if(recv_cnt == 3'd4 && address_ready && Sdr_init_done && !Sdr_init_ref_vld && !Sdr_refresh_pending)//新增与sdram_refresh_ctrl配合的Sdr_refresh_pending
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