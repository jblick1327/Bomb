from pathlib import Path
import contextlib,io,json,runpy,os
root=Path(__file__).resolve().parent.parent
os.chdir(root)
with contextlib.redirect_stdout(io.StringIO()): ns=runpy.run_path(str(root/'scripts/compare-cover.py'))
e=root/'evidence/cover-performance'; a=e/'baseline-soak-snapshot.json'
base=ns['signatures'](ns['scene'](a));rows=[]
for phase in ('part1','final'):
    p=e/(phase+'-soak-snapshot.json');scene=ns['scene'](p);sig=ns['signatures'](scene)
    row={'phase':phase,'byte_identical':a.read_bytes()==p.read_bytes(),'outlines':base[0]==sig[0],'poses':base[1]==sig[1],'partition':base[2]==sig[2], 'baseline_counts':[sum(x.get('live',True) for x in ns['scene'](a)[k]) for k in ('subdivisions','connections','pieces')], 'counts':[sum(x.get('live',True) for x in scene[k]) for k in ('subdivisions','connections','pieces')]}
    rows.append(row);print(row)
(e/'extended-comparison.json').write_text(json.dumps(rows,indent=2))
