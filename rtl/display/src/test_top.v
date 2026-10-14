module test_top( 
input sys_clk,
input sys_rst_n,

output HDMI_CLK_P,
output HDMI_D2_P,
output HDMI_D1_P,
output HDMI_D0_P

);

wire pix_valid;        //像素有效
wire [23:0]pix_rgb;
wire pix_clk;           //HDMI像素时钟
wire pix_req;           //请求下一个像素
wire frame_sync;        //一帧开始前的同步脉冲，用于帧位置同步


hdmi_tx_display u_hdmi_tx_display(
    //input
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .pix_rgb(pix_rgb),
    .pix_valid(pix_valid),

    //output
    .pix_clk(pix_clk),
    .pix_req(pix_req),
    .frame_sync(frame_sync),
    .HDMI_CLK_P(HDMI_CLK_P),
    .HDMI_D2_P(HDMI_D2_P),
    .HDMI_D1_P(HDMI_D1_P),
    .HDMI_D0_P(HDMI_D0_P)
);

test_FIFO u_test_FIFO(
    .sys_clk(sys_clk),
    .sys_rst_n(sys_rst_n),
    .pix_clk(pix_clk),
    .pix_req(pix_req),
    .frame_sync(frame_sync),
    .pix_rgb(pix_rgb),
    .pix_valid(pix_valid)
);


endmodule
