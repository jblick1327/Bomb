"""G5 I5 settle check (design doc 3.1 I5; the C2b harness): for each layout, start the real BOM-server with it, join a spectator
native client (Settle.csproj) and watch the world revision for --seconds with no players and no blasts.
OD-6 I5 (default): ticks 0..--window-ticks (120) are a start-up window; the baseline is the first sample at or after that tick, then
--seconds of observation: pass when the cell count never drops below the baseline and no piece moves more than --max-move (0.1) from its
baseline pose. Revision changes after the window are reported, not failing. The old strict verdict (revision constant from the first
sample) stays in each result as strict_status. Evidence (server log, client log, summary.json) goes to --out.
Usage: python Run-G5Settle.py --config integration/local.config.owner-validation.json --out DIR [--native-root CHECKPOINT/source] LAYOUT.json [LAYOUT.json ...]
--native-root runs another owner-native checkpoint's BOM-server and bomcore.dll instead of the config's OdinRoot."""
import argparse, json, os, pathlib, re, shutil, socket, subprocess, sys, time
p = argparse.ArgumentParser(); p.add_argument('--config', required=True); p.add_argument('--out', required=True)
p.add_argument('--seconds', type=float, default=35); p.add_argument('--native-root', default=''); p.add_argument('--window-ticks', type=int, default=120); p.add_argument('--max-move', type=float, default=0.1); p.add_argument('layouts', nargs='+'); a = p.parse_args()
cfg = json.loads(pathlib.Path(a.config).read_text(encoding='utf-8-sig')); odin = pathlib.Path(a.native_root or cfg['OdinRoot'])
here = pathlib.Path(__file__).resolve().parent; out = pathlib.Path(a.out).resolve(); out.mkdir(parents=True, exist_ok=True)
build = here.parents[2] / 'build' / 'g5-settle'  # git-ignored; the harness and a copy of the checkpoint's bomcore.dll
subprocess.run(['dotnet', 'build', str(here / 'Settle.csproj'), '-c', 'Release', '-o', str(build), '--nologo', '-v', 'q'], check=True)
shutil.copy2(odin / 'build' / 'bomcore.dll', build / 'bomcore.dll')
TOKEN = 'g5settletoken0123456789abcdef'
results = []
for layout in a.layouts:
    layout = pathlib.Path(layout).resolve(); name = layout.stem
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s: s.bind(('127.0.0.1', 0)); port = s.getsockname()[1]
    srv_log = (out / (name + '-server.log')).open('w')
    srv = subprocess.Popen([str(odin / 'build' / 'BOM-server.exe'), '--port', str(port), '--layout', str(layout), '--seconds', str(int(a.seconds + 40)), '--host-token', TOKEN],
                           cwd=str(odin), stdout=srv_log, stderr=subprocess.STDOUT)
    time.sleep(1.5)
    try:
        client = subprocess.run([str(build / 'Settle.exe'), str(port), str(a.seconds), '1', TOKEN, '0', str(a.window_ticks)], capture_output=True, text=True, timeout=a.seconds + 90)
        text = client.stdout + client.stderr
    finally:
        srv.terminate()
        try: srv.wait(timeout=10)
        except Exception: srv.kill()
        srv_log.close()
    (out / (name + '-client.log')).write_text(text)
    rows = [re.match(r't=([\d.]+) rev=(\d+)(?: tick=\d+)? poses=(\d+) cells=(\d+) moved=(\d+) maxd=([\d.]+)', l) for l in text.splitlines()]
    rows = [m for m in rows if m]
    revs = [int(m.group(2)) for m in rows]
    server = (out / (name + '-server.log')).read_text(errors='replace')
    changes = sorted(set(int(x) for x in re.findall(r'HASH EXPECT .*?revision=(\d+)', server)))
    last = rows[-1] if rows else None
    r = {'layout': str(layout), 'level': name, 'seconds': a.seconds, 'samples': len(rows),
         'observed_seconds': float(last.group(1)) if last else 0, 'first_revision': revs[0] if revs else None, 'last_revision': revs[-1] if revs else None,
         'revision_changes_seen': len(set(revs)) - 1 if revs else None, 'first_cells': int(rows[0].group(4)) if rows else None, 'last_cells': int(last.group(4)) if last else None,
         'last_moved_pieces': int(last.group(5)) if last else None, 'last_max_displacement': float(last.group(6)) if last else None,
         'server_revisions_logged': changes,
         'revision_constant': bool(revs) and len(set(revs)) == 1 and float(last.group(1)) >= a.seconds - 2}
    r['strict_status'] = 'passed' if r['revision_constant'] else 'failed'
    m = re.search(r'I5 BASELINE t=([\d.]+) tick=(\d+) rev=(\d+) cells=(\d+)', text)
    res = re.search(r'I5 RESULT baseline_tick=(\d+) observed=([\d.]+) base_cells=(\d+) min_cells=(\d+) max_disp=([\d.]+)\((\d+)\) max_disp_tick=(\d+) revisions_after=(\d+) pieces=(\d+)', text)
    if res:
        r.update({'window_ticks': a.window_ticks, 'max_move': a.max_move, 'baseline_tick': int(res.group(1)), 'baseline_t': float(m.group(1)) if m else None,
                  'baseline_revision': int(m.group(3)) if m else None, 'observed_after_baseline': float(res.group(2)), 'baseline_cells': int(res.group(3)),
                  'min_cells_after': int(res.group(4)), 'max_move_after': float(res.group(5)), 'max_move_piece': res.group(6), 'max_move_tick': int(res.group(7)),
                  'revision_changes_after': int(res.group(8)), 'pieces_tracked': int(res.group(9))})
        r['cells_kept'] = r['min_cells_after'] >= r['baseline_cells']
        r['pieces_still'] = r['max_move_after'] <= a.max_move
        r['observed_full'] = r['observed_after_baseline'] >= a.seconds - 0.5
        r['status'] = 'passed' if r['cells_kept'] and r['pieces_still'] and r['observed_full'] else 'failed'
    else:
        r['status'] = 'failed'; r['i5_error'] = 'no I5 RESULT line (no baseline sample at or after the window)'
    results.append(r); print(json.dumps(r)); sys.stdout.flush()
(out / 'summary.json').write_text(json.dumps(results, indent=2))
print('Evidence: ' + str(out))
