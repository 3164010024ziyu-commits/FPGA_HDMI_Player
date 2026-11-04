"""FAT sector stream boundary/backpressure/reset regression, ModelSim."""
from pathlib import Path
import argparse, subprocess, shutil, json, hashlib

R=Path(__file__).resolve().parent
p=argparse.ArgumentParser()
p.add_argument('--project',type=Path,default=R.parents[1])
p.add_argument('--output',type=Path,required=True)
p.add_argument('--simulator-bin',type=Path,default=Path(r'D:/modelsim2020/win64'))
a=p.parse_args(); S=a.project.resolve(); O=a.output.resolve();O.mkdir(parents=True,exist_ok=True)
sources=[S/'rtl/storage/fat32_bmp_reader.v',R/'cache_tb.sv']
hashes={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
def run(label,exe,args):
    q=subprocess.run([str(a.simulator_bin/(exe+'.exe')),*[str(x) for x in args]],cwd=O,
                     capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
    log=q.stdout+q.stderr;(O/(label+'.log')).write_text(log,encoding='utf-8')
    assert q.returncode==0 and '** Error:' not in log and '** Fatal:' not in log,log[-4500:]
    return log
run('init','vmap',['-c']);run('library','vlib',['work']);run('map','vmap',['work',O/'work'])
run('compile','vlog',['-sv',*sources])
for name in ('card.hex','image.hex'):
    shutil.copy2(S/'verification/storage_mbr_fix_20261026/tb/storage/vectors'/name,O/name)
(O/'run.do').write_text('onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n',encoding='ascii')
log=run('simulation','vsim',['-c','-onfinish','stop','work.fat_sector_cache_tb','-do','run.do'])
assert 'FAT_SECTOR_CACHE_PASS cases=23' in log,log[-4000:]
assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==h for f,h in hashes.items())
result={'passed':True,'source_sha256':hashes,'markers':[l for l in log.splitlines() if 'PASS' in l]}
(O/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result['markers'][-1:]),flush=True)
