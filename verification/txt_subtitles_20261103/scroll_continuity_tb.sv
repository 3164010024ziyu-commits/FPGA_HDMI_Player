`timescale 1ns/1ps
module caption_scroll_continuity_tb;
 reg clk=0,rst_n=0;always #10 clk=~clk;
 reg [9:0]x=0,y=0;
 reg left_pressed=0,right_pressed=0,info_valid=0,text_active=1,text_changed=0;
 reg [135:0] info={16'd0,"TEST    BMP",16'd640,16'd480};
 reg [6:0]caption_length=64;
 wire [23:0]rgb_out;wire [9:0]caption_addr;
 subtitle_overlay #(.ENABLE_TEXT(1),.LONG_PRESS_CYCLES(4))dut(
 .clk(clk),.rst_n(rst_n),.de(1'b0),.frame_sync(1'b0),.x(x),.y(y),.rgb_in(24'd0),
 .sub_enable(1'b1),.time_enable(1'b0),.left_pressed(left_pressed),.right_pressed(right_pressed),
 .info_valid(info_valid),.info(info),.audio_playing(1'b0),.audio_bcd(24'd0),.rgb_out(rgb_out),
 .text_active(text_active),.text_changed(text_changed),.caption_length(caption_length),.caption_bits(16'd0),.caption_addr(caption_addr));
 integer expected_offset=0,expected_direction=1,period=1088,changes=0,frames=0;
 reg expected_marquee=1,slow=0;
 task check;
 begin
  if(dut.direction!==expected_direction[1:0] || dut.marquee!==expected_marquee || dut.scroll!==expected_offset[10:0])
   $fatal(1,"scroll continuity change=%0d frame=%0d dir=%0d/%0d offset=%0d/%0d marquee=%b/%b",changes,frames,dut.direction,expected_direction,dut.scroll,expected_offset,dut.marquee,expected_marquee);
 end endtask
 task pulse_frame;
 begin
  @(negedge clk);x=799;y=524;@(negedge clk);x=0;y=0;
  slow=!slow;frames=frames+1;repeat(2)@(negedge clk);
 end endtask
 task advance_frame;
 begin
  if(slow && expected_direction==1)expected_offset=(expected_offset+1)%period;
  if(slow && expected_direction==2)expected_offset=(expected_offset+period-1)%period;
  pulse_frame();check();
 end endtask
 task caption(input integer length_value,input bit active_value);
 begin
  @(negedge clk);caption_length=length_value;text_active=active_value;text_changed=1;
  @(negedge clk);text_changed=0;
  period=(active_value ? length_value+4:29)*16;
  expected_offset=expected_offset%period;
  repeat(32)@(negedge clk);changes=changes+1;check();
 end endtask
 task metadata;
 begin
  @(negedge clk);info[135:120]=info[135:120]+1'b1;info_valid=1;
  @(negedge clk);info_valid=0;repeat(60)@(negedge clk);
  advance_frame();changes=changes+1;check();
 end endtask
 task command(input integer action);
 begin
  @(negedge clk);left_pressed=action==1 || action==3 || action==5;right_pressed=action==2 || action==4 || action==5;
  if(action==3 || action==4)repeat(6)@(negedge clk);else repeat(2)@(negedge clk);
  left_pressed=0;right_pressed=0;repeat(3)@(negedge clk);
  case(action)
   1:begin expected_direction=0;expected_marquee=1;expected_offset=(expected_offset+16)%period;end
   2:begin expected_direction=0;expected_marquee=1;expected_offset=(expected_offset+period-16)%period;end
   3:begin expected_direction=1;expected_marquee=1;end
   4:begin expected_direction=2;expected_marquee=1;end
   5:begin expected_direction=0;expected_marquee=0;expected_offset=0;end
  endcase
  pulse_frame();check();
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  caption(64,1);metadata();repeat(4)advance_frame();
  command(4);repeat(8)advance_frame();metadata();
  if(expected_offset<112)$fatal(1,"shorter-caption wrap case was not exercised");
  caption(3,1);repeat(4)advance_frame();
  caption(64,1);metadata();repeat(4)advance_frame();
  caption(0,0);repeat(4)advance_frame();metadata();
  caption(2,1);repeat(4)advance_frame();command(3);metadata();caption(1,1);repeat(4)advance_frame();
  command(1);caption(64,1);metadata();repeat(4)advance_frame();
  command(5);caption(64,1);metadata();repeat(4)advance_frame();
  $display("CAPTION_SCROLL_CONTINUITY_PASS changes=%0d frames=%0d left=1 right=1 shorter_wrap=1 fallback=1 paused=1 explicit_home=1 first_long_auto=1",changes,frames);$finish;
 end
 initial begin #1000000;$fatal(1,"scroll continuity watchdog");end
endmodule
