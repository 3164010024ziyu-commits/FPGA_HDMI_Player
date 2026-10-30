from pathlib import Path
import subprocess,os,tempfile,argparse,json
HERE=Path(__file__).resolve().parent;PROJECT=HERE.parents[1]
p=argparse.ArgumentParser(description='Check binary-row decode hazard and registered frame-flush alignment.')
p.add_argument('--project',type=Path,default=PROJECT)
p.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_frame_flush_20261029')
a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
tools=Path(os.environ.get('IVERILOG_BIN',r'D:\2026-2027\iverilog\iverilog\bin'))
sources=[a.project/'rtl/display/src/read_RAM.v']
results={}
for case in ('glitch','line'):
 files=[*sources,HERE/'tests'/(case+'_tb.sv')]
 if case=='glitch':files.append(HERE/'tests/read_RAM_before.v')
 for index,cmd in enumerate(([tools/'iverilog.exe','-g2012','-s',case+'_tb','-o',out/(case+'.vvp'),*files],[tools/'vvp.exe',out/(case+'.vvp')])):
  r=subprocess.run(list(map(str,cmd)),cwd=out,capture_output=True,text=True,timeout=60)
  log=r.stdout+r.stderr;(out/(case+str(index)+'.log')).write_text(log,encoding='utf-8')
  assert r.returncode==0,log
  if index:
   marker='FRAME_FLUSH_GLITCH_PASS' if case=='glitch' else 'FRAME_FLUSH_ALIGNMENT_PASS'
   assert marker in log;results[case]=log;print(log)
(out/'results.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
