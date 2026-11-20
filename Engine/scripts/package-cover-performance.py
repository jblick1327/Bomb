"""Validate and package the blast-cover performance change and its evidence."""
from pathlib import Path
import json,re,statistics,hashlib,zipfile
root=Path(__file__).resolve().parent.parent
e=root/'evidence/cover-performance'
env_data=(e/'benchmark-environment.txt').read_bytes()
env_text=env_data.decode('utf-16') if env_data.startswith(b'\xff\xfe') else env_data.decode('utf-8-sig')
assert 'AC end: Online' in env_text
assert 'Finished 146 tests' in (e/'complete-tests.txt').read_text(encoding='utf-16')
assert '+++ leak' not in (e/'complete-tests.txt').read_text(encoding='utf-16')
comparison=json.loads((e/'comparison.json').read_text())
for phase in ('part1','final'):
    rows=[r for r in comparison if r['phase']==phase]
    assert len(rows)==23
    assert all(all(r[k] for k in ('outlines','poses','partition')) for r in rows)
    if phase=='part1': assert all(r['byte_identical'] for r in rows)
lines=['| Fixture | Part 1 bytes | Part 2 bytes | Outlines / poses / partition |','|---|---|---|---|']
for r in comparison:
    if r['phase']=='final': lines.append(f"| {r['fixture']} | identical | {'identical' if r['byte_identical'] else 'IDs changed'} | exact / exact / exact |")
(e/'fixture-comparison.md').write_text('\n'.join(lines)+'\n')
worsts=[]
for i in range(1,4):
    t=(e/f'soak-{i}.txt').read_text(encoding='utf-16')
    rows=[line.split(',') for line in t.splitlines() if line and line[0].isdigit()]
    assert len(rows)==20 and 'after_destroy_odin_bytes=0,after_destroy_box2d_bytes=0' in t
    worsts.append(max(float(r[5]) for r in rows))
median=statistics.median(worsts)
text=(e/'final-profile.txt').read_text(encoding='utf-16')
assert 'after_destroy_odin_bytes=0,after_destroy_box2d_bytes=0' in text
profiles=[]; cover={}; all_cover=[]; latest_cover=None
for line in text.splitlines():
    if line.startswith('COVER,'):
        values=list(map(int,line.split(',')[1:])); cover[values[0]]=values[1:]; all_cover.append(values[1:]); latest_cover=values
    if line.startswith('PROFILE,'):
        m=re.match(r'PROFILE,(\d+),([\d.]+),(\[.*?\])',line)
        assert latest_cover is not None and latest_cover[0]==int(m[1])
        profiles.append((float(m[2]),int(m[1]),json.loads(m[3]),latest_cover[1:]))
total,tick,ms,worst_cover=max(profiles,key=lambda row:row[0])
counts=[sum(v[i] for v in all_cover) for i in range(4)]
samples,fast,hits,skips=counts
performance=f"Timing **{'PASS' if median<=26 else 'FAIL'}**: three sequential 20-minute soaks, with no concurrent test/compiler jobs, have worst blast passes {', '.join(f'{v:.4f}' for v in worsts)} ms. Median **{median:.4f} ms** versus the **26 ms** limit ({(median/94.8583-1)*100:.1f}% versus the previous cover median; {(median/20.9-1)*100:+.1f}% versus 20.9 ms).\n\n"
performance+=f"The separate profiled 20-minute soak's worst blast is **{total:.4f} ms**, tick **{tick}**. No-cover flags handled **{fast:,}/{samples:,} samples ({100*fast/samples:.3f}%)** overall and **{worst_cover[1]}/{worst_cover[0]} ({100*worst_cover[1]/worst_cover[0]:.3f}%)** at that event. There were {hits:,} memoized query hits and {skips:,} geometric failure-upper-bound skips; these counters are not disjoint from flag counts.\n\n"
names=['Refinement','Direct recursion','Glass source / travel','Glass staging','Glass bond breaking','Regrouping (nested)','Commit','Physics synchronization','Impulse loop / motion read','Generation (nested)','Inheritance (nested)','Sibling attachment (nested)','Containment scans (nested)','Shared boundaries (nested)','Inheritance queries (nested)','Cover ray queries (nested)','Shadow checks (nested)','Cover snapshot / index build']
performance+='The competing game and download process had exited, and all compiler/test runs had finished before these measurements. Earlier contended probes are excluded; the 94.9/20.9 ms figures are historical references.\n\n'
performance+='| Phase | ms at worst profiled blast |\n|---|---:|\n'+'\n'.join(f'| {name} | {value:.4f} |' for name,value in zip(names,ms))+'\n\nNested timings overlap their containing phases and must not be summed.'
extended=json.loads((e/'extended-comparison.json').read_text())
part1_extended=next(row for row in extended if row['phase']=='part1')
final_extended=next(row for row in extended if row['phase']=='final')
assert part1_extended['byte_identical']
extended_text=f"**Extended 20-minute check: Part 2 FAIL.** Part 1 remains byte-identical, with counts {part1_extended['counts']}. Part 2 changes counts to {final_extended['counts']} (cells/links/pieces), with different outlines, poses and partition. The controlled toggle isolates this to shortcut activation and its different intermediate staging/body history; the first divergent solver step is not localized. The default build is this Part 2 candidate; use `-define:COVER_SHORTCUTS=false` for identical Part 1 behavior. [Extended comparison](extended-comparison.json) and complete snapshots are included."
report=(e/'report-template.md').read_text().replace('PERFORMANCE',performance).replace('EXTENDED',extended_text).replace('SOAK_LEAKS','All three measured soaks and the profiled soak release all tracked Odin and Box2D bytes after teardown.')
(e/'report.md').write_text(report)
(root/'report.md').write_text(report.replace('](fixture-comparison.md)','](evidence/cover-performance/fixture-comparison.md)').replace('](extended-comparison.json)','](evidence/cover-performance/extended-comparison.json)'))
files=set()
for directory in ('src','scripts','docs'):
    files.update(p for p in (root/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
files.update(root/p for p in ('README.md','AGENTS.md','report.md','evidence/world-v3/before-v2-ticked.json'))
files.update(p for p in (root/'evidence/blast-cover').rglob('*.json') if p.relative_to(root/'evidence/blast-cover').as_posix().startswith('after'))
for p in e.rglob('*'):
    if p.is_file() and (p.suffix in ('.json','.md') or p.name in ('complete-tests.txt','final-profile.txt','soak-1.txt','soak-2.txt','soak-3.txt','wall.txt','wood.txt','bridge.txt','msaa.txt','replay.txt','part1-replay.txt','baseline-cover.odin.txt','benchmark-environment.txt','baseline-soak.txt','part1-soak.txt') or p.name.startswith(('power-event-soak-','pre-boundary-reuse-soak-'))): files.add(p)
archive=root/'BOM-blast-cover-performance-source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(files): z.write(p,p.relative_to(root).as_posix())
print(archive.name,archive.stat().st_size,'bytes',hashlib.sha256(archive.read_bytes()).hexdigest())
print('Worst blasts:',worsts,'median:',median,'limit_pass:',median<=26)
print('Profile worst:',total,'tick',tick,'no-cover fraction:',fast/samples)
