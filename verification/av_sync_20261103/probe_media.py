from pathlib import Path
import argparse,wave,struct,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--media',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
R=Path(__file__).resolve().parent;S=R.parents[1];O=a.output.resolve();O.mkdir(parents=True,exist_ok=True);B=Path('D:/modelsim2020/win64')
files=sorted(a.media.glob('*.WAV'));assert len(files)==4;sizes=[]
for k,f in enumerate(files):
 with f.open('rb')as h:data=h.read(1024)
 with wave.open(str(f),'rb')as h:
  assert h.getframerate()==48000 and h.getnchannels()==2 and h.getsampwidth()==2
  samples=h.readframes(64)
 expected=[(l<<16)|r for l,r in struct.iter_unpack('<HH',samples)]
 (O/f'probe{k}.hex').write_text('\n'.join(f'{b:02x}'for b in data));(O/f'samples{k}.hex').write_text('\n'.join(f'{b:08x}'for b in expected));sizes.append(f.stat().st_size)
(O/'sizes.hex').write_text('\n'.join(f'{n:08x}'for n in sizes))
def run(label,exe,args):
 q=subprocess.run([str(B/(exe+'.exe')),*map(str,args)],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
 log=q.stdout+q.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8');assert q.returncode==0 and '** Error:'not in log and '** Fatal:'not in log,log[-4000:];return log
run('init','vmap',['-c']);run('library','vlib',['work']);run('map','vmap',['work',O/'work']);run('compile','vlog',['-sv',S/'rtl/storage/wav_stream_decoder.v',R/'media_tb.sv'])
(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
log=run('simulation','vsim',['-c','-onfinish','stop','work.av_media_probe_tb','-do','run.do']);assert 'REAL_MEDIA_PROBE_PASS'in log
(O/'results.json').write_text(json.dumps({'passed':True,'files':[str(f)for f in files],'markers':[l for l in log.splitlines()if'PASS'in l]},indent=2));print('REAL_MEDIA_PROBE_PASS',flush=True)
