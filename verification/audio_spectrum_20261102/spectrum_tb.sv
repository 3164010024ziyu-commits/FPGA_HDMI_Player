`timescale 1ns/1ps
module spectrum_tb;
reg clk=0,rst=0,enable=0,valid=0;reg [31:0] sample=0;reg [7:0] volume=255;always #20 clk=~clk;
wire [111:0] levels;wire update;
audio_spectrum dut(clk,rst,enable,sample,valid,volume,levels,update);
reg [31:0] inputs[0:6143];reg [111:0] expected[0:11];reg [7:0] volumes[0:11];
integer c,n,block;
initial begin
 $readmemh("spectrum_input.hex",inputs);$readmemh("spectrum_expected.hex",expected);$readmemh("spectrum_volume.hex",volumes);
 repeat(3)@(negedge clk);rst=1;
 for(c=0;c<12;c=c+1)begin
  enable=0;repeat(4)@(negedge clk);enable=1;volume=volumes[c];
  for(block=0;block<2;block=block+1)begin
   // Bursts are intentionally faster than real audio to check pipeline bounds.
   for(n=0;n<512;n=n+1)begin sample=inputs[c*512+n];valid=1;@(negedge clk);valid=0;repeat(3)@(negedge clk);end
   wait(update);@(negedge clk);repeat(4)@(negedge clk);
  end
  if(levels!==expected[c])$fatal(1,"SPECTRUM case=%d got=%h expected=%h",c,levels,expected[c]);
  $display("SPECTRUM_CASE_PASS case=%d levels=%h",c,levels);
 end
 enable=0;repeat(3)@(negedge clk);if(levels!=0)$fatal(1,"disable stale spectrum");
 $display("SPECTRUM_PASS cases=12 hann=1 all_16_bands_exact=1 right_channel=1 antiphase=1 volume=1 mute=1 disable_clear=1");$finish;
end
initial begin #100000000;$fatal(1,"spectrum watchdog");end
endmodule
