// Compact glyph ROM, one shared serial decimal converter, no video framebuffer.
// ROM reads look ahead exactly one pixel. RGB, sync and coordinates are not delayed.
module subtitle_overlay #(
 parameter LONG_PRESS_CYCLES=12500000
)(
 input wire clk,rst_n,de,frame_sync,
 input wire [9:0] x,y,input wire [23:0] rgb_in,
 input wire sub_enable,time_enable,left_pressed,right_pressed,
 input wire info_valid,input wire [135:0] info,
 input wire audio_playing,input wire [23:0] audio_bcd,
 output reg [23:0] rgb_out
);
 // Metadata: {zero-based image index, FAT short name[11 bytes], width, height}.
 reg [135:0] prepared_info,active_info;
 reg have_prepared,have_image,prepared_toggle,active_toggle;
 reg [19:0] index_digits,width_digits,height_digits;
 reg [19:0] prepared_index,prepared_width,prepared_height;
 reg [19:0] decimal;
 reg [16:0] binary;
 reg [4:0] bit_count;
 reg [1:0] field;
 reg formatting;
 function [19:0] bcd_shift;
  input [19:0] bcd;input bit_in;
  reg [19:0] t;integer j;
  begin
   t=bcd;
   for(j=0;j<5;j=j+1)if(t[j*4+:4]>=5)t[j*4+:4]=t[j*4+:4]+4'd3;
   bcd_shift={t[18:0],bit_in};
  end
 endfunction
 wire [19:0] converted=bcd_shift(decimal,binary[16]);
 wire frame_end=x==799 && y==524;
 reg [23:0] shown_time;
 reg sub_visible,time_visible;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   prepared_info<=0;active_info<=0;have_prepared<=0;have_image<=0;
   prepared_toggle<=0;active_toggle<=0;index_digits<=0;width_digits<=0;height_digits<=0;
   prepared_index<=0;prepared_width<=0;prepared_height<=0;
   decimal<=0;binary<=0;bit_count<=0;field<=0;formatting<=0;
   shown_time<=0;sub_visible<=0;time_visible<=0;
  end else begin
   if(info_valid)begin
    prepared_info<=info;binary<={1'b0,info[135:120]}+17'd1;
    decimal<=0;bit_count<=0;field<=0;formatting<=1;
   end else if(formatting)begin
    decimal<=converted;binary<={binary[15:0],1'b0};
    if(bit_count==16)begin
     bit_count<=0;decimal<=0;
     case(field)
      0:begin prepared_index<=converted;binary<={1'b0,prepared_info[31:16]};field<=1;end
      1:begin prepared_width<=converted;binary<={1'b0,prepared_info[15:0]};field<=2;end
      default:begin
       prepared_height<=converted;formatting<=0;have_prepared<=1;prepared_toggle<=!prepared_toggle;
      end
     endcase
    end else bit_count<=bit_count+1'b1;
   end
   // Last blank pixel: metadata delivered anywhere during blank has time to format.
   if(frame_end)begin
    sub_visible<=sub_enable;time_visible<=time_enable && audio_playing;shown_time<=audio_bcd;
    if(have_prepared && !formatting && !info_valid)begin
     active_info<=prepared_info;have_image<=1;active_toggle<=prepared_toggle;
     index_digits<=prepared_index;width_digits<=prepared_width;height_digits<=prepared_height;
    end
   end
  end
 end

 reg [3:0] name_length;
 integer n;
 always @*begin
  name_length=1;
  for(n=0;n<8;n=n+1)
   if(active_info[119-n*8-:8]!=8'h20 && active_info[119-n*8-:8]!=0)name_length=n+1;
 end
 wire [1:0] width_length=active_info[31:16]>=100 ? 3 : active_info[31:16]>=10 ? 2 : 1;
 wire [1:0] height_length=active_info[15:0]>=100 ? 3 : active_info[15:0]>=10 ? 2 : 1;
 wire [6:0] text_length=have_image ? 7'd15+name_length+width_length+height_length : 7'd4;
 wire [6:0] period_chars=text_length+7'd4;
 function [7:0] ascii;
  input [7:0] value;
  begin ascii=(value>=32 && value<127)?value:8'd127;end
 endfunction
 function [7:0] normal_char;
  input [6:0] pos;
  reg [6:0] k;reg [3:0] digit;
  begin
   normal_char=32;k=0;digit=0;
   if(!have_image)begin
    case(pos)0:normal_char=132;1:normal_char=133;2:normal_char=128;3:normal_char=129;default:normal_char=32;endcase
   end else if(pos==0)normal_char=128;
   else if(pos==1)normal_char=129;
   else if(pos>=3 && pos<8)normal_char=8'd48+((index_digits >> ((7-pos)*4))&4'hf);
   else if(pos>=9 && pos<9+name_length)normal_char=ascii(active_info[119-(pos-9)*8-:8]);
   else if(pos==9+name_length)normal_char=".";
   else if(pos>=10+name_length && pos<13+name_length)normal_char=ascii(active_info[55-(pos-10-name_length)*8-:8]);
   else if(pos>=14+name_length && pos<14+name_length+width_length)begin
    k=pos-14-name_length;digit=(width_digits >> ((width_length-1-k)*4))&4'hf;normal_char=48+digit;
   end else if(pos==14+name_length+width_length)normal_char="x";
   else if(pos>=15+name_length+width_length && pos<text_length)begin
    k=pos-15-name_length-width_length;digit=(height_digits >> ((height_length-1-k)*4))&4'hf;normal_char=48+digit;
   end
  end
 endfunction
 function [7:0] time_char;
  input [3:0] pos;
  begin
   case(pos)
    0:time_char=130;1:time_char=131;2:time_char=32;
    3:time_char=48+shown_time[23:20];4:time_char=48+shown_time[19:16];5:time_char=":";
    6:time_char=48+shown_time[15:12];7:time_char=48+shown_time[11:8];8:time_char=":";
    9:time_char=48+shown_time[7:4];10:time_char=48+shown_time[3:0];default:time_char=32;
   endcase
  end
 endfunction

 // Debounced levels arrive from the existing display key synchronizers.
 localparam HOLD_BITS=LONG_PRESS_CYCLES>1?$clog2(LONG_PRESS_CYCLES):1;
 reg [HOLD_BITS-1:0] left_count,right_count;
 reg left_was,right_was,left_long,right_long;
 reg [2:0] pending_action; // 1/2 step, 3/4 auto, 5 reset
 reg [1:0] direction; // 0 pause, 1 left, 2 right
 reg marquee,slow_tick;
 reg [10:0] scroll;
 wire [10:0] period_pixels={period_chars,4'b0};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   left_count<=0;right_count<=0;left_was<=0;right_was<=0;left_long<=0;right_long<=0;
   pending_action<=0;direction<=0;marquee<=0;slow_tick<=0;scroll<=0;
  end else begin
   left_was<=left_pressed;right_was<=right_pressed;
   if(frame_end)begin
    slow_tick<=!slow_tick;
    if(have_prepared && !formatting && prepared_toggle!=active_toggle)begin
     scroll<=0;marquee<=text_length>38;direction<=text_length>38?1:0;pending_action<=0;
    end else if(pending_action!=0)begin
     pending_action<=0;
     case(pending_action)
      1:begin direction<=0;marquee<=1;scroll<=scroll+16>=period_pixels?scroll+16-period_pixels:scroll+16;end
      2:begin direction<=0;marquee<=1;scroll<=scroll<16?scroll+period_pixels-16:scroll-16;end
      3:begin direction<=1;marquee<=1;end
      4:begin direction<=2;marquee<=1;end
      default:begin direction<=0;marquee<=0;scroll<=0;end
     endcase
    end else if(sub_enable && slow_tick && direction!=0)begin
     if(direction==1)scroll<=scroll==period_pixels-1?0:scroll+1'b1;
     else scroll<=scroll==0?period_pixels-1:scroll-1'b1;
    end
   end
   if(left_pressed && right_pressed)begin
    if(!(left_was && right_was))pending_action<=5;
    left_count<=0;right_count<=0;left_long<=1;right_long<=1;
   end else begin
    if(left_pressed)begin
     if(!left_long)begin
      if(left_count==LONG_PRESS_CYCLES-1)begin pending_action<=3;left_long<=1;end
      else left_count<=left_count+1'b1;
     end
    end else begin
     left_count<=0;left_long<=0;
     if(left_was && !left_long)pending_action<=1;
    end
    if(right_pressed)begin
     if(!right_long)begin
      if(right_count==LONG_PRESS_CYCLES-1)begin pending_action<=4;right_long<=1;end
      else right_count<=right_count+1'b1;
     end
    end else begin
     right_count<=0;right_long<=0;
     if(right_was && !right_long)pending_action<=2;
    end
   end
  end
 end

 wire [9:0] nx=x==799?0:x+1'b1;
 wire [9:0] ny=x==799?(y==524?0:y+1'b1):y;
 wire next_sub=nx>=16 && nx<624 && ny>=452 && ny<468;
 wire next_time=nx>=16 && nx<192 && ny>=12 && ny<28;
 wire in_sub=de && sub_visible && x>=16 && x<624 && y>=452 && y<468;
 wire in_time=de && time_visible && x>=16 && x<192 && y>=12 && y<28;
 reg [6:0] scan_char;
 reg [3:0] scan_pixel,draw_pixel;
 wire [7:0] glyph=next_time?time_char((nx-16)>>4):next_sub?normal_char(scan_char):8'd32;
 wire [3:0] row=next_time?ny-12:ny-452;
 wire [15:0] glyph_bits;
 subtitle_font u_font(.clk(clk),.glyph(glyph),.row(row),.bits(glyph_bits));
 wire current_bit=glyph_bits[15-draw_pixel];
 reg previous_bit;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin scan_char<=0;scan_pixel<=0;draw_pixel<=0;previous_bit<=0;end
  else begin
   if(x==14)begin scan_char<=marquee?scroll[10:4]:0;scan_pixel<=marquee?scroll[3:0]:0;end
   if(next_sub)begin
    draw_pixel<=scan_pixel;scan_pixel<=scan_pixel+1'b1;
    if(scan_pixel==15)scan_char<=marquee && scan_char==period_chars-1?0:scan_char+1'b1;
   end else if(next_time)draw_pixel<=(nx-16)&15;
   previous_bit<=(in_sub || in_time)?current_bit:0;
  end
 end
 always @*begin
  rgb_out=rgb_in;
  if(in_sub || in_time)begin
   rgb_out={1'b0,rgb_in[23:17],1'b0,rgb_in[15:9],1'b0,rgb_in[7:1]};
   if(previous_bit && x!=16)rgb_out=0;
   if(current_bit)rgb_out=24'hffffff;
  end
 end
 wire unused=frame_sync;
endmodule
