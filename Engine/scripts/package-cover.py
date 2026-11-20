"""Package source and blast-cover evidence after all three 20-minute soaks finish."""
from pathlib import Path
import statistics, zipfile, hashlib
root=Path(__file__).resolve().parent.parent
evidence=root/'evidence/blast-cover'
worst=[]
for i in range(1,4):
    text=(evidence/f'final-soak-{i}.txt').read_text(encoding='utf-16')
    rows=[line.split(',') for line in text.splitlines() if line and line[0].isdigit()]
    assert len(rows)==20 and 'after_destroy_odin_bytes=0,after_destroy_box2d_bytes=0' in text, f'Incomplete soak {i}'
    worst.append(max(float(row[5]) for row in rows))
median=statistics.median(worst)
performance=f"Performance **FAIL**: three sequential 20-minute soaks have worst blast passes {', '.join(f'{x:.4f}' for x in worst)} ms; median **{median:.4f} ms**, **{(median/20.9-1)*100:.1f}%** versus 20.9 ms (limit 26.125 ms). These three reported runs had no competing test or diagnostic runs. All three end with Odin bytes 0 and Box2D bytes 0. "
performance+=(evidence/'profile-summary.txt').read_text().strip()
performance+=' Profiling was a separate diagnostic run; inclusive query time overlaps refinement/direct/impulse timings. Cost comes from scanning snapshot-cell bounding boxes and sorting polygon intersection intervals for each sample, including reach refinement. This exact polygon implementation misses the requested performance bound; a spatial index and reusable query scratch are the next optimization targets.'
report=(evidence/'report.md').read_text().replace('PERFORMANCE_PENDING',performance)
(evidence/'report.md').write_text(report)
(root/'report.md').write_text(report.replace('](wall-','](evidence/blast-cover/wall-').replace('](fixture-counts.md)','](evidence/blast-cover/fixture-counts.md)'))
files=set()
for directory in ('src','scripts','docs'):
    files.update(p for p in (root/directory).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
files.update(root/name for name in ('README.md','AGENTS.md','report.md'))
files.add(root/'evidence/world-v3/before-v2-ticked.json')
files.update(p for p in evidence.rglob('*.json'))
for name in ('report.md','fixture-counts.md','wall-before.png','wall-after.png','wall.txt','wall-fail-first.txt','wall-pass.txt','all-tests.txt','target-tests.txt','wood.txt','before-glass.txt','after-glass.txt','replay.txt','bridge.txt','msaa.txt','profile-summary.txt','final-profile.txt','final-soak-1.txt','final-soak-2.txt','final-soak-3.txt'):
    files.add(evidence/name)
archive=root/'BOM-blast-cover-source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(files): z.write(p,p.relative_to(root).as_posix())
print(archive.name,archive.stat().st_size,'bytes',hashlib.sha256(archive.read_bytes()).hexdigest())
print(performance)
