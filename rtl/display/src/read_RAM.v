module read_RAM
(
	input	clk25M,//25MHz时钟
	input	reset_n,
    output  HDMI_EN,//HDMI                                                                      使能信号
	output 	HDMI_HSYNC,//行同步信号
	output 	HDMI_VSYNC,//场同步信号

	output reg [23:0] HDMI_D
);		

reg  [9:0]hcnt;
reg  [9:0]vcnt;		
reg	 hs;	
reg  vs;

wire dis_en;

assign HDMI_VSYNC = vs;
assign HDMI_HSYNC = hs;
assign dis_en = (hcnt<10'd640 && vcnt<10'd480);
assign HDMI_EN  = (((hcnt >= 0) && (hcnt < 640))
                 &&((vcnt >= 0) && (vcnt < 480)))
                 ?  1'b1 : 1'b0;


			
always @(posedge clk25M or negedge reset_n) begin			//水平扫描计数器
	if(!reset_n)
		hcnt <= 1'b0;
	else begin
		if (hcnt < 799)
			hcnt <= hcnt + 1'b1;
		else
			hcnt <= 1'b0;
	end
end
			
always @(posedge clk25M or negedge reset_n) begin			//垂直扫描计数器
	if(!reset_n)
		vcnt <= 1'b0;
	else begin
		if (hcnt == 799) begin
			if (vcnt < 10'd524)
				vcnt <= vcnt +1'b1;
			else
				vcnt <= 1'b0;
		end
	end
end
			
always @(posedge clk25M or negedge reset_n) begin			//行同步信号发生
	if(!reset_n)
		hs	<=	1'b1;
	else begin
		if((hcnt >= 640+8+8) & (hcnt < 640+8+8+96))
			hs <= 1'b0;
		else
			hs <= 1'b1;
	end
end
			
always @(vcnt or reset_n) begin							//场同步信号发生
	if(!reset_n)
		vs	<=	1'b1;
	else begin
		if((vcnt >= 480+8+2) && (vcnt < 480+8+2+2))
			vs	<=	1'b0;
		else
			vs	<=	1'b1;
	end
end
			
always @(posedge clk25M or negedge reset_n) begin
	if(!reset_n)
		HDMI_D <= 1'b0;
	else begin
		if (hcnt < 10'd640 & vcnt < 10'd480 && dis_en)	begin	//读取RAM数据
//			HDMI_D[11:8] <= rgb[0]?4'hf:0;
//			HDMI_D[ 7:4] <= rgb[1]?4'hf:0;
//			HDMI_D[ 3:0] <= rgb[2]?4'hf:0;
            HDMI_D[23:16] <= 8'h79; 
            HDMI_D[15: 8] <= 8'hAF;
            HDMI_D[ 7: 0] <= 8'h75;
		end
		else begin
			HDMI_D <= 1'b0;
		end
	end
end
		
endmodule 
