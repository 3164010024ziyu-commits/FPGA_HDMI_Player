module sdram_refresh_ctrl #(
    parameter integer INTERVAL_CYCLES = 1875,
    parameter integer QUIET_CYCLES = 4,
    parameter integer TIMEOUT_CYCLES = 1024
)(
    input wire Clk,
    input wire Reset_n,
    input wire Sdr_init_done,
    input wire Sdr_init_ref_vld,
    input wire Sdr_busy,
    input wire App_wr_en,
    input wire App_rd_en,
    input wire manual_refresh_req,
    output wire refresh_pending,    //模块内部对其他应用控制器的通知
    output reg App_ref_req, //向厂家 sdr_as_ram 发出的刷新请求
    output reg refresh_error
);
    localparam IDLE = 2'd0, //正常运行，等待定期或手动刷新
               DRAIN = 2'd1,    //禁止新事务启动，等待已有读写和底层活动排空
               WAIT_START = 2'd2,   //已经请求刷新，等待厂家 IP 报告刷新占用
               WAIT_END = 2'd3; //等待刷新占用解除且厂商控制器不忙
    reg [1:0] state;
    reg [31:0] interval_count;  //0到INTERVAL_CYCLES计数器
    reg [31:0] quiet_count;
    reg [31:0] wait_count;
    reg manual_d;
    wire due = (interval_count == INTERVAL_CYCLES - 1); //说明刷新调度时间到
    wire manual_edge = manual_refresh_req && !manual_d;
    assign refresh_pending = (state != IDLE) || refresh_error;

    always @(posedge Clk or negedge Reset_n) begin
        if (!Reset_n) begin
            state <= IDLE;
            interval_count <= 0;
            quiet_count <= 0;
            wait_count <= 0;
            manual_d <= 1'b0;
            App_ref_req <= 1'b0;
            refresh_error <= 1'b0;
        end else if (!Sdr_init_done) begin
            state <= IDLE;
            interval_count <= 0;
            quiet_count <= 0;
            wait_count <= 0;
            manual_d <= 1'b0;
            App_ref_req <= 1'b0;
            refresh_error <= 1'b0;
        end else begin
            manual_d <= manual_refresh_req;
            App_ref_req <= 1'b0;
            if (due)
                interval_count <= 0;
            else
                interval_count <= interval_count + 1'b1;

            if (state == IDLE)
                wait_count <= 0;
            else if (wait_count < TIMEOUT_CYCLES)
                wait_count <= wait_count + 1'b1;
            if (state != IDLE && wait_count == TIMEOUT_CYCLES - 1)  //防止刷新一直等不到
                refresh_error <= 1'b1;
            if (state != IDLE && due)
                refresh_error <= 1'b1;

            case (state)
                IDLE: begin
                    quiet_count <= 0;
                    if ((due || manual_edge) && !refresh_error) begin   //due到了触发刷新
                        interval_count <= 0;
                        state <= DRAIN;
                    end
                end
                DRAIN: begin
                    if (App_wr_en || App_rd_en || Sdr_busy || Sdr_init_ref_vld) //只要下面任何一种情况发生，就继续等待：
                                                                                // 1. 应用层正在提交写请求。
                                                                                // 2. 应用层正在提交读请求。
                                                                                // 3. 下游厂商控制器报告忙。
                                                                                // 4. 厂商控制器报告初始化或刷新占用。
                        quiet_count <= 0;
                    else if (quiet_count == QUIET_CYCLES - 1) begin
                        quiet_count <= 0;
                        App_ref_req <= 1'b1;    //向厂家 IP 发出刷新请求
                        state <= WAIT_START;
                    end
                    else
                        quiet_count <= quiet_count + 1'b1;
                end
                WAIT_START: if (Sdr_init_ref_vld) state <= WAIT_END;
                WAIT_END: if (!Sdr_init_ref_vld && !Sdr_busy) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
