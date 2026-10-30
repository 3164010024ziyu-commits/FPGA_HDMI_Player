from pathlib import Path
import os, subprocess, tempfile
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parents[1]
OUT=Path(tempfile.gettempdir())/'fpga_display_diagnostic_20261029'
OUT.mkdir(exist_ok=True)
BIN=Path(os.environ.get('IVERILOG_BIN',r'D:\2026-2027\iverilog\iverilog\bin'))
commands=[ [BIN/'iverilog.exe','-g2012','-s','diagnostic_wrapper_tb','-o',OUT/'test.vvp',PROJECT/'rtl/top/hdmi_player_board_top.v',HERE/'diagnostic_wrapper_tb.sv'], [BIN/'vvp.exe',OUT/'test.vvp'] ]
for i,cmd in enumerate(commands):
 p=subprocess.run(list(map(str,cmd)),cwd=OUT,capture_output=True,text=True,timeout=60)
 log=p.stdout+p.stderr;(OUT/f'stage_{i}.log').write_text(log,encoding='utf-8')
 assert p.returncode==0,log
 if i:assert 'DIAGNOSTIC_LED_PASS' in log;print(log)
