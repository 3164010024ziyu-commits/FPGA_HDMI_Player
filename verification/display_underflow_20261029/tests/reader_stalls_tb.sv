`timescale 1ns/1ps
module reader_stalls_tb;
reg clk=0,rst=0,blank=0;
always #5 clk=~clk;
reg [15:0] w=16,h=8;
reg [20:0] base=0;
wire request,active,raster,app_en,wr_en,error;
wire [20:0] addr;
wire [23:0] data;
reg ret=0;reg [31:0] retdata=0;
integer cycle=0,issued=0,index=0,delay_count=0;
integer emitted=0,requests=0,frames=0,stalls=0;
reg returning=0,checking=0;
reg [20:0] addresses[0:3];
wire full=(cycle%17<5)||(cycle%53<7);
wire grant=request && issued==0 && !returning;
sdram_read_ctrl #(.DISPLAY_WIDTH(16),.DISPLAY_HEIGHT(8)) dut(
.Clk(clk),.Reset_n(rst),.blank_flush(blank),.front_valid(1'b1),
.front_base(base),.front_width(w),.front_height(h),.read_request(request),
.read_grant(grant),.read_active(active),.raster_active(raster),.App_rd_en(app_en),
.App_rd_addr(addr),.Sdr_rd_en(ret),.Sdr_rd_dout(retdata),
.fifo_full(full),.fifo_wr_en(wr_en),.fifo_wr_data(data),.read_error(error));
function [23:0] pattern(input [20:0] a);pattern=24'h105a00 ^ {3'd0,a};endfunction
always @(posedge clk) begin
cycle=cycle+1;ret<=0;
if(rst)begin
 if(dut.finish_emit && dut.next_group_data !==
    (dut.x==12 ? dut.y+16'd1<dut.height : dut.x+16'd4<dut.width && dut.y<dut.height))
  $fatal(1,"registered next-group geometry was not ready at handoff");
 if(app_en)begin
  if(issued>=4 || returning)$fatal(1,"overlapping read");
  if(checking && addr!==base+requests)$fatal(1,"read address %d expected %d",addr,base+requests);
  addresses[issued]=addr;issued=issued+1;requests=requests+1;
  if(issued==4)begin returning=1;index=0;delay_count=3;end
 end else if(returning)begin
  if(delay_count>0)delay_count=delay_count-1;
  else begin
   ret<=1;retdata<={8'd0,pattern(addresses[index])};
   if(index==3)begin returning=0;issued=0;end
   else begin index=index+1;delay_count=cycle%4;end
  end
 end
 if(full && active)stalls=stalls+1;
 if(blank && wr_en)$fatal(1,"write during flush");
 if(checking && wr_en)begin
  if(full)$fatal(1,"write despite full");
  if(emitted>=128)$fatal(1,"extra output");
  if(data !== ((emitted%16 < w && emitted/16 < h) ? pattern(base+(emitted/16)*w+emitted%16) : 24'd0))
   $fatal(1,"output mismatch at pixel %d data=%h width=%d height=%d",emitted,data,w,h);
  emitted=emitted+1;
 end
 if(error)$fatal(1,"unexpected timeout");
end
end
task launch(input integer ww,hh,bb);
begin
 @(negedge clk);checking=0;blank=1;
 repeat(24)@(negedge clk);
 w=ww;h=hh;base=bb;emitted=0;requests=0;checking=1;blank=0;
 wait(emitted==128);@(negedge clk);
 if(requests!=ww*hh)$fatal(1,"read coverage mismatch");
 frames=frames+1;checking=0;
end
endtask
initial begin
 #31;rst=1;
 launch(16,8,0);launch(4,1,256);launch(8,3,1024);
 launch(12,7,2048);launch(4,8,4096);
 // Cancel in-flight reads at different response positions; flush must not
 // truncate a four-beat request or leak its words into the next raster.
 repeat(4)begin
  @(negedge clk);blank=1;repeat(24)@(negedge clk);
  w=16;h=8;base=8192;requests=0;blank=0;
  wait(active);repeat(7+frames%4)@(negedge clk);
  blank=1;repeat(24)@(negedge clk);
  launch(8,3,16384);
 end
 if(stalls<10)$fatal(1,"backpressure coverage missing");
 $display("READER_STALLS_PASS rasters=%0d pixels=%0d cancel_cases=4 stalled_active_cycles=%0d",frames,frames*128,stalls);
 $finish;
end
initial begin #1000000;$fatal(1,"test timeout emitted=%d state=%d",emitted,dut.state);end
endmodule
