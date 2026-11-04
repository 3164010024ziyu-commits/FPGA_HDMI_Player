from pathlib import Path
import argparse,subprocess,json,hashlib,struct,re
R=Path(__file__).resolve().parent;S=R.parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
O=a.output.resolve();O.mkdir(parents=True,exist_ok=True);B=Path('D:/modelsim2020/win64')
def run(label,exe,args):
 q=subprocess.run([str(B/(exe+'.exe')),*map(str,args)],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1200)
 log=q.stdout+q.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8')
 assert q.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-6500:]
 return log
def hexfile(name,data): (O/(name+'.hex')).write_text('\n'.join(f'{x:02x}' for x in data))
boot=bytearray(512);boot[:3]=b'\xeb\x58\x90';struct.pack_into('<HBHB',boot,11,512,128,32,2)
struct.pack_into('<I',boot,32,1056+65530*128);struct.pack_into('<I',boot,36,512);struct.pack_into('<I',boot,44,2);boot[510:]=b'\x55\xaa';hexfile('boot',boot)
root=bytearray(512)
# WAV order is intentionally different from BMP order.
entries=[('THIRD   WAV',9,1644),('FIRST   BMP',6,246),('SECOND  WAV',8,1644),('SECOND  BMP',10,246),('FIRST   WAV',7,1644),('THIRD   BMP',11,246),('CAPTION TXT',12,9),('FONT16  BIN',20,0x2200000)]
for k,(name,c,size)in enumerate(entries):
 i=k*32;root[i:i+11]=name.encode();root[i+11]=32;struct.pack_into('<H',root,i+26,c);struct.pack_into('<I',root,i+28,size)
hexfile('root',root)
caption='同声图'.encode('utf-8');hexfile('caption',caption+bytes(512-len(caption)))
for track in range(3):
 wav=bytearray(2048);wav[:12]=b'RIFF'+struct.pack('<I',1636)+b'WAVE';wav[12:36]=b'fmt '+struct.pack('<IHHIIHH',16,1,2,48000,192000,4,16);wav[36:44]=b'data'+struct.pack('<I',1600)
 for n in range(400):struct.pack_into('<HH',wav,44+n*4,track*4096+n,(~(track*4096+n))&65535)
 hexfile('wav'+str(track),wav)
 bmp=bytearray(512);bmp[:2]=b'BM';struct.pack_into('<I',bmp,2,246);struct.pack_into('<I',bmp,10,54);struct.pack_into('<IiiHHI',bmp,14,40,8,8,1,24,0);bmp[54:246]=bytes([track*80,0,255-track*80])*64;hexfile('bmp'+str(track),bmp)
model=(S/'verification/wav_audio_20261101/audio_sd_card_model.sv').read_text().replace('module audio_sd_card_model','module av_sd_card_model')
model=model.replace('    function [7:0] read_byte(input integer address,offset);','    `include "virtual_card.svh"\n    function [7:0] read_byte(input integer address,offset);')
model=re.sub(r'            read_byte=\(s<0\).*?;',r'            read_byte=card_byte(address,offset);',model).replace('$readmemh("tb/storage/vectors/card.hex",card);','')
(O/'av_sd_card_model.sv').write_text(model)
run('init','vmap',['-c']);run('library','vlib',['work']);run('map','vmap',['work',O/'work'])
sources=[*sorted((S/'rtl/storage').glob('*.v')),S/'rtl/top/av_slideshow_ctrl.v',S/'rtl/display/src/audio_progress.v',*R.glob('*_tb.sv')]
run('compile','vlog',['-sv','+incdir+'+R.as_posix(),*sources])
(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
tests={}
for top,marker in [('paired_audio_tb','PAIRED_AUDIO_PASS'),('av_timer_tb','AV_TIMER_PASS'),('av_progress_tb','AV_PROGRESS_PASS')]:
 if top=='av_timer_tb' and not (R/'timer_tb.sv').exists():continue
 log=run(top,'vsim',['-c','-onfinish','stop','work.'+top,'-do','run.do']);assert marker in log
 tests[top]={'passed':True,'markers':[l for l in log.splitlines()if'PASS'in l]};print(top+': PASS',flush=True)
(O/'results.json').write_text(json.dumps({'passed':True,'tests':tests,'source_sha256':{f.relative_to(S).as_posix():hashlib.sha256(f.read_bytes()).hexdigest()for f in sources}},indent=2))
