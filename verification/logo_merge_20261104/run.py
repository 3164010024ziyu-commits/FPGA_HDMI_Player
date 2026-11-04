"""Check the merged bitmap ROM and pixel alignment over two complete VGA frames."""
from pathlib import Path
import argparse, hashlib, json, re, struct, subprocess

p = argparse.ArgumentParser()
p.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[2])
p.add_argument('--output', type=Path)
a = p.parse_args()
r = a.repo.resolve()
o = (a.output or Path(__file__).resolve().parent / 'logo_pixels').resolve()
o.mkdir(parents=True, exist_ok=True)
src = r / 'rtl/display/src'
rom = (src / 'logo_rom.v').read_text()
key = int(re.search(r"assign key = 24'h([0-9A-Fa-f]+)", rom)[1], 16)
pixels = [key] * 4096
for address, color in re.findall(r"mem\[(\d+)\] = 24'h([0-9A-Fa-f]+)", rom):
    pixels[int(address)] = int(color, 16)
bmp = (r / 'rtl/display/my_logo.bmp').read_bytes()
offset = struct.unpack_from('<I', bmp, 10)[0]
w, h = struct.unpack_from('<ii', bmp, 18)
assert (w, abs(h), struct.unpack_from('<H', bmp, 28)[0]) == (64, 64, 24)
expected = []
for y in range(64):
    row = y if h < 0 else 63-y
    for x in range(64):
        b, g, red = bmp[offset+row*192+x*3:offset+row*192+x*3+3]
        expected.append((red << 16) | (g << 8) | b)
def distance(color):
    return max(abs(((color >> s) & 255)-((key >> s) & 255)) for s in (0,8,16))
tolerances=[t for t in range(256) if all(actual==(key if distance(raw)<=t else raw) for actual,raw in zip(pixels,expected))]
assert tolerances, 'Committed ROM differs from BMP even after transparent-color tolerance'
expected=[key if distance(raw)<=tolerances[0] else raw for raw in expected]
(o / 'golden.hex').write_text('\n'.join(f'{x:06x}' for x in expected))
(o / 'logo_pixels_tb.sv').write_text(r'''
`timescale 1ns/1ps
module logo_pixels_tb;
reg clk=0; always #20 clk=~clk;
reg [9:0] x=0,y=0;
wire de=x<640 && y<480;
wire [23:0] background={x[7:0],y[7:0],8'h91};
wire [23:0] result;
reg [23:0] golden[0:4095]; reg[23:0] expected;
integer frame=0,checked=0,opaque=0,transparent=0;
logo_overlay dut(.clk(clk),.de(de),.x(x),.y(y),.rgb_in(background),.rgb_out(result));
initial $readmemh("golden.hex",golden);
always @(posedge clk) begin
  if(x==799)begin x<=0;if(y==524)begin y<=0;frame<=frame+1;end else y<=y+1;end
  else x<=x+1;
end
always @(negedge clk) begin
  expected=background;
  if(de && x>=568 && x<632 && y>=8 && y<72)begin
    if(golden[(y-8)*64+x-568]!=24'hKEY)begin
      expected=golden[(y-8)*64+x-568];opaque=opaque+1;
    end else transparent=transparent+1;
  end
  if(result!==expected)$fatal(1,"LOGO mismatch frame=%0d x=%0d y=%0d actual=%h expected=%h",frame,x,y,result,expected);
  checked=checked+1;
  if(frame==2)begin
    if(opaque==0 || transparent==0)$fatal(1,"No transparency/opaque coverage");
    $display("LOGO_PIXELS_PASS checked=%0d opaque=%0d transparent=%0d",checked,opaque,transparent);
    $finish;
  end
end
endmodule
'''.replace('KEY', f'{key:06x}'))
def run(label, args):
    q = subprocess.run([str(x) for x in args], cwd=o, capture_output=True, text=True)
    log=q.stdout+q.stderr
    (o/(label+'.log')).write_text(log)
    assert q.returncode==0, log
    return log
run('compile', ['iverilog','-g2012','-s','logo_pixels_tb','-o','sim.vvp',src/'logo_overlay.v',src/'logo_rom.v',o/'logo_pixels_tb.sv'])
log=run('simulation',['vvp','sim.vvp'])
assert 'LOGO_PIXELS_PASS' in log
project=(r/'project/td/HDMI_Player.al').read_text()
orders=[]
for block in re.findall(r'<File Path="[^"]+\.v">.*?</File>',project,re.S):
    orders.append(int(re.search(r'CompileOrder" Val="(\d+)"',block)[1]))
assert len(orders)==len(set(orders)), 'Duplicate Verilog compile order'
assert not re.search(r'<Project[^>]*\bPath=',project), 'Machine-specific project root'
assert not re.search(r'^(<<<<<<<|=======|>>>>>>>)', (src/'hdmi_tx_display.v').read_text(), re.M)
result={'passed':True,'rom_matches_bmp_pixels':4096,'transparent_key_tolerance':tolerances,'markers':log.splitlines(),
        'unique_verilog_compile_orders':len(orders),
        'source_sha256':{str(f.relative_to(r)):hashlib.sha256(f.read_bytes()).hexdigest() for f in [src/'logo_rom.v',src/'logo_overlay.v',src/'hdmi_tx_display.v',r/'project/td/HDMI_Player.al']}}
(o/'results.json').write_text(json.dumps(result,indent=2))
print(log, end='')
