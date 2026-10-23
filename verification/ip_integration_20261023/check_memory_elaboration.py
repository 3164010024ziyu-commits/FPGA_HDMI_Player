"""Compile the supplied SDRAM IP and unchanged user hierarchy with ModelSim.

All generated libraries, logs and results stay beside this helper. The default
loads memory_top and advances zero simulation time; it is not a memory test.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
import re
import subprocess
import sys


HERE = Path(__file__).resolve().parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--modelsim", type=Path, default=Path(r"D:\modelsim2020\win64"))
    parser.add_argument("--vendor-libs", type=Path, default=Path(
        r"C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\sim_release"))
    parser.add_argument("--output", type=Path, default=HERE / "run")
    parser.add_argument("--testbench", type=Path)
    parser.add_argument("--top", default="memory_top")
    parser.add_argument("--run-time", default="0 ns")
    parser.add_argument("--expect-marker")
    parser.add_argument("--skip-libraries", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", args.top):
        parser.error("--top must be a simple Verilog module name")
    if not re.fullmatch(r"\d+(?:\.\d+)?\s*(?:fs|ps|ns|us|ms|s)", args.run_time):
        parser.error("--run-time must be a nonnegative duration such as '0 ns'")

    project = args.project.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    ini = output / "modelsim.ini"
    header = project / "include/global_def.v"
    sources = [
        header,
        project / "rtl/ip/clk_pll/clk_pll.v",
        project / "rtl/ip/sdram/sdr_as_ram.enc.v",
        project / "rtl/ip/sdram/sdr_init_ref.enc.v",
        project / "rtl/ip/sdram/sdr_wrrd.enc.v",
        project / "rtl/memory/sync_fifo.v",
        project / "rtl/memory/sdram_write_ctrl.v",
        project / "rtl/memory/memory_top.v",
    ]
    if args.testbench:
        sources.append(args.testbench.resolve())
    common = sorted((args.vendor_libs / "common").glob("*.v"))
    eg4 = sorted((args.vendor_libs / "eg4").glob("*.v"))
    global_source = args.vendor_libs / "eg4/eg_phy_glbl.v"
    original = {}
    record = {
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "purpose": "ModelSim compile and hierarchy load; zero-time default is not functional validation",
        "project": str(project), "top": args.top, "run_time": args.run_time,
        "commands": [], "sources": [], "passed": False,
    }

    def save() -> None:
        record["finished_utc"] = datetime.now(timezone.utc).isoformat()
        record["source_files_unchanged"] = all(
            path.read_bytes() == data for path, data in original.items())
        (output / "results.json").write_text(
            json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    def run(name: str, executable: str, arguments: list[str], cwd: Path = output) -> None:
        command = [str(args.modelsim / (executable + ".exe")), *arguments]
        stage = {"name": name, "command": command, "cwd": str(cwd), "log": name + ".log"}
        record["commands"].append(stage)
        try:
            result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, encoding="utf-8",
                                    errors="replace", timeout=180, check=False)
        except (OSError, subprocess.TimeoutExpired) as error:
            stage["exception"] = type(error).__name__
            stage["error"] = str(error)
            (output / stage["log"]).write_text(str(error) + "\n", encoding="utf-8")
            raise RuntimeError(f"{name}: {error}") from error
        stage["exit_code"] = result.returncode
        (output / stage["log"]).write_text(result.stdout, encoding="utf-8")
        print(f"{name}: exit_code={result.returncode}; {output / stage['log']}", flush=True)
        if result.returncode:
            raise RuntimeError(f"{name} failed; see log")

    try:
        for path in sources:
            data = path.read_bytes()
            original[path] = data
            record["sources"].append({"path": str(path), "bytes": len(data),
                                      "sha256": hashlib.sha256(data).hexdigest()})
        if not common or not eg4:
            raise RuntimeError("Vendor simulation library sources not found")
        if not ini.exists():
            run("vmap_init", "vmap", ["-c"])
        for library in ("work", "al", "eg"):
            folder = output / library
            if not folder.exists():
                run("vlib_" + library, "vlib", [str(folder)])
            run("vmap_" + library, "vmap", ["-modelsimini", str(ini), library, str(folder)])
        if not args.skip_libraries:
            run("compile_common", "vlog", ["-modelsimini", str(ini), "-work", "al",
                *map(str, (p for p in common if p.name != "al_phy_glbl.v"))])
            run("compile_eg4", "vlog", ["-modelsimini", str(ini), "-work", "eg",
                *map(str, (p for p in eg4 if p.name != "eg_phy_glbl.v"))])
        run("compile_design", "vlog", ["-modelsimini", str(ini), "-work", "work", "-mfcu",
            "+incdir+" + str(header.parent), *map(str, sources), str(global_source)],
            cwd=project / "rtl/memory")
        action_file = output / "run_check.do"
        action_file.write_text(
            "onerror {quit -f -code 1}\nonbreak {quit -f -code 1}\n"
            f"run {args.run_time}\nquit -f -code 0\n", encoding="ascii")
        run("load_hierarchy", "vsim", ["-c", "-modelsimini", ini.name,
            "-voptargs=+acc", "-L", "al", "-L", "eg", "work." + args.top, "work.glbl",
            "-do", action_file.name])
        if args.expect_marker and args.expect_marker not in (output / "load_hierarchy.log").read_text(encoding="utf-8"):
            raise RuntimeError("Required test success marker missing: " + args.expect_marker)
        record["passed"] = True
        print("MODELSIM_HIERARCHY_CHECK_PASS", flush=True)
    except Exception as error:
        record["error"] = str(error)
        print("MODELSIM_HIERARCHY_CHECK_FAILED: " + str(error), file=sys.stderr, flush=True)
    finally:
        save()
    return 0 if record["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
