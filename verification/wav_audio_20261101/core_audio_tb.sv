`timescale 1ns/1ps
module core_audio_tb;
reg clk=0,rst_n=0,start=0,enable=0,mute=0;always #10 clk=~clk;
wire ready,busy,done,error,audio_error,cs,sck,mosi,miso,front,underflow;
wire [7:0] error_code,audio_code;wire [3:0] flags;
hdmi_player_top #(.ENABLE_AUDIO(1),.INIT_HALF_PERIOD(3)) dut(
 .SYS_CLK(clk),.Reset_n(rst_n),.audio_enable(enable),.audio_mute(mute),.audio_error(audio_error),.audio_error_code(audio_code),
 .start(start),.file_index(16'd0),.select_last(1'b0),.opened_file_index(),.frame_base_addr(21'd256),.key_img(4'hf),
 .load_ready(ready),.load_busy(busy),.load_done(done),.load_error(error),.load_error_code(error_code),.card_initialized(),.debug_error_flags(flags),
 .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),.memory_frame_write_done(),.LED(),
 .display_ready(front),.display_underflow(underflow),.HDMI_CLK_P(),.HDMI_D2_P(),.HDMI_D1_P(),.HDMI_D0_P());
integer reads,commands;
audio_sd_card_model card(.rst_n(rst_n),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),
 .high_capacity(1'b1),.corrupt_crc(1'b0),.suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),.reads(reads),.commands(commands));
reg [31:0] samples[0:9999];integer wp=0,rp=0,source_pixels=0,frames_loaded=0,muted=0;
always @(posedge clk)if(rst_n)begin
 if(dut.audio_valid && dut.audio_ready)begin samples[wp]=dut.audio_sample;wp=wp+1;end
 if(dut.pixel_transfer)source_pixels=source_pixels+1;
 if(done)frames_loaded=frames_loaded+1;
 if(enable && mute && dut.u_storage_pipeline.g_audio.player.pop)muted=muted+1;
end
always @(posedge dut.display_clk)if(dut.display_reset_n && dut.u_display.audio_pop && !dut.u_display.audio_empty)begin
 if(rp>=wp || dut.u_display.audio_rd_data!==samples[rp])$fatal(1,"core audio CDC sample=%d got=%h expected=%h",rp,dut.u_display.audio_rd_data,samples[rp]);
 rp=rp+1;
end
task image;
begin wait(ready);@(negedge clk);start=1;@(negedge clk);start=0;wait(!ready);wait(ready);
 if(error)$fatal(1,"core image error=%h",error_code);
end endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;enable=1;
 wait(dut.u_storage_pipeline.g_audio.player.primed);image();
 mute=1;repeat(120000)@(negedge clk);mute=0;image();
 wait(dut.u_storage_pipeline.g_audio.player.buffer.rp>1500);repeat(10000)@(negedge clk);
 if(audio_error || error || flags!=0 || !front || underflow || frames_loaded!=2 || source_pixels!=256 || rp<1500 || muted<50)
  $fatal(1,"core audio/image status audio=%h image=%h flags=%h front=%b pixels=%d samples=%d",audio_code,error_code,flags,front,source_pixels,rp);
 $display("CORE_WAV_HDMI_PASS source_pixels=%0d images=%0d audio_cdc_samples=%0d muted_frames=%0d front_valid=1 all_errors=0",source_pixels,frames_loaded,rp,muted);$finish;
end
initial begin #150000000;$fatal(1,"core audio watchdog flags=%h audio=%h",flags,audio_code);end
endmodule
