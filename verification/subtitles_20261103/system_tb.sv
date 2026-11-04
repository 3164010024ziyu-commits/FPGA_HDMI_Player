`timescale 1ns/1ps
module subtitle_system_tb;
reg clk=0,rst=0,load_n=1,spectrum_n=1,audio_n=1,mute_n=1;reg [6:0] keys=7'h67;
always #10 clk=~clk;
wire cs,sck,mosi,miso;wire [3:0] led;
hdmi_player_board_top #(.POWERUP_CYCLES(8),.DEBOUNCE_CYCLES(4),.SPECTRUM_DB_CYCLES(4),.FADE_STEP(8)) dut(
 .SYS_CLK(clk),.Reset_n(rst),.KEY_LOAD_N(load_n),.KEY_PREV_N(1'b1),.KEY_NEXT_N(1'b1),.KEY_AUTO_N(1'b1),
 .KEY_SPECTRUM_N(spectrum_n),.SW_AUDIO_N(audio_n),.SW_MUTE_N(mute_n),.key_img(4'hf),.key_in(keys),.LED(led),
 .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),.HDMI_CLK_P(),.HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P());
integer reads,commands;
audio_sd_card_model card(.rst_n(rst),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),.high_capacity(1'b1),
 .corrupt_crc(1'b0),.suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),.reads(reads),.commands(commands));
reg [2:0] tags[0:39999];reg [31:0] samples[0:39999];integer wp=0,rp=0,updates=0,overlay_pixels=0,source_pixels=0;
always @(posedge clk)if(dut.board_reset_n)begin
 if(dut.u_player.audio_valid && dut.u_player.audio_ready)begin samples[wp]=dut.u_player.audio_sample;tags[wp]=dut.u_player.audio_tag;wp=wp+1;end
 if(dut.u_player.pixel_transfer)source_pixels=source_pixels+1;
end
always @(posedge dut.u_player.display_clk)if(dut.u_player.display_reset_n)begin
 if(dut.u_player.u_display.audio_pop && !dut.u_player.u_display.audio_empty)begin
  if(rp>=wp || dut.u_player.u_display.audio_rd_data!==samples[rp])$fatal(1,"spectrum corrupted audio sample=%d",rp);rp=rp+1;
 end
 if(dut.u_player.u_display.g_spectrum.u_analyzer.update)updates=updates+1;
 if(dut.u_player.u_display.VGA_DE && dut.u_player.u_display.SPECTRUM_D!==dut.u_player.u_display.PARAM_D)overlay_pixels=overlay_pixels+1;
end
task cycles(input integer n);repeat(n)@(negedge clk);endtask
task press;begin spectrum_n=0;cycles(20);spectrum_n=1;cycles(20);end endtask
task image;begin wait(dut.load_ready);load_n=0;cycles(15);load_n=1;wait(!dut.load_ready);wait(dut.load_ready);end endtask
integer n,before_samples;
integer cp=0;integer valid_samples=0,loop_markers=0,descriptor_events=0,subtitle_pixels=0;
integer ref_samples=0,ref_seconds=0;reg [135:0] last_descriptor=0;
reg [23:0] expected_bcd;
function [23:0] as_bcd(input integer seconds);
 integer h,m,s;
 begin h=(seconds/3600)%100;m=(seconds/60)%60;s=seconds%60;
 as_bcd={4'(h/10),4'(h%10),4'(m/10),4'(m%10),4'(s/10),4'(s%10)};end
endfunction
always @(posedge dut.u_player.display_clk) if(dut.u_player.display_reset_n)begin
 if(dut.u_player.display_info_valid)begin
  last_descriptor=dut.u_player.display_info;descriptor_events=descriptor_events+1;
 end
 if(dut.u_player.u_display.VGA_X==0 && dut.u_player.u_display.VGA_Y==1 && descriptor_events>0)begin
  if(dut.u_player.u_display.g_subtitles.u_overlay.active_info!==last_descriptor)
    $fatal(1,"subtitle does not match the descriptor adopted by the raster reader");
 end
 if(dut.u_player.u_display.VGA_DE && dut.u_player.u_display.OSD_D!==dut.u_player.u_display.FADE_D)subtitle_pixels=subtitle_pixels+1;
 if(dut.u_player.u_display.audio_pop && !dut.u_player.u_display.audio_empty)begin
  if(dut.u_player.u_display.audio_rd_tag!==tags[cp])$fatal(1,"PCM tag CDC mismatch at %d",rp);
  if(!tags[cp][2])begin ref_samples=0;ref_seconds=0;end
  else if(tags[cp][1])begin
   valid_samples=valid_samples+1;
   if(tags[cp][0])begin ref_samples=1;ref_seconds=0;loop_markers=loop_markers+1;end
   else if(ref_samples==47999)begin ref_samples=0;ref_seconds=ref_seconds+1;end
   else ref_samples=ref_samples+1;
  end
  expected_bcd=as_bcd(ref_seconds);cp=cp+1;
  #1;
  if(dut.u_player.u_display.g_subtitles.u_progress.time_bcd!==expected_bcd ||
     dut.u_player.u_display.g_subtitles.u_progress.samples!==ref_samples)
    $fatal(1,"audio progress differs from actual HDMI PCM consumption expected=%h/%d actual=%h/%d tag=%b cp=%d",expected_bcd,ref_samples,dut.u_player.u_display.g_subtitles.u_progress.time_bcd,dut.u_player.u_display.g_subtitles.u_progress.samples,tags[cp-1],cp);
 end
end
initial begin
 cycles(4);rst=1;wait(dut.load_ready);cycles(10);
 spectrum_n=0;cycles(1);spectrum_n=1;cycles(15);
 if(dut.u_player.u_display.g_spectrum.selected)$fatal(1,"spectrum key bounce accepted");
 press();if(!dut.u_player.u_display.g_spectrum.selected)$fatal(1,"spectrum selection did not enable");
 cycles(100);if(dut.u_player.u_display.g_spectrum.u_overlay.visible)$fatal(1,"panel visible while audio off");
 audio_n=0;wait(dut.u_player.audio_playing);wait(dut.u_player.u_display.g_spectrum.u_overlay.visible);
 wait(updates>=3);if(dut.u_player.u_display.g_spectrum.levels==0)$fatal(1,"playing WAV produced empty spectrum");
 image();image();if(source_pixels!=256)$fatal(1,"image reload corrupted");
 // Source mute: PCM zeros, stream continues and spectrum becomes empty.
 mute_n=0;n=updates;wait(updates>=n+3);if(dut.u_player.u_display.g_spectrum.levels!=0)$fatal(1,"source mute not reflected");
 mute_n=1;n=updates;wait(updates>=n+3);if(dut.u_player.u_display.g_spectrum.levels==0)$fatal(1,"unmute not restored");
 // HDMI-side mute and volume operate after the audio FIFO.
 keys[2]=0;cycles(550000);n=updates;wait(updates>=n+3);
 if(dut.u_player.u_display.g_spectrum.levels!=0)$fatal(1,"HDMI-side mute not reflected");
 keys[2]=1;cycles(550000);n=updates;wait(updates>=n+3);
 if(dut.u_player.u_display.g_spectrum.levels==0)$fatal(1,"HDMI mute release not restored");
 // Subtitle switches hide text without changing PCM progress or playback.
 keys[4]=1;keys[3]=1;cycles(2000000);
 if(dut.u_player.u_display.g_subtitles.u_overlay.time_visible || dut.u_player.u_display.g_subtitles.u_overlay.sub_visible)
  $fatal(1,"subtitle switches did not hide both regions");
 keys[4]=0;keys[3]=0;cycles(2000000);
 if(!dut.u_player.u_display.g_subtitles.u_overlay.time_visible || !dut.u_player.u_display.g_subtitles.u_overlay.sub_visible)
  $fatal(1,"subtitle switches did not restore both regions");
 audio_n=1;wait(!dut.u_player.audio_playing);wait(!dut.u_player.u_display.g_spectrum.u_overlay.visible);
 if(!dut.u_player.u_display.g_spectrum.selected)$fatal(1,"audio stop forgot selection");
 audio_n=0;wait(dut.u_player.audio_playing);wait(dut.u_player.u_display.g_spectrum.u_overlay.visible);
 before_samples=rp;spectrum_n=0;cycles(2000);
 if(dut.u_player.u_display.g_spectrum.selected)$fatal(1,"spectrum key hold toggled repeatedly");
 spectrum_n=1;cycles(20);wait(!dut.u_player.u_display.g_spectrum.u_overlay.visible);cycles(10000);
 if(rp<=before_samples || !dut.u_player.audio_playing)$fatal(1,"hiding spectrum stopped audio");
 if(descriptor_events<2 || valid_samples<1000 || loop_markers<2 || subtitle_pixels<1000)$fatal(1,"subtitle coverage desc=%d valid=%d loops=%d pixels=%d",descriptor_events,valid_samples,loop_markers,subtitle_pixels);
 if(led[3] || dut.u_player.debug_error_flags!=0 || overlay_pixels<1000)$fatal(1,"spectrum system status led=%b flags=%h pixels=%d",led,dut.u_player.debug_error_flags,overlay_pixels);
 rst=0;cycles(3);if(dut.u_player.u_display.g_spectrum.selected)$fatal(1,"spectrum reset retained selection");
 $display("SUBTITLE_SYSTEM_PASS descriptors=%d valid_audio=%d loops=%d subtitle_pixels=%d",descriptor_events,valid_samples,loop_markers,subtitle_pixels);
 $display("SPECTRUM_SYSTEM_PASS source_pixels=%d audio_cdc_samples=%d spectrum_updates=%d overlay_pixels=%d two_images=1 source_mute=1 hdmi_mute=1 audio_off_hide=1 restart=1 toggle_hold_once=1 no_audio_stall=1 reset=1",source_pixels,rp,updates,overlay_pixels);$finish;
end
initial begin #750000000;$fatal(1,"spectrum system watchdog led=%b updates=%d samples=%d",led,updates,rp);end
endmodule
