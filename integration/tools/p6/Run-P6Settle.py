"""P6 measurement: headless settle (OD-6) and one-blast overhang runs for each candidate server.

For each candidate dir (holding BOM-server.exe from Build-P6Candidates.py) and each level:
  settle : --settle-ticks 2220 (2 s start-up window + 35 s), twice; both reports must be byte-identical.
  blast  : one scripted bomb-sized blast that leaves cantilevers (Bridge: top deck between two posts; Tower: a slab
           between two pillars), 1500 ticks; counts seam breaks after the blast settles (pieces giving way under
           their own weight) and the pieces left.
Writes <out>/<candidate>/<level>-<kind>-<run>.json and <out>/summary.json. Measurement only; nothing ships.
"""
import argparse, json, pathlib, subprocess, sys, time

p = argparse.ArgumentParser()
p.add_argument('--candidates', required=True, help='dir with one sub-dir per candidate')
p.add_argument('--out', required=True)
p.add_argument('--only', nargs='*', default=None)
a = p.parse_args()
repo = pathlib.Path(__file__).resolve().parents[3]
fixtures = repo / 'integration' / 'fixtures'
LEVELS = {
    'classic-yard': fixtures / 'network-yard' / 'yard.json',
    'yard': fixtures / 'levels' / 'YardLevel.json',
    'bridge': fixtures / 'levels' / 'BridgeLevel.json',
    'tower': fixtures / 'levels' / 'TowerLevel.json',
}
BLASTS = {  # tick,x,y,radius (bomb_radius 5)
    'bridge': '300,-3.25,13.4,5',
    'tower': '300,0,15.8,5',
}
BLAST_TICKS = 1500
SETTLE_GRACE = 30  # ticks after the blast that belong to the blast itself


def run(server, layout, report, extra):
    started = time.time()
    proc = subprocess.run([str(server), '--validate-layout', str(layout), '--report', str(report)] + extra,
                          capture_output=True, text=True)
    report.with_suffix('.stdout.txt').write_text(proc.stdout + proc.stderr, encoding='utf-8')
    return proc.returncode, round(time.time() - started, 1)


def settle_summary(path):
    r = json.loads(path.read_text(encoding='utf-8-sig'))['settle']
    lost = sum(s['cells_lost'] for s in r['sources'])
    late = [s for s in r['seams'] if s.get('break_tick', 0) and s['break_tick'] > r['window_ticks']]
    return {'status': r['status'], 'cells_lost': lost, 'max_piece_displacement': round(r['max_piece_displacement'], 4),
            'seam_breaks_after_window': len(late), 'max_r': round(max([s['max_r'] for s in r['seams']] or [0]), 3)}


def blast_summary(path):
    r = json.loads(path.read_text(encoding='utf-8-sig'))['settle']
    b = r['blast']
    after = [t for t in b['trace'] if t['tick'] > b['tick'] + SETTLE_GRACE]
    return {'cells_before': b['cells_before'], 'cells_after_blast': b['cells_after_blast'],
            'pieces_before': len(b['pieces_before']), 'pieces_final': len(b['pieces_final']),
            'breaks_at_blast': sum(t['breaks'] for t in b['trace'] if t['tick'] <= b['tick'] + SETTLE_GRACE),
            'breaks_after_blast': sum(t['breaks'] for t in after),
            'last_break_tick': max([t['tick'] for t in after if t['breaks']] or [0])}


rows = []
root = pathlib.Path(a.candidates)
out = pathlib.Path(a.out)
for cand in sorted(d for d in root.iterdir() if (d / 'BOM-server.exe').exists()):
    if a.only and cand.name not in a.only:
        continue
    server = cand / 'BOM-server.exe'
    target = out / cand.name
    target.mkdir(parents=True, exist_ok=True)
    for level, layout in LEVELS.items():
        texts = []
        for n in (1, 2):
            report = target / f'{level}-settle-{n}.json'
            code, secs = run(server, layout, report, ['--settle-ticks', '2220'])
            row = {'candidate': cand.name, 'level': level, 'kind': 'settle', 'run': n, 'exit': code, 'seconds': secs}
            if report.exists():
                row.update(settle_summary(report)); texts.append(report.read_bytes())
            rows.append(row); print(json.dumps(row), flush=True)
        rows.append({'candidate': cand.name, 'level': level, 'kind': 'settle-repeat',
                     'byte_identical': len(texts) == 2 and texts[0] == texts[1]})
        print(json.dumps(rows[-1]), flush=True)
        if level in BLASTS:
            report = target / f'{level}-blast.json'
            code, secs = run(server, layout, report, ['--settle-ticks', str(BLAST_TICKS), '--settle-blast', BLASTS[level]])
            row = {'candidate': cand.name, 'level': level, 'kind': 'blast', 'blast': BLASTS[level], 'exit': code, 'seconds': secs}
            if report.exists():
                row.update(blast_summary(report))
            rows.append(row); print(json.dumps(row), flush=True)
(out / 'summary.json').write_text(json.dumps(rows, indent=1), encoding='utf-8')
