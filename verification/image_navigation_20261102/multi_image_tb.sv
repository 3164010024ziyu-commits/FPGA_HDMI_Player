`timescale 1ns/1ps
module multi_image_tb #(parameter CASE=0);
reg clk=0,rst_n=0,prev_n=1,next_n=1;always #10 clk=~clk;
wire cs,sck,mosi,miso;wire [3:0] led;
hdmi_player_board_top #(.ENABLE_FADE(0),.POWERUP_CYCLES(8),.DEBOUNCE_CYCLES(4)) dut(
 .SYS_CLK(clk),.Reset_n(rst_n),.KEY_LOAD_N(1'b1),.KEY_AUTO_N(1'b1),.KEY_PREV_N(prev_n),.KEY_NEXT_N(next_n),
 .SW_AUDIO_N(1'b1),.SW_MUTE_N(1'b1),.key_in(7'h7f),.key_img(4'hf),.LED(led),
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
initial begin
 bank_tag[0]=0;bank_tag[1]=0;
 #2;if(CASE==1)card.card[4*512+480]=0;
 #98;rst_n=1;wait(dut.load_ready);
 if(CASE==1)begin
  request(0,0);request(0,1);request(0,0);
  // The root becomes complete after an earlier observed two-entry boundary.
  card.card[4*512+480]=8'h49;
  request(0,1);request(0,2);request(0,3);request(0,4);request(0,5);
 end else begin request(0,0);request(0,1);request(0,2);request(0,3);request(0,4);request(0,5);end
 request(0,0);request(1,5);request(0,0);
 if(loads!=(CASE==1?11:9) || source_pixels!=(CASE==1?11:9)*128)$fatal(1,"multi load/pixel count=%d pixels=%d",loads,source_pixels);
 $display("MULTI_IMAGE_SYSTEM_PASS images_on_card=6 sequence=0,1,2,3,4,5,0,5,0 loads=%0d source_pixels=%0d display_pixels=%0d two_banks=1 spi_reads=%0d",loads,source_pixels,display_pixels,reads);$finish;
end
initial begin #220000000;$fatal(1,"multi-image watchdog current=%d code=%h",dut.current_file_index,dut.load_error_code);end
endmodule
