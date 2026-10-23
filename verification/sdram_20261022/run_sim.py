"""Run the SDRAM write controller suites without modifying the source project."""
from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
import shutil
import subprocess
import sys


HERE = Path(__file__).resolve().parent
LOCAL_TZ = timezone(timedelta(hours=8))


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def execute(argv: list[str], log_name: str) -> dict:
    result = subprocess.run(
        argv, cwd=HERE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        encoding="utf-8", errors="replace", timeout=30, check=False,
    )
    (HERE / log_name).write_text(result.stdout, encoding="utf-8")
    return {"command": argv, "exit_code": result.returncode, "log": log_name}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--project", type=Path,
        default=Path(r"C:\Users\31640\Desktop\FPGA_Projects\FPGA_HDMI_Player"),
    )
    parser.add_argument("--iverilog", default=shutil.which("iverilog"))
    parser.add_argument("--vvp", default=shutil.which("vvp"))
    args = parser.parse_args()
    if not args.iverilog or not args.vvp:
        parser.error("iverilog and vvp are required; supply their paths if absent from PATH")

    paths = [
        args.project / "rtl/memory/sdram_write_ctrl.v",
        args.project / "rtl/memory/sync_fifo.v",
        args.project / "tb/memory/sdram_write_ctrl_tb.v",
    ]
    original_data = {path: path.read_bytes() for path in paths}
    snapshots = HERE / "sources"
    snapshots.mkdir(exist_ok=True)
    for path, data in original_data.items():
        (snapshots / path.name).write_bytes(data)

    results = {
        "started_at": datetime.now(LOCAL_TZ).isoformat(),
        "source_project": str(args.project.resolve()),
        "sources": [
            {"path": str(path), "bytes": len(data), "sha256": digest(data),
             "snapshot": str((snapshots / path.name).relative_to(HERE))}
            for path, data in original_data.items()
        ],
        "testbenches": [
            {"path": name, "sha256": digest((HERE / name).read_bytes())}
            for name in ("sdram_write_ctrl_tb.v", "sdram_fifo_integration_tb.v")
        ],
        "suites": [],
    }

    suites = [
        ("sdram_write_ctrl_tb", "sdram_write_ctrl", ["sdram_write_ctrl.v"],
         "SUITE_PASS cases=11", "sdram_write_ctrl.vcd"),
        ("sdram_fifo_integration_tb", "integration",
         ["sdram_write_ctrl.v", "sync_fifo.v"], "INTEGRATION_PASS", "integration.vcd"),
    ]
    passed = True
    for top, prefix, rtl_names, marker, waveform in suites:
        binary = HERE / f"{prefix}.vvp"
        compile_result = execute(
            [args.iverilog, "-g2012", "-Wall", "-s", top, "-o", str(binary)]
            + [str(snapshots / name) for name in rtl_names]
            + [str(HERE / f"{top}.v")],
            f"{prefix}_compile.log",
        )
        suite = {"name": top, "compile": compile_result}
        if compile_result["exit_code"] == 0:
            run_result = execute([args.vvp, "-n", str(binary)], f"{prefix}.log")
            suite["simulation"] = run_result
            log_text = (HERE / run_result["log"]).read_text(encoding="utf-8")
            suite["passed"] = (
                run_result["exit_code"] == 0 and marker in log_text
                and (HERE / waveform).is_file() and (HERE / waveform).stat().st_size > 0
            )
            suite["waveform"] = waveform
            print(log_text, end="" if log_text.endswith("\n") else "\n")
        else:
            suite["passed"] = False
            print((HERE / compile_result["log"]).read_text(encoding="utf-8"))
        results["suites"].append(suite)
        passed = passed and suite["passed"]

    results["source_files_unchanged"] = all(
        path.read_bytes() == data for path, data in original_data.items()
    )
    results["finished_at"] = datetime.now(LOCAL_TZ).isoformat()
    results["passed"] = passed and results["source_files_unchanged"]
    (HERE / "results.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("ALL_SUITES_PASS" if results["passed"] else "SIMULATION_FAILED")
    return 0 if results["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
