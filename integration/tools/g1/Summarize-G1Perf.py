"""Summarise G1 perf runs (Run-G1Perf.ps1 folders) with F2's analyser, plus a blast window: the frames from 0.5 s
before each world-revision change to 3 s after it. Usage: python Summarize-G1Perf.py <run dir>... > table.md"""
import json, pathlib, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'evidence' / 'F2' / 'tools'))
import analyze_f2 as f2

def window(rows):
    marks = [r['elapsed'] for a, r in zip(rows, rows[1:]) if r['revision'] != a['revision']]
    picked = [r for r in rows if any(m - 0.5 <= r['elapsed'] <= m + 3 for m in marks)]
    fm = [r['frame_ms'] for r in picked]; gc = [r['frame_gc'] for r in picked if r['frame_gc'] >= 0]
    geo = [r['geometry_ms'] + r['present_ms'] for r in picked]
    return dict(revisions=len(marks), frames=len(fm), p50=round(f2.q(fm, .5), 2) if fm else None, p95=round(f2.q(fm, .95), 2) if fm else None,
                max=round(max(fm), 1) if fm else None, h33=sum(1 for x in fm if x > 33.4), gc_MB=round(sum(gc) / 1e6, 1),
                present_geometry_p95=round(f2.q(geo, .95), 2) if geo else None, present_geometry_max=round(max(geo), 2) if geo else None)

print('| Run | frames | p50 | p95 | p99 | max | >33 ms/min | GC MB/min | present+geometry max ms | revisions | blast-window p95 / max | blast-window >33 ms | blast-window GC MB |')
print('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
for d in sys.argv[1:]:
    d = pathlib.Path(d); p = d / 'host-perf.json'
    if not p.exists(): print(f'| {d.name} | (no perf file) |'); continue
    s = f2.perf(p); rows = json.loads(p.read_text(encoding='utf-8'))['rows']; w = window(rows)
    print(f"| {d.name} | {s['frames']} | {s['p50']} | {s['p95']} | {s['p99']} | {s['max']} | {s['h33_per_min']} | {s['gc_MB_per_min']} | "
          f"{max(s['present_max'], s['geometry_max'])} | {w['revisions']} | {w['p95']} / {w['max']} | {w['h33']} | {w['gc_MB']} |")
