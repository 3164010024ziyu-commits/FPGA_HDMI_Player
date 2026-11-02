`timescale 1ns/1ps
module fade_pixels_tb;
reg clk=0,rst=0;always #10 clk=~clk;
reg [5:0] gain=32;reg [23:0] adjusted;
hdmi_tx_display #(.HDMI_AUDIO_EN(0),.HDMI_SUBTITLE_EN(0),.IMAGE_FADE_EN(1)) dut(
 .sys_clk(clk),.sys_rst_n(rst),.pix_rgb(24'd0),.fade_level(gain),.pix_valid(1'b1),.frame_ready(1'b1),.pix_underflow(1'b0),
 .audio_clk(clk),.audio_sample(32'd0),.audio_valid(1'b0),.key_in(7'h7f),.key_img(4'hf),
 .osd_slot(1'b0),.osd_char_idx(4'd0),.osd_char_code(16'd0),.osd_char_we(1'b0),.osd_y(10'd0),.osd_fg(24'd0));
integer i,g,expected;
initial begin
 force dut.VGA_ADJ=adjusted;
 for(g=0;g<=32;g=g+2)begin
  gain=g;
  for(i=0;i<256;i=i+1)begin adjusted={i[7:0],i[7:0],i[7:0]};#1;expected=(i*g)>>5;
   if(dut.FADE_D!=={expected[7:0],expected[7:0],expected[7:0]})$fatal(1,"RGB fade arithmetic channel=%d gain=%d got=%h",i,g,dut.FADE_D);
  end
 end
 gain=0;adjusted=24'hffffff;#1;if(dut.FADE_D!=0)$fatal(1,"positive brightness cannot reach black");
 $display("FADE_PIXEL_PASS channel_values=256 gains=17 rgb_channels=3 exact_endpoints=1 no_latency=1");$finish;
end
endmodule
