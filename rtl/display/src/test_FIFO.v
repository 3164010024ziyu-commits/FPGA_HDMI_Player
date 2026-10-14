module test_FIFO( 
input sys_clk,
input sys_rst_n,

input pix_clk,           //HDMI像素时钟
input pix_req,           //请求下一个像素
input frame_sync,        //一帧开始前的同步脉冲，用于帧位置同步

output [23:0] pix_rgb,  //RGB888像素数据
output pix_valid,       //像素有效
output frame_ready,     //完整图像已经可以显示
output pix_underflow   //显示过程中数据供应不足
);


wire [23:0] rgb;

reg [9:0] h_cnt;
reg [9:0] v_cnt;

always @(negedge sys_rst_n or posedge pix_clk) begin
    if (!sys_rst_n) begin
        h_cnt <= 10'd0;
    end else if (frame_sync) begin
        h_cnt <= 10'd0;
    end else begin
        if (h_cnt == 10'd639 && pix_req) 
            h_cnt <= 10'd0;
        else if (pix_req) 
            h_cnt <= h_cnt + 1;
    end
end

always @(negedge sys_rst_n or posedge pix_clk) begin
    if (!sys_rst_n ) begin
        v_cnt <= 10'd0;
    end else if( frame_sync) begin
        v_cnt <= 10'd0;
    end else begin
        if (h_cnt == 10'd639 && pix_req) begin
            if (v_cnt == 10'd479) 
                v_cnt <= 10'd0;
            else 
                v_cnt <= v_cnt + 1;
        end
    end
end



assign pix_valid = (h_cnt < 10'd640) && (v_cnt < 10'd480);
assign rgb[23:16] = h_cnt[6:0] + v_cnt[6:0];
assign rgb[15:8] = h_cnt[6:0];
assign rgb[7:0] = v_cnt[6:0];

assign pix_rgb = rgb;


endmodule
