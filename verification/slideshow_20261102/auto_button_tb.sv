`timescale 1ns/1ps
module auto_button_tb;
reg clk=0,rst=0,key=1;always #10 clk=~clk;
hdmi_player_board_top #(.ENABLE_FADE(0),.POWERUP_CYCLES(4),.DEBOUNCE_CYCLES(4),.SLIDESHOW_CYCLES(100)) dut(
 .SYS_CLK(clk),.Reset_n(rst),.KEY_LOAD_N(1'b1),.KEY_PREV_N(1'b1),.KEY_NEXT_N(1'b1),.KEY_AUTO_N(key),
 .SW_AUDIO_N(1'b1),.SW_MUTE_N(1'b1),.key_img(4'hf),.sd_miso(1'b1));
task cycles(input integer n);repeat(n)@(negedge clk);endtask
integer saved;
initial begin
 cycles(2);rst=1;wait(dut.board_reset_n);cycles(10);
 key=0;cycles(1);key=1;cycles(12);if(dut.slideshow_enabled)$fatal(1,"button bounce");
 key=0;cycles(300);if(!dut.slideshow_enabled || dut.u_player.starts<2)$fatal(1,"held AUTO repeated toggle or no timer");
 key=1;cycles(12);key=0;cycles(12);key=1;cycles(60);
 if(dut.slideshow_enabled)$fatal(1,"second AUTO press did not stop");saved=dut.u_player.starts;
 cycles(300);if(dut.u_player.starts!=saved)$fatal(1,"AUTO queued after stop");
 rst=0;cycles(2);if(dut.slideshow_enabled)$fatal(1,"AUTO reset");
 $display("AUTO_BUTTON_PASS GPIO=G12 debounce=1 hold_once=1 toggle_on_off=1 no_delayed_request=1 reset=1");$finish;
end
initial begin #100000;$fatal(1,"AUTO watchdog");end
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
