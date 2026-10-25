"""Compile exact project snapshots and an unmodified reference SDRAM model."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
PROJECT = Path(r"C:\Users\31640\Desktop\FPGA_Projects\FPGA_HDMI_Player")
MODELSIM = Path(r"D:\modelsim2020\win64")
VENDOR = Path(r"C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\sim_release")
MODEL = Path(r"C:\Users\31640\Desktop\FPGA_Projects\APUG011_high_performance_sdram_read_write_reference_design_v1.2\APUG011_high_performance_sdram_read_write_reference_design_v1.2\source_code\model\IS42s32200.v")
LIBRARIES = Path(r"C:\Users\31640\Documents\ChatGPT\FFF\sdram_sip_integration_20261024\run")


def sha(data):
    return hashlib.sha256(data).hexdigest()


parser = argparse.ArgumentParser()
parser.add_argument("--name", default="refresh_matrix_180")
parser.add_argument("--project", type=Path, default=ROOT.parents[1])
parser.add_argument("--profile", type=int, default=0)
parser.add_argument("--duration-us", type=int, default=1200)
parser.add_argument("--phase-diag", action="store_true")
parser.add_argument("--phase-degrees", type=int, choices=(90, 270), default=90)
args = parser.parse_args()
PROJECT = args.project.resolve()
if not re.fullmatch(r"[a-zA-Z0-9_-]+", args.name) or not 0 <= args.profile <= 10 or not 1 <= args.duration_us <= 10000:
    raise SystemExit("Invalid case settings")
out = ROOT / args.name
out.mkdir(parents=True, exist_ok=True)
snapshot = out / "project_snapshot"
names = ["include/global_def.v", "rtl/ip/clk_pll/clk_pll.v", "rtl/ip/sdram/sdr_init_ref.enc.v",
         "rtl/ip/sdram/sdr_wrrd.enc.v", "rtl/ip/sdram/sdr_as_ram.enc.v", "rtl/memory/sync_fifo.v",
         "rtl/memory/sdram_write_ctrl.v", "rtl/memory/memory_top.v"]
if (PROJECT / "rtl/memory/sdram_refresh_ctrl.v").exists():
    names.insert(-1, "rtl/memory/sdram_refresh_ctrl.v")
record = {"started_utc": datetime.now(timezone.utc).isoformat(), "profile": args.profile,
          "diagnostic_clock_phase_override": args.phase_diag,
          "diagnostic_phase_degrees": args.phase_degrees if args.phase_diag else None,
          "commands": [], "sources": [], "source_files_unchanged": False, "passed": False}
original = {}


def run(name, exe, arguments, cwd=out):
    command = [str(MODELSIM / (exe + ".exe")), *map(str, arguments)]
    stage = {"name": name, "command": command, "cwd": str(cwd)}
    record["commands"].append(stage)
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=120)
    stage["exit_code"] = result.returncode
    stage["log"] = str(out / (name + ".log"))
    log = result.stdout + result.stderr
    Path(stage["log"]).write_text(log, encoding="utf-8")
    print(name + ": exit_code=" + str(result.returncode), flush=True)
    if result.returncode:
        raise RuntimeError(name + " failed; see " + stage["log"])
    return log


try:
    for name in names:
        source = PROJECT / name
        data = source.read_bytes()
        original[source] = data
        target = snapshot / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        record["sources"].append({"source": str(source), "compiled": str(target), "sha256": sha(data)})
    for source, target in [(MODEL, out / "IS42s32200.v"), (ROOT / "functional_tb.v", out / "functional_tb.v")]:
        data = source.read_bytes()
        original[source] = data
        target.write_bytes(data)
        record["sources"].append({"source": str(source), "compiled": str(target), "sha256": sha(data)})
    run("vmap_init", "vmap", ["-c"])
    if not (out / "work").exists():
        run("vlib_work", "vlib", ["work"])
    for library, directory in [("work", out / "work"), ("al", LIBRARIES / "al"), ("eg", LIBRARIES / "eg")]:
        run("vmap_" + library, "vmap", [library, directory])
    run("compile", "vlog", ["-modelsimini", out / "modelsim.ini", "-mfcu", "-work", "work", "+incdir+" + str(snapshot / "include"),
        *[snapshot / n for n in names], out / "IS42s32200.v", out / "functional_tb.v", VENDOR / "eg4/eg_phy_glbl.v"],
        cwd=snapshot / "rtl/memory")
    action = out / "run_check.do"
    action.write_text("onerror {quit -f -code 1}\nonbreak {quit -f -code 1}\n"
                      + "set hierarchy_file [open hierarchy.txt w]\n"
                      + "catch {puts $hierarchy_file [find instances -recursive /functional_tb/dut/u2_ram/*]}\n"
                      + "catch {puts $hierarchy_file [find signals -recursive /functional_tb/dut/u2_ram/*]}\n"
                      + "close $hierarchy_file\n"
                      + f"run {args.duration_us} us\nquit -f -code 0\n", encoding="ascii")
    log = run("simulation", "vsim", ["-c", "-onfinish", "stop", "-modelsimini", "modelsim.ini",
        "-voptargs=+acc", "-L", "al", "-L", "eg", "work.functional_tb", "work.glbl",
        "+PROFILE=" + str(args.profile), "+PHASE_DIAG=" + str(int(args.phase_diag)),
        "+PHASE_DEGREES=" + str(args.phase_degrees), "-do", "run_check.do"])
    record["functional_pass"] = "FUNCTIONAL_SUITE_PASS" in log and "TB_FAIL" not in log
    record["model_timing_errors"] = [line for line in log.splitlines()
        if re.search(r"ERROR:|Timing violation|\$setuphold|\$width\(|\$period\(", line, re.IGNORECASE)]
    record["timing_clean"] = not record["model_timing_errors"]
    record["markers"] = [line for line in log.splitlines() if re.search(r"CASE_|SUITE_|INITIALIZED|MODE_REGISTER", line)]
    summary = next((line for line in log.splitlines() if "SUITE_EXECUTED" in line), "")
    record["suite_executed"] = bool(summary)
    record["summary_counts"] = {key: int(value) for key, value in re.findall(r"([a-z_]+)=(\d+)(?![\d.])", summary)}
    record["passed"] = record["functional_pass"] and record["timing_clean"]
except Exception as error:
    record["error"] = str(error)
    simulation = out / "simulation.log"
    if simulation.exists():
        log = simulation.read_text(encoding="utf-8")
        record["model_timing_errors"] = [line for line in log.splitlines() if re.search(r"ERROR:|Timing violation", line, re.IGNORECASE)]
        record["failures"] = [line for line in log.splitlines() if "TB_FAIL" in line or "READ_RESULT" in line]
finally:
    record["source_files_unchanged"] = all(path.read_bytes() == data for path, data in original.items())
    record["finished_utc"] = datetime.now(timezone.utc).isoformat()
    (out / "results.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in record.items() if k not in ("commands", "sources")}, ensure_ascii=True))
raise SystemExit(0 if record["passed"] and record["source_files_unchanged"] else 1)
