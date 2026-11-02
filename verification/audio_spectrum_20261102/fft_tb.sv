`timescale 1ns/1ps
module fft_tb;
reg clk=0,rst=0,enable=1,valid=0;reg signed [15:0] data=0;always #20 clk=~clk;
wire [8:0] addr;wire [15:0] mag;wire mv,busy;
audio_fft512 dut(clk,rst,enable,data,valid,addr,mag,mv,busy);
reg [15:0] inputs[0:8191],expected[0:8191];
integer c=0,n,seen=0,total=0;
always @(negedge clk)if(rst && mv)begin
 if(addr!==seen || mag!==expected[c*512+seen])$fatal(1,"FFT case=%d bin=%d got_addr=%d mag=%d expected=%d",c,seen,addr,mag,expected[c*512+seen]);
 seen=seen+1;total=total+1;
end
initial begin
 $readmemh("fft_input.hex",inputs);$readmemh("fft_expected.hex",expected);
 repeat(3)@(negedge clk);rst=1;
 // Clear an incomplete block synchronously; stale samples must be discarded.
 data=123;valid=1;repeat(13)@(negedge clk);valid=0;enable=0;repeat(3)@(negedge clk);enable=1;
 for(c=0;c<16;c=c+1)begin
  seen=0;
  for(n=0;n<512;n=n+1)begin data=inputs[c*512+n];valid=1;@(negedge clk);end
  valid=0;wait(busy);repeat(5)@(negedge clk);
  // Input changes while computing must not corrupt the captured block.
  valid=1;data=16'h8123;repeat(17)@(negedge clk);valid=0;
  wait(seen==512);@(negedge clk);
 end
 $display("FFT512_PASS cases=16 bins=%0d fixed_reference_exact=1 disabled_partial_discard=1 busy_input_ignored=1",total);$finish;
end
initial begin #100000000;$fatal(1,"FFT watchdog");end
endmodule
