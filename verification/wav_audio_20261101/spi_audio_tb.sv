`timescale 1ns/1ps
module spi_audio_tb;
reg clk=0,rst_n=0,start=0,enable=0,mute=0;always #10 clk=~clk;
wire cs,sck,mosi,miso,ready,busy,done,error,meta_valid,top_down,initialized;
wire [7:0] error_code,audio_error_code;
wire [31:0] sample;wire audio_valid,audio_error;
reg pix=0,x5=0;always #20 pix=~pix;always #4 x5=~x5;
reg [9:0] h=0,v=0;
wire [31:0] pcm;wire pcm_empty,pcm_full,pcm_overflow,pcm_pop;
wire [1:0] hdmi_status;
audio_fifo #(.AWIDTH(5)) audio_fifo_dut(.wr_clk(clk),.wr_rst(!rst_n),.wr_en(audio_valid),.wr_data(sample),
 .full(pcm_full),.overflow(pcm_overflow),.rd_clk(pix),.rd_rst(!rst_n),.rd_en(pcm_pop),.rd_data(pcm),.empty(pcm_empty));
hdmi_tx_core #(.AUDIO_EN(1)) hdmi(.clk_pixel(pix),.clk_pixel_x5(x5),.reset(!rst_n),.hcnt(h),.vcnt(v),.rgb(24'h123456),
 .hs(!(h>=656 && h<752)),.vs(!(v>=490 && v<492)),.audio_sample(pcm),.audio_vol(8'hff),.audio_empty(pcm_empty),
 .audio_overflow(pcm_overflow),.audio_pop(pcm_pop),.audio_status(hdmi_status),.audio_pkt(),
 .HDMI_CLK_P(),.HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P());
always @(posedge pix)if(!rst_n)begin h<=0;v<=0;end else if(h==799)begin h<=0;v<=v==524?0:v+1'b1;end else h<=h+1'b1;
wire [23:0] rgb;wire pixel_valid;reg pixel_ready=1;
wire [15:0] px,py;
integer reads,commands;
storage_pipeline #(.ENABLE_AUDIO(1),.INIT_HALF_PERIOD(3),.MAX_WIDTH(64),.MAX_HEIGHT(64)) dut(
 .clk(clk),.rst_n(rst_n),.audio_enable(enable),.audio_mute(mute),.audio_sink_active(1'b1),.audio_ready(!pcm_full),
 .audio_sample(sample),.audio_valid(audio_valid),.audio_error(audio_error),.audio_error_code(audio_error_code),
 .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),
 .start(start),.file_index(16'd0),.select_last(1'b0),.opened_index(),.ready(ready),.busy(busy),
 .card_initialized(initialized),.done(done),.error(error),.error_code(error_code),
 .short_name(),.file_size(),.meta_valid(meta_valid),.width(),.height(),.top_down(top_down),
 .pixel_valid(pixel_valid),.pixel_ready(pixel_ready),.pixel_rgb888(rgb),.pixel_rgb565(),
 .pixel_x(px),.pixel_y(py),.pixel_addr(),.pixel_sof(),.pixel_eol(),.pixel_eof());
reg corrupt=0;
audio_sd_card_model card(.rst_n(rst_n),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),
 .high_capacity(1'b1),.corrupt_crc(corrupt),.suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),.reads(reads),.commands(commands));
integer cursor=0,frames=0,pixels=0,ticks=0,muted=0,silence=0,cycles=0,last_tick=0;
reg [31:0] expected_sent;reg [23:0] expected_rgb;
reg [31:0] hdmi_expected[0:19999];integer hw=0,hr=0,packets=0,acr=0;
function [31:0] scale(input [31:0] a);
reg signed [23:0] l,r;
begin l=$signed(a[31:16])*9'sd255;r=$signed(a[15:0])*9'sd255;scale={l[23:8],r[23:8]};end endfunction
always @(posedge clk)if(rst_n && audio_valid && !pcm_full)begin hdmi_expected[hw]=scale(sample);hw=hw+1;end
task check_packet(input [55:0] payload);
begin
 if(hr>=hw || {payload[23:8],payload[47:32]}!==hdmi_expected[hr])$fatal(1,"SD to HDMI payload sample=%d got=%h expected=%h",hr,{payload[23:8],payload[47:32]},hdmi_expected[hr]);
 hr=hr+1;
end endtask
always @(posedge pix)if(rst_n && hdmi.slot_pulse)begin
 if(hdmi.u_picker.use_audio_now)begin
  #1;check_packet(hdmi.pkt_sub0);check_packet(hdmi.pkt_sub1);check_packet(hdmi.pkt_sub2);check_packet(hdmi.pkt_sub3);packets=packets+1;
 end else if(hdmi.u_picker.use_acr_now)begin #1;acr=acr+1;end
end
function [31:0] expected(input integer i);
reg [15:0] l,r;
begin l=(i*13+1000)%12000;r=-((i*7+2000)%14000);expected={l,r};end
endfunction
always @(posedge clk)if(rst_n)begin
 cycles=cycles+1;if(cycles>13000000)$fatal(1,"SPI audio watchdog");
 expected_sent=dut.g_audio.g_background.player.pop && !mute ? expected(cursor) : 32'd0;
 if(!enable)cursor=0;
 else if(dut.g_audio.g_background.player.pop)begin cursor=cursor==2047 ? 0 : cursor+1;frames=frames+1;if(mute)muted=muted+1;end
 if(pixel_valid && pixel_ready)begin
  expected_rgb={8'(8'h80+pixels/17+pixels%17),8'(pixels%17),8'(8'h30+pixels/17)};
  if(rgb!==expected_rgb || px!==16'(pixels%17) || py!==16'(22-pixels/17))$fatal(1,"concurrent BMP corruption pixel=%d rgb=%h",pixels,rgb);
  pixels=pixels+1;
 end
end
always @(negedge clk)if(rst_n && audio_valid)begin
 ticks=ticks+1;
 if(last_tick!=0 && cycles-last_tick!=1041 && cycles-last_tick!=1042)$fatal(1,"48kHz cadence gap=%d",cycles-last_tick);
 last_tick=cycles;
 if(sample!==expected_sent)$fatal(1,"SPI PCM cursor=%d sample=%h expected=%h",cursor,sample,expected_sent);
 if(sample==0)silence=silence+1;
end
task image;
begin wait(ready);@(negedge clk);pixels=0;start=1;@(negedge clk);start=0;wait(done || error);
 if(error || pixels!=391)$fatal(1,"concurrent image failed pixels=%d code=%h",pixels,error_code);
end endtask
initial begin
 repeat(4)@(negedge clk);rst_n=1;wait(initialized);
 repeat(1200)@(negedge clk);if(sample!=0)$fatal(1,"disabled is not silent");
 enable=1;wait(frames>=1200);image();
 wait(frames>=2200);mute=1;repeat(300000)@(negedge clk);mute=0;
 wait(frames>=4400);
 if(audio_error || error || muted<100 || dut.g_audio.g_background.player.file_index!=1)$fatal(1,"audio concurrent/skip/loop code=%h index=%d",audio_error_code,dut.g_audio.g_background.player.file_index);
 // Disable while a WAV sector is owned. It must drain, allowing BMP progress.
 wait(dut.g_audio.arbiter.owner==2);@(negedge clk);enable=0;image();
 if(audio_error)$fatal(1,"stop did not clear fault");
 enable=1;wait(frames>=4700);
 // A corrupted audio sector reports an error but image reads can recover.
 wait(dut.g_audio.arbiter.owner==2 && !cs);corrupt=1;wait(audio_error);corrupt=0;
 if(error)$fatal(1,"audio error leaked to image client");
 repeat(1000)@(negedge clk);image();
 enable=0;repeat(10000)@(negedge clk);enable=1;wait(frames>=5000);
 if(audio_error)$fatal(1,"off/on did not recover audio code=%h",audio_error_code);
 // No compatible WAV must leave image reading available and report B6.
 @(negedge clk);enable=0;wait(dut.g_audio.arbiter.owner==0 && dut.sd.req_ready);
 card.card[4*512+32]=0;enable=1;wait(audio_error);
 if(audio_error_code!='hB6)$fatal(1,"missing WAV error=%h",audio_error_code);
 image();
 if(pcm_overflow || packets<1000 || acr<80)$fatal(1,"HDMI audio transport count/status");
 $display("SPI_WAV_PASS played=%0d ticks=%0d stereo_exact=1 skip_mono=1 loop=1 mute_consumes=%0d shared_bmp=1 disable_drains=1 crc_isolated=1 restart=1 no_wav_isolated=1 hdmi_samples=%0d packets=%0d acr=%0d",frames,ticks,muted,hr,packets,acr);$finish;
end
endmodule
