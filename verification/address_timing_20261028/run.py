from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,tempfile
HERE=Path(__file__).resolve().parent;PROJECT=HERE.parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'hx4s20_writer_address');a=p.parse_args()
OUT=a.output.resolve();OUT.mkdir(parents=True,exist_ok=True)
BIN=Path(os.environ.get('MODELSIM_BIN',r'D:\modelsim2020\win64'))
result={'commands':[],'tests':{}}
def save():(OUT/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
def run(label,exe,args,marker=None):
    argv=[str(BIN/(exe+'.exe')),*[str(x) for x in args]]
    t=subprocess.run(argv,cwd=OUT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
    log=t.stdout+t.stderr;(OUT/(label+'.log')).write_text(log,encoding='utf-8')
    okay=t.returncode==0 and not re.search(r'\*\* (Error|Fatal):',log) and (not marker or marker in log)
    result['commands'].append({'label':label,'passed':okay,'argv':argv})
    if marker:
        result['tests'][label]={'passed':okay,'markers':[line for line in log.splitlines() if 'PASS' in line or 'DIAG_COMPLETE' in line]}
        print(json.dumps(result['tests'][label]),flush=True)
    save()
    if not okay:raise RuntimeError(log[-5000:])
writer=PROJECT/'rtl/memory/sdram_write_ctrl.v'
result['writer_sha256']=hashlib.sha256(writer.read_bytes()).hexdigest()
run('init','vmap',['-c'])
if not (OUT/'work').exists():run('library','vlib',['work'])
run('map','vmap',['work',OUT/'work'])
run('compile','vlog',['-modelsimini','modelsim.ini','-sv',PROJECT/'rtl/memory/sync_fifo.v',writer,HERE/'writer_address_matrix_tb.sv',HERE/'writer_address_tb.sv'])
for name,marker,params in [('writer_address_matrix_tb','WRITER_ADDRESS_MATRIX_PASS',[]),('writer_address_tb','ADDRESS_DIAG_COMPLETE',['-gEXPECT_ERRORS=0'])]:
    script=OUT/(name+'.do');script.write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n',encoding='ascii')
    run(name,'vsim',['-c','-onfinish','stop','-modelsimini','modelsim.ini',*params,'work.'+name,'-do',script.name],marker)
assert result['writer_sha256']==hashlib.sha256(writer.read_bytes()).hexdigest()
result['sources_unchanged_during_test']=True;save()
