from pathlib import Path
import math,random,json,shutil
import numpy as np
R=Path(__file__).resolve().parent;S=R.parents[1];T=R;T.mkdir(parents=True,exist_ok=True)
def int16(v):return ((int(v)+32768)&65535)-32768
def fft_fixed(values):
    n=512;a=[(int(values[int(f'{i:09b}'[::-1],2)]),0) for i in range(n)]
    for stage in range(9):
        half=1<<stage
        for base in range(0,n,half*2):
            for j in range(half):
                p=base+j;q=p+half;k=j*(256//half)
                c=round(math.cos(2*math.pi*k/n)*16384);s=round(math.sin(2*math.pi*k/n)*16384)
                ar,ai=a[p];br,bi=a[q]
                tr=(c*br+s*bi)>>14;ti=(c*bi-s*br)>>14
                a[p]=(int16((ar+tr)>>1),int16((ai+ti)>>1));a[q]=(int16((ar-tr)>>1),int16((ai-ti)>>1))
    mags=[max(abs(x),abs(y))+min(abs(x),abs(y))//4 for x,y in a]
    return mags,a
def tone(k,amp=20000):return [round(amp*math.sin(2*math.pi*k*i/512)) for i in range(512)]
rng=random.Random(451)
vectors=[[0]*512,[16000]*512,[32767]*512,[-32768]*512,[32767]+[0]*511,
         *[tone(k) for k in (1,2,7,11,32,64,120,200,255)],
         [round(10000*math.sin(2*math.pi*11*i/512)+7000*math.sin(2*math.pi*64*i/512)) for i in range(512)],
         [rng.randrange(-32768,32768) for _ in range(512)]]
expected=[];max_err=0
for v in vectors:
    m,c=fft_fixed(v);expected.extend(m)
    ideal=np.fft.fft(v)/512
    max_err=max(max_err,max(max(abs(z.real-x),abs(z.imag-y)) for z,(x,y) in zip(ideal,c)))
assert max_err<12,max_err
def hexfile(name,values,width):
    (T/name).write_text(''.join(f'{int(v)&((1<<width)-1):0{width//4}x}\n' for v in values),encoding='ascii')
hexfile('fft_input.hex',[x for v in vectors for x in v],16);hexfile('fft_expected.hex',expected,16)
(T/'fft_tb.sv').write_text(f'''`timescale 1ns/1ps
module fft_tb;
reg clk=0,rst=0,enable=1,valid=0;reg signed [15:0] data=0;always #20 clk=~clk;
wire [8:0] addr;wire [15:0] mag;wire mv,busy;
audio_fft512 dut(clk,rst,enable,data,valid,addr,mag,mv,busy);
reg [15:0] inputs[0:{len(vectors)*512-1}],expected[0:{len(vectors)*512-1}];
integer c=0,n,seen=0,total=0;
always @(negedge clk)if(rst && mv)begin
 if(addr!==seen || mag!==expected[c*512+seen])$fatal(1,"FFT case=%d bin=%d got_addr=%d mag=%d expected=%d",c,seen,addr,mag,expected[c*512+seen]);
 seen=seen+1;total=total+1;
end
initial begin
 $readmemh("fft_input.hex",inputs);$readmemh("fft_expected.hex",expected);
 repeat(3)@(negedge clk);rst=1;
 // Clear an incomplete block synchronously; stale samples must be discarded.
 data=123;valid=1;repeat(13)@(negedge clk);valid=0;enable=0;repeat(3)@(negedge clk);enable=1;
 for(c=0;c<{len(vectors)};c=c+1)begin
  seen=0;
  for(n=0;n<512;n=n+1)begin data=inputs[c*512+n];valid=1;@(negedge clk);end
  valid=0;wait(busy);repeat(5)@(negedge clk);
  // Input changes while computing must not corrupt the captured block.
  valid=1;data=16'h8123;repeat(17)@(negedge clk);valid=0;
  wait(seen==512);@(negedge clk);
 end
 $display("FFT512_PASS cases={len(vectors)} bins=%0d fixed_reference_exact=1 disabled_partial_discard=1 busy_input_ignored=1",total);$finish;
end
initial begin #100000000;$fatal(1,"FFT watchdog");end
endmodule
''',encoding='ascii')
edges=[1,2,3,4,5,7,10,14,20,28,40,57,80,113,160,208,256]
window=[round((.5-.5*math.cos(2*math.pi*i/511))*32767) for i in range(512)]
def height(m):
 if m<=16:return 0
 hi=m.bit_length()-1;q=(hi<<3)+(((m<<3)>>hi)&7)
 return min(72,q-32)
cases=[('silence',[0]*512,[0]*512,255),('bass',tone(1),tone(1),255),('1k',tone(11),tone(11),255),
       ('6k',tone(64),tone(64),255),('high',tone(200),tone(200),255),
       ('right_only',[0]*512,tone(32),255),('anti_phase',tone(11),[-v for v in tone(11)],255),
       ('stereo_louder_right',tone(7,7000),tone(64,24000),255),
       ('two_tones',vectors[-2],vectors[-2],255),('low_volume',tone(11),tone(11),64),
       ('muted',tone(11),tone(11),0),('noise',vectors[-1],vectors[-1],255)]
samples=[];level_expected=[];volumes=[];dominant=[]
for name,l,r,vol in cases:
 sl=[(v*vol)>>8 for v in l];sr=[(v*vol)>>8 for v in r]
 chosen=sr if sum(map(abs,sr))>sum(map(abs,sl)) else sl
 win=[(v*w)>>15 for v,w in zip(chosen,window)];m,_=fft_fixed(win)
 h=[height(max(m[a:b])) for a,b in zip(edges,edges[1:])]
 samples.extend(((a&65535)<<16)|(b&65535) for a,b in zip(l,r));level_expected.append(sum(v<<(7*i) for i,v in enumerate(h)));volumes.append(vol)
 dominant.append({'case':name,'bands':h,'peak_band':h.index(max(h))})
hexfile('spectrum_input.hex',samples,32);hexfile('spectrum_expected.hex',level_expected,112);hexfile('spectrum_volume.hex',volumes,8)
(T/'spectrum_tb.sv').write_text(f'''`timescale 1ns/1ps
module spectrum_tb;
reg clk=0,rst=0,enable=0,valid=0;reg [31:0] sample=0;reg [7:0] volume=255;always #20 clk=~clk;
wire [111:0] levels;wire update;
audio_spectrum dut(clk,rst,enable,sample,valid,volume,levels,update);
reg [31:0] inputs[0:{len(cases)*512-1}];reg [111:0] expected[0:{len(cases)-1}];reg [7:0] volumes[0:{len(cases)-1}];
integer c,n,block;
initial begin
 $readmemh("spectrum_input.hex",inputs);$readmemh("spectrum_expected.hex",expected);$readmemh("spectrum_volume.hex",volumes);
 repeat(3)@(negedge clk);rst=1;
 for(c=0;c<{len(cases)};c=c+1)begin
  enable=0;repeat(4)@(negedge clk);enable=1;volume=volumes[c];
  for(block=0;block<2;block=block+1)begin
   // Bursts are intentionally faster than real audio to check pipeline bounds.
   for(n=0;n<512;n=n+1)begin sample=inputs[c*512+n];valid=1;@(negedge clk);valid=0;repeat(3)@(negedge clk);end
   wait(update);@(negedge clk);repeat(4)@(negedge clk);
  end
  if(levels!==expected[c])$fatal(1,"SPECTRUM case=%d got=%h expected=%h",c,levels,expected[c]);
  $display("SPECTRUM_CASE_PASS case=%d levels=%h",c,levels);
 end
 enable=0;repeat(3)@(negedge clk);if(levels!=0)$fatal(1,"disable stale spectrum");
 $display("SPECTRUM_PASS cases={len(cases)} hann=1 all_16_bands_exact=1 right_channel=1 antiphase=1 volume=1 mute=1 disable_clear=1");$finish;
end
initial begin #100000000;$fatal(1,"spectrum watchdog");end
endmodule
''',encoding='ascii')
(T/'overlay_tb.sv').write_text('''`timescale 1ns/1ps
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
  x=i;y=j;rgb={i[7:0],j[7:0],8'h80};#1;$fwrite(file,"%h\\n",out);
  if(out!==rgb)changed=changed+1;
 end
 $fclose(file);if(changed<10000 || changed>33408)$fatal(1,"panel footprint=%d",changed);
 levels=0;frame();if(dut.height[0]!=15)$fatal(1,"decay must be two pixels per frame");
 enable=0;#1;if(!dut.visible)$fatal(1,"disable changed midframe");frame();if(dut.visible)$fatal(1,"disable not latched");
 $display("SPECTRUM_OVERLAY_PASS frame_atomic=1 ROI_exact=1 no_pixel_latency=1 decay=1 hidden_passthrough=1 changed_pixels=%d",changed);$finish;
end
endmodule
''',encoding='ascii')
(T/'reference_results.json').write_text(json.dumps({'numpy_complex_max_error_units':max_err,'cases':dominant,'frequency_edges_hz':[x*48000/512 for x in edges]},indent=2))
# Use actual board + SPI + audio/video; only the memory application IP is modeled.
(T/'system_tb.sv').write_text('''`timescale 1ns/1ps
module spectrum_system_tb;
reg clk=0,rst=0,load_n=1,spectrum_n=1,audio_n=1,mute_n=1;reg [6:0] keys=7'h7f;
always #10 clk=~clk;
wire cs,sck,mosi,miso;wire [3:0] led;
hdmi_player_board_top #(.POWERUP_CYCLES(8),.DEBOUNCE_CYCLES(4),.SPECTRUM_DB_CYCLES(4),.FADE_STEP(8)) dut(
 .SYS_CLK(clk),.Reset_n(rst),.KEY_LOAD_N(load_n),.KEY_PREV_N(1'b1),.KEY_NEXT_N(1'b1),.KEY_AUTO_N(1'b1),
 .KEY_SPECTRUM_N(spectrum_n),.SW_AUDIO_N(audio_n),.SW_MUTE_N(mute_n),.key_img(4'hf),.key_in(keys),.LED(led),
 .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),.HDMI_CLK_P(),.HDMI_D0_P(),.HDMI_D1_P(),.HDMI_D2_P());
integer reads,commands;
audio_sd_card_model card(.rst_n(rst),.cs_n(cs),.sck(sck),.mosi(mosi),.miso(miso),.high_capacity(1'b1),
 .corrupt_crc(1'b0),.suppress_token(1'b0),.bad_token(1'b0),.bad_cmd8(1'b0),.suppress_response(1'b0),.reads(reads),.commands(commands));
reg [31:0] samples[0:39999];integer wp=0,rp=0,updates=0,overlay_pixels=0,source_pixels=0;
always @(posedge clk)if(dut.board_reset_n)begin
 if(dut.u_player.audio_valid && dut.u_player.audio_ready)begin samples[wp]=dut.u_player.audio_sample;wp=wp+1;end
 if(dut.u_player.pixel_transfer)source_pixels=source_pixels+1;
end
always @(posedge dut.u_player.display_clk)if(dut.u_player.display_reset_n)begin
 if(dut.u_player.u_display.audio_pop && !dut.u_player.u_display.audio_empty)begin
  if(rp>=wp || dut.u_player.u_display.audio_rd_data!==samples[rp])$fatal(1,"spectrum corrupted audio sample=%d",rp);rp=rp+1;
 end
 if(dut.u_player.u_display.g_spectrum.u_analyzer.update)updates=updates+1;
 if(dut.u_player.u_display.VGA_DE && dut.u_player.u_display.SPECTRUM_D!==dut.u_player.u_display.PARAM_D)overlay_pixels=overlay_pixels+1;
end
task cycles(input integer n);repeat(n)@(negedge clk);endtask
task press;begin spectrum_n=0;cycles(20);spectrum_n=1;cycles(20);end endtask
task image;begin wait(dut.load_ready);load_n=0;cycles(15);load_n=1;wait(!dut.load_ready);wait(dut.load_ready);end endtask
integer n,before_samples;
initial begin
 cycles(4);rst=1;wait(dut.load_ready);cycles(10);
 spectrum_n=0;cycles(1);spectrum_n=1;cycles(15);
 if(dut.u_player.u_display.g_spectrum.selected)$fatal(1,"spectrum key bounce accepted");
 press();if(!dut.u_player.u_display.g_spectrum.selected)$fatal(1,"spectrum selection did not enable");
 cycles(100);if(dut.u_player.u_display.g_spectrum.u_overlay.visible)$fatal(1,"panel visible while audio off");
 audio_n=0;wait(dut.u_player.audio_playing);wait(dut.u_player.u_display.g_spectrum.u_overlay.visible);
 wait(updates>=3);if(dut.u_player.u_display.g_spectrum.levels==0)$fatal(1,"playing WAV produced empty spectrum");
 image();image();if(source_pixels!=256)$fatal(1,"image reload corrupted");
 // Source mute: PCM zeros, stream continues and spectrum becomes empty.
 mute_n=0;n=updates;wait(updates>=n+3);if(dut.u_player.u_display.g_spectrum.levels!=0)$fatal(1,"source mute not reflected");
 mute_n=1;n=updates;wait(updates>=n+3);if(dut.u_player.u_display.g_spectrum.levels==0)$fatal(1,"unmute not restored");
 // HDMI-side mute and volume operate after the audio FIFO.
 keys[2]=0;cycles(550000);n=updates;wait(updates>=n+3);
 if(dut.u_player.u_display.g_spectrum.levels!=0)$fatal(1,"HDMI-side mute not reflected");
 keys[2]=1;cycles(550000);n=updates;wait(updates>=n+3);
 if(dut.u_player.u_display.g_spectrum.levels==0)$fatal(1,"HDMI mute release not restored");
 audio_n=1;wait(!dut.u_player.audio_playing);wait(!dut.u_player.u_display.g_spectrum.u_overlay.visible);
 if(!dut.u_player.u_display.g_spectrum.selected)$fatal(1,"audio stop forgot selection");
 audio_n=0;wait(dut.u_player.audio_playing);wait(dut.u_player.u_display.g_spectrum.u_overlay.visible);
 before_samples=rp;spectrum_n=0;cycles(2000);
 if(dut.u_player.u_display.g_spectrum.selected)$fatal(1,"spectrum key hold toggled repeatedly");
 spectrum_n=1;cycles(20);wait(!dut.u_player.u_display.g_spectrum.u_overlay.visible);cycles(10000);
 if(rp<=before_samples || !dut.u_player.audio_playing)$fatal(1,"hiding spectrum stopped audio");
 if(led[3] || dut.u_player.debug_error_flags!=0 || overlay_pixels<1000)$fatal(1,"spectrum system status led=%b flags=%h pixels=%d",led,dut.u_player.debug_error_flags,overlay_pixels);
 rst=0;cycles(3);if(dut.u_player.u_display.g_spectrum.selected)$fatal(1,"spectrum reset retained selection");
 $display("SPECTRUM_SYSTEM_PASS source_pixels=%d audio_cdc_samples=%d spectrum_updates=%d overlay_pixels=%d two_images=1 source_mute=1 hdmi_mute=1 audio_off_hide=1 restart=1 toggle_hold_once=1 no_audio_stall=1 reset=1",source_pixels,rp,updates,overlay_pixels);$finish;
end
initial begin #750000000;$fatal(1,"spectrum system watchdog led=%b updates=%d samples=%d",led,updates,rp);end
endmodule
''',encoding='ascii')
script='''from pathlib import Path
import argparse,subprocess,json,shutil,hashlib,tempfile
R=Path(__file__).resolve().parent;S=R.parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_audio_spectrum');p.add_argument('--simulator-bin',type=Path,default=Path('D:/modelsim2020/win64'));p.add_argument('--units-only',action='store_true');args=p.parse_args();O=args.output.resolve();O.mkdir(parents=True,exist_ok=True);B=args.simulator_bin
def run(label,exe,argv):
 q=subprocess.run([str(B/(exe+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in argv]],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1200)
 log=q.stdout+q.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8');assert q.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-5000:];return log
run('init','vmap',['-c'])
if not (O/'work').exists():run('library','vlib',['work'])
run('map','vmap',['work',O/'work'])
core=[S/'include/global_def.v',*[S/'rtl/memory'/n for n in ('async_fifo.v','frame_desc_cdc.v','sdram_write_ctrl.v','sdram_refresh_ctrl.v','sdram_app_arbiter.v','sdram_read_ctrl.v','frame_buffer_ctrl.v','display_pixel_fifo.v','memory_top.v')]]
sources=[*core,*list((S/'rtl/storage').glob('*.v')),*list((S/'rtl/display/src/enc').glob('*.v')),*list((S/'rtl/display/src').glob('*.v')),*list((S/'rtl/top').glob('*.v'))]
hashes={f.relative_to(S).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
run('compile','vlog',['-mfcu','+define+SIM_ODDR','+incdir+'+(S/'rtl/memory').as_posix(),*sources])
run('vhdl','vcom',['-2008',S/'rtl/display/src/hdmi_tx.vhd'])
run('benches','vlog',['-sv',S/'verification/display_memory_20261028/tests/application_models.sv',S/'verification/wav_audio_20261101/audio_sd_card_model.sv',*[R/n for n in ('fft_tb.sv','spectrum_tb.sv','overlay_tb.sv','system_tb.sv')]])
for f in R.glob('*.hex'):shutil.copy2(f,O/f.name)
d=O/'tb/storage/vectors';d.mkdir(parents=True,exist_ok=True);shutil.copy2(S/'verification/wav_audio_20261101/fixtures/core_card.hex',d/'card.hex')
(O/'run.do').write_text('onerror {quit -f -code 1}\\nrun -all\\nquit -f -code 0\\n')
tests={};cases=[('fft_tb','FFT512_PASS'),('spectrum_tb','SPECTRUM_PASS'),('overlay_tb','SPECTRUM_OVERLAY_PASS')]
if not args.units_only:cases.append(('spectrum_system_tb','SPECTRUM_SYSTEM_PASS'))
for top,marker in cases:
 log=run(top,'vsim',['-c','-onfinish','stop','work.'+top,'-do','run.do']);assert marker in log,log[-5000:]
 tests[top]={'passed':True,'markers':[x for x in log.splitlines() if 'PASS' in x]};print(top+': PASS',flush=True)
 (O/'results.json').write_text(json.dumps({'passed':len(tests)==len(cases),'tests':tests,'source_sha256':hashes},indent=2))
assert all(hashlib.sha256((S/f).read_bytes()).hexdigest()==h for f,h in hashes.items())
'''
(T/'run.py').write_text(script,encoding='utf-8');(T/'.gitignore').write_text('__pycache__/\n*.pyc\n')
print(json.dumps({'fft_cases':len(vectors),'numpy_max_complex_error':max_err,'spectrum_cases':len(cases)}))
