from pathlib import Path
import argparse, hashlib, json, os, shutil, struct, subprocess, sys, tempfile

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
p=argparse.ArgumentParser(description='Return-streaming reader regression; writes only to the selected output directory.')
p.add_argument('stage',choices=['stalls','stress','physical'])
p.add_argument('--bmp',type=Path)
p.add_argument('--model',type=Path)
p.add_argument('--extra-delay',type=int,default=4)
p.add_argument('--baseline',action='store_true',help='Use the archived pre-fix reader; expect the stress test to underrun.')
p.add_argument('--project',type=Path,default=PROJECT)
p.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_display_underflow_20261029')
args=p.parse_args();PROJECT=args.project.resolve();OUT=args.output.resolve();OUT.mkdir(parents=True,exist_ok=True)
SRC=PROJECT
if args.baseline:
    if args.stage!='stress':p.error('--baseline is valid for stress only')
    SRC=OUT/'baseline_source'
    if SRC.exists():p.error('Choose a fresh --output directory for the baseline comparison')
    for name in ('rtl','include'):shutil.copytree(PROJECT/name,SRC/name)
    shutil.copy2(HERE/'tests/baseline_sdram_read_ctrl.v',SRC/'rtl/memory/sdram_read_ctrl.v')

def call(name,cmd,cwd,env=None,expected=None):
    proc=subprocess.run(list(map(str,cmd)),cwd=cwd,env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=2400)
    log=proc.stdout+proc.stderr;(OUT/(name+'.log')).write_text(log,encoding='utf-8')
    okay=proc.returncode==0 if expected is None else expected in log
    if not okay:raise RuntimeError(log[-6000:])
    return {'exit_code':proc.returncode,'log':str(OUT/(name+'.log')),'expected_underrun':expected is not None}

if args.stage=='stalls':
    tools=Path(os.environ.get('IVERILOG_BIN',r'D:\2026-2027\iverilog\iverilog\bin'))
    call('compile',[tools/'iverilog.exe','-g2012','-s','reader_stalls_tb','-o',OUT/'test.vvp',SRC/'rtl/memory/sdram_read_ctrl.v',HERE/'tests/reader_stalls_tb.sv'],OUT)
    result=call('stalls',[tools/'vvp.exe',OUT/'test.vvp'],OUT)
    assert 'READER_STALLS_PASS' in (OUT/'stalls.log').read_text()
else:
    if not args.bmp or not args.bmp.is_file():p.error('Supply --bmp with the original 640x480 24-bit BI_RGB test pattern')
    raw=args.bmp.read_bytes();off=struct.unpack_from('<I',raw,10)[0]
    assert raw[:2]==b'BM' and struct.unpack_from('<ii',raw,18)==(640,480)
    assert struct.unpack_from('<H',raw,28)[0]==24 and struct.unpack_from('<I',raw,30)[0]==0
    assert len(raw)>=off+640*480*3
    expected=[]
    for y in range(480):
        line=raw[off+(479-y)*1920:off+(480-y)*1920]
        expected.extend(f'{line[x+2]:02x}{line[x+1]:02x}{line[x]:02x}' for x in range(0,1920,3))
    fixture=OUT/'harness';(fixture/'tests').mkdir(parents=True,exist_ok=True)
    if args.stage=='stress':
        script=PROJECT/'verification/display_memory_20261028/run.py'
        shutil.copy2(PROJECT/'verification/display_memory_20261028/tests/application_models.sv',fixture/'tests/application_models.sv')
        bench=(HERE/'tests/stress_raster_tb.sv').read_text().replace('extra_delay=4;',f'extra_delay={args.extra_delay};')
        stages=['raster'];directory=OUT/'simulation/full_raster'
    else:
        if not args.model or not args.model.is_file():p.error('Supply --model with the unmodified SDRAM model')
        script=PROJECT/'verification/sdram_timing_20261028/run.py'
        shutil.copy2(PROJECT/'verification/sdram_timing_20261028/tests/pll_readback_tb.sv',fixture/'tests/pll_readback_tb.sv')
        bench=(HERE/'tests/physical_raster_tb.sv').read_text()
        stages=['readback','full','--model',str(args.model)];directory=OUT/'simulation/full'
    (fixture/'tests/full_raster_tb.sv').write_text(bench,encoding='utf-8')
    source=script.read_text()
    if args.stage=='physical':
        source=source.replace("if stage=='full': sources.append(SRC/'rtl/display/src/read_RAM.v')", "if stage=='full': sources += [SRC/'rtl/display/src/read_RAM.v',SRC/'rtl/display/ipsrc/clock_ip/clk_wize.v']")
    (fixture/'run.py').write_text(source,encoding='utf-8')
    directory.mkdir(parents=True,exist_ok=True);(directory/'expected.hex').write_text('\n'.join(expected),encoding='ascii')
    env=os.environ.copy();env['FPGA_PLAYER_PROJECT']=str(SRC);env['FPGA_PLAYER_SIM_OUTPUT']=str(OUT/'simulation')
    result=call(args.stage,[sys.executable,fixture/'run.py',*stages],OUT,env,'full raster underrun' if args.baseline else None)
result.update(stage=args.stage,baseline=args.baseline,reader_sha256=hashlib.sha256((SRC/'rtl/memory/sdram_read_ctrl.v').read_bytes()).hexdigest())
(OUT/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2))
