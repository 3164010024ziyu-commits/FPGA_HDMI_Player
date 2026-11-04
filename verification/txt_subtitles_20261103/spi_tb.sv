`timescale 1ns/1ps
module caption_spi_tb;
 reg clk=0,rst_n=0,start=0;always #10 clk=~clk;reg [15:0]file_index=0;
 wire sd_cs_n,sd_sck,sd_mosi,sd_miso,ready,busy,card_initialized,done,error,pixel_valid;
 wire [7:0]error_code;wire [23:0]pixel_rgb888;wire [15:0]pixel_x,pixel_y;
 wire text_glyph_we,text_commit,text_has_text;wire [9:0]text_glyph_addr;wire [15:0]text_glyph_data;wire [6:0]text_length;
 storage_pipeline #(.ENABLE_TEXT(1),.INIT_HALF_PERIOD(1),.READ_HALF_PERIOD(1)) dut(
  .clk(clk),.rst_n(rst_n),.sd_cs_n(sd_cs_n),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_miso(sd_miso),
  .audio_enable(1'b0),.audio_mute(1'b0),.audio_sink_active(1'b0),.audio_ready(1'b1),
  .start(start),.file_index(file_index),.select_last(1'b0),.ready(ready),.busy(busy),.card_initialized(card_initialized),
  .done(done),.error(error),.error_code(error_code),.pixel_valid(pixel_valid),.pixel_ready(1'b1),
  .pixel_rgb888(pixel_rgb888),.pixel_x(pixel_x),.pixel_y(pixel_y),
  .text_cache_ready(1'b1),.text_glyph_we(text_glyph_we),.text_glyph_addr(text_glyph_addr),
  .text_glyph_data(text_glyph_data),.text_commit(text_commit),.text_length(text_length),.text_has_text(text_has_text));
 integer reads,commands;
 caption_sd_card_model card(.rst_n(rst_n),.cs_n(sd_cs_n),.sck(sd_sck),.mosi(sd_mosi),.miso(sd_miso),
  .high_capacity(1'b1),.corrupt_crc(1'b0),.suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),.reads(reads),.commands(commands));
 integer pixels=0,writes=0,commits=0,cases=0;integer expected_chars=3;
 reg expected_text=1;reg [20:0]expected[0:2];
 function [7:0]payload(input integer byte_offset);payload=(byte_offset*13)^(byte_offset>>8)^(byte_offset>>16)^8'h5a;endfunction
 always @(posedge clk)begin
  if(text_glyph_we)begin
   if(text_glyph_addr!=writes || text_glyph_data!=={payload(expected[writes/16]*32+(writes%16)*2),payload(expected[writes/16]*32+(writes%16)*2+1)})
    $fatal(1,"real SPI glyph byte mismatch word=%0d addr=%0d data=%h",writes,text_glyph_addr,text_glyph_data);
   writes=writes+1;
  end
  if(text_commit)begin
   if(text_has_text!==expected_text || (expected_text && text_length!=expected_chars))$fatal(1,"SPI caption publish");commits=commits+1;
  end
  if(pixel_valid)begin
   if(pixel_x!=pixels%8 || pixel_y!=7-pixels/8 || pixel_rgb888!=={8'(pixels*3+2),8'(pixels*3+1),8'(pixels*3)})
    $fatal(1,"caption corrupted BMP pixels=%0d x=%0d y=%0d rgb=%h",pixels,pixel_x,pixel_y,pixel_rgb888);
   pixels=pixels+1;
  end
 end
 task image;
  begin wait(ready);@(negedge clk);start=1;pixels=0;writes=0;commits=0;@(negedge clk);start=0;
   wait(done || error);if(error || pixels!=64 || commits!=1 || (expected_text && writes!=48))
    $fatal(1,"SPI caption/image transaction failed case=%0d code=%h pixels=%d writes=%d",cases,error_code,pixels,writes);
   cases=cases+1;$display("CAPTION_SPI_CASE_PASS case=%0d glyph_words=%0d pixels=%0d reads=%0d",cases,writes,pixels,reads);repeat(10)@(negedge clk);
  end
 endtask
 initial begin
  expected[0]=65;expected[1]='h4e2d;expected[2]='h20bb7;
  repeat(4)@(negedge clk);rst_n=1;image();image();
  card.missing_text=1;expected_text=0;image();card.missing_text=0;
  // Reset discards the font directory cache, allowing a missing-font check.
  @(negedge clk);rst_n=0;repeat(4)@(negedge clk);rst_n=1;card.missing_font=1;image();
  card.missing_font=0;expected_text=1;image();
  // End-of-directory is a BMP error, then index zero must restart TXT and BMP.
  wait(ready);@(negedge clk);file_index=1;start=1;pixels=0;writes=0;commits=0;expected_text=0;
  @(negedge clk);start=0;wait(error);if(error_code!='h36)$fatal(1,"missing BMP diagnostic");
  repeat(5)@(negedge clk);file_index=0;expected_text=1;image();
  $display("CAPTION_SPI_PASS cases=%0d reload=1 missing_txt_fallback=1 missing_font_fallback=1 end_of_directory_recovery=1 pixels=384",cases);$finish;
 end
 initial begin #150000000;$fatal(1,"SPI caption watchdog");end
endmodule
