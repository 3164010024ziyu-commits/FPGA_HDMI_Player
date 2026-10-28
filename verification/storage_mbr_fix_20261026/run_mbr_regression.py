"""Portable focused MBR regression; run from the engineering repository."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parents[1]
parser=argparse.ArgumentParser()
parser.add_argument("--simulator-bin",type=Path,default=Path(r"D:\modelsim2020\win64"))
parser.add_argument("--output",type=Path,default=ROOT/"run")
args=parser.parse_args()
OUT=args.output.resolve();OUT.mkdir(parents=True,exist_ok=True)
result={"tests":{},"commands":[],"passed":False}
def execute(name,exe,params,cwd=OUT):
    argv=[args.simulator_bin/(exe+".exe"),*params];argv=[p.as_posix() if isinstance(p,Path) else str(p) for p in argv]
    p=subprocess.run(argv,cwd=cwd,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=180)
    log=p.stdout+p.stderr;(cwd/(name+".log")).write_text(log,encoding="utf-8")
    result["commands"].append({"command":argv,"cwd":str(cwd),"exit_code":p.returncode})
    if p.returncode:raise RuntimeError(name+" failed")
    return log
try:
    production=[PROJECT/"rtl/storage"/n for n in ("storage_pipeline.v","sd_spi_reader.v","fat32_bmp_reader.v","bmp_stream_decoder.v")]
    sources=[*production,ROOT/"fat32_mbr_regression_tb.sv",ROOT/"storage_mbr_regression_tb.sv",ROOT/"sd_spi_card_model.sv"]
    result["source_sha256"]={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    execute("init","vmap",["-c"])
    if not (OUT/"work").exists():execute("library","vlib",["work"])
    execute("map","vmap",["work",OUT/"work"])
    execute("compile","vlog",["-modelsimini",OUT/"modelsim.ini","-sv","-work","work",*sources])
    for name,top,marker in (("fat","fat32_mbr_regression_tb","MBR_REGRESSION_PASS cases=18"),("spi","storage_mbr_regression_tb","MBR_PIN_REGRESSION_PASS cases=6")):
        folder=OUT/name;folder.mkdir(exist_ok=True)
        vectors=folder/"tb/storage/vectors";vectors.mkdir(parents=True,exist_ok=True)
        for n in ("card.hex","image.hex"):shutil.copyfile(ROOT/"tb/storage/vectors"/n,vectors/n)
        (folder/"run.do").write_text("onerror {quit -f -code 1}\nrun -all\nquit -f -code 0\n",encoding="ascii")
        log=execute("simulation","vsim",["-c","-onfinish","stop","-modelsimini",OUT/"modelsim.ini","work."+top,"-do","run.do"],folder)
        passed=marker in log and "** Fatal:" not in log and "** Error:" not in log
        result["tests"][name]={"passed":passed,"markers":[s for s in log.splitlines() if "PASS" in s]}
        print(json.dumps({"test":name,"passed":passed}),flush=True)
    result["sources_unchanged"]=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in result["source_sha256"].items())
    result["passed"]=all(t["passed"] for t in result["tests"].values()) and result["sources_unchanged"]
except Exception as error:result["error"]=str(error)
(OUT/"results.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
raise SystemExit(0 if result["passed"] else 1)
