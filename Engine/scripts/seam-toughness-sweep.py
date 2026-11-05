"""Sweep SEAM_TOUGHNESS over the five feasibility checks; writes evidence/seam-toughness/sweep*.{txt,md}."""
import subprocess,re,sys
from pathlib import Path
root=Path(__file__).resolve().parent.parent;out=root/'evidence/seam-toughness'
values=['0.025','0.05','0.1','0.2','0.4','0.8','1.6']
checks={'a':'demo_original_blast_remote_seams','c1':'force_rule_tip_block_breaks','c2':'mortar_force_calibration_and_cantilevers','c3':'shape_glue_holds_breaks','f':'force_rule_drop_block'}
names=','.join('main.'+n for n in checks.values())
rows=[]
for v in values:
    p=subprocess.run(['odin','test','src','-out:build/BOM-sweep.exe','-define:ODIN_TEST_THREADS=1','-define:SEAM_TOUGHNESS='+v,'-define:ODIN_TEST_NAMES='+names],cwd=root,capture_output=True,text=True)
    log=p.stdout+p.stderr;(out/f'sweep-{v}.txt').write_text('\n'.join(l for l in log.splitlines() if '[INFO' not in l)+'\n',encoding='utf8')
    failed=set(re.findall(r'^ - main\.(\w+)',log,re.M))
    res={k:('FAIL' if n in failed else 'pass') for k,n in checks.items()}
    live={m[1]:(m[2],m[3]) for m in re.finditer(r'Original blast tick=(\d+) protected=\d+ surviving=(\d+) right_post_max_movement=(\S+)',log) for m in [(0,m[1],m[2],m[3])]}
    far=re.findall(r'far_connection=(\d+) first_break_tick=(\d+) peak_damage=(\S+)',log)
    tip=re.search(r'tip-block-3x .*first_break_tick=(\d+)',log);drop=re.search(r'drop-1x1-from-3m .*first_break_tick=(\d+)',log)
    rows.append((v,res,live,far,tip and tip[1],drop and drop[1]))
    print(v,res,flush=True)
lines=['| SEAM_TOUGHNESS (s) | a: far seams live @20/@120, post max (m) | c1: tip block | c2: N1 holds / N2 breaks | c3: 600-tick glued cantilever | f: 1x1 drop | all five |','|---:|---|---|---|---|---|---|']
for v,res,live,far,tip,drop in rows:
    a=' / '.join(f'{live[t][0]}/17' for t in ('20','120') if t in live)+(f", {live['120'][1]}" if '120' in live else '')
    lines.append(f"| {v} | {res['a']}: {a} | {res['c1']}: break tick {tip} | {res['c2']} | {res['c3']} | {res['f']}: break tick {drop} | {'YES' if all(x=='pass' for x in res.values()) else 'no'} |")
lines+=['','Far seams in (a): first break tick (0 = never within 120) and peak damage in seconds, per connection id.','']
ids=sorted({int(f[0]) for r in rows for f in r[3]})
lines.append('| connection | '+' | '.join(r[0] for r in rows)+' |');lines.append('|---|'+'---|'*len(rows))
for i in ids:
    cells=[]
    for r in rows:
        d={int(f[0]):f for f in r[3]}[i];cells.append(f"{d[1]} / {float(d[2]):.4f}")
    lines.append(f'| {i} | '+' | '.join(cells)+' |')
(out/'sweep.md').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
