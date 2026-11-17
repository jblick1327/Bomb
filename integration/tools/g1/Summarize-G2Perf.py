# G2: summarise a Run-G2PerfMatrix.ps1 folder (one row per run folder with host-perf.json).
# usage: python -I Summarize-G2Perf.py <matrix folder> [<matrix folder> ...]
# gc_mb_min = total_frame_gc / seconds * 60 (MB = 1e6 bytes); p95/p99 of frame_ms; over33_min = frames > 33.4 ms per minute;
# pg_max = max(present_ms + geometry_ms); first_blast_pg = present+geometry of the first frame with present+geometry > 1 ms
# (the first blast's presentation cost); native_max = max native_ms (Lane N, G-N5).
# E1-G: also one row per guest-perf.json (run name ends '#guest'), and blast-window columns: the frames from 0.5 s before to 3 s
# after each world-revision change (as Summarize-G1Perf.py). bw_p95_ms/bw_max_ms = frame ms there, bw_native_max = max native_ms there,
# worst_bw = the worst blast-window frame split as frame:native:present+geometry:gpu ms, to show what causes it.
import json, os, sys


def pct(values, p):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(p / 100 * (len(values) - 1))))] if values else 0.0


def window(rows):
    marks = [r['elapsed'] for a, r in zip(rows, rows[1:]) if r['revision'] != a['revision']]
    return [r for r in rows if any(m - 0.5 <= r['elapsed'] <= m + 3 for m in marks)]


print('run,frames,gc_mb_min,p95_ms,p99_ms,over33_min,pg_max,first_blast_pg,native_max,present_gc_max,resources_drained,'
      'bw_frames,bw_p95_ms,bw_max_ms,bw_native_max,worst_bw')
for root in sys.argv[1:]:
    for name in sorted(os.listdir(root)):
        for role in ('host', 'guest'):
            path = os.path.join(root, name, role + '-perf.json')
            if not os.path.isfile(path):
                continue
            d = json.load(open(path, encoding='utf-8'))
            run = name if role == 'host' else name + '#guest'
            rows = d.get('rows') or []
            frames = [r['frame_ms'] for r in rows]
            pg = [r['present_ms'] + r['geometry_ms'] for r in rows]
            first = next((x for x in pg if x > 1.0), 0.0)
            minutes = d['seconds'] / 60
            bw = window(rows)
            bwf = [r['frame_ms'] for r in bw]
            w = max(bw, key=lambda r: r['frame_ms']) if bw else None
            worst = '%.1f:%.1f:%.1f:%.1f' % (w['frame_ms'], w['native_ms'], w['present_ms'] + w['geometry_ms'], w['gpu_ms']) if w else ''
            print('%s/%s,%d,%.1f,%.2f,%.2f,%.1f,%.1f,%.1f,%.1f,%d,%s,%d,%.2f,%.1f,%.1f,%s' % (
                os.path.basename(root.rstrip('/\\')), run, len(rows), d['total_frame_gc'] / d['seconds'] * 60 / 1e6,
                pct(frames, 95), pct(frames, 99), sum(1 for f in frames if f > 33.4) / minutes, max(pg or [0]), first,
                max((r['native_ms'] for r in rows), default=0), d.get('max_present_gc', 0), d.get('resources_drained'),
                len(bw), pct(bwf, 95), max(bwf or [0]), max((r['native_ms'] for r in bw), default=0), worst))
