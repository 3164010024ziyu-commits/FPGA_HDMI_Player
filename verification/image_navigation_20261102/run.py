from pathlib import Path
import subprocess,shutil,json,hashlib
import argparse,tempfile
R=Path(__file__).resolve().parent
arg=argparse.ArgumentParser();arg.add_argument('--project',type=Path,default=R.parents[1]);arg.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_image_navigation_20261102');arg.add_argument('--case',type=int,choices=(0,1),default=0);arg.add_argument('--simulator-bin',type=Path,default=Path(r'D:/modelsim2020/win64'));args=arg.parse_args()
S=args.project.resolve();O=args.output.resolve();O.mkdir(parents=True,exist_ok=True);B=args.simulator_bin
def run(label,exe,args):
 p=subprocess.run([str(B/(exe+'.exe')),*[x.as_posix() if isinstance(x,Path) else str(x) for x in args]],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
 log=p.stdout+p.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8');assert p.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-5000:];return log
run('init','vmap',['-c'])
if not (O/'work').exists():run('library','vlib',['work'])
run('map','vmap',['work',O/'work'])
core=[S/'include/global_def.v',*[S/'rtl/memory'/n for n in ('async_fifo.v','frame_desc_cdc.v','sdram_write_ctrl.v','sdram_refresh_ctrl.v','sdram_app_arbiter.v','sdram_read_ctrl.v','frame_buffer_ctrl.v','display_pixel_fifo.v','memory_top.v')]]
sources=[*core,*list((S/'rtl/storage').glob('*.v')),*list((S/'rtl/display/src/enc').glob('*.v')),*list((S/'rtl/display/src').glob('*.v')),*list((S/'rtl/top').glob('*.v'))]
hashes={f.relative_to(S).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
run('compile','vlog',['-mfcu','+define+SIM_ODDR','+incdir+'+(S/'rtl/memory').as_posix(),*sources])
run('vhdl','vcom',['-2008',S/'rtl/display/src/hdmi_tx.vhd'])
run('bench','vlog',['-sv',S/'verification/display_memory_20261028/tests/application_models.sv',R/'multi_image_card_model.sv',R/'multi_image_tb.sv',R/'cached_limit_tb.sv'])
d=O/'tb/storage/vectors';d.mkdir(parents=True,exist_ok=True);shutil.copy2(R/'card.hex',d/'card.hex')
(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
log=run('simulation','vsim',['-c','-onfinish','stop','work.multi_image_tb',f'-gCASE={args.case}','-do','run.do'])
assert 'MULTI_IMAGE_SYSTEM_PASS' in log,log[-3000:]
out={'passed':True,'markers':[x for x in log.splitlines() if 'PASS' in x or 'REQUEST' in x],'source_sha256':hashes}
assert all(hashlib.sha256((S/f).read_bytes()).hexdigest()==h for f,h in hashes.items())
(O/'results.json').write_text(json.dumps(out,indent=2));print(json.dumps(out['markers']),flush=True)

unit=run('cached_unit','vsim',['-c','-onfinish','stop','work.cached_limit_tb','-do','run.do'])
assert 'CACHED_LIMIT_FIX_PASS' in unit
out['cached_limit']={'passed':True,'markers':[x for x in unit.splitlines() if 'PASS' in x]}
(O/'results.json').write_text(json.dumps(out,indent=2))
