`timescale 1ns/1ps
module overlay_tb;
reg clk=0,rst=0,enable=0,fs=0,de=1;reg [9:0] x=0,y=0;
reg [23:0] rgb=24'h7090b0;reg [111:0] levels=0;wire [23:0] out;
always #20 clk=~clk;
spectrum_overlay dut(clk,rst,enable,fs,de,x,y,rgb,levels,out);
task frame;begin fs=1;repeat(3)@(negedge clk);fs=0;@(negedge clk);end endtask
integer i,j,file,changed=0;
initial begin
 repeat(3)@(negedge clk);rst=1;
 x=330;y=410;#1;if(out!==rgb)$fatal(1,"overlay visible before enabled");
 enable=1;for(i=0;i<16;i=i+1)levels[i*7+:7]=(i*13+17)%73;
 #1;if(out!==rgb)$fatal(1,"overlay changed midframe on enable");frame();
 x=303;#1;if(out!==rgb)$fatal(1,"left ROI leaked");x=592;#1;if(out!==rgb)$fatal(1,"right ROI leaked");
 x=330;y=327;#1;if(out!==rgb)$fatal(1,"top ROI leaked");y=444;#1;if(out!==rgb)$fatal(1,"bottom ROI leaked");
 x=330;y=410;de=0;#1;if(out!==rgb)$fatal(1,"blanking changed");de=1;
 file=$fopen("overlay_pixels.hex","w");
 for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin
  x=i;y=j;rgb={i[7:0],j[7:0],8'h80};#1;$fwrite(file,"%h\n",out);
  if(out!==rgb)changed=changed+1;
 end
 $fclose(file);if(changed<10000 || changed>33408)$fatal(1,"panel footprint=%d",changed);
 levels=0;frame();if(dut.height[0]!=15)$fatal(1,"decay must be two pixels per frame");
 enable=0;#1;if(!dut.visible)$fatal(1,"disable changed midframe");frame();if(dut.visible)$fatal(1,"disable not latched");
 $display("SPECTRUM_OVERLAY_PASS frame_atomic=1 ROI_exact=1 no_pixel_latency=1 decay=1 hidden_passthrough=1 changed_pixels=%d",changed);$finish;
end
endmodule
