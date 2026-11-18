"""G5 I5 settle check (design doc 3.1 I5; the C2b harness): for each layout, start the real BOM-server with it, join a spectator
native client (Settle.csproj) and watch the world revision for --seconds with no players and no blasts.
Passes a level when the revision never changes. Evidence (server log, client log, summary.json) goes to --out.
Usage: python Run-G5Settle.py --config integration/local.config.owner-validation.json --out DIR [--native-root CHECKPOINT/source] LAYOUT.json [LAYOUT.json ...]
--native-root runs another owner-native checkpoint's BOM-server and bomcore.dll instead of the config's OdinRoot."""
import argparse, json, os, pathlib, re, shutil, socket, subprocess, sys, time
p = argparse.ArgumentParser(); p.add_argument('--config', required=True); p.add_argument('--out', required=True)
p.add_argument('--seconds', type=float, default=35); p.add_argument('--native-root', default=''); p.add_argument('layouts', nargs='+'); a = p.parse_args()
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
    srv = subprocess.Popen([str(odin / 'build' / 'BOM-server.exe'), '--port', str(port), '--layout', str(layout), '--seconds', str(int(a.seconds + 25)), '--host-token', TOKEN],
                           cwd=str(odin), stdout=srv_log, stderr=subprocess.STDOUT)
    time.sleep(1.5)
    try:
        client = subprocess.run([str(build / 'Settle.exe'), str(port), str(a.seconds), '1', TOKEN, '0'], capture_output=True, text=True, timeout=a.seconds + 60)
        text = client.stdout + client.stderr
    finally:
        srv.terminate()
        try: srv.wait(timeout=10)
        except Exception: srv.kill()
        srv_log.close()
    (out / (name + '-client.log')).write_text(text)
    rows = [re.match(r't=([\d.]+) rev=(\d+) poses=(\d+) cells=(\d+) moved=(\d+) maxd=([\d.]+)', l) for l in text.splitlines()]
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
    r['status'] = 'passed' if r['revision_constant'] else 'failed'
    results.append(r); print(json.dumps(r)); sys.stdout.flush()
(out / 'summary.json').write_text(json.dumps(results, indent=2))
print('Evidence: ' + str(out))
