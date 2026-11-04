from pathlib import Path
import subprocess,shutil,json
import argparse,os,tempfile
R=Path(__file__).resolve().parent;S=R.parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_wav_core');p.add_argument('--simulator-bin',type=Path,default=Path(os.environ.get('MODELSIM_BIN',r'D:/modelsim2020/win64')));args=p.parse_args()
O=args.output.resolve();O.mkdir(parents=True,exist_ok=True);B=args.simulator_bin
def run(label,exe,args):
 p=subprocess.run([str(B/(exe+'.exe')),*[x.as_posix() if isinstance(x,Path) else str(x) for x in args]],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
 log=p.stdout+p.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8');assert p.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-5000:];return log
run('init','vmap',['-c'])
if not (O/'work').exists():run('library','vlib',['work'])
run('map','vmap',['work',O/'work'])
core=[S/'include/global_def.v',*[S/'rtl/memory'/n for n in ('async_fifo.v','frame_desc_cdc.v','sdram_write_ctrl.v','sdram_refresh_ctrl.v','sdram_app_arbiter.v','sdram_read_ctrl.v','frame_buffer_ctrl.v','display_pixel_fifo.v','memory_top.v')]]
run('compile','vlog',['-mfcu','+define+SIM_ODDR','+incdir+'+(S/'rtl/memory').as_posix(),*core,*list((S/'rtl/storage').glob('*.v')),*list((S/'rtl/display/src/enc').glob('*.v')),*list((S/'rtl/display/src').glob('*.v')),S/'rtl/top/hdmi_player_top.v'])
run('vhdl','vcom',['-2008',S/'rtl/display/src/hdmi_tx.vhd'])
run('bench','vlog',['-sv',S/'verification/display_memory_20261028/tests/application_models.sv',R/'audio_sd_card_model.sv',R/'core_audio_tb.sv'])
d=O/'tb/storage/vectors';d.mkdir(parents=True,exist_ok=True);shutil.copy2(R/'fixtures/core_card.hex',d/'card.hex')
(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
log=run('simulation','vsim',['-c','-onfinish','stop','work.core_audio_tb','-do','run.do'])
assert 'CORE_WAV_HDMI_PASS' in log,log[-3000:]
out={'passed':True,'markers':[x for x in log.splitlines() if 'PASS' in x]};(O/'results.json').write_text(json.dumps(out,indent=2));print(json.dumps(out),flush=True)
