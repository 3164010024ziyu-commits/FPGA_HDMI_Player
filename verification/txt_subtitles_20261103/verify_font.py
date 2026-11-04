"""Independently compare generated SD slots with upstream HEX rows."""
from pathlib import Path
import argparse,gzip,json,hashlib
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--font',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
font=a.font.read_bytes();assert len(font)==0x110000*32
rows=0;glyphs=0
for line in gzip.decompress(a.source.read_bytes()).decode('ascii').splitlines():
 cp,bits=line.split(':');cp=int(cp,16);raw=bytes.fromhex(bits);stride=len(raw)//16
 assert stride in (1,2)
 for row in range(16):
  value=int.from_bytes(raw[row*stride:(row+1)*stride],'big')
  if stride==1:value*=16
  actual=int.from_bytes(font[cp*32+row*2:cp*32+row*2+2],'big')
  assert actual==value,(hex(cp),row,actual,value)
  rows+=1
 glyphs+=1
box=b'\x7f\xfe'+b'\x40\x02'*14+b'\x7f\xfe'
assert font[0x10ffff*32:0x110000*32]==box
report={'passed':True,'glyphs':glyphs,'rows_compared':rows,'font_sha256':hashlib.sha256(font).hexdigest(),'unknown_box':True}
a.output.write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
