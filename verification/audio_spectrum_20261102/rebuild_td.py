"""Rebuild the board bitstream with TD's explicit physical hold-fix step."""
from pathlib import Path
import argparse,subprocess,re,time,json,hashlib,tempfile
P=argparse.ArgumentParser()
P.add_argument('--td-root',type=Path,default=Path(r'C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116'))
P.add_argument('--output',type=Path,default=Path(tempfile.gettempdir())/'fpga_spectrum_td')
a=P.parse_args();R=Path(__file__).resolve().parents[2];O=a.output.resolve();O.mkdir(parents=True,exist_ok=True)
td=R/'project/td/HDMI_Player.al';s=td.read_text(encoding='utf-8')
s=re.sub(r' Path="[^"]*"(?=>)','',s,count=1)
s=re.sub(r'<File Path="([^"]+)"',lambda m:'<File Path="'+(td.parent/m.group(1)).resolve().as_posix()+'"',s)
(O/'HDMI_Player.prj').write_text(s,encoding='utf-8')
adc=(R/'constraints/hx4s20_hdmi_player.adc').as_posix();sdc=(R/'constraints/hx4s20_hdmi_player.sdc').as_posix()
(O/'settings.cfg').write_text(f'''set ADCList {{"{adc}"}}
set SDCList {{"{sdc}"}}
set area_option -packarea
set device_name eagle_s20.db
set end_step opt_gate
set package_name EG4S20BG256
set prj_name {{HDMI_Player}}
set run_type syn
set start_step read_design
set top_model_name {{hdmi_player_board_top}}
''',encoding='utf-8')
def run(label,script):
 p=subprocess.run([str(a.td_root/'bin/td_commands_prompt.exe'),str(script)],cwd=O,capture_output=True,timeout=900)
 log=p.stdout.decode(errors='replace')+p.stderr.decode(errors='replace');(O/(label+'.log')).write_text(log,encoding='utf-8')
 assert p.returncode==0 and not re.search(r'(?:USR|TMR|SYN)-\d+\s+ERROR:|CRITICAL-WARNING',log),log[-5000:]
 print(label+': PASS',flush=True)
epoch=time.time();run('synthesis',a.td_root/'doc/scripts/DefaultFlow.tcl')
assert (O/'.opt_gate.end.f').stat().st_mtime>=epoch
(O/'route.tcl').write_text(f'''import_device eagle_s20.db -package EG4S20BG256
import_db HDMI_Player_gate.db
clear_sdc -user
read_sdc {{{sdc}}}
place
route
fix_hold
update_timing -mode final
report_timing_summary -file final.timing -ep_num 5000 -path_num 1
report_timing_exception -file final_exceptions.rpt -ep_num 5000 -path_num 1
report_area -io_info -file final.area
export_db HDMI_Player_pr.db
exit
''',encoding='utf-8')
run('route_and_hold_fix','./route.tcl')
t=(O/'final.timing').read_text(encoding='utf-8');setup=float(re.search(r'SWNS:\s*(-?[\d.]+)ns',t).group(1));hold=float(re.search(r'HWNS:\s*(-?[\d.]+)ns',t).group(1))
assert setup>=0 and hold>=0,(setup,hold)
(O/'bit.tcl').write_text('''import_device eagle_s20.db -package EG4S20BG256
import_db HDMI_Player_pr.db
bitgen -bit HDMI_Player_audio_spectrum.bit
exit
''')
run('bitgen','./bit.tcl');bit=O/'HDMI_Player_audio_spectrum.bit';assert bit.stat().st_size>100000
result={'passed':True,'setup_ns':setup,'hold_ns':hold,'bit':str(bit),'sha256':hashlib.sha256(bit.read_bytes()).hexdigest(),'hold_fix':True}
(O/'build_result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))
