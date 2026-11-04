from pathlib import Path
import subprocess,shutil,json,hashlib
import argparse,tempfile
R=Path(__file__).resolve().parent
arg=argparse.ArgumentParser();arg.add_argument('--project',type=Path,default=R.parents[1]);arg.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_slideshow_20261102');arg.add_argument('--simulator-bin',type=Path,default=Path(r'D:/modelsim2020/win64'));args=arg.parse_args()
S=args.project.resolve();O=args.output.resolve();O.mkdir(parents=True,exist_ok=True);B=args.simulator_bin
def run(label,exe,args):
 p=subprocess.run([str(B/(exe+'.exe')),*[x.as_posix() if isinstance(x,Path) else str(x) for x in args]],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1200)
 log=p.stdout+p.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8');assert p.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-5000:];return log
run('init','vmap',['-c'])
if not (O/'work').exists():run('library','vlib',['work'])
run('map','vmap',['work',O/'work'])
core=[S/'include/global_def.v',*[S/'rtl/memory'/n for n in ('async_fifo.v','frame_desc_cdc.v','sdram_write_ctrl.v','sdram_refresh_ctrl.v','sdram_app_arbiter.v','sdram_read_ctrl.v','frame_buffer_ctrl.v','display_pixel_fifo.v','memory_top.v')]]
sources=[*core,*list((S/'rtl/storage').glob('*.v')),*list((S/'rtl/display/src/enc').glob('*.v')),*list((S/'rtl/display/src').glob('*.v')),*list((S/'rtl/top').glob('*.v'))]
hashes={f.relative_to(S).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
run('compile','vlog',['-mfcu','+define+SIM_ODDR','+incdir+'+(S/'rtl/memory').as_posix(),*sources])
run('vhdl','vcom',['-2008',S/'rtl/display/src/hdmi_tx.vhd'])
run('bench','vlog',['-sv',S/'verification/display_memory_20261028/tests/application_models.sv',R/'multi_image_card_model.sv',R/'slideshow_system_tb.sv',R/'timer_tb.sv',R/'fade_control_tb.sv',R/'fade_pixels_tb.sv'])
d=O/'tb/storage/vectors';d.mkdir(parents=True,exist_ok=True);shutil.copy2(R/'card.hex',d/'card.hex')
(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
results={}
for top,marker in [('timer_tb','SLIDESHOW_TIMER_PASS'),('fade_control_tb','FADE_CONTROL_PASS'),('fade_pixels_tb','FADE_PIXEL_PASS'),('slideshow_system_tb','SLIDESHOW_SYSTEM_PASS')]:
 log=run(top,'vsim',['-c','-onfinish','stop','work.'+top,'-do','run.do'])
 assert marker in log,log[-3000:]
 results[top]={'passed':True,'markers':[x for x in log.splitlines() if 'PASS' in x]}
 print(top+': PASS',flush=True)
 (O/'results.json').write_text(json.dumps({'passed':len(results)==5,'tests':results,'source_sha256':hashes},indent=2))
assert all(hashlib.sha256((S/f).read_bytes()).hexdigest()==h for f,h in hashes.items())

run('button_library','vlib',['button_work'])
run('button_compile','vlog',['-work','button_work','-sv',S/'rtl/top/hdmi_player_board_top.v',S/'rtl/top/av_slideshow_ctrl.v',S/'rtl/top/image_navigation_ctrl.v',R/'auto_button_tb.sv'])
log=run('auto_button_tb','vsim',['-c','-onfinish','stop','button_work.auto_button_tb','-do','run.do'])
assert 'AUTO_BUTTON_PASS' in log,log[-3000:]
results['auto_button_tb']={'passed':True,'markers':[x for x in log.splitlines() if 'PASS' in x]}
(O/'results.json').write_text(json.dumps({'passed':len(results)==5,'tests':results,'source_sha256':hashes},indent=2))
print('auto_button_tb: PASS',flush=True)
