module hdmi_top( 
        input   PXLCLK_I,         //像素时钟
        input   PXLCLK_5X_I,      //像素时钟5倍
		input	RST_I,            //复位信号

        //HDMI
		output			HDMI_CLK_P,  //HDMI时钟
		output			HDMI_D2_P,   //HDMI数据2  blue    
		output			HDMI_D1_P,   //HDMI数据1  green
		output			HDMI_D0_P,   //HDMI数据0  red	
		
		output			VGA_HS,
		output			VGA_VS,
			
    	output [7:0]	VGA_R,		
		output [7:0]	VGA_G,		
		output [7:0]	VGA_B	
    );

    wire  			   VGA_DE;
    wire [23:0]        VGA_D;

    assign VGA_R = VGA_D[23:16];	
    assign VGA_G = VGA_D[15:8];
    assign VGA_B = VGA_D[7:0];

//color to VGA_D
read_RAM u_read_RAM(
	.clk25M 	(PXLCLK_I),
	.reset_n    (RST_I),
    //output
	.HDMI_HSYNC	(VGA_HS),
	.HDMI_VSYNC	(VGA_VS),
    .HDMI_EN     (VGA_DE),
	.HDMI_D		(VGA_D)

);


hdmi_tx #(.FAMILY("EG4"))	//EF2、EF3、EG4、AL3、PH1

 u3_hdmi_tx
	(
		.PXLCLK_I(PXLCLK_I),
		.PXLCLK_5X_I(PXLCLK_5X_I),

		.RST_N (RST_I),
		
		//VGA
		.VGA_HS (VGA_HS ),
		.VGA_VS (VGA_VS ),
		.VGA_DE (VGA_DE ),
		.VGA_RGB({VGA_R,VGA_G,VGA_B}),

		//HDMI
		.HDMI_CLK_P(HDMI_CLK_P),
		.HDMI_D2_P (HDMI_D2_P ),
		.HDMI_D1_P (HDMI_D1_P ),
		.HDMI_D0_P (HDMI_D0_P )	
		
	);

endmodule
