`timescale 1ns/1ps
module subtitle_overlay_tb;
reg clk=0,rst=0;always #20 clk=~clk;
reg [9:0] x=0,y=0;
always @(posedge clk)if(!rst)begin x<=0;y<=0;end else if(x==799)begin x<=0;y<=y==524?0:y+1'b1;end else x<=x+1'b1;
wire de=x<640 && y<480;
wire [23:0] rgb={x[7:0],y[7:0],8'h80};
reg sub_en=0,time_en=0,left=0,right=0,info_valid=0,playing=1;
reg [23:0] bcd=24'h010203;reg [135:0] info;
wire [23:0] out_rgb;
subtitle_overlay #(.LONG_PRESS_CYCLES(20)) dut(
 .clk(clk),.rst_n(rst),.de(de),.frame_sync(y==480),.x(x),.y(y),.rgb_in(rgb),.rgb_out(out_rgb),
 .sub_enable(sub_en),.time_enable(time_en),.left_pressed(left),.right_pressed(right),
 .info_valid(info_valid),.info(info),.audio_playing(playing),.audio_bcd(bcd));
integer fd,manifest;
task cycles(input integer n);repeat(n)@(negedge clk);endtask
task capture(input string name,input bit known_image);
 integer pixels;
 begin
  while(!(x==0 && y==0))@(negedge clk);
  fd=$fopen({name,".ppm"},"wb");$fwrite(fd,"P6\n640 480\n255\n");pixels=0;
  $fwrite(manifest,"%s %d %d %d %d %h %d\n",name,known_image,dut.sub_visible,dut.time_visible,dut.scroll,dut.shown_time,dut.marquee);
  begin:scan
   forever begin
    if(de)begin $fwrite(fd,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);pixels=pixels+1;end
    else if(out_rgb!==rgb)$fatal(1,"blanking changed");
    if(x==799 && y==524)disable scan;
    @(negedge clk);
   end
  end
  $fclose(fd);if(pixels!=307200)$fatal(1,"pixel count");@(negedge clk);
 end
endtask
initial begin
 manifest=$fopen("frames.txt","w");cycles(4);rst=1;cycles(2);
 capture("off",0);
 sub_en=1;time_en=1;
 capture("empty",0); // new switches become visible at the end of this frame
 capture("no_image",0);
 info={16'd2,"TEST    BMP",16'd640,16'd480};info_valid=1;cycles(1);info_valid=0;
 cycles(100);capture("before_commit",1);capture("picture",1);
 // Short-press steps once and pauses, long press starts pixel scrolling.
 left=1;cycles(4);left=0;cycles(2);
 capture("before_step",1);capture("step_left",1);
 if(dut.scroll!=16 || dut.direction!=0)$fatal(1,"short press did not step once");
 right=1;cycles(4);right=0;cycles(2);
 capture("before_right",1);capture("step_right",1);
 if(dut.scroll!=0)$fatal(1,"right step");
 left=1;cycles(25);left=0;cycles(2);capture("before_auto",1);capture("auto_left",1);
 if(dut.direction!=1)$fatal(1,"long press direction");
 left=1;right=1;cycles(3);left=0;right=0;cycles(3);
 capture("before_home",1);capture("home",1);
 if(dut.scroll!=0 || dut.direction!=0)$fatal(1,"both keys home");
 playing=0;capture("before_stop",1);capture("audio_stopped",1);
 if(dut.time_visible)$fatal(1,"time visible when stopped");
 $fclose(manifest);$display("SUBTITLE_OVERLAY_PASS full_frames=1 no_pixel_latency=1 switches=1 short_long_keys=1 audio_hide=1");$finish;
end
initial begin #400000000;$fatal(1,"overlay watchdog");end
endmodule
