module hdmi_tx_display
(
    input           sys_clk      ,  //系统时钟
    input           sys_rst_n    ,  //系统复位，低电平有效

    input           [23:0]pix_rgb,  //像素数据       @
    input           pix_valid,      //像素有效       @
    input           frame_ready,    //完整图像已经可以显示
    input           pix_underflow,  //显示过程中数据供应不足

    output          pix_clk,        //像素时钟  @
    output          pix_req,        //请求下一个像素  @
    output          frame_sync,     //一帧开始前的同步脉冲，用于帧位置同步 @
    
    //hdmi接口                           
    output			HDMI_CLK_P,     //HDMI时钟           
	output			HDMI_D2_P,      //HDMI数据2  blue    
	output			HDMI_D1_P,      //HDMI数据1  green   
	output			HDMI_D0_P		//HDMI数据0  red	 				
    
);

wire VGA_DE;
wire [23:0]VGA_D;
wire [7:0] vga_r, vga_g, vga_b;

wire pixel_clk;
wire pixel_clk_5x;

assign pix_clk = pixel_clk;

clk_wize u_clk_wize (    //像素时钟
  .refclk(sys_clk),
  .reset(1'b0),
  .clk0_out(pixel_clk_5x),
  .clk1_out(pixel_clk)
);

read_RAM u_read_RAM(                //像素数据读取模块
	.clk25M 	(pixel_clk),
	.reset_n    (sys_rst_n),
    .pix_rgb    (pix_rgb),
    .pix_valid  (pix_valid),

    //output
    .pix_req    (pix_req),
    .frame_sync (frame_sync),
	.HDMI_HSYNC	(VGA_HS),
	.HDMI_VSYNC	(VGA_VS),
    .HDMI_EN     (VGA_DE),
	.HDMI_D		(VGA_D)
);

hdmi_tx #(.FAMILY("EG4"))

 u3_hdmi_tx
	(
		.PXLCLK_I(pixel_clk),
		.PXLCLK_5X_I(pixel_clk_5x),

		.RST_N (sys_rst_n),
		
		//VGA
		.VGA_HS (VGA_HS ),
		.VGA_VS (VGA_VS ),
		.VGA_DE (VGA_DE ),
		.VGA_RGB({vga_r,vga_g,vga_b}),

		//HDMI
		.HDMI_CLK_P(HDMI_CLK_P),
		.HDMI_D2_P (HDMI_D2_P ),
		.HDMI_D1_P (HDMI_D1_P ),
		.HDMI_D0_P (HDMI_D0_P )	
	);

    assign vga_r = VGA_D[23:16];
    assign vga_g = VGA_D[15:8];
    assign vga_b = VGA_D[7:0];
            
                    
endmodule
