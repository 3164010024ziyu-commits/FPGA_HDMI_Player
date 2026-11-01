from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,tempfile

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
p=argparse.ArgumentParser(description='Test the board wrapper with a controlled system-core substitute.')
p.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'hx4s20_board_wrapper')
args=p.parse_args();out=args.output.resolve();out.mkdir(parents=True,exist_ok=True)
tools=Path(os.environ.get('IVERILOG_BIN',str(Path(shutil.which('iverilog') or r'D:\2026-2027\iverilog\iverilog\bin\iverilog.exe').parent)))
wrapper=PROJECT/'rtl/top/hdmi_player_board_top.v'
sources=[wrapper,PROJECT/'rtl/top/image_navigation_ctrl.v',HERE/'board_wrapper_tb.sv']
commands=[['iverilog.exe','-g2012','-s','board_wrapper_tb','-o',out/'board_wrapper.vvp',*sources],['vvp.exe',out/'board_wrapper.vvp']]
result={'source_sha256':{str(s):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources},'commands':[]}
for index,command in enumerate(commands):
    argv=[str(tools/command[0]),*[str(v) for v in command[1:]]]
    process=subprocess.run(argv,cwd=out,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
    log=process.stdout+process.stderr;(out/f'stage_{index}.log').write_text(log,encoding='utf-8')
    okay=process.returncode==0 and (index==0 or 'BOARD_WRAPPER_PASS' in log)
    result['commands'].append({'argv':argv,'exit_code':process.returncode,'passed':okay})
    if not okay:
        result['passed']=False;(out/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        raise RuntimeError(log)
    if index:print(log,end='')
result['passed']=True
(out/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
