`timescale 1ns/1ps
module line_tb;
reg clk=0,rst=0;always #20 clk=~clk;
wire flush;wire [9:0] x,y;
integer highs=0,frames=0;
read_RAM dut(.clk25M(clk),.reset_n(rst),.pix_rgb(24'd0),.pix_valid(1'b0),
.pix_req(),.frame_sync(flush),.HDMI_EN(),.HDMI_HSYNC(),.HDMI_VSYNC(),.HDMI_X(x),.HDMI_Y(y),.HDMI_D());
always @(negedge clk)if(rst)begin
 if(flush !== (y==480))$fatal(1,"flush not aligned xy=%d,%d flush=%b",x,y,flush);
 if(flush)highs=highs+1;
 if(x==799 && y==524)begin
  if(highs!=800)$fatal(1,"wrong flush width %d",highs);
  frames=frames+1;highs=0;
  if(frames==2)begin $display("FRAME_FLUSH_ALIGNMENT_PASS frames=2 cycles_per_flush=800 line=480");$finish;end
 end
end
initial begin #55;rst=1;end
initial begin #40000000;$fatal(1,"timeout");end
endmodule
