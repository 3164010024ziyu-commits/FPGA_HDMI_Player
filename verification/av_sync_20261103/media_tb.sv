`timescale 1ns/1ps
module av_media_probe_tb;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,start=0,valid=0,last=0,sample_ready=1;reg [31:0]file_size=0;reg [7:0]data=0;
 wire ready,sample_valid,sample_first,format_valid,done,error;wire [31:0]sample;wire [7:0]error_code;
 wav_stream_decoder dut(.*);
 reg [7:0]bytes[0:1023];reg [31:0]expected[0:63],sizes[0:3];
 integer seen=0,ptr=0,case_id=0,total=0,cycles=0;reg checking=0;
 always @(negedge clk)begin
  valid=rst_n && !start && checking && cycles%3!=0;
  data=bytes[ptr];
 end
 always @(posedge clk)begin
  cycles=cycles+1;if(cycles>100000)$fatal(1,"media probe watchdog");
  if(valid && ready)ptr=ptr+1;
  if(rst_n && checking)begin
   if(error)$fatal(1,"real media rejected case=%0d code=%h",case_id,error_code);
   if(sample_valid && sample_ready)begin
    if(sample!==expected[seen] || sample_first!==(seen==0))$fatal(1,"real media sample mismatch case=%0d sample=%0d",case_id,seen);
    seen=seen+1;total=total+1;
    if(seen==64)checking=0;
   end
  end
 end
 initial begin
  $readmemh("sizes.hex",sizes);
  for(case_id=0;case_id<4;case_id=case_id+1)begin
   rst_n=0;checking=0;valid=0;repeat(4)@(negedge clk);
   $readmemh($sformatf("probe%0d.hex",case_id),bytes);$readmemh($sformatf("samples%0d.hex",case_id),expected);
   seen=0;ptr=0;file_size=sizes[case_id];rst_n=1;start=1;
   @(negedge clk);start=0;checking=1;
   wait(!checking);@(negedge clk);$display("REAL_MEDIA_CASE_PASS case=%0d size=%0d samples=%0d",case_id,file_size,seen);
  end
  $display("REAL_MEDIA_PROBE_PASS files=4 samples=%0d real_riff_headers=1 sample_endian=1",total);$finish;
 end
endmodule
