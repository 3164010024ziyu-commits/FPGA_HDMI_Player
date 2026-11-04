`timescale 1ns/1ps
module caption_publish_tb;
reg src_clk=0,pix_clk=0,rst_n=0;always #10 src_clk=~src_clk;always #17 pix_clk=~pix_clk;
reg write_enable=0,commit=0,src_has_text=1,publish=0,discard=0,frame_end=0;
reg [9:0] write_addr=0,read_addr=0;reg [15:0] write_data=0;reg [6:0]src_length=1;
wire src_ready,has_text,changed;wire[6:0]text_length;wire[15:0]read_data;
text_glyph_cache #(.WAIT_IMAGE(1))dut(.*);
task frame;begin @(negedge pix_clk);frame_end=1;@(negedge pix_clk);frame_end=0;repeat(8)@(negedge src_clk);end endtask
task fill(input integer value,input bit textflag);
begin wait(src_ready);@(negedge src_clk);write_enable=1;write_data=value;src_has_text=textflag;src_length=textflag?1:0;
@(negedge src_clk);write_enable=0;commit=1;@(negedge src_clk);commit=0;repeat(8)@(negedge pix_clk);end endtask
task show;begin @(negedge pix_clk);publish=1;@(negedge pix_clk);publish=0;frame();wait(src_ready);repeat(3)@(negedge pix_clk);end endtask
initial begin
repeat(4)@(negedge src_clk);rst_n=1;
fill('h1111,1);frame();frame();if(has_text || src_ready)$fatal(1,"preload published early");show();if(read_data!='h1111 || !has_text)$fatal(1,"first caption");
fill('h2222,1);frame();if(read_data!='h1111)$fatal(1,"old caption not held");@(negedge src_clk);discard=1;@(negedge src_clk);discard=0;repeat(5)@(negedge pix_clk);frame();wait(src_ready);if(read_data!='h1111)$fatal(1,"failed image changed caption");discard=0;
repeat(5)@(negedge pix_clk);fill('h3333,1);if(read_data!='h1111)$fatal(1,"cancel corrupted active bank");show();if(read_data!='h3333)$fatal(1,"reuse after cancel");
fill(0,0);frame();if(!has_text)$fatal(1,"missing TXT changed old image early");show();if(has_text || text_length!=0)$fatal(1,"missing TXT did not clear");
fill('h4444,1);show();if(read_data!='h4444 || !has_text)$fatal(1,"reload after missing TXT");
$display("CAPTION_PUBLISH_PASS no_early_publish=1 old_caption_held=1 failed_frame_discard=1 bank_reuse=1 missing_txt_clear=1");$finish;end
initial begin #1000000;$fatal(1,"publish watchdog");end
endmodule
