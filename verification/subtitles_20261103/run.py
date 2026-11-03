from pathlib import Path
import argparse,subprocess,json,hashlib,shutil
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
R=Path(__file__).resolve().parent;S=R.parents[1];O=a.output.resolve();O.mkdir(parents=True,exist_ok=True)
B=Path('D:/modelsim2020/win64')
def run(label,exe,args):
 r=subprocess.run([str(B/(exe+'.exe')),*map(str,args)],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=900)
 log=r.stdout+r.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8')
 assert r.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-4000:]
 return log
run('init','vmap',['-c'])
if not (O/'work').exists():run('library','vlib',['work'])
run('map','vmap',['work',str(O/'work')])
sources=[S/'rtl/display/src'/f for f in ['subtitle_font.v','subtitle_overlay.v','audio_progress.v','param_osd.v']]
run('compile','vlog',['-sv',*sources,R/'progress_tb.sv',R/'overlay_tb.sv',R/'percent_tb.sv'])
(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
results={}
for top,marker in [('percent_tb','PARAM_PERCENT_PASS'),('progress_tb','AUDIO_PROGRESS_PASS'),('progress_rollover_tb','AUDIO_PROGRESS_ROLLOVER_PASS'),('subtitle_overlay_tb','SUBTITLE_OVERLAY_PASS')]:
 log=run(top,'vsim',['-c','-onfinish','stop','work.'+top,'-do','run.do']);assert marker in log
 results[top]={'passed':True,'markers':[l for l in log.splitlines() if 'PASS' in l]};print(top+': PASS',flush=True)

# Independent full-frame compositor. Font bits are input data, not RTL outputs.
font=[int(x,16) for x in (S/'rtl/display/src/subtitle_font.hex').read_text().splitlines()]
ids=json.loads((S/'rtl/display/src/subtitle_font_ids.json').read_text(encoding='utf-8'))
compared=0
for line in (O/'frames.txt').read_text().splitlines():
 name,image,sub,time,scroll,bcd,marquee=line.split();marquee=int(marquee);image,sub,time,scroll=map(int,[image,sub,time,scroll])
 text='图片 00003 TEST.BMP 640x480' if image else '暂无图片'
 clock='音频 '+bcd[:2]+':'+bcd[2:4]+':'+bcd[4:]
 # All static captures use one text instance. A moved/marquee capture repeats
 # the message with four spaces; left/right wrap at the message period.

 data=(O/(name+'.ppm')).read_bytes();header=b'P6\n640 480\n255\n';assert data.startswith(header);data=data[len(header):]
 assert len(data)==640*480*3
 for y in range(480):
  previous=False
  for x in range(640):
   expected=[x&255,y&255,128];inside=False;bit=False
   if sub and 16<=x<624 and 452<=y<468:
    inside=True;u=x-16+scroll;row=y-452
    if marquee:u%=16*(len(text)+4)
    cell,px=divmod(u,16);ch=text[cell] if cell<len(text) else ' '
    bit=bool(font[ids[ch]*16+row]&(1<<(15-px)))
   elif time and 16<=x<192 and 12<=y<28:
    inside=True;cell,px=divmod(x-16,16);ch=clock[cell]
    bit=bool(font[ids[ch]*16+y-12]&(1<<(15-px)))
   if inside:
    expected=[c>>1 for c in expected]
    if previous and x!=16:expected=[0,0,0]
    if bit:expected=[255,255,255]
   previous=bit if inside else False
   offset=(y*640+x)*3
   assert data[offset:offset+3]==bytes(expected),(name,x,y,data[offset:offset+3].hex(),bytes(expected).hex())
   compared+=1
results['golden_pixels']={'passed':True,'pixels':compared}
report={'passed':True,'tests':results,'sha256':{str(f.relative_to(S)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}}
(O/'results.json').write_text(json.dumps(report,indent=2));print('Golden RGB pixels:',compared,flush=True)
