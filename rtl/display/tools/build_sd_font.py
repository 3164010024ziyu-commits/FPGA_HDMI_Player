"""Convert Unifont HEX/HEX.GZ glyphs to the SD Unicode-indexed FONT16.BIN.

FONT16.BIN: 0x110000 scalar slots, 16 big-endian 16-bit rows per slot.
Unassigned glyphs use a visible replacement box. Font pixels retain their
upstream font license; this tool does not embed font data into FPGA logic.
"""
from pathlib import Path
import argparse,gzip,hashlib,json

p=argparse.ArgumentParser()
p.add_argument('source',type=Path,nargs='+')
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
box=b'\x7f\xfe'+b'\x40\x02'*14+b'\x7f\xfe'
font=bytearray(box*0x110000);defined=set()
sources=[]
for path in a.source:
    data=path.read_bytes();sources.append({'path':path.name,'sha256':hashlib.sha256(data).hexdigest()})
    text=(gzip.decompress(data) if path.suffix=='.gz' else data).decode('ascii')
    for line in text.splitlines():
        if not line or line.startswith('#') or ':' not in line:continue
        key,bits=line.strip().split(':',1);cp=int(key,16)
        if cp>0x10ffff:continue
        raw=bytes.fromhex(bits);stride=len(raw)//16
        if stride not in (1,2,3,4) or len(raw)!=stride*16:raise ValueError(line[:40])
        rows=[]
        for y in range(16):
            value=int.from_bytes(raw[y*stride:(y+1)*stride],'big')
            if stride==1:value<<=4
            elif stride>2:
                width=stride*8
                value=sum((bool(value & (((1<<((x+1)*width//16-x*width//16))-1)<<(width-(x+1)*width//16))))<<(15-x) for x in range(16))
            rows.append(value)
        font[cp*32:(cp+1)*32]=b''.join(n.to_bytes(2,'big') for n in rows);defined.add(cp)
out=a.output/'FONT16.BIN';out.write_bytes(font)
report={'format':'Unicode scalar * 32, 16 big-endian rows','bytes':len(font),
        'glyphs':len(defined),'bmp_han':sum(0x3400<=c<=0x9fff for c in defined),
        'supplementary_han':sum(0x20000<=c<0x32400 for c in defined),
        'source':sources,'sha256':hashlib.sha256(font).hexdigest()}
(a.output/'FONT16.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2),flush=True)
