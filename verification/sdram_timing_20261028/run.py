from pathlib import Path
import argparse, hashlib, json, re, subprocess, shutil, os, tempfile
from datetime import datetime, timezone

ROOT=Path(__file__).resolve().parent
SRC=Path(os.environ.get('FPGA_PLAYER_PROJECT',str(ROOT.parents[1])))
OUT=Path(os.environ.get('FPGA_PLAYER_SIM_OUTPUT',str(Path(tempfile.gettempdir())/'fpga_sdram_timing_20261028'))); OUT.mkdir(parents=True,exist_ok=True)
BIN=Path(os.environ.get('MODELSIM_BIN',r'D:\modelsim2020\win64'))
LIB=Path(os.environ.get('TD_MODEL_LIBS',r'C:\Users\31640\Documents\ChatGPT\FFF\sdram_sip_integration_20261024\run'))
GLBL=Path(os.environ.get('TD_SIM_ROOT',r'C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\sim_release'))/'eg4/eg_phy_glbl.v'
p=argparse.ArgumentParser();p.add_argument('stages',nargs='+',choices=['readback','full','refresh']);p.add_argument('--model',type=Path,default=os.environ.get('SDRAM_MODEL'));args=p.parse_args()
if not args.model or not args.model.is_file():p.error('Supply --model with the unmodified APUG011 IS42s32200.v path')
RESULT=OUT/'verification_results.json'
r=json.loads(RESULT.read_text()) if RESULT.exists() else {'commands':[], 'tests':{}}
def save():
    r['updated_utc']=datetime.now(timezone.utc).isoformat()
    RESULT.write_text(json.dumps(r,indent=2),encoding='utf-8')
def run(folder,label,exe,params,marker=None):
    cmd=[str(BIN/(exe+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in params]]
    try:
        t=subprocess.run(cmd,cwd=folder,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1800)
    except subprocess.TimeoutExpired as exc:
        output=exc.stdout or b''
        if isinstance(output,bytes):output=output.decode('utf-8',errors='replace')
        (folder/(label+'.log')).write_text(output,encoding='utf-8')
        r['commands'].append({'label':label,'command':cmd,'cwd':str(folder),'passed':False,'status':'tool_timeout','timeout_seconds':600})
        r['tests'][label]={'passed':False,'status':'incomplete_tool_timeout','markers':[x for x in output.splitlines() if 'RESULT' in x]}
        save();raise
    log=t.stdout+t.stderr; (folder/(label+'.log')).write_text(log,encoding='utf-8')
    ok=t.returncode==0 and not re.search(r'\*\* (Error|Fatal):',log) and (not marker or marker in log)
    r['commands'].append({'label':label,'command':cmd,'cwd':str(folder),'exit_code':t.returncode,'passed':ok})
    if marker:r['tests'][label]={'passed':ok,'markers':[x for x in log.splitlines() if 'PASS' in x or 'RESULT' in x], 'log':str(folder/(label+'.log'))}
    save()
    print(json.dumps({'stage':label,'passed':ok}),flush=True)
    if not ok: raise RuntimeError(log[-6000:])
    return log
def init(name,real=False):
    f=OUT/name;f.mkdir(exist_ok=True)
    run(f,'init','vmap',['-c'])
    if not (f/'work').exists():run(f,'library','vlib',['work'])
    run(f,'map','vmap',['work',f/'work'])
    if real:
        for lib in ('al','eg'):run(f,'map_'+lib,'vmap',[lib,LIB/lib])
    return f
def sim(f,label,top,marker,params=(),action='run -all'):
    script=f/(label+'.do')
    script.write_text('onerror {quit -f -code 1}\n'+action+'\nquit -f -code 0\n',encoding='ascii')
    return run(f,label,'vsim',['-c','-onfinish','stop','-modelsimini','modelsim.ini','-voptargs=+acc',*params,'work.'+top,'-do',script.name],marker)
core=[SRC/'include/global_def.v',*[SRC/'rtl/memory'/n for n in ('async_fifo.v','frame_desc_cdc.v','sdram_write_ctrl.v','sdram_refresh_ctrl.v','sdram_app_arbiter.v','sdram_read_ctrl.v','frame_buffer_ctrl.v','display_pixel_fifo.v','memory_top.v')]]
core.append(SRC/'rtl/display/src/subtitle_mailbox.v')
inc='+incdir+'+(SRC/'rtl/memory').as_posix()

physical=[*core,SRC/'rtl/ip/clk_pll/clk_pll.v',*list((SRC/'rtl/ip/sdram').glob('*.v')),args.model,GLBL]
for stage in args.stages:
    if stage=='refresh': cases=range(3)
    else: cases=[None]
    for case in cases:
        f=init(stage if case is None else 'refresh_'+str(case),True)
        sources=[*physical]
        if stage=='full': sources.append(SRC/'rtl/display/src/read_RAM.v')
        run(f,'compile','vlog',['-modelsimini','modelsim.ini','-mfcu',inc,*sources])
        bench={'readback':'pll_readback_tb.sv','full':'full_raster_tb.sv','refresh':'refresh_tb.sv'}[stage]
        benches=[ROOT/'tests'/bench]
        if stage=='refresh':benches.append(ROOT/'tests/refresh_probe.sv')
        run(f,'compile_tb','vlog',['-modelsimini','modelsim.ini','-sv',*benches])
        top={'readback':'real_ip_display_tb','full':'full_raster_tb','refresh':'refresh_wait_tb'}[stage]
        marker={'readback':'PRODUCTION_PLL_READ_PASS','full':'PRODUCTION_FULL_RASTER_PASS','refresh':'CURRENT_REFRESH_PASS'}[stage]
        params=['-L','al','-L','eg','work.glbl']
        if stage=='refresh':params+=['work.refresh_bind_top',f'+SCENARIO={case}']
        sim(f,stage if case is None else 'refresh_'+str(case),top,marker,params)
r['source_sha256']={p.relative_to(SRC).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [*core,SRC/'rtl/ip/clk_pll/clk_pll.v',*list((SRC/'rtl/ip/sdram').glob('*.v')),SRC/'constraints/hx4s20_hdmi_player.sdc']}
save()
