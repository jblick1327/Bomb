# G2: summarise a Run-G2PerfMatrix.ps1 folder (one row per run folder with host-perf.json).
# usage: python -I Summarize-G2Perf.py <matrix folder> [<matrix folder> ...]
# gc_mb_min = total_frame_gc / seconds * 60 (MB = 1e6 bytes); p95/p99 of frame_ms; over33_min = frames > 33.4 ms per minute;
# pg_max = max(present_ms + geometry_ms); first_blast_pg = present+geometry of the first frame with present+geometry > 1 ms
# (the first blast's presentation cost); native_max = max native_ms (Lane N, G-N5).
import json, os, sys


def pct(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(p / 100 * (len(values) - 1))))] if values else 0.0


print('run,frames,gc_mb_min,p95_ms,p99_ms,over33_min,pg_max,first_blast_pg,native_max,present_gc_max,resources_drained')
for root in sys.argv[1:]:
    for name in sorted(os.listdir(root)):
        path = os.path.join(root, name, 'host-perf.json')
        if not os.path.isfile(path):
            continue
        d = json.load(open(path, encoding='utf-8'))
        rows = d.get('rows') or []
        frames = [r['frame_ms'] for r in rows]
        pg = [r['present_ms'] + r['geometry_ms'] for r in rows]
        first = next((x for x in pg if x > 1.0), 0.0)
        minutes = d['seconds'] / 60
        print('%s/%s,%d,%.1f,%.2f,%.2f,%.1f,%.1f,%.1f,%.1f,%d,%s' % (
            os.path.basename(root.rstrip('/\\')), name, len(rows), d['total_frame_gc'] / d['seconds'] * 60 / 1e6,
            pct(frames, 95), pct(frames, 99), sum(1 for f in frames if f > 33.4) / minutes, max(pg or [0]), first,
            max((r['native_ms'] for r in rows), default=0), d.get('max_present_gc', 0), d.get('resources_drained')))
