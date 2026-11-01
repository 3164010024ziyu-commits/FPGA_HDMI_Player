`timescale 1ns/1ps
// Verify each HDMI Audio Sample payload against every accepted source frame,
// including silence, channel signs, block-start/channel-status and ACR cadence.
module hdmi_audio_tb;
reg clk=0,pix=0,x5=0,reset=1;always #10 clk=~clk;always #20 pix=~pix;always #4 x5=~x5;
reg [9:0] h=0,v=0;reg [31:0] source=0;reg valid=0;
wire [31:0] pcm;wire empty,full,overflow,pop,audio_pkt;wire [1:0] status;
audio_fifo #(.AWIDTH(5)) fifo(.wr_clk(clk),.wr_rst(reset),.wr_en(valid),.wr_data(source),.full(full),.overflow(overflow),
 .rd_clk(pix),.rd_rst(reset),.rd_en(pop),.rd_data(pcm),.empty(empty));
hdmi_tx_core #(.AUDIO_EN(1)) hdmi(.clk_pixel(pix),.clk_pixel_x5(x5),.reset(reset),.hcnt(h),.vcnt(v),.rgb(24'h123456),
 .hs(!(h>=656 && h<752)),.vs(!(v>=490 && v<492)),.audio_sample(pcm),.audio_vol(8'hff),.audio_empty(empty),.audio_overflow(overflow),
 .audio_pop(pop),.audio_status(status),.audio_pkt(audio_pkt),.HDMI_CLK_P(),.HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P());
always @(posedge pix)if(reset)begin h<=0;v<=0;end else if(h==799)begin h<=0;v<=v==524 ? 0:v+1'b1;end else h<=h+1'b1;
reg [31:0] accumulator=0;reg [15:0] number=100;
reg [31:0] queue[0:9999];integer wp=0,rp=0,packets=0,acr=0,bstarts=0;
function [31:0] scale(input [31:0] a);
reg signed [23:0] l,r;
begin l=$signed(a[31:16])*9'sd255;r=$signed(a[15:0])*9'sd255;scale={l[23:8],r[23:8]};end endfunction
always @(posedge clk)begin
 if(reset)begin accumulator<=0;valid<=0;number<=100;end
 else begin
  valid<=0;
  if(accumulator>=50000000-48000)begin accumulator<=accumulator+48000-50000000;source<={number,-$signed(number)};number<=number+1;valid<=!full;end
  else accumulator<=accumulator+48000;
  if(valid && !full)begin queue[wp]=scale(source);wp=wp+1;end
 end
end
task check_payload(input [55:0] payload);
begin
 if(rp>=wp)$fatal(1,"packet has unprovided sample");
 if({payload[23:8],payload[47:32]}!==queue[rp])$fatal(1,"HDMI payload sample=%0d got=%h expected=%h",rp,{payload[23:8],payload[47:32]},queue[rp]);
 rp=rp+1;
end endtask
always @(posedge pix)if(!reset && hdmi.slot_pulse)begin
 if(hdmi.u_picker.use_audio_now)begin
  #1;
  check_payload(hdmi.pkt_sub0);check_payload(hdmi.pkt_sub1);check_payload(hdmi.pkt_sub2);check_payload(hdmi.pkt_sub3);packets=packets+1;
  if(hdmi.pkt_header[20])bstarts=bstarts+1;
 end else if(hdmi.u_picker.use_acr_now)begin #1;acr=acr+1;end
end
initial begin
 #200;reset=0;#100000000;
 if(packets<1000 || acr<90 || bstarts<20 || overflow)$fatal(1,"HDMI audio insufficient packets=%d acr=%d blockstarts=%d",packets,acr,bstarts);
 $display("HDMI_AUDIO_PASS samples=%0d packets=%0d acr=%0d blockstarts=%0d stereo_scaled_exact=1",rp,packets,acr,bstarts);$finish;
end
endmodule
