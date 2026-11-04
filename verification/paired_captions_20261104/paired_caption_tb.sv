`timescale 1ns/1ps
module paired_caption_tb;
reg clk=0,rst_n=0,start=0,select_last=0;always #10 clk=~clk;
reg [15:0] file_index=0;
wire cs,sck,mosi,miso,ready,done,error,pixel_valid,we,commit,has_text;
wire [7:0] error_code;wire [9:0] addr;wire [15:0] bits;wire [6:0] length;wire [15:0] opened_index;
storage_pipeline #(.ENABLE_TEXT(1),.INIT_HALF_PERIOD(1),.READ_HALF_PERIOD(1)) dut(
.clk(clk),.rst_n(rst_n),.start(start),.file_index(file_index),.select_last(select_last),.opened_index(opened_index),
.ready(ready),.done(done),.error(error),.error_code(error_code),.sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),
.audio_enable(1'b0),.audio_mute(1'b0),.audio_sink_active(1'b0),.audio_ready(1'b1),.audio_select(1'b0),.audio_start(1'b0),.audio_name(64'd0),
.pixel_valid(pixel_valid),.pixel_ready(1'b1),.text_cache_ready(1'b1),.text_glyph_we(we),.text_glyph_addr(addr),.text_glyph_data(bits),.text_commit(commit),.text_length(length),.text_has_text(has_text));
integer reads,commands;
paired_card_model card(.rst_n(rst_n),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),.high_capacity(1'b1),.corrupt_crc(1'b0),.suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),.reads(reads),.commands(commands));
integer expected_cp=65,writes=0,pixels=0,commits=0,cases=0;
function[7:0] glyph(input integer b);glyph=(b*13)^(b>>8)^8'h5a;endfunction
always @(posedge clk)begin
 if(we)begin
 if(expected_cp==0 || addr!=writes || bits!=={glyph(expected_cp*32+writes*2),glyph(expected_cp*32+writes*2+1)})$fatal(1,"wrong paired glyph case=%0d addr=%0d data=%h",cases,addr,bits);
 writes=writes+1;end
 if(commit)begin if(has_text!==(expected_cp!=0) || (expected_cp!=0 && length!=1))$fatal(1,"wrong caption state");commits=commits+1;end
 if(pixel_valid)pixels=pixels+1;
end
task load(input integer indexnum,cp,expected_index,input bit lastmode,expect_error);
 begin wait(ready);@(negedge clk);file_index=indexnum;select_last=lastmode;expected_cp=cp;writes=0;pixels=0;commits=0;start=1;
 @(negedge clk);start=0;wait(done || error);
 if(error!==expect_error || commits!=1 || (cp!=0 && writes!=16))$fatal(1,"load failed case=%0d error=%h pixels=%0d writes=%0d commits=%0d",cases,error_code,pixels,writes,commits);
 if(!expect_error && (pixels!=64 || opened_index!=expected_index))$fatal(1,"wrong BMP selection");
 cases=cases+1;repeat(8)@(negedge clk);end
endtask
initial begin
repeat(4)@(negedge clk);rst_n=1;
load(0,65,0,0,0);load(2,66,2,0,0);load(1,0,1,0,0);load(0,66,2,1,0);
load(0,65,0,0,0);card.broken_image=1;load(0,65,0,0,1);card.broken_image=0;
load(2,66,2,0,0);load(3,0,0,0,1);load(0,65,0,0,0);
$display("PAIRED_CAPTION_PASS cases=%0d directory_order_independent=1 missing_txt=1 select_last=1 invalid_bmp_recovery=1 missing_bmp_recovery=1",cases);$finish;end
initial begin #150000000;$fatal(1,"paired caption watchdog");end
endmodule
