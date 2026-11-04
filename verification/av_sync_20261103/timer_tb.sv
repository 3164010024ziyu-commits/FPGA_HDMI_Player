`timescale 1ns/1ps
module av_timer_tb;
 reg clk=0;always #5 clk=~clk;
 reg reset_n=0,toggle_press=0,manual_press=0,can_advance=1,image_loaded=1,transition_start=0;
 wire enabled,next_press,hold_presentation,audio_prepare_window;
 av_slideshow_ctrl #(.INTERVAL_CYCLES(100),.PRELOAD_CYCLES(40),.AUDIO_LEAD_CYCLES(10))dut(.*);
 integer cycles=0,requests=0;
 always @(posedge clk)begin cycles=cycles+1;if(next_press)requests=requests+1;end
 task pulse_transition;
 begin @(negedge clk);transition_start=1;@(negedge clk);transition_start=0;end endtask
 initial begin
  repeat(3)@(negedge clk);reset_n=1;toggle_press=1;@(negedge clk);toggle_press=0;
  pulse_transition();
  repeat(59)@(negedge clk);if(next_press || hold_presentation)$fatal(1,"early prefetch");
  wait(next_press);@(negedge clk);can_advance=0;
  if(!hold_presentation)$fatal(1,"no preload hold");
  repeat(20)@(negedge clk);if(!hold_presentation)$fatal(1,"early deadline release");
  if(audio_prepare_window)$fatal(1,"audio reader switched away from old track too early");
  wait(audio_prepare_window);if(dut.age!=90)$fatal(1,"wrong audio prefetch window");
  wait(!hold_presentation);if(dut.age!=100)$fatal(1,"wrong deadline");
  repeat(30)@(negedge clk);if(requests!=1)$fatal(1,"duplicate pending request");
  pulse_transition();can_advance=1;
  repeat(10)@(negedge clk);manual_press=1;@(negedge clk);manual_press=0;can_advance=0;
  repeat(10)@(negedge clk);pulse_transition();repeat(4)@(negedge clk);can_advance=1;
  repeat(30)@(negedge clk);if(requests!=1)$fatal(1,"manual timeline not reset");
  wait(next_press);@(negedge clk);toggle_press=1;@(negedge clk);toggle_press=0;
  if(enabled || hold_presentation)$fatal(1,"stop retained scheduled hold");
  $display("AV_TIMER_PASS production_interval=250000000 prefetch_deadline=1 busy_saturation=1 manual_reset=1 stop_releases=1");$finish;
 end
 initial begin #100000;$fatal(1,"timer watchdog");end
endmodule

module av_progress_tb;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,consume=0,restart=0;reg [2:0]tag=0;wire playing;wire [23:0]time_bcd;
 audio_progress #(.FS(4),.HOLD_IDLE(1))dut(.*);
 initial begin
  repeat(3)@(negedge clk);rst_n=1;restart=1;@(negedge clk);restart=0;
  consume=1;tag=3'b111;@(negedge clk);tag=3'b110;repeat(3)@(negedge clk);
  if(time_bcd!=1 || dut.samples!=0)$fatal(1,"progress setup");
  tag=3'b100;repeat(20)@(negedge clk);
  if(time_bcd!=1 || dut.samples!=0 || !playing)$fatal(1,"paused progress not frozen/visible");
  tag=3'b110;@(negedge clk);if(dut.samples!=1)$fatal(1,"resume progress");
  restart=1;@(negedge clk);restart=0;tag=3'b100;repeat(10)@(negedge clk);
  if(time_bcd!=0 || dut.samples!=0 || !playing)$fatal(1,"paused next track reset");
  tag=3'b111;@(negedge clk);if(dut.samples!=1)$fatal(1,"new first sample");
  $display("AV_PROGRESS_PASS pause_seconds=1 pause_samples=1 paused_next_zero=1 restart=1");$finish;
 end
endmodule
