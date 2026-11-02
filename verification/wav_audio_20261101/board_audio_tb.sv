`timescale 1ns/1ps
module board_audio_tb;
reg clk=0,rst=1,load_n=1,prev_n=1,next_n=1,sw_audio_n=1,sw_mute_n=1;
always #10 clk=~clk;
wire [3:0] leds;
hdmi_player_board_top #(.ENABLE_FADE(0),.POWERUP_CYCLES(8),.DEBOUNCE_CYCLES(4)) dut(
.SYS_CLK(clk),.Reset_n(rst),.KEY_LOAD_N(load_n),.KEY_AUTO_N(1'b1),.KEY_PREV_N(prev_n),.SW_AUDIO_N(sw_audio_n),.SW_MUTE_N(sw_mute_n),.KEY_NEXT_N(next_n),
.key_img(4'hf),.LED(leds),.sd_cs_n(),.sd_sck(),.sd_mosi(),.sd_miso(1'b1),
.HDMI_CLK_P(),.HDMI_D2_P(),.HDMI_D1_P(),.HDMI_D0_P());
task cycles(input integer n);repeat(n)@(negedge clk);endtask
task press(input integer direction);
begin
@(negedge clk);if(direction==0)load_n=0;else if(direction==1)prev_n=0;else next_n=0;
cycles(10);load_n=1;prev_n=1;next_n=1;cycles(10);
end endtask
task idle;
integer stable;
begin stable=0;while(stable<5)begin @(negedge clk);if(!dut.u_navigation.in_flight && !dut.request_pending && dut.u_player.remaining==0)stable=stable+1;else stable=0;end end
endtask
integer saved;
initial begin
wait(dut.board_reset_n);cycles(5);
// Short bounces are ignored before the first image.
prev_n=0;cycles(1);prev_n=1;cycles(1);prev_n=0;cycles(1);prev_n=1;cycles(12);
if(dut.u_player.starts!=0)$fatal(1,"GPIO bounce caused a load");
// A NEXT before ready waits, then selects image zero.
dut.u_player.ready_drive=0;press(2);if(!dut.request_pending)$fatal(1,"GPIO queued request missing");
dut.u_player.ready_drive=1;idle();if(dut.current_file_index!=0)$fatal(1,"first GPIO selection skipped image zero");
// Holding next must cause only one load, not repeated automatic navigation.
saved=dut.u_player.starts;next_n=0;cycles(100);next_n=1;cycles(10);idle();
if(dut.current_file_index!=1 || dut.u_player.starts!=saved+1)$fatal(1,"held GPIO repeated");
press(2);idle();if(dut.current_file_index!=2)$fatal(1,"next button mapping");
press(2);idle();if(dut.current_file_index!=0 || leds[3])$fatal(1,"last to first wrap");
press(1);idle();if(dut.current_file_index!=2 || leds[3])$fatal(1,"first to last wrap");
press(1);idle();press(1);idle();if(dut.current_file_index!=0)$fatal(1,"previous sequence");
saved=dut.u_player.starts;
prev_n=0;next_n=0;cycles(12);prev_n=1;next_n=1;cycles(12);
if(dut.u_player.starts!=saved)$fatal(1,"simultaneous GPIO events");
// The existing SW2 remains a reload control.
press(0);idle();if(dut.current_file_index!=0 || dut.u_player.starts!=saved+1)$fatal(1,"reload regression");
rst=0;#1;if(leds!==0 || dut.request_pending)$fatal(1,"reset did not clear GPIO control");
cycles(3);rst=1;wait(dut.board_reset_n);cycles(5);
if(dut.current_file_index!=0 || dut.request_pending)$fatal(1,"reset state");
// Debounced level controls must not consume any image key events.
sw_audio_n=0;cycles(1);sw_audio_n=1;cycles(10);
if(dut.u_player.audio_enable)$fatal(1,"SW3 glitch accepted");
sw_audio_n=0;cycles(10);if(!dut.u_player.audio_enable || dut.u_player.audio_mute)$fatal(1,"SW3 mapping");
sw_mute_n=0;cycles(10);if(!dut.u_player.audio_mute || !dut.u_player.audio_enable)$fatal(1,"SW4 mapping");
sw_mute_n=1;cycles(10);if(dut.u_player.audio_mute)$fatal(1,"SW4 release");
dut.u_player.audio_error_drive=1;cycles(5);if(!leds[3])$fatal(1,"audio error LED4 missing");
dut.u_player.audio_error_drive=0;sw_audio_n=1;cycles(10);
if(dut.u_player.audio_enable || !leds[3])$fatal(1,"stop or sticky audio error");
rst=0;cycles(2);if(leds[3])$fatal(1,"reset did not clear audio LED4");
rst=1;wait(dut.board_reset_n);cycles(10);
$display("BOARD_AUDIO_PASS sw3_enable=1 sw4_mute=1 glitch_rejected=1 sticky_LED4=1 reset=1 gpio_navigation_preserved=1");
$display("GPIO_BUTTONS_PASS J1_prev=1 J1_next=2 bounce_ignored=1 hold_once=1 startup_queue=1 circular_wrap=1 no_false_LED4=1 simultaneous_ignore=1 reload=1 reset=1");$finish;
end
initial begin #100000;$fatal(1,"GPIO timeout index=%d",dut.current_file_index);end
endmodule

module hdmi_player_top #(parameter CLK_HZ=50000000,parameter ENABLE_AUDIO=0,parameter ENABLE_FADE=0,parameter FADE_STEP=1)(
input audio_enable,audio_mute,output audio_error,output [7:0] audio_error_code,
input select_last,output [15:0] opened_file_index,
input SYS_CLK,Reset_n,start,input [15:0] file_index,input [20:0] frame_base_addr,
input [3:0] key_img,output load_ready,load_busy,output reg load_done,load_error,
output reg [7:0] load_error_code,output card_initialized,
output [3:0] debug_error_flags,output sd_cs_n,sd_sck,sd_mosi,input sd_miso,
output memory_frame_write_done,LED,display_ready,display_underflow,
output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P);
reg ready_drive=1,front_valid=0;
integer remaining=0,starts=0;
reg [15:0] latched_index;
reg audio_error_drive=0;
assign audio_error=audio_error_drive;assign audio_error_code=audio_error_drive ? 8'hB6 : 0;
assign opened_file_index=latched_index;
assign load_ready=Reset_n && ready_drive && remaining==0;
assign load_busy=remaining!=0;assign card_initialized=Reset_n;
assign LED=Reset_n;assign display_ready=Reset_n && front_valid;
assign display_underflow=0;assign memory_frame_write_done=0;
assign debug_error_flags={load_error,3'b000};
assign {sd_cs_n,sd_sck,sd_mosi,HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P}=7'd0;
always @(posedge SYS_CLK)begin
load_done<=0;
if(!Reset_n)begin remaining<=0;load_error<=0;load_error_code<=0;front_valid<=0;end
else if(start)begin
 if(!load_ready || frame_base_addr!=0)$fatal(1,"board started while busy");
 starts=starts+1;remaining<=20;latched_index<=select_last ? 16'd2 : file_index;load_error<=0;load_error_code<=0;
end else if(remaining>0)begin
 if(!select_last && file_index!==latched_index)$fatal(1,"file index changed before transaction finished");
 remaining<=remaining-1;
 if(remaining==8)begin
  if(latched_index<=2)begin load_done<=1;front_valid<=1;end
  else begin load_error<=1;load_error_code<=8'h36;end
 end
end
end
endmodule
