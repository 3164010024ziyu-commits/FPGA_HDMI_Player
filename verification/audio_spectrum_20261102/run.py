from pathlib import Path
import argparse,subprocess,json,shutil,hashlib,tempfile
R=Path(__file__).resolve().parent;S=R.parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_audio_spectrum');p.add_argument('--simulator-bin',type=Path,default=Path('D:/modelsim2020/win64'));p.add_argument('--units-only',action='store_true');args=p.parse_args();O=args.output.resolve();O.mkdir(parents=True,exist_ok=True);B=args.simulator_bin
def run(label,exe,argv):
 q=subprocess.run([str(B/(exe+'.exe')),*[a.as_posix() if isinstance(a,Path) else str(a) for a in argv]],cwd=O,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1200)
 log=q.stdout+q.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8');assert q.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-5000:];return log
run('init','vmap',['-c'])
if not (O/'work').exists():run('library','vlib',['work'])
run('map','vmap',['work',O/'work'])
core=[S/'include/global_def.v',*[S/'rtl/memory'/n for n in ('async_fifo.v','frame_desc_cdc.v','sdram_write_ctrl.v','sdram_refresh_ctrl.v','sdram_app_arbiter.v','sdram_read_ctrl.v','frame_buffer_ctrl.v','display_pixel_fifo.v','memory_top.v')]]
sources=[*core,*list((S/'rtl/storage').glob('*.v')),*list((S/'rtl/display/src/enc').glob('*.v')),*list((S/'rtl/display/src').glob('*.v')),*list((S/'rtl/top').glob('*.v'))]
hashes={f.relative_to(S).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
run('compile','vlog',['-mfcu','+define+SIM_ODDR','+incdir+'+(S/'rtl/memory').as_posix(),*sources])
run('vhdl','vcom',['-2008',S/'rtl/display/src/hdmi_tx.vhd'])
run('benches','vlog',['-sv',S/'verification/display_memory_20261028/tests/application_models.sv',S/'verification/wav_audio_20261101/audio_sd_card_model.sv',*[R/n for n in ('fft_tb.sv','spectrum_tb.sv','overlay_tb.sv','system_tb.sv')]])
for f in R.glob('*.hex'):shutil.copy2(f,O/f.name)
d=O/'tb/storage/vectors';d.mkdir(parents=True,exist_ok=True);shutil.copy2(S/'verification/wav_audio_20261101/fixtures/core_card.hex',d/'card.hex')
(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
tests={};cases=[('fft_tb','FFT512_PASS'),('spectrum_tb','SPECTRUM_PASS'),('overlay_tb','SPECTRUM_OVERLAY_PASS')]
if not args.units_only:cases.append(('spectrum_system_tb','SPECTRUM_SYSTEM_PASS'))
for top,marker in cases:
 log=run(top,'vsim',['-c','-onfinish','stop','work.'+top,'-do','run.do']);assert marker in log,log[-5000:]
 tests[top]={'passed':True,'markers':[x for x in log.splitlines() if 'PASS' in x]};print(top+': PASS',flush=True)
 (O/'results.json').write_text(json.dumps({'passed':len(tests)==len(cases),'tests':tests,'source_sha256':hashes},indent=2))
assert all(hashlib.sha256((S/f).read_bytes()).hexdigest()==h for f,h in hashes.items())
