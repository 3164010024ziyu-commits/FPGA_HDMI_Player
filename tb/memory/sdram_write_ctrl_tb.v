`timescale 1 ns / 1 ps
module sdram_write_ctrl_tb;

    // ports
    reg         Clk             ;  // 
    reg         Reset_n         ;  // 
    reg         Sdr_init_done   ;  // 
    reg         Sdr_init_ref_vld;  // 
    reg  [31:0] fifo_rd_data    ;  // 
    reg         fifo_rd_valid   ;  // 
    reg         fifo_empty      ;  // 
    wire        fifo_rd_en      ;  // 
    wire        App_wr_en       ;  // 
    wire [20:0] App_wr_addr     ;  // 
    wire [31:0] App_wr_din      ;  // 
    wire  [3:0] App_wr_dm       ;  // 
    // module
    sdram_write_ctrl uut (
        .Clk                (Clk                ),
        .Reset_n            (Reset_n            ),
        .Sdr_init_done      (Sdr_init_done      ),
        .Sdr_init_ref_vld   (Sdr_init_ref_vld   ),
        .Sdr_refresh_pending(1'b0              ),
        .fifo_rd_data       (fifo_rd_data       ),
        .fifo_rd_valid      (fifo_rd_valid      ),
        .fifo_empty         (fifo_empty         ),
        .fifo_rd_en         (fifo_rd_en         ),
        .App_wr_en          (App_wr_en          ),
        .App_wr_addr        (App_wr_addr        ),
        .App_wr_din         (App_wr_din         ),
        .App_wr_dm          (App_wr_dm          )
    );

    initial Clk = 0;
    always #5 Clk = ~Clk;  // 100 MHz

    initial begin
        Reset_n = 0;
        Sdr_init_done = 0;
        Sdr_init_ref_vld = 0;

        #100;
        Reset_n = 1;

        #100;
        Sdr_init_done = 1;
    end

    reg [2:0] mock_rd_cnt;

    always @(posedge Clk or negedge Reset_n) begin
        if(!Reset_n) begin
            mock_rd_cnt  <= 0;
            fifo_empty   <= 1;
            fifo_rd_valid <= 0;
            fifo_rd_data  <= 0;
        end
        else begin
            // 默认本周期没有新的读取响应
            fifo_rd_valid <= 0;

            // 模拟初始化后，FIFO 中已有四个数据
            if(Sdr_init_done && mock_rd_cnt == 0)
                fifo_empty <= 0;

            // FIFO 接受读取请求
            if(fifo_rd_en && !fifo_empty) begin
                case(mock_rd_cnt)
                    0: fifo_rd_data <= 32'h00000011;
                    1: fifo_rd_data <= 32'h00000022;
                    2: fifo_rd_data <= 32'h00000033;
                    3: fifo_rd_data <= 32'h00000044;
                endcase

                fifo_rd_valid <= 1;
                mock_rd_cnt <= mock_rd_cnt + 1'b1;

                if(mock_rd_cnt == 3)
                    fifo_empty <= 1;
            end
        end
    end


endmodule