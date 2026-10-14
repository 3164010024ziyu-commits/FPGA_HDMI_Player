module hdmi_tx_display
(
    input           sys_clk      ,  //系统时钟
    input           sys_rst_n    ,  //系统复位，低电平有效
    
    //hdmi接口                           
    output			HDMI_CLK_P,     //HDMI时钟           
	output			HDMI_D2_P,      //HDMI数据2  blue    
	output			HDMI_D1_P,      //HDMI数据1  green   
	output			HDMI_D0_P,		//HDMI数据0  red	 				
    
    //VGA_TEST
	output			VGA_HS,         //VGA水平同步
	output			VGA_VS,         //VGA垂直同步
    
    output [7:0]	VGA_R,          //VGA红色数据
	output [7:0]	VGA_G,          //VGA绿色数据
	output [7:0]	VGA_B           //VGA蓝色数据
);

    	wire	HDMI_CLK_P2 ;
		wire	HDMI_D2_P2  ;
		wire	HDMI_D1_P2  ;
		wire	HDMI_D0_P2  ;

clk_wize u_clk_wize (
  .refclk(sys_clk),
  .reset(1'b0),
  .clk0_out(pixel_clk_5x),
  .clk1_out(pixel_clk)
);

//例化HDMI驱动模块
hdmi_top u_hdmi_top(
    .PXLCLK_I(pixel_clk),
    .PXLCLK_5X_I(pixel_clk_5x),
    .RST_I(sys_rst_n),
    
    .VGA_HS(VGA_HS),
    .VGA_VS(VGA_VS),

    .VGA_R(VGA_R),
    .VGA_G(VGA_G),
    .VGA_B(VGA_B),
    
    .HDMI_CLK_P   (HDMI_CLK_P),
    .HDMI_D2_P   (HDMI_D2_P),
    .HDMI_D1_P  (HDMI_D1_P),
    .HDMI_D0_P  (HDMI_D0_P)   
                 
    );
                        
    assign        HDMI_CLK_P1   =      HDMI_CLK_P ;
	assign	      HDMI_D2_P1     =      HDMI_D2_P  ;
	assign	      HDMI_D1_P1     =      HDMI_D1_P  ;
	assign	      HDMI_D0_P1     =      HDMI_D0_P  ;              
                    
endmodule
