from pathlib import Path
import subprocess,shutil,json,sys
import argparse,os,tempfile,hashlib
R=Path(__file__).resolve().parent;S=R.parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_wav_audio_20261101');p.add_argument('--simulator-bin',type=Path,default=Path(os.environ.get('MODELSIM_BIN',r'D:/modelsim2020/win64')));args=p.parse_args()
O=args.output.resolve();O.mkdir(parents=True,exist_ok=True);B=args.simulator_bin
results={}
def run(label,args,cwd=O):
 p=subprocess.run([x.as_posix() if isinstance(x,Path) else str(x) for x in args],cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
 log=p.stdout+p.stderr;(cwd/(label+'.log')).write_text(log,encoding='utf-8')
 assert p.returncode==0 and '** Fatal:' not in log and '** Error:' not in log,log[-5000:]
 return log
run('init',[B/'vmap.exe','-c'])
if not (O/'work').exists():run('library',[B/'vlib.exe','work'])
run('map',[B/'vmap.exe','work',O/'work'])
run('compile',[B/'vlog.exe','-sv','+define+SIM_ODDR',*list((S/'rtl/storage').glob('*.v')),S/'rtl/display/src/audio_fifo.v',*list((S/'rtl/display/src/enc').glob('*.v')),R/'decoder_tb.sv',R/'spi_audio_tb.sv',R/'hdmi_audio_tb.sv',R/'audio_sd_card_model.sv',S/'rtl/top/hdmi_player_board_top.v',S/'rtl/top/image_navigation_ctrl.v',R/'board_audio_tb.sv'])
for top,marker in [('decoder_tb','WAV_DECODER_PASS'),('spi_audio_tb','SPI_WAV_PASS'),('hdmi_audio_tb','HDMI_AUDIO_PASS'),('board_audio_tb','BOARD_AUDIO_PASS')]:
 d=O/top;(d/'tb/storage/vectors').mkdir(parents=True,exist_ok=True)
 shutil.copy2(R/'fixtures/card.hex',d/'tb/storage/vectors/card.hex')
 for n in ('good.hex','mono.hex'):shutil.copy2(R/'fixtures'/n,d/n)
 (d/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n')
 log=run('simulation',[B/'vsim.exe','-c','-onfinish','stop','-modelsimini',O/'modelsim.ini','work.'+top,'-do','run.do'],d)
 assert marker in log,log[-3000:]
 results[top]={'passed':True,'markers':[x for x in log.splitlines() if 'PASS' in x]};print(json.dumps(results[top]),flush=True)
 (O/'results.json').write_text(json.dumps(results,indent=2))

proc=subprocess.run([sys.executable,str(R/'run_core.py'),'--output',str(O/'core'),'--simulator-bin',str(B)],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
(O/'core_run.log').write_text(proc.stdout+proc.stderr,encoding='utf-8')
assert proc.returncode==0,proc.stdout[-2000:]+proc.stderr[-3000:]
results['core_audio']=json.loads((O/'core/results.json').read_text())
report={'passed':all(x['passed'] for x in results.values()),'tests':results,
 'source_sha256':{f.relative_to(S).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for folder in ('rtl','include') for f in (S/folder).rglob('*') if f.is_file() and f.suffix in ('.v','.vhd')}}
(O/'results.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'all_passed':report['passed'],'core_audio':results['core_audio']}),flush=True)
