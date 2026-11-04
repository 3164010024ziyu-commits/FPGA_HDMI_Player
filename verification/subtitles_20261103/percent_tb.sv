`timescale 1ns/1ps
module percent_tb;
reg clk=0;always #5 clk=~clk;
reg [4:0] val=0;reg [1:0] sel=0;wire [23:0] rgb_out;
param_osd dut(.clk(clk),.reset(1'b0),.de(1'b0),.x(10'd0),.y(10'd0),
 .rgb_in(24'h123456),.rgb_out(rgb_out),.sel(sel),.val(val),.visible(1'b1));
integer i,expected;
initial begin
 sel=2;
 for(i=0;i<32;i=i+1)begin
  @(negedge clk);val=i;@(posedge clk);#1;expected=i<=19?i*100/19:100;
  if(dut.pct!==expected[6:0] || rgb_out!=24'h123456)$fatal(1,"volume percent level=%d got=%d wanted=%d",i,dut.pct,expected);
 end
 sel=0;for(i=0;i<=20;i=i+1)begin
  @(negedge clk);val=i;@(posedge clk);#1;expected=i<=20?i*5:100;
  if(dut.pct!==expected[6:0])$fatal(1,"brightness percent changed");
 end
 $display("PARAM_PERCENT_PASS volume_levels=20 clamp=1 brightness_unchanged=1 no_latency=1");$finish;
end
endmodule
