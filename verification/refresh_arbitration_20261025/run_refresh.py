"""Run independent refresh scenarios on exact project snapshots, without RTL edits."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parents[1]
MODELSIM = Path(r"D:\modelsim2020\win64")
VENDOR = Path(r"C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\sim_release")
MODEL = Path(r"C:\Users\31640\Desktop\FPGA_Projects\APUG011_high_performance_sdram_read_write_reference_design_v1.2\APUG011_high_performance_sdram_read_write_reference_design_v1.2\source_code\model\IS42s32200.v")
LIBS = Path(r"C:\Users\31640\Documents\ChatGPT\FFF\sdram_sip_integration_20261024\run")
parser = argparse.ArgumentParser()
parser.add_argument("--scenario", choices=("idle", "continuous", "pause"), default="idle")
parser.add_argument("--probe-only", action="store_true")
parser.add_argument("--project", type=Path, default=PROJECT)
parser.add_argument("--tag", default="rerun")
args = parser.parse_args()
PROJECT = args.project.resolve()
if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.tag): raise SystemExit("Bad tag")
out = ROOT / args.tag / ("probe_setup" if args.probe_only else args.scenario)
out.mkdir(parents=True, exist_ok=True)
snapshot = out / "project_snapshot"
names = ["include/global_def.v", "rtl/ip/clk_pll/clk_pll.v", "rtl/ip/sdram/sdr_init_ref.enc.v",
         "rtl/ip/sdram/sdr_wrrd.enc.v", "rtl/ip/sdram/sdr_as_ram.enc.v", "rtl/memory/sync_fifo.v",
         "rtl/memory/sdram_write_ctrl.v", "rtl/memory/memory_top.v"]
if (PROJECT / "rtl/memory/sdram_refresh_ctrl.v").exists():
    names.insert(-1, "rtl/memory/sdram_refresh_ctrl.v")
record = {"scenario": args.scenario, "probe_only": args.probe_only,
          "started_utc": datetime.now(timezone.utc).isoformat(), "commands": [], "sources": [], "passed": False}
original = {}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(name, exe, arguments, cwd=out):
    command = [str(MODELSIM / (exe + ".exe")), *map(str, arguments)]
    stage = {"name": name, "command": command, "cwd": str(cwd)}
    record["commands"].append(stage)
    process = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=90)
    log = process.stdout + process.stderr
    (out / (name + ".log")).write_text(log, encoding="utf-8")
    stage["exit_code"] = process.returncode
    print(name + ": " + str(process.returncode), flush=True)
    if process.returncode:
        raise RuntimeError(name + " failed")
    return log


try:
    for name in names:
        source = PROJECT / name
        data = source.read_bytes()
        original[source] = data
        target = snapshot / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        record["sources"].append({"path": str(source), "snapshot": str(target), "sha256": sha(data)})
    for source in (MODEL, ROOT / "refresh_wait_tb.v", ROOT / "refresh_probe.sv"):
        data = source.read_bytes()
        original[source] = data
        target = out / source.name
        target.write_bytes(data)
        record["sources"].append({"path": str(source), "snapshot": str(target), "sha256": sha(data)})
    run("vmap_init", "vmap", ["-c"])
    if not (out / "work").exists(): run("vlib_work", "vlib", ["work"])
    for library, path in (("work", out / "work"), ("al", LIBS / "al"), ("eg", LIBS / "eg")):
        run("map_" + library, "vmap", [library, path])
    defines = ["+define+REFRESH_ARBITER"] if (PROJECT / "rtl/memory/sdram_refresh_ctrl.v").exists() else []
    run("compile_design", "vlog", ["-modelsimini", out / "modelsim.ini", "-mfcu", "-work", "work", *defines,
        "+incdir+" + str(snapshot / "include"), *[snapshot / name for name in names],
        out / MODEL.name, out / "refresh_wait_tb.v", VENDOR / "eg4/eg_phy_glbl.v"], cwd=snapshot / "rtl/memory")
    run("compile_probe", "vlog", ["-modelsimini", out / "modelsim.ini", "-sv", "-work", "work", out / "refresh_probe.sv"])
    duration = "1 us" if args.probe_only else "1600 us"
    (out / "run_check.do").write_text("onerror {quit -f -code 1}\nonbreak {quit -f -code 1}\n"
        + "run " + duration + "\nquit -f -code 0\n", encoding="ascii")
    number = ("idle", "continuous", "pause").index(args.scenario)
    log = run("simulation", "vsim", ["-c", "-onfinish", "stop", "-modelsimini", "modelsim.ini",
        "-voptargs=+acc", "-L", "al", "-L", "eg", "work.refresh_wait_tb", "work.refresh_bind_top", "work.glbl",
        "+SCENARIO=" + str(number), "-do", "run_check.do"])
    record["markers"] = [s for s in log.splitlines() if "WAIT_TEST_" in s]
    record["model_errors"] = [s for s in log.splitlines() if re.search(r"ERROR:|Timing violation", s, re.I)]
    record["passed"] = ((args.probe_only and "REFRESH_OBSERVER_BOUND" in log) or "WAIT_TEST_COMPLETE" in log) and not record["model_errors"] and "** Fatal:" not in log
except Exception as error:
    record["error"] = str(error)
finally:
    record["sources_unchanged"] = all(path.read_bytes() == data for path, data in original.items())
    record["finished_utc"] = datetime.now(timezone.utc).isoformat()
    (out / "results.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in record.items() if k not in ("commands", "sources")}, ensure_ascii=True))
raise SystemExit(0 if record["passed"] and record["sources_unchanged"] else 1)
