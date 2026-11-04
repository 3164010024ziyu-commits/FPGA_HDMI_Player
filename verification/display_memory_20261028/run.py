from pathlib import Path
import argparse, hashlib, json, re, subprocess, shutil, os, tempfile
from datetime import datetime, timezone

ROOT=Path(__file__).resolve().parent
SRC=Path(os.environ.get('FPGA_PLAYER_PROJECT',str(ROOT.parents[1])))
OUT=Path(os.environ.get('FPGA_PLAYER_SIM_OUTPUT',str(Path(tempfile.gettempdir())/'fpga_display_memory_20261028'))); OUT.mkdir(parents=True,exist_ok=True)
BIN=Path(os.environ.get('MODELSIM_BIN',r'D:\modelsim2020\win64'))
LIB=Path(os.environ.get('TD_MODEL_LIBS',r'C:\Users\31640\Documents\ChatGPT\FFF\sdram_sip_integration_20261024\run'))
GLBL=Path(os.environ.get('TD_SIM_ROOT',r'C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\sim_release'))/'eg4/eg_phy_glbl.v'
p=argparse.ArgumentParser();p.add_argument('stages',nargs='+');args=p.parse_args()
RESULT=OUT/'verification_results.json'
r=json.loads(RESULT.read_text()) if RESULT.exists() else {'commands':[], 'tests':{}}
def save():
    r['updated_utc']=datetime.now(timezone.utc).isoformat()
    RESULT.write_text(json.dumps(r,indent=2),encoding='utf-8')
