`timescale 1ns/1ps
module glitch_tb;
reg clk=0,rst=0;
always #20 clk=~clk;
reg [9:0] ideal_row=383;
wire [9:0] skew_row;
genvar k;
generate for(k=0;k<10;k=k+1)begin: skew
 if(k<5)assign #0.05 skew_row[k]=ideal_row[k];
 else if(k==7)assign #0.10 skew_row[k]=ideal_row[k];
 else assign #0.20 skew_row[k]=ideal_row[k];
end endgenerate
wire old_flush,new_flush;
reg [7:0] old_queue=128,new_queue=128;
integer old_spurious=0,new_spurious=0;
read_RAM_before old_timing(.clk25M(clk),.reset_n(rst),.pix_rgb(24'd0),.pix_valid(1'b0),
.pix_req(),.frame_sync(old_flush),.HDMI_EN(),.HDMI_HSYNC(),.HDMI_VSYNC(),.HDMI_X(),.HDMI_Y(),.HDMI_D());
read_RAM new_timing(.clk25M(clk),.reset_n(rst),.pix_rgb(24'd0),.pix_valid(1'b0),
.pix_req(),.frame_sync(new_flush),.HDMI_EN(),.HDMI_HSYNC(),.HDMI_VSYNC(),.HDMI_X(),.HDMI_Y(),.HDMI_D());
// Model Q/path skew after a real binary row counter changes. Delays are
// illustrative, not measured board delays; they expose a static decode hazard.
initial begin force old_timing.vcnt=skew_row;force new_timing.vcnt=skew_row;end
always @(posedge old_flush)if(rst && ideal_row==384)begin old_spurious=old_spurious+1;old_queue=0;end
always @(posedge new_flush)if(rst && ideal_row==384)begin new_spurious=new_spurious+1;new_queue=0;end
initial begin
#5;rst=1;#50;
@(negedge clk);force old_timing.hcnt=799;force new_timing.hcnt=799;
@(posedge clk);ideal_row<=384;
#1;release old_timing.hcnt;release new_timing.hcnt;
if(old_spurious!=1 || old_queue!=0)$fatal(1,"old decode hazard not reproduced");
if(new_spurious!=0 || new_queue!=128 || new_flush!==0)$fatal(1,"registered flush still glitched");
$display("FRAME_FLUSH_GLITCH_PASS transition=383_to_384 old_false_flushes=%0d new_false_flushes=%0d old_queue=%0d new_queue=%0d",old_spurious,new_spurious,old_queue,new_queue);
$finish;
end
initial begin #10000;$fatal(1,"timeout");end
endmodule
