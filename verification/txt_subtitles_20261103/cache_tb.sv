`timescale 1ns/1ps
module caption_cache_tb;
 reg clk=0,src_clk=0,rst_n=0;always #20 clk=~clk;always #10 src_clk=~src_clk;
 reg [9:0]x=0,y=0;
 always @(posedge clk)if(!rst_n)begin x<=0;y<=0;end else if(x==799)begin x<=0;y<=y==524?0:y+1'b1;end else x<=x+1'b1;
 wire publish=0,discard=0;
 reg write_enable=0,commit=0,src_has_text=1;reg [9:0]write_addr=0;reg [15:0]write_data=0;reg [6:0]src_length=3;
 wire src_ready,has_text,changed;wire [6:0]text_length;wire [9:0]read_addr;wire [15:0]read_data;
 wire frame_end=x==799 && y==524;
 text_glyph_cache cache(.src_clk(src_clk),.pix_clk(clk),.rst_n(rst_n),.*);
 reg left=0,right=0;wire [23:0]rgb={x[7:0],y[7:0],8'h80};wire [23:0]rgb_out;
 subtitle_overlay #(.ENABLE_TEXT(1),.LONG_PRESS_CYCLES(20)) overlay(
  .clk(clk),.rst_n(rst_n),.de(x<640 && y<480),.frame_sync(y==480),.x(x),.y(y),.rgb_in(rgb),.rgb_out(rgb_out),
  .sub_enable(1'b1),.time_enable(1'b0),.left_pressed(left),.right_pressed(right),.info_valid(1'b0),.info(136'd0),
  .audio_playing(1'b0),.audio_bcd(24'd0),.text_active(has_text),.text_changed(changed),.caption_length(text_length),
  .caption_bits(read_data),.caption_addr(read_addr));
 integer epoch=1,pixels=0,frames=0;
 function [15:0]bits(input integer bank_epoch,cellnum,rownum);
  bits=(bank_epoch*16'hac39)^(cellnum*7919)^(rownum*657);
 endfunction
 task fill(input integer count,input integer bank_epoch);
  begin
   wait(src_ready);src_length=count;
   for(integer n=0;n<count*16;n=n+1)begin
    @(negedge src_clk);write_enable=1;write_addr=n;write_data=bits(bank_epoch,n/16,n%16);
   end
   @(negedge src_clk);write_enable=0;commit=1;
   @(negedge src_clk);commit=0;
  end
 endtask
 task adopt;
  begin wait(!src_ready);wait(src_ready);repeat(3)@(negedge clk);end
 endtask
 task capture(input integer count,bank_epoch,offset,input bit marquee);
  integer u,cellnum,px;reg bit_on,prevbit,in_area;reg [23:0]expected;reg [15:0]rowbits;
  begin
   while(x!=0 || y!=0)@(negedge clk);
   begin:scan forever begin
    expected=rgb;in_area=x>=16 && x<624 && y>=452 && y<468;bit_on=0;
    if(in_area)begin
     u=x-16+offset;if(marquee)u=u%((count+4)*16);
     cellnum=u/16;px=u%16;rowbits=bits(bank_epoch,cellnum,y-452);
     bit_on=cellnum<count && rowbits[15-px];
     expected={1'b0,rgb[23:17],1'b0,rgb[15:9],1'b0,rgb[7:1]};
     if(prevbit && x!=16)expected=0;if(bit_on)expected='hffffff;
    end
    if(rgb_out!==expected)$fatal(1,"caption pixel frame=%0d x=%0d y=%0d got=%h expected=%h",frames,x,y,rgb_out,expected);
    prevbit=in_area && bit_on;pixels=pixels+1;
    if(frame_end)disable scan;@(negedge clk);
   end end
   frames=frames+1;@(negedge clk);
  end
 endtask
 task key(input integer action);
  begin left=action==1 || action==3;right=action==2 || action==3;
   repeat(4)@(negedge clk);left=0;right=0;repeat(3)@(negedge clk);
   while(!frame_end)@(negedge clk);repeat(3)@(negedge clk);
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  fill(3,1);adopt();if(text_length!=3 || !has_text)$fatal(1,"first bank");capture(3,1,0,0);
  key(1);if(overlay.scroll!=16)$fatal(1,"step");capture(3,1,16,1);
  key(2);key(2);if(overlay.scroll!=96)$fatal(1,"right wrap");capture(3,1,96,1);
  key(3);capture(3,1,0,0);
  // Build another complete bank during visible video, without disturbing A.
  while(x!=100 || y!=100)@(negedge clk);
  fill(64,2);if(src_ready)$fatal(1,"missing pending acknowledgement");
  if(text_length!=3 || !has_text)$fatal(1,"changed bank inside frame");
  while(!frame_end)begin @(negedge clk);if(text_length!=3)$fatal(1,"early bank adoption");end
  wait(src_ready);repeat(3)@(negedge clk);
  if(text_length!=64 || overlay.direction!=0)$fatal(1,"caption swap changed paused direction");
  key(3);capture(64,2,0,0);key(1);capture(64,2,16,1);
  // Missing/empty caption publishes an explicit fallback at a frame boundary.
  src_has_text=0;fill(0,3);adopt();if(has_text)$fatal(1,"fallback publish");
  $display("CAPTION_CACHE_PASS frames=%0d pixels=%0d bank_atomic=1 short_keys=1 wrap=1 fallback=1",frames,pixels);$finish;
 end
 initial begin #600000000;$fatal(1,"cache watchdog");end
endmodule
