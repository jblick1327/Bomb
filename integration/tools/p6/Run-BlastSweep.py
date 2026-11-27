"""P6 (d) measurement: one bomb-sized blast at several points on Bridge and Tower, today's rule (base) vs a candidate.

Per run: cells and pieces after 25 s, and how many glue seams gave way after the blast itself (pieces left hanging
that then fall). Writes <out>/sweep.json and prints one line per run. Measurement only.
"""
import argparse, json, pathlib, subprocess

p = argparse.ArgumentParser()
p.add_argument('--candidates', required=True)
p.add_argument('--out', required=True)
p.add_argument('names', nargs='+')
a = p.parse_args()
repo = pathlib.Path(__file__).resolve().parents[3]
levels = repo / 'integration' / 'fixtures' / 'levels'
POINTS = {
    'bridge': [(-3.25, 13.4), (0, 13.4), (3.25, 13.4), (-6, 11), (6, 11), (-3.25, 9)],
    'tower': [(0, 15.8), (-3, 12), (3, 12), (0, 9), (-3, 20), (3, 20)],
}
FILES = {'bridge': 'BridgeLevel.json', 'tower': 'TowerLevel.json'}
out = pathlib.Path(a.out); out.mkdir(parents=True, exist_ok=True)
rows = []
for level, points in POINTS.items():
    for x, y in points:
        for name in a.names:
            report = out / f'{name}-{level}-{x}_{y}.json'
            proc = subprocess.run([str(pathlib.Path(a.candidates) / name / 'BOM-server.exe'), '--validate-layout', str(levels / FILES[level]),
                                   '--report', str(report), '--settle-ticks', '1500', '--settle-blast', f'300,{x},{y},5'],
                                  capture_output=True, text=True)
            row = {'level': level, 'point': [x, y], 'candidate': name, 'exit': proc.returncode}
            if report.exists():
                r = json.loads(report.read_text(encoding='utf-8-sig'))['settle']; b = r['blast']
                row.update(cells_after=b['cells_after_blast'], pieces_final=len(b['pieces_final']),
                           seams_broken_after_blast=sum(1 for s in r['seams'] if s.get('break_tick', 0) > b['tick'] + 30),
                           seams_broken_total=sum(1 for s in r['seams'] if s.get('break_tick', 0)))
            rows.append(row); print(json.dumps(row), flush=True)
(out / 'sweep.json').write_text(json.dumps(rows, indent=1), encoding='utf-8')
