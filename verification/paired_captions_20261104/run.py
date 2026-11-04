from pathlib import Path
import argparse,subprocess,struct,json,hashlib
R=Path(__file__).resolve().parent;S=R.parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();O=a.output.resolve();O.mkdir(parents=True,exist_ok=True)
def run(label,exe,args):
 q=subprocess.run([str(Path('D:/modelsim2020/win64')/(exe+'.exe')),*map(str,args)],cwd=O,capture_output=True,text=True,errors='replace',timeout=600)
 log=q.stdout+q.stderr;(O/(label+'.log')).write_text(log);assert q.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-6000:];return log
def save(name,data):(O/(name+'.hex')).write_text('\n'.join(f'{v:02x}' for v in data))
boot=bytearray(512);boot[:3]=b'\xeb\x58\x90';struct.pack_into('<HBHB',boot,11,512,128,32,2);struct.pack_into('<I',boot,32,1056+65530*128);struct.pack_into('<I',boot,36,512);struct.pack_into('<I',boot,44,2);boot[510:]=b'\x55\xaa';save('boot',boot)
root=bytearray(512)
# Caption order differs from BMP order; global CAPTION.TXT is a deliberate decoy.
entries=[('SECOND  TXT',5,1),('CAPTION TXT',3,1),('FIRST   BMP',6,246),('FONT16  BIN',10,0x2200000),('THIRD   BMP',8,246),('FIRST   TXT',4,1),('SECOND  BMP',7,246)]
for k,(name,c,size) in enumerate(entries):
 i=k*32;root[i:i+11]=name.encode();root[i+11]=32;struct.pack_into('<H',root,i+26,c);struct.pack_into('<I',root,i+28,size)
save('root',root)
image=bytearray(512);image[:2]=b'BM';struct.pack_into('<I',image,2,246);struct.pack_into('<I',image,10,54);struct.pack_into('<IiiHHI',image,14,40,8,8,1,24,0);image[54:246]=bytes(i%256 for i in range(192));save('image',image)
model=(S/'verification/wav_audio_20261101/audio_sd_card_model.sv').read_text().replace('module audio_sd_card_model','module paired_card_model');model=model.replace('    function [7:0] read_byte(input integer address,offset);','    `include "virtual_card.svh"\n    function [7:0] read_byte(input integer address,offset);')
import re
model=re.sub(r'            read_byte=\(s<0\).*?;',r'            read_byte=card_byte(address,offset);',model).replace('$readmemh("tb/storage/vectors/card.hex",card);','');(O/'card.sv').write_text(model)
run('init','vmap',['-c']);run('library','vlib',['work']);run('map','vmap',['work',O/'work'])
sources=[*sorted((S/'rtl/storage').glob('*.v')),S/'rtl/display/src/text_glyph_cache.v',*R.glob('*_tb.sv')]
run('compile','vlog',['-sv','+incdir+'+R.as_posix(),*sources,O/'card.sv']);(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
tests={}
for top,marker in [('paired_caption_tb','PAIRED_CAPTION_PASS'),('caption_publish_tb','CAPTION_PUBLISH_PASS')]:
 log=run(top,'vsim',['-c','-onfinish','stop','work.'+top,'-do','run.do']);assert marker in log;tests[top]=[l for l in log.splitlines() if 'PASS' in l];print(marker,flush=True)
(O/'results.json').write_text(json.dumps({'passed':True,'tests':tests,'source_sha256':{str(f.relative_to(S)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}},indent=2))
