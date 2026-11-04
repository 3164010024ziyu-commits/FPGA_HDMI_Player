from pathlib import Path
import argparse,subprocess,json,shutil,hashlib
R=Path(__file__).resolve().parent;S=R.parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--fixtures',type=Path,required=True);a=p.parse_args()
O=a.output.resolve();O.mkdir(parents=True,exist_ok=True);B=Path('D:/modelsim2020/win64')
def run(label,exe,args):
 q=subprocess.run([str(B/(exe+'.exe')),*map(str,args)],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1200)
 log=q.stdout+q.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8')
 assert q.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-6500:]
 return log
run('init','vmap',['-c']);run('library','vlib',['work']);run('map','vmap',['work',O/'work'])
core=[S/'include/global_def.v',*[S/'rtl/memory'/n for n in ('async_fifo.v','frame_desc_cdc.v','sdram_write_ctrl.v','sdram_refresh_ctrl.v','sdram_app_arbiter.v','sdram_read_ctrl.v','frame_buffer_ctrl.v','display_pixel_fifo.v','memory_top.v')]]
sources=[*core,*list((S/'rtl/storage').glob('*.v')),*list((S/'rtl/display/src/enc').glob('*.v')),*list((S/'rtl/display/src').glob('*.v')),*list((S/'rtl/top').glob('*.v'))]
hashes={f.relative_to(S).as_posix():hashlib.sha256(f.read_bytes()).hexdigest()for f in sources}
run('compile','vlog',['-mfcu','+define+SIM_ODDR','+incdir+'+(S/'rtl/memory').as_posix(),*sources])
run('vhdl','vcom',['-2008',S/'rtl/display/src/hdmi_tx.vhd'])
for f in a.fixtures.glob('*.hex'):shutil.copy2(f,O/f.name)
shutil.copy2(a.fixtures/'av_sd_card_model.sv',O/'av_sd_card_model.sv')
run('bench','vlog',['-sv','+incdir+'+R.as_posix(),S/'verification/display_memory_20261028/tests/application_models.sv',O/'av_sd_card_model.sv',R/'system_tb.sv'])
(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
log=run('simulation','vsim',['-c','-onfinish','stop','work.av_system_tb','-do','run.do']);assert 'AV_SYSTEM_PASS' in log
assert all(hashlib.sha256((S/f).read_bytes()).hexdigest()==h for f,h in hashes.items())
(O/'results.json').write_text(json.dumps({'passed':True,'source_sha256':hashes,'markers':[l for l in log.splitlines()if'PASS'in l]},indent=2));print('AV_SYSTEM_PASS',flush=True)
