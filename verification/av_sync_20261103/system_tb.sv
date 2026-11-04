`timescale 1ns/1ps
module av_system_tb;
 reg clk=0,rst_n=0,load_n=1,prev_n=1,next_n=1,auto_n=1,pause_n=1;
 reg [6:0]keys=7'h67;always #10 clk=~clk;
 wire cs,sck,mosi,miso;wire [3:0]led;
 hdmi_player_board_top #(.POWERUP_CYCLES(8),.DEBOUNCE_CYCLES(4),.SPECTRUM_DB_CYCLES(4),
  .SLIDESHOW_CYCLES(5000000),.FADE_STEP(8))dut(
  .SYS_CLK(clk),.Reset_n(rst_n),.KEY_LOAD_N(load_n),.KEY_PREV_N(prev_n),.KEY_NEXT_N(next_n),.KEY_AUTO_N(auto_n),
  .KEY_SPECTRUM_N(1'b1),.SW_MUTE_N(pause_n),.key_img(4'hf),.key_in(keys),.LED(led),
  .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),.HDMI_CLK_P(),.HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P());
 defparam dut.u_player.u_display.g_subtitles.u_overlay.LONG_PRESS_CYCLES=8;
 reg expect_caption_scroll=0;
 always @(negedge dut.u_player.display_clk)if(expect_caption_scroll && dut.u_player.display_reset_n)begin
  if(dut.u_player.u_display.g_subtitles.u_overlay.direction!=1)
   $fatal(1,"image change interrupted subtitle scrolling");
 end
 integer reads,commands;
 av_sd_card_model card(.rst_n(rst_n),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),.high_capacity(1'b1),
  .corrupt_crc(1'b0),.suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),.reads(reads),.commands(commands));
 integer transitions=0,consumed=0,loops=0,track=-1,seq=0,first_pending=0,first_checks=0;
 integer ref_samples=0,max_start_ns=0,delta=0,auto_checks=0;time last_start=0,transition_time=0;
 reg check_auto=0,paused_on_start=0;
 always @(posedge dut.u_player.display_clk)if(dut.u_player.display_reset_n)begin
  if(dut.u_player.u_display.transition_start)begin
   track=dut.u_player.opened_file_index;transitions=transitions+1;seq=0;first_pending=1;transition_time=$time;ref_samples=0;
   paused_on_start=!pause_n;
   if(check_auto && last_start!=0)begin
    delta=$time-last_start;
    if(delta<99000000 || delta>117000000)$fatal(1,"auto transition not on timeline delta=%0d",delta);
    auto_checks=auto_checks+1;
   end
   last_start=$time;
   $display("AV_VIDEO_START n=%0d target=%0d t=%0t paused=%b",transitions,track,$time,!pause_n);
  end
  if(first_pending && paused_on_start && pause_n)begin transition_time=$time;paused_on_start=0;end
  if(dut.u_player.u_display.audio_pop && !dut.u_player.u_display.audio_empty)begin
   if(!dut.u_player.u_display.audio_rd_tag[2])ref_samples=0;
   else if(dut.u_player.u_display.audio_rd_tag[1])begin
    if(dut.u_player.u_display.audio_rd_tag[0])begin seq=0;loops=loops+1;ref_samples=1;end
    else ref_samples=ref_samples+1;
    if(track<0 || dut.u_player.u_display.audio_rd_data!=={16'(track*4096+seq),16'(~(track*4096+seq))})
     $fatal(1,"wrong paired audio track=%0d seq=%0d got=%h",track,seq,dut.u_player.u_display.audio_rd_data);
    if(first_pending)begin
     if(seq!=0 || !dut.u_player.u_display.audio_rd_tag[0])$fatal(1,"track did not restart at first PCM");
     delta=$time-transition_time;if(delta>16800000)$fatal(1,"AV skew > one video frame %0d",delta);
     if(delta>max_start_ns)max_start_ns=delta;first_pending=0;first_checks=first_checks+1;
    end
    seq=(seq+1)%400;consumed=consumed+1;
   end
   #1;
   if(dut.u_player.u_display.g_subtitles.u_progress.samples!==ref_samples || dut.u_player.u_display.g_subtitles.u_progress.time_bcd!=0)
    $fatal(1,"audio progress not aligned with actual HDMI samples expected=%d actual=%d",ref_samples,dut.u_player.u_display.g_subtitles.u_progress.samples);
  end
 end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task load;begin wait(dut.load_ready);load_n=0;cycles(20);load_n=1;wait(!dut.load_ready);wait(dut.load_ready);cycles(5);end endtask
 task next;begin wait(dut.load_ready);next_n=0;cycles(20);next_n=1;wait(!dut.load_ready);wait(dut.load_ready);cycles(5);end endtask
 task previous;begin wait(dut.load_ready);prev_n=0;cycles(20);prev_n=1;wait(!dut.load_ready);wait(dut.load_ready);cycles(5);end endtask
 integer n,before_samples,before_progress;
 initial begin
  cycles(4);rst_n=1;load();wait(consumed>=100);
  if(!dut.u_player.u_display.g_subtitles.u_text_cache.has_text ||
      dut.u_player.u_display.g_subtitles.u_text_cache.text_length!=3)$fatal(1,"TXT caption lost during AV startup");
  keys[5]=0;cycles(600000);keys[5]=1;cycles(600000);
  if(dut.u_player.u_display.g_subtitles.u_overlay.direction!=1)$fatal(1,"subtitle long press did not start scrolling");
  expect_caption_scroll=1;
  n=transitions;next();if(transitions!=n+1 || dut.current_file_index!=1)$fatal(1,"normal next navigation");wait(!first_pending);
  n=transitions;previous();if(transitions!=n+1 || dut.current_file_index!=0)$fatal(1,"normal previous navigation");wait(!first_pending);
  pause_n=0;cycles(2000);before_samples=consumed;before_progress=ref_samples;cycles(10000);
  if(consumed!=before_samples || ref_samples!=before_progress)$fatal(1,"source pause advanced playback");
  n=transitions;next();if(transitions!=n+1 || dut.current_file_index!=1)$fatal(1,"paused next navigation");
  before_samples=consumed;cycles(10000);
  if(consumed!=before_samples || ref_samples!=0)$fatal(1,"paused next audio did not wait at zero");
  pause_n=1;wait(!first_pending);wait(consumed>before_samples+50);
  // The merged J1-7 control mutes HDMI while playback and its timer continue.
  keys[2]=0;cycles(600000);before_samples=consumed;before_progress=ref_samples;cycles(20000);
  if(consumed<=before_samples || dut.u_player.u_display.volume!=0 || dut.u_player.u_display.pause_request)
   $fatal(1,"display mute must silence HDMI while playback continues");
  keys[2]=1;cycles(600000);wait(consumed>before_samples+50);
  // First run AUTO with sound. Early image preparation must not drain the old
  // PCM bank while waiting for the deadline; every sample is still checked.
  auto_n=0;cycles(20);
  n=transitions;check_auto=0;wait(transitions>n);last_start=transition_time;check_auto=1;
  wait(transitions>=n+3);check_auto=0;before_samples=consumed;cycles(2000);
  if(led[3])$fatal(1,"old audio underflow while waiting for auto deadline");
  // Then pause audio while auto keeps its independent schedule.
  pause_n=0;cycles(2000);n=transitions;wait(transitions>=n+2);
  before_samples=consumed;cycles(2000);
  if(consumed!=before_samples || ref_samples!=0)$fatal(1,"auto during pause consumed PCM");
  // Stop scheduling and resume the most recent image at sample zero.
  auto_n=1;cycles(20);pause_n=1;wait(!first_pending);cycles(10000);
  if(first_checks<3 || auto_checks<2 || led[3] || dut.u_player.debug_error_flags!=0)
   $fatal(1,"AV coverage/status first=%0d auto=%0d leds=%h errors=%h",first_checks,auto_checks,led,dut.u_player.debug_error_flags);
  $display("AV_SYSTEM_PASS transitions=%0d first_sample_checks=%0d max_start_ns=%0d audio_samples=%0d loops=%0d auto_intervals=%0d source_pause=1 display_mute=1 paused_auto=1 no_old_epoch=1 caption_scroll_continuous=1",transitions,first_checks,max_start_ns,consumed,loops,auto_checks);$finish;
 end
 initial begin #1200000000;$fatal(1,"AV system watchdog transitions=%d ready=%b errors=%h",transitions,dut.load_ready,led);end
endmodule
