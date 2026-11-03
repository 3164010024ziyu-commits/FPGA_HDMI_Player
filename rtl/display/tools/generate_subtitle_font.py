"""Build a small, path-independent 16x16 ROM from a fixed KBITX font source.

Only the Python standard library is needed. KBITX bitmap data uses ULEB128
dimensions and byte runs (see Bits'N'Picas / kbitfont format readers).
The generated glyph subset remains OFL-1.1, independently of the RTL license.
"""
from pathlib import Path
import argparse,base64,xml.etree.ElementTree as ET,json

p=argparse.ArgumentParser();p.add_argument('source',type=Path)
p.add_argument('--extra',default='图片音频暂无大家好')
p.add_argument('--output',type=Path,default=Path(__file__).resolve().parents[1]/'src')
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
glyphs={int(g.attrib['u']):g.attrib for g in ET.fromstring(a.source.read_bytes()).findall('g') if 'u' in g.attrib}
ids={chr(i):i for i in range(32,127)}
for ch in dict.fromkeys(a.extra):
    if ch not in ids:ids[ch]=128+sum(ord(x)>127 for x in ids)
assert max(ids.values())<160, "Compact font supports ASCII plus 32 extra glyphs"

def decode(g):
    d=g['d'];b=iter(base64.b64decode(d+'='*((-len(d))%4)))
    def number():
        v=s=0
        while True:
            n=next(b);v|=(n&127)<<s
            if n<128:return v
            s+=7
    h,w=number(),number();pixels=[]
    while len(pixels)<w*h:
        n=next(b);count=(n&31)*(32 if n&32 else 1);kind=n>>6
        assert count
        if kind==3:pixels.extend(next(b) for _ in range(count))
        else:
            color=0 if kind==0 else 255 if kind==1 else next(b)
            pixels.extend([color]*count)
    assert len(pixels)==w*h
    rows=[0]*16;x0=int(g.get('x',0))+(16-int(g['w']))//2;y0=14-int(g.get('y',0))
    for y in range(h):
        for x in range(w):
            xx,yy=x+x0,y+y0
            if 0<=xx<16 and 0<=yy<16 and pixels[y*w+x]>=128:rows[yy]|=1<<(15-xx)
    return rows

rom=[0]*4096
for ch,idx in ids.items():
    if ord(ch) not in glyphs:raise ValueError('Missing glyph '+ch)
    rom[idx*16:idx*16+16]=decode(glyphs[ord(ch)])
# An explicit replacement box for non-ASCII FAT short-name bytes.
rom[127*16:128*16]=[0x7ffe]+[0x4002]*14+[0x7ffe]
lines=['// Generated OFL-1.1 font subset; see licenses/subtitle-font-OFL.txt.',
       '// Source: Astro-2539/ZLabs-RoundPix-16px @ df114b8dd1564e722e09f3e726b919f2a27d0afd.',
       '// Internal resource name: HDMI Player Subtitle Subset (reserved names not used).',
       'module subtitle_font(input wire clk,input wire [7:0] glyph,input wire [3:0] row,output reg [15:0] bits);',
       'reg [15:0] rom[0:2047];','integer i;','initial begin','for(i=0;i<2048;i=i+1)rom[i]=0;']
lines += [f"rom[{(((i//16)-32)&127)*16+i%16}]=16'h{v:04x};" for i,v in enumerate(rom) if v]
lines+=['end','wire [6:0] compact_glyph=glyph[6:0]-7\'d32;', 'always @(posedge clk) bits<=rom[{compact_glyph,row}];','endmodule']
(a.output/'subtitle_font.v').write_text('\n'.join(lines)+'\n',encoding='utf-8')
(a.output/'subtitle_font_ids.json').write_text(json.dumps(ids,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Independent fixture: every pixel, including blank rows.
(a.output/'subtitle_font.hex').write_text(''.join(f'{x:04x}\n' for x in rom),encoding='ascii')
print('Generated',len(ids),'glyphs; Chinese IDs:',{c:i for c,i in ids.items() if ord(c)>127})
