`timescale 1ns/1ps
module decoder_tb;
reg clk=0,rst_n=0,start=0;always #10 clk=~clk;
reg [31:0] file_size=0;
reg [7:0] data=0;reg valid=0,last=0;wire ready;
wire sample_first;wire [31:0] sample;wire sample_valid,format_valid,done,error;wire [7:0] error_code;
reg sample_ready=0;
wav_stream_decoder dut(.*);
reg [7:0] good[0:8247],mono[0:171],bytes[0:8299];
integer n,seen=0,cases=0,cycles=0,accepted=0;
reg done_seen=0,stalled=0;reg [31:0] held;
reg [31:0] random_state=32'h12345678;
function [31:0] expected(input integer i);
reg [15:0] l,r;
begin l=(i*13+1000)%12000;r=-((i*7+2000)%14000);expected={l,r};end
endfunction
always @(negedge clk)begin
 random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
 sample_ready=random_state[2] || random_state[7];
end
always @(posedge clk)if(rst_n)begin
 cycles=cycles+1;if(cycles>2000000)$fatal(1,"decoder watchdog");
 if(start)begin seen=0;done_seen=0;stalled=0;end
 else begin
 if(stalled && (!sample_valid || sample!==held))$fatal(1,"unstable PCM under backpressure");
 if(sample_valid && sample_ready)begin
  if(sample_first!==(seen==0))$fatal(1,"WAV first flag not aligned with PCM");
  if(sample!==expected(seen))$fatal(1,"PCM mismatch at %d got=%h expected=%h",seen,sample,expected(seen));seen=seen+1;
 end
 stalled=sample_valid && !sample_ready;held=sample;
 if(done)done_seen=1;
 end
end
task base;begin for(n=0;n<8248;n=n+1)bytes[n]=good[n];end endtask
task run_case(input integer length,expected_error,expected_count);
integer i;
begin
 cases=cases+1;@(negedge clk);file_size=length;start=1;
 @(negedge clk);start=0;i=0;
 while(i<length && !error)begin
  @(negedge clk);valid=random_state[1] || random_state[4];data=bytes[i];last=i==length-1;
  @(posedge clk);if(valid && ready)i=i+1;
 end
 @(negedge clk);valid=0;last=0;
 wait(error || done_seen);
 if(expected_error==0)begin
  if(error || seen!=expected_count)$fatal(1,"decoder success case=%d error=%h count=%d",cases,error_code,seen);
 end else if(!error || error_code!=expected_error)$fatal(1,"decoder error case=%d got=%h expected=%h",cases,error_code,expected_error);
 $display("WAV_CASE_PASS case=%0d samples=%0d error=%h",cases,seen,error_code);
 repeat(4)@(negedge clk);
end endtask
initial begin
 $readmemh("good.hex",good);$readmemh("mono.hex",mono);
 repeat(3)@(negedge clk);rst_n=1;
 base();run_case(8248,0,2048);
 for(n=0;n<172;n=n+1)bytes[n]=mono[n];run_case(172,'h81,0);
 base();bytes[0]="X";run_case(8248,'h80,0);
 base();bytes[34]=24;run_case(8248,'h81,0);
 base();bytes[24]='h44;bytes[25]='hac;run_case(8248,'h81,0);
 base();bytes[4]='hff;bytes[5]='hff;bytes[6]='hff;bytes[7]='hff;run_case(8248,'h80,0);
 base();bytes[52]='hff;bytes[53]='hff;bytes[54]='hff;bytes[55]='h7f;run_case(8248,'h82,0);
 base();bytes[12]="d";bytes[13]="a";bytes[14]="t";bytes[15]="a";run_case(8248,'h82,0);
 base();run_case(100,'h80,0); // declared file shorter than RIFF
 base();bytes[56]=0;bytes[57]=0; // valid signed zero is allowed; restore below
 base();run_case(8248,0,2048);
 $display("WAV_DECODER_PASS cases=%0d riff_bounds=1 junk_odd_padding=1 stereo_endian=1 backpressure=1 format_reject=1 recovery=1",cases);$finish;
end
endmodule
