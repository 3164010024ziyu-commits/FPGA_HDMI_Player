"""Audit final routed endpoints, including exceptions and SDRAM DQ checks."""
from pathlib import Path
import argparse, subprocess, json, re, collections

p=argparse.ArgumentParser()
p.add_argument('--build',type=Path,required=True)
p.add_argument('--td-root',type=Path,default=Path(r'C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116'))
a=p.parse_args();O=a.build.resolve()
(O/'audit.tcl').write_text('''import_device eagle_s20.db -package EG4S20BG256
import_db HDMI_Player_pr.db
report_timing_summary -file all_endpoints_verified.rpt -ep_num 5000 -path_num 1
report_timing_exception -file exceptions_verified.rpt -ep_num 5000 -path_num 1
report_timing_ignored -file ignored_verified.rpt -ep_num 1000 -path_num 1
report_clock_summary -file clocks_verified.rpt
exit
''',encoding='ascii')
q=subprocess.run([str(a.td_root/'bin/td_commands_prompt.exe'),'./audit.tcl'],cwd=O,capture_output=True,timeout=180)
log=q.stdout.decode(errors='replace')+q.stderr.decode(errors='replace')
(O/'audit.log').write_text(log,encoding='utf-8')
assert q.returncode==0 and not re.search(r'CRITICAL-WARNING|[A-Z]+-\d+ ERROR:',log),log[-4000:]
text=(O/'all_endpoints_verified.rpt').read_text(encoding='utf-8')+'\n'+(O/'exceptions_verified.rpt').read_text(encoding='utf-8')
pattern=r'\nSlack\s+:\s*(-?[\d.]+)ns\nBegin Point\s+:\s*([^\n]+)\nEnd Point\s+:\s*([^\n]+)\nCheck Type\s+:\s*([^\n]+)'
records=[dict(slack=float(x),start=s.split(' (')[0],end=e.split(' (')[0],kind=k.strip()) for x,s,e,k in re.findall(pattern,text)]
records=list({(x['slack'],x['start'],x['end'],x['kind']):x for x in records}.values())
def stats(items):
    return {'checks':len(items),'minimum_ns':min((x['slack'] for x in items),default=None),'negative':sum(x['slack']<0 for x in items)}
result={'total_checks':len(records),'types':dict(collections.Counter(x['kind'] for x in records)),
        'all':stats(records),'read_dq':stats([x for x in records if '/u_sdram_phy.dq' in x['start']]),
        'write_dq':stats([x for x in records if '/u_sdram_phy.dq' in x['end']]),
        'fat':stats([x for x in records if '/fat/' in x['end']]),
        'setup':stats([x for x in records if x['kind']=='setup']),
        'hold':stats([x for x in records if x['kind']=='hold']),
        'reset':stats([x for x in records if x['kind'] in ('recovery','removal')])}
assert result['total_checks']>1000 and result['all']['negative']==0,result
assert result['read_dq']['checks']==64 and result['write_dq']['checks']==64,result
(O/'timing_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2),flush=True)
