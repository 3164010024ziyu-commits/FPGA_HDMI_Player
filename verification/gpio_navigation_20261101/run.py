"""GPIO button/navigation, FAT last-selection, SPI and HDMI regression."""
from pathlib import Path
import argparse, hashlib, json, os, shutil, subprocess, sys, tempfile

HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
p=argparse.ArgumentParser()
p.add_argument('--simulator-bin',type=Path,default=Path(r'D:\modelsim2020\win64'))
p.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_gpio_navigation_20261101')
a=p.parse_args()
OUT=a.output.resolve();OUT.mkdir(parents=True,exist_ok=True)
result={'passed':False,'tests':{},'commands':[]}

def execute(label,exe,args,cwd=OUT):
    argv=[a.simulator_bin/(exe+'.exe'),*args]
    argv=[x.as_posix() if isinstance(x,Path) else str(x) for x in argv]
    proc=subprocess.run(argv,cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
    log=proc.stdout+proc.stderr;(cwd/(label+'.log')).write_text(log,encoding='utf-8')
    result['commands'].append({'label':label,'argv':argv,'exit_code':proc.returncode})
    if proc.returncode or '** Error:' in log or '** Fatal:' in log:
        raise RuntimeError(log[-5000:])
    return log

sources=[PROJECT/'rtl/top/image_navigation_ctrl.v',PROJECT/'rtl/top/hdmi_player_board_top.v',
         *[PROJECT/'rtl/storage'/n for n in ('fat32_bmp_reader.v','storage_pipeline.v','sd_spi_reader.v','bmp_stream_decoder.v')],
         *[HERE/n for n in ('navigation_tb.sv','navigation_buttons_tb.sv','last_file_tb.sv','last_storage_tb.sv')],
         PROJECT/'verification/storage_mbr_fix_20261026/sd_spi_card_model.sv']
try:
    result['source_sha256']={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
    execute('init','vmap',['-c'])
    if not (OUT/'work').exists():execute('library','vlib',['work'])
    execute('map','vmap',['work',OUT/'work'])
    execute('compile','vlog',['-modelsimini',OUT/'modelsim.ini','-sv',*sources])
    for top,marker in [('navigation_tb','NAVIGATION_PASS'),('navigation_buttons_tb','GPIO_BUTTONS_PASS'),
                       ('last_file_tb','PASS fat32_bmp_reader: 28 cases'),('last_storage_tb','LAST_STORAGE_SPI_PASS cases=6')]:
        d=OUT/top;(d/'tb/storage/vectors').mkdir(parents=True,exist_ok=True)
        for n in ('card.hex','image.hex'):
            shutil.copy2(PROJECT/'verification/storage_mbr_fix_20261026/tb/storage/vectors'/n,d/'tb/storage/vectors'/n)
        (d/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n',encoding='ascii')
        log=execute('simulation','vsim',['-c','-onfinish','stop','-modelsimini',OUT/'modelsim.ini','work.'+top,'-do','run.do'],d)
        assert marker in log,log[-2000:]
        result['tests'][top]={'passed':True,'markers':[line for line in log.splitlines() if 'PASS' in line]}
        print(top+': PASS',flush=True)
    env=os.environ.copy()
    env.update(FPGA_PLAYER_PROJECT=str(PROJECT),FPGA_PLAYER_SIM_OUTPUT=str(OUT/'system'),MODELSIM_BIN=str(a.simulator_bin))
    run=subprocess.run([sys.executable,str(HERE/'system_harness/run.py'),'system'],env=env,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
    (OUT/'system.log').write_text(run.stdout+run.stderr,encoding='utf-8')
    assert run.returncode==0,run.stdout[-3000:]+run.stderr[-2000:]
    system=json.loads((OUT/'system/verification_results.json').read_text())
    result['tests']['system_last_selection']=system['tests']['system_display']
    assert result['tests']['system_last_selection']['passed']
    result['sources_unchanged']=all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in result['source_sha256'].items())
    result['passed']=all(x['passed'] for x in result['tests'].values()) and result['sources_unchanged']
    print('system_last_selection: PASS',flush=True)
except Exception as error:
    result['error']=str(error)
(OUT/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
raise SystemExit(0 if result['passed'] else 1)
