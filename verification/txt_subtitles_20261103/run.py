"""UTF-8, FAT ranges and frame-atomic dual-clock glyph regression."""
from pathlib import Path
import argparse,subprocess,json,hashlib,struct,re
R=Path(__file__).resolve().parent;S=R.parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
O=a.output.resolve();O.mkdir(parents=True,exist_ok=True);B=Path('D:/modelsim2020/win64')
def run(label,exe,args):
 q=subprocess.run([str(B/(exe+'.exe')),*map(str,args)],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
 log=q.stdout+q.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8')
 assert q.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-6000:]
 return log
run('init','vmap',['-c']);run('library','vlib',['work']);run('map','vmap',['work',O/'work'])
model=(S/'verification/wav_audio_20261101/audio_sd_card_model.sv').read_text().replace('module audio_sd_card_model','module caption_sd_card_model')
model=model.replace('    function [7:0] read_byte(input integer address,offset);','    `include "virtual_card.svh"\n    function [7:0] read_byte(input integer address,offset);')
model=re.sub(r'            read_byte=\(s<0\).*?;',r'            read_byte=card_byte(address,offset);',model)
model=model.replace('$readmemh("tb/storage/vectors/card.hex",card);','')
(O/'caption_sd_card_model.sv').write_text(model)
sources=[*sorted((S/'rtl/storage').glob('*.v')),S/'rtl/display/src/text_glyph_cache.v',S/'rtl/display/src/subtitle_font.v',S/'rtl/display/src/subtitle_overlay.v',*R.glob('*_tb.sv')]
run('compile','vlog',['-sv','+incdir+'+R.as_posix(),*sources,O/'caption_sd_card_model.sv']);(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
boot=bytearray(512);boot[:3]=b'\xeb\x58\x90';struct.pack_into('<HBHB',boot,11,512,128,32,2)
struct.pack_into('<I',boot,32,1056+65530*128);struct.pack_into('<I',boot,36,512);struct.pack_into('<I',boot,44,2);boot[510:512]=b'\x55\xaa'
root=bytearray(512)
for n,(name,cluster,size) in enumerate([(b'CAPTION TXT',5,17),(b'FONT16  BIN',10,0x2200000),(b'TEST    BMP',6,246),(b'MUSIC   WAV',7,8248)]):
 i=n*32;root[i:i+11]=name;root[i+11]=32;struct.pack_into('<H',root,i+26,cluster);struct.pack_into('<I',root,i+28,size)
caption='A中𠮷'.encode('utf-8');caption+=bytes(512-len(caption))
image=bytearray(512);image[:2]=b'BM';struct.pack_into('<I',image,2,246);struct.pack_into('<I',image,10,54);struct.pack_into('<IiiHHI',image,14,40,8,8,1,24,0)
image[54:246]=bytes(n%256 for n in range(192))
card=bytes(int(s,16) for s in (S/'verification/wav_audio_20261101/fixtures/core_card.hex').read_text().split())
wav=card[9*512:9*512+8248];wav+=bytes(10240-len(wav))
for name,data in [('boot',boot),('root',root),('caption',caption),('image',image),('wav',wav)]:(O/f'virtual_{name}.hex').write_text('\n'.join(f'{x:02x}' for x in data))
tests={}
for top,marker in [('caption_loader_tb','CAPTION_LOADER_PASS'),('caption_fat_tb','CAPTION_FAT_PASS'),('caption_cache_tb','CAPTION_CACHE_PASS'),('caption_spi_tb','CAPTION_SPI_PASS')]:
 if not any(top in f.read_text() for f in R.glob('*_tb.sv')):continue
 log=run(top,'vsim',['-c','-onfinish','stop','work.'+top,'-do','run.do']);assert marker in log
 tests[top]={'passed':True,'markers':[l for l in log.splitlines() if 'PASS' in l]};print(top+': PASS',flush=True)
(O/'results.json').write_text(json.dumps({'passed':True,'tests':tests,'sha256':{f.relative_to(S).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}},indent=2))