def run(folder,label,exe,params,marker=None):
    cmd=[str(BIN/(exe+'.exe')),*[v.as_posix() if isinstance(v,Path) else str(v) for v in params]]
    try:
        t=subprocess.run(cmd,cwd=folder,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
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
if 'hierarchy' in args.stages:
    f=init('hierarchy',True)
    td=(SRC/'project/td/HDMI_Player.al').read_text(encoding='utf-8')
    sources=[(SRC/'project/td'/x).resolve() for x in re.findall(r'<File Path="([^"]+)"',td)]
    run(f,'compile_design','vlog',['-modelsimini','modelsim.ini','-mfcu',inc,*[s for s in sources if s.suffix=='.v'],GLBL])
    for s in sources:
        if s.suffix=='.vhd':run(f,'compile_vhdl','vcom',['-modelsimini','modelsim.ini','-2008',s])
    top=re.search(r'<MODULE>([A-Za-z_][A-Za-z0-9_]*)</MODULE>',td).group(1)
    sim(f,'real_hierarchy',top,'REAL_HIERARCHY_PASS',('-L','al','-L','eg','work.glbl'),action='run 0 ns\nputs "REAL_HIERARCHY_PASS"')
if 'unit' in args.stages:
    f=init('unit')
    run(f,'compile_core','vlog',['-modelsimini','modelsim.ini','-mfcu',inc,*core])
    run(f,'compile_tb','vlog',['-modelsimini','modelsim.ini','-sv',ROOT/'tests/application_models.sv',ROOT/'tests/memory_display_tb.sv'])
    sim(f,'memory_display','memory_display_tb','MEMORY_DISPLAY_PASS')
if 'real' in args.stages:
    f=init('real_ip',True)
    model=Path(os.environ['SDRAM_MODEL'])
    run(f,'compile_real','vlog',['-modelsimini','modelsim.ini','-mfcu',inc,*core,
        SRC/'rtl/ip/clk_pll/clk_pll.v',*list((SRC/'rtl/ip/sdram').glob('*.v')),model,GLBL])
    run(f,'compile_tb','vlog',['-modelsimini','modelsim.ini','-sv',ROOT/'tests/real_ip_display_tb.sv'])
    for phase in (0,1):
        sim(f,'real_ip_'+('270_diagnostic' if phase else '180_current'),'real_ip_display_tb','REAL_IP_DIAGNOSTIC_PASS',
            ('-L','al','-L','eg','work.glbl',f'+PHASE270={phase}'))
if 'raster' in args.stages:
    f=init('full_raster')
    run(f,'compile_core','vlog',['-modelsimini','modelsim.ini','-mfcu',inc,*core,SRC/'rtl/display/src/read_RAM.v'])
    run(f,'compile_tb','vlog',['-modelsimini','modelsim.ini','-sv',ROOT/'tests/application_models.sv',ROOT/'tests/full_raster_tb.sv'])
    sim(f,'full_raster','full_raster_tb','FULL_RASTER_PASS')
if 'real_raster' in args.stages:
    f=init('real_full_raster',True)
    model=Path(os.environ['SDRAM_MODEL'])
    bench=(ROOT/'tests/full_raster_tb.sv').read_text(encoding='utf-8')
    bench=bench.replace('module full_raster_tb;', '''module full_raster_real_tb;
    reg mem_clk=0,shifted_clk=0;
    always #4 mem_clk=~mem_clk;
    always @(mem_clk)shifted_clk<=#6 mem_clk;
    integer physical_refreshes=0;
    always @(posedge dut.SDRAM_CLK)
        if({dut.SDR_RAS,dut.SDR_CAS,dut.SDR_WE}===3'b001)physical_refreshes=physical_refreshes+1;
    IS42s32200 dram(.Clk(dut.SDRAM_CLK),.Cke(1'b1),.Cs_n(1'b0),.Ras_n(dut.SDR_RAS),
        .Cas_n(dut.SDR_CAS),.We_n(dut.SDR_WE),.Ba(dut.SDR_BA),.Addr(dut.SDR_ADDR),.Dqm(dut.SDR_DM),.Dq(dut.SDR_DQ));''')
    bench=bench.replace('#100;rst_n=1;', '''force dut.Clk=mem_clk; force dut.Clk_sft=shifted_clk; force dut.lock=1'b1;
        #100;rst_n=1;''').replace('dut.u2_ram.refreshes','physical_refreshes').replace('FULL_RASTER_PASS','REAL_FULL_RASTER_DIAGNOSTIC_PASS')
    target=OUT/'full_raster_real_tb.sv';target.write_text(bench,encoding='utf-8')
    run(f,'compile_real','vlog',['-modelsimini','modelsim.ini','-mfcu',inc,*core,
        SRC/'rtl/ip/clk_pll/clk_pll.v',*list((SRC/'rtl/ip/sdram').glob('*.v')),SRC/'rtl/display/src/read_RAM.v',model,GLBL])
    run(f,'compile_tb','vlog',['-modelsimini','modelsim.ini','-sv',target])
    sim(f,'real_full_raster_270_diagnostic','full_raster_real_tb','REAL_FULL_RASTER_DIAGNOSTIC_PASS',('-L','al','-L','eg','work.glbl'))
if 'real_lines' in args.stages:
    bench=(ROOT/'tests/full_raster_tb.sv').read_text(encoding='utf-8')
    bench=bench.replace('module full_raster_tb;', '''module full_raster_real_tb;
    reg mem_clk=0,shifted_clk=0;
    always #4 mem_clk=~mem_clk;
    always @(mem_clk)shifted_clk<=#6 mem_clk;
    integer physical_refreshes=0;
    always @(posedge dut.SDRAM_CLK)
        if({dut.SDR_RAS,dut.SDR_CAS,dut.SDR_WE}===3'b001)physical_refreshes=physical_refreshes+1;
    IS42s32200 dram(.Clk(dut.SDRAM_CLK),.Cke(1'b1),.Cs_n(1'b0),.Ras_n(dut.SDR_RAS),
        .Cas_n(dut.SDR_CAS),.We_n(dut.SDR_WE),.Ba(dut.SDR_BA),.Addr(dut.SDR_ADDR),.Dqm(dut.SDR_DM),.Dq(dut.SDR_DQ));''')
    bench=bench.replace('#100;rst_n=1;', '''force dut.Clk=mem_clk; force dut.Clk_sft=shifted_clk; force dut.lock=1'b1;
        #100;rst_n=1;''').replace('dut.u2_ram.refreshes','physical_refreshes').replace('FULL_RASTER_PASS','REAL_FULL_RASTER_DIAGNOSTIC_PASS')
    target=OUT/'full_raster_real_tb.sv';target.write_text(bench,encoding='utf-8')
    f=init('real_lines',True)
    model=Path(os.environ['SDRAM_MODEL'])
    bench=(OUT/'full_raster_real_tb.sv').read_text(encoding='utf-8')
    bench=bench.replace('module full_raster_real_tb;','module real_lines_tb;')
    bench=bench.replace('memory_top dut(', 'memory_top #(.DISPLAY_WIDTH(640),.DISPLAY_HEIGHT(16)) dut(')
    bench=bench.replace(".frame_height(16'd480)",".frame_height(16'd16)")
    a=bench.index('    read_RAM timing(');b=bench.index('    integer seeds',a)
    bench=bench[:a]+'''    reg [9:0] hx=0,vy=0;
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if(!pix_rst_n)begin hx<=0;vy<=0;end
        else if(hx==799)begin hx<=0;vy<=vy==60?0:vy+1;end
        else hx<=hx+1;
    end
    assign x=hx;assign y=vy;assign req=pix_rst_n && hx<640 && vy<16;
    assign de=req;assign blank=pix_rst_n && vy==16;
    assign hdmi_rgb=valid?rgb:24'd0;
'''+bench[b:]
    bench=bench.replace('307200','10240').replace('y==479','y==15').replace('REAL_FULL_RASTER_DIAGNOSTIC_PASS','REAL_640_LINE_DIAGNOSTIC_PASS')
    target=OUT/'real_lines_tb.sv';target.write_text(bench,encoding='utf-8')
    run(f,'compile_real','vlog',['-modelsimini','modelsim.ini','-mfcu',inc,*core,
        SRC/'rtl/ip/clk_pll/clk_pll.v',*list((SRC/'rtl/ip/sdram').glob('*.v')),model,GLBL])
    run(f,'compile_tb','vlog',['-modelsimini','modelsim.ini','-sv',target])
    sim(f,'real_640_lines_270_diagnostic','real_lines_tb','REAL_640_LINE_DIAGNOSTIC_PASS',('-L','al','-L','eg','work.glbl'))
if 'system' in args.stages:
    f=init('system')
    display=[*sorted((SRC/'rtl/display/src/enc').glob('*.v')),*sorted((SRC/'rtl/display/src').glob('*.v'))]
    storage=[SRC/'rtl/storage'/n for n in ('sd_spi_reader.v','fat32_bmp_reader.v','bmp_stream_decoder.v','storage_pipeline.v')]
    run(f,'compile_system','vlog',['-modelsimini','modelsim.ini','-mfcu','+define+SIM_ODDR',inc,*core,*storage,*display,SRC/'rtl/top/hdmi_player_top.v'])
    run(f,'compile_vhdl','vcom',['-modelsimini','modelsim.ini','-2008',SRC/'rtl/display/src/hdmi_tx.vhd'])
    run(f,'compile_tb','vlog',['-modelsimini','modelsim.ini','-sv',ROOT/'tests/application_models.sv',ROOT/'tests/system_display_tb.sv',SRC/'verification/storage_mbr_fix_20261026/sd_spi_card_model.sv'])
    vectors=f/'tb/storage/vectors';vectors.mkdir(parents=True,exist_ok=True)
    for name in ('card.hex','image.hex'):shutil.copyfile(ROOT/'vectors'/name,vectors/name)
    sim(f,'system_display','system_display_tb','SYSTEM_DISPLAY_PASS')
r['source_sha256']={f.relative_to(SRC).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in SRC.rglob('*') if f.is_file() and f.suffix in ('.v','.vhd','.al')}
save()
