`timescale 1ns/1ps
module paired_audio_tb;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,select_track=0,play_start=0,pause=0;reg [63:0]track_name="FIRST   ";
 wire track_ready,playing,audio_valid,audio_epoch,error,req_valid,sec_ready,reader_enabled;
 wire [31:0]audio_sample,req_lba;wire [2:0]audio_tag;wire [7:0]error_code;
 wire req_ready,sec_valid,sec_last,sec_error;wire [7:0]sec_data;
 wav_image_player #(.CLK_HZ(1000000),.BUFFER_AWIDTH(8),.PREFILL_FRAMES(64)) dut(
  .clk(clk),.rst_n(rst_n),.select_track(select_track),.play_start(play_start),.pause(pause),.track_name(track_name),
  .card_initialized(1'b1),.sink_active(1'b1),.sink_ready(1'b1),
  .track_ready(track_ready),.playing(playing),.audio_sample(audio_sample),.audio_valid(audio_valid),.audio_tag(audio_tag),.audio_epoch(audio_epoch),
  .error(error),.error_code(error_code),.req_valid(req_valid),.req_lba(req_lba),.req_ready(req_ready),
  .sec_data(sec_data),.sec_valid(sec_valid),.sec_last(sec_last),.sec_error(sec_error),.sec_error_code(8'h10),.sec_ready(sec_ready),.reader_enabled(reader_enabled));
 wire card_req,card_ready;wire [31:0]card_lba;reg card_grant=0,card_valid=0,card_last=0,card_error=0;reg [7:0]card_data=0;
 sd_sector_arbiter arb(.clk(clk),.rst_n(rst_n),.a_req(1'b0),.a_lba(32'd0),.a_grant(),.a_valid(),.a_last(),.a_error(),.a_code(),.a_ready(1'b1),
  .b_enable(reader_enabled),.b_req(req_valid),.b_lba(req_lba),.b_grant(req_ready),.b_valid(sec_valid),.b_last(sec_last),.b_error(sec_error),.b_code(),.b_ready(sec_ready),
  .req(card_req),.grant(card_grant),.lba(card_lba),.valid(card_valid),.last(card_last),.error(card_error),.code(8'h10),.ready(card_ready));
 assign sec_data=card_data;
 `include "virtual_card.svh"
 integer pending=0,lba=0,off=0,cycles=0,samples=0,loops=0,expected_track=-1,expected_sample=0,epoch=0,cases=0;
 reg suppress=0;
 always @(negedge clk)begin
  card_grant=!pending;card_valid=0;card_last=0;
  if(pending && !suppress)begin card_valid=1;card_data=card_byte(lba,off);card_last=off==511;end
 end
 always @(posedge clk)begin
  cycles=cycles+1;if(cycles>1000000)$fatal(1,"paired watchdog");
  if(!rst_n)pending=0;
  else begin
   if(card_req && card_grant)begin pending=1;lba=card_lba;off=0;end
   if(card_valid && card_ready)begin if(card_last)pending=0;else off=off+1;end
  end
 end
 always @(negedge clk)if(rst_n && audio_valid && audio_tag[1])begin
  if(expected_track<0 || audio_epoch!==epoch || pause)$fatal(1,"unexpected file PCM");
  if(audio_tag[0])begin expected_sample=0;loops=loops+1;end
  if(audio_sample!=={16'(expected_track*4096+expected_sample),16'(~(expected_track*4096+expected_sample))})
   $fatal(1,"paired PCM mismatch track=%0d sample=%0d got=%h",expected_track,expected_sample,audio_sample);
  if(audio_tag[0] !== (expected_sample==0))$fatal(1,"loop marker");
  expected_sample=(expected_sample+1)%400;samples=samples+1;
 end
 task prepare(input [63:0]name);
  begin @(negedge clk);track_name=name;select_track=1;@(negedge clk);select_track=0;
   wait(track_ready);@(negedge clk);end
 endtask
 task start_audio(input integer track);
  begin @(negedge clk);expected_track=track;expected_sample=0;epoch=1-epoch;play_start=1;
   @(negedge clk);play_start=0;end
 endtask
 integer before_samples,n;
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  prepare("FIRST   ");if(error)$fatal(1,"first prepare failed %h",error_code);
  repeat(200)@(negedge clk);if(samples!=0)$fatal(1,"prepared audio started early");
  start_audio(0);wait(samples>=450);cases=cases+1;
  @(negedge clk);pause=1;repeat(100)@(negedge clk);before_samples=samples;
  repeat(300)@(negedge clk);if(samples!=before_samples)$fatal(1,"pause advanced PCM");
  pause=0;wait(samples>=before_samples+40);cases=cases+1;
  // Prepare B while A is paused. Starting B must leave its first sample intact.
  @(negedge clk);pause=1;prepare("SECOND  ");if(error)$fatal(1,"second prepare");
  start_audio(1);before_samples=samples;repeat(200)@(negedge clk);
  if(samples!=before_samples)$fatal(1,"paused next picture advanced");
  pause=0;wait(samples>=before_samples+450);cases=cases+1;
  // Missing basename must not silently select some unrelated WAV.
  @(negedge clk);pause=1;prepare("MISSING ");if(!error || error_code!='hb6)$fatal(1,"missing pair not reported");
  start_audio(-1);pause=0;repeat(200)@(negedge clk);cases=cases+1;
  prepare("THIRD   ");if(error)$fatal(1,"recovery prepare");start_audio(2);n=samples;
  wait(samples>=n+50);cases=cases+1;
  // Cancel with a physical sector in flight. The arbiter must drain/discard it.
  @(negedge clk);pause=1;suppress=1;
  fork begin prepare("FIRST   ");end
       begin wait(pending);repeat(30)@(negedge clk);suppress=0;end join
  if(error)$fatal(1,"in-flight cancellation failed");start_audio(0);pause=0;n=samples;wait(samples>=n+50);cases=cases+1;
  wait((dut.play_bank ? dut.level1:dut.level0)>220);
  prepare("SECOND  ");if(error)$fatal(1,"prepare while old audio playing");
  start_audio(1);n=samples;wait(samples>=n+50);cases=cases+1;
  $display("PAIRED_AUDIO_PASS cases=%0d samples=%0d loops=%0d filename_match=1 pause_no_loss=1 paused_next_starts_zero=1 missing_pair=1 cancel_sector=1 old_audio_during_prepare=1",cases,samples,loops);$finish;
 end
endmodule
