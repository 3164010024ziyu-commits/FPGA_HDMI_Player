`timescale 1ns/1ps
module progress_tb;
reg clk=0,rst=0,consume=0;reg [2:0] tag=0;always #5 clk=~clk;
wire playing;wire [23:0] time_bcd;
audio_progress dut(.clk(clk),.rst_n(rst),.consume(consume),.tag(tag),.playing(playing),.time_bcd(time_bcd));
task sample(input [2:0] t);begin @(negedge clk);consume=1;tag=t;@(negedge clk);consume=0;end endtask
integer i;
initial begin
 repeat(3)@(negedge clk);rst=1;
 sample(7);if(!playing || time_bcd!=0 || dut.samples!=1)$fatal(1,"first sample");
 for(i=0;i<47998;i=i+1)sample(6);
 if(time_bcd!=0 || dut.samples!=47999)$fatal(1,"before second");
 sample(6);if(time_bcd!=24'h000001 || dut.samples!=0)$fatal(1,"48000 stereo frames != 1 second");
 repeat(20)sample(4);
 if(time_bcd!=1 || dut.samples!=0 || playing)$fatal(1,"underrun advanced time");
 sample(6);if(time_bcd!=1 || dut.samples!=1 || !playing)$fatal(1,"underrun recovery");
 sample(7);if(time_bcd!=0 || dut.samples!=1)$fatal(1,"loop did not restart");
 sample(0);if(time_bcd!=0 || dut.samples!=0 || playing)$fatal(1,"stop did not clear");
 sample(7);repeat(9)sample(6);
 rst=0;@(negedge clk);if(time_bcd!=0 || playing)$fatal(1,"reset");rst=1;
 $display("AUDIO_PROGRESS_PASS real_48000=1 underrun_freeze=1 loop=1 stop=1 reset=1");$finish;
end
endmodule

module progress_rollover_tb;
reg clk=0,rst=0,consume=0;reg [2:0] tag=0;always #5 clk=~clk;
wire playing;wire [23:0] time_bcd;
audio_progress #(.FS(2)) dut(.clk(clk),.rst_n(rst),.consume(consume),.tag(tag),.playing(playing),.time_bcd(time_bcd));
integer i;
initial begin
 repeat(3)@(negedge clk);rst=1;consume=1;tag=7;@(negedge clk);tag=6;
 for(i=1;i<120;i=i+1)@(negedge clk);
 if(time_bcd!=24'h000100)$fatal(1,"minute rollover %h",time_bcd);
 for(i=120;i<7200;i=i+1)@(negedge clk);
 if(time_bcd!=24'h010000)$fatal(1,"hour rollover %h",time_bcd);
 for(i=7200;i<720000;i=i+1)@(negedge clk);
 if(time_bcd!=0)$fatal(1,"100 hour rollover %h",time_bcd);
 $display("AUDIO_PROGRESS_ROLLOVER_PASS minute=1 hour=1 wrap_100h=1");$finish;
end
endmodule
