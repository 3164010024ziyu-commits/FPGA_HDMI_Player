`timescale 1ns/1ps
module slideshow_system_tb;
reg clk=0,rst_n=0,prev_n=1,next_n=1,auto_n=1;always #10 clk=~clk;
reg [6:0] display_keys=7'h7f;
wire cs,sck,mosi,miso;wire [3:0] led;
hdmi_player_board_top #(.ENABLE_FADE(1),.FADE_STEP(8),.SLIDESHOW_CYCLES(5000),.POWERUP_CYCLES(8),.DEBOUNCE_CYCLES(4)) dut(
 .SYS_CLK(clk),.Reset_n(rst_n),.KEY_LOAD_N(1'b1),.KEY_SPECTRUM_N(1'b1),.KEY_AUTO_N(auto_n),.KEY_PREV_N(prev_n),.KEY_NEXT_N(next_n),
 .SW_AUDIO_N(1'b1),.SW_MUTE_N(1'b1),.key_in(display_keys),.key_img(4'hf),.LED(led),
 .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),
 .HDMI_CLK_P(),.HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P());
integer reads,commands,loads=0,source_pixels=0,display_pixels=0,tag=0,source_offset=0;
integer bank_tag[0:1];
reg [23:0] expected;
integer x,y,bank;
multi_image_card_model card(.rst_n(rst_n),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),
 .high_capacity(1'b1),.corrupt_crc(1'b0),.suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),.reads(reads),.commands(commands));
always @(posedge clk)if(dut.board_reset_n)begin
 if(dut.load_start)$display("MULTI_REQUEST index=%0d select_last=%b current=%0d",dut.selected_file_index,dut.select_last,dut.current_file_index);
 if(dut.u_player.u_storage_pipeline.fat.file_open)begin
  tag=dut.opened_file_index+1;source_offset=0;loads=loads+1;
 end
 if(dut.u_player.image_meta_valid)begin
  bank=dut.u_player.u_memory.desc_base==0?0:1;bank_tag[bank]=tag;
 end
 if(dut.u_player.pixel_transfer)begin
  expected=(tag<<16)+source_offset;
  if(dut.u_player.pixel_rgb888!==expected)$fatal(1,"multi source pixel index=%d offset=%d got=%h",tag-1,source_offset,dut.u_player.pixel_rgb888);
  source_offset=source_offset+1;source_pixels=source_pixels+1;
 end
 if(dut.load_error)$display("MULTI_LOAD_ERROR code=%h target=%d",dut.load_error_code,dut.selected_file_index);
end
always @(posedge dut.u_player.display_clk)if(dut.u_player.display_reset_n && dut.u_player.u_display.VGA_DE && dut.display_ready)begin
 x=dut.u_player.u_display.VGA_X;y=dut.u_player.u_display.VGA_Y;
 bank=dut.u_player.u_memory.front_base==0?0:1;
 expected=x<16 && y<8 ? (bank_tag[bank]<<16)+y*16+x:0;
 if(dut.display_underflow || !dut.u_player.display_valid || dut.u_player.u_display.VGA_D!==expected)
  $fatal(1,"multi display bank=%0d tag=%0d xy=%0d,%0d got=%h expected=%h",bank,bank_tag[bank],x,y,dut.u_player.u_display.VGA_D,expected);
 display_pixels=display_pixels+1;
end
task request(input integer direction,wanted);
integer stable;
begin
 @(negedge clk);if(direction==0)next_n=0;else prev_n=0;
 repeat(12)@(negedge clk);next_n=1;prev_n=1;
 stable=0;
 while(stable<5)begin
  @(negedge clk);
  if(dut.load_ready && !dut.request_pending && !dut.u_navigation.in_flight)stable=stable+1;else stable=0;
 end
 if(dut.current_file_index!=wanted || dut.navigation_error || led[3])
  $fatal(1,"multi selection want=%0d current=%0d code=%h LED=%b",wanted,dut.current_file_index,dut.load_error_code,led);
 bank=dut.u_player.u_memory.front_base==0?0:1;
 if(bank_tag[bank]!=wanted+1)$fatal(1,"front buffer shows old image want=%d tag=%d",wanted,bank_tag[bank]);
 $display("MULTI_IMAGE_PASS index=%0d bank=%0d rgb=%h",wanted,bank,dut.u_player.u_memory.u2_ram.data[dut.u_player.u_memory.front_base]);
end endtask
integer seen=0,last_seen=-1,gain_checks=0,black_swaps=0;
reg [20:0] last_base=0;reg was_valid=0;
reg [5:0] frame_gain;
integer red,green,blue,level;
always @(posedge dut.u_player.display_clk)if(dut.u_player.display_reset_n)begin
 if(dut.u_player.u_display.VGA_DE && dut.display_ready)begin
  level=dut.u_player.display_fade_level;
  if(dut.u_player.u_display.VGA_X==0 && dut.u_player.u_display.VGA_Y==0)frame_gain=level;
  if(level!==frame_gain)$fatal(1,"gain changed in active frame");
  red=(dut.u_player.u_display.VGA_ADJ[23:16]*level)>>5;
  green=(dut.u_player.u_display.VGA_ADJ[15:8]*level)>>5;
  blue=(dut.u_player.u_display.VGA_ADJ[7:0]*level)>>5;
  if(dut.u_player.u_display.FADE_D!=={red[7:0],green[7:0],blue[7:0]})$fatal(1,"live faded pixel mismatch");
  gain_checks=gain_checks+1;
 end
end
always @(negedge dut.u_player.u_memory.Clk)if(dut.u_player.u_memory.mem_reset_n)begin
 if(was_valid && dut.u_player.u_memory.front_base!=last_base)begin
  if(dut.u_player.u_memory.fade_step!=0 || !dut.u_player.u_memory.blank_flush)$fatal(1,"nonblack or nonblank bank swap");
  black_swaps=black_swaps+1;
 end
 last_base=dut.u_player.u_memory.front_base;was_valid=dut.u_player.u_memory.front_valid;
end
// Subtitle descriptors must follow each real image through alternating slots.
reg [135:0] expected_info0,expected_info1,last_display_info;
integer subtitle_adoptions=0;
always @(posedge clk)if(dut.u_player.sys_reset_n && dut.u_player.u_memory.desc_valid)begin
 if(dut.u_player.u_memory.desc_base==0)
  expected_info0={dut.u_player.opened_file_index,dut.u_player.image_name,dut.u_player.image_width,dut.u_player.image_height};
 else expected_info1={dut.u_player.opened_file_index,dut.u_player.image_name,dut.u_player.image_width,dut.u_player.image_height};
end
always @(posedge dut.u_player.display_clk)if(dut.u_player.display_reset_n)begin
 if(dut.u_player.display_info_valid)begin
  last_display_info=dut.u_player.display_info;subtitle_adoptions=subtitle_adoptions+1;
  if(dut.u_player.display_info!==(dut.u_player.u_memory.front_base==0?expected_info0:expected_info1))
   $fatal(1,"subtitle metadata changed before its actual image adoption");
 end
 if(subtitle_adoptions>0 && dut.u_player.u_display.VGA_X==0 && dut.u_player.u_display.VGA_Y==1)
  if(dut.u_player.u_display.g_subtitles.u_overlay.active_info!==last_display_info)
   $fatal(1,"subtitle is not the current front image");
end
initial begin
 bank_tag[0]=0;bank_tag[1]=0;
 #100;rst_n=1;wait(dut.load_ready);
 // Reject short bounce, then hold AUTO through the first two image loads.
 @(negedge clk);auto_n=0;repeat(1)@(negedge clk);auto_n=1;
 repeat(15)@(negedge clk);if(dut.slideshow_enabled)$fatal(1,"AUTO bounce toggled");
 auto_n=0;
 while(seen<7)begin
  @(negedge clk);
  if(dut.load_ready && !dut.navigation_busy && dut.image_loaded_status && dut.current_file_index!=last_seen)begin
   if(dut.current_file_index!=(seen%6))$fatal(1,"auto sequence seen=%d actual=%d",seen,dut.current_file_index);
   $display("AUTO_IMAGE_PASS index=%d",dut.current_file_index);
   last_seen=dut.current_file_index;seen=seen+1;
   if(seen==2)begin auto_n=1;end
  end
 end
 // Stop on the seventh fully visible picture; no delayed automatic request.
 auto_n=1;repeat(12)@(negedge clk);auto_n=0;repeat(12)@(negedge clk);auto_n=1;
 repeat(10020)@(negedge clk);
 if(dut.slideshow_enabled || dut.navigation_busy || dut.current_file_index!=0)$fatal(1,"AUTO stop did not hold picture");
 request(0,1); // manual navigation still works with fade while stopped
 // Main key_in[1] is volume down, [2] is hold-to-mute.
 display_keys[1]=0;repeat(600000)@(negedge clk);
 if(dut.u_player.u_display.vol_level!=18)$fatal(1,"main volume key bus disconnected");
 repeat(600000)@(negedge clk);
 if(dut.u_player.u_display.vol_level!=18)$fatal(1,"held volume key repeated");
 display_keys[1]=1;repeat(600000)@(negedge clk);
 display_keys[2]=0;repeat(600000)@(negedge clk);
 if(dut.u_player.u_display.volume!=0)$fatal(1,"main mute key bus disconnected");
 display_keys[2]=1;repeat(600000)@(negedge clk);
 if(dut.u_player.u_display.volume!=242)$fatal(1,"main mute release lost volume");
 if(dut.slideshow_enabled || dut.navigation_busy)$fatal(1,"display key changed navigation");
 $display("MAIN_DISPLAY_KEYS_PASS routed_bus=1 volume_down=1 hold_once=1 mute=1 restore_volume=1 navigation_isolated=1");
 if(black_swaps<7 || gain_checks<307200 || led[3])$fatal(1,"integration checks incomplete");
 if(subtitle_adoptions<6)$fatal(1,"insufficient subtitle image coverage");
 $display("SUBTITLE_MULTI_IMAGE_PASS adoptions=%d filename_index_dimensions=1",subtitle_adoptions);
 $display("SLIDESHOW_SYSTEM_PASS auto_sequence=0,1,2,3,4,5,0 manual_after_stop=1 hold_once=1 bounce_ignored=1 black_swaps=%0d faded_pixels=%0d",black_swaps,gain_checks);$finish;
end
initial begin #900000000;$fatal(1,"slideshow watchdog current=%d code=%h",dut.current_file_index,dut.load_error_code);end
endmodule
