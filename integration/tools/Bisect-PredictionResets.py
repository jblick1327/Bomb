"""Short A/B of saved native builds on one prediction profile, round-robin, counting resets.

Each build in integration/build/owner-native/<dir>/source/build is staged into a scratch root with the current
Engine/build/interop harness (same harness for all ABI-1.7 builds), then Run-PredictionProfile.py runs it.
Usage: python Bisect-PredictionResets.py --out <dir> --seconds 180 --rounds 2 <snapshot-dir-name>...
"""
import argparse, ctypes, json, pathlib, shutil, subprocess, sys, re


class _PowerStatus(ctypes.Structure):
    _fields_ = [('ACLineStatus', ctypes.c_ubyte), ('BatteryFlag', ctypes.c_ubyte), ('BatteryLifePercent', ctypes.c_ubyte),
                ('SystemStatusFlag', ctypes.c_ubyte), ('BatteryLifeTime', ctypes.c_ulong), ('BatteryFullLifeTime', ctypes.c_ulong)]


def on_ac():
    """True on the charger, False on battery, None if unknown. Battery runs are flagged, not counted."""
    status = _PowerStatus()
    if not ctypes.windll.kernel32.GetSystemPowerStatus(ctypes.byref(status)):
        return None
    return {0: False, 1: True}.get(status.ACLineStatus)

p = argparse.ArgumentParser()
p.add_argument('--out', required=True)
p.add_argument('--seconds', type=int, default=180)
p.add_argument('--rounds', type=int, default=2)
p.add_argument('--seed', type=int, default=2026)
p.add_argument('--rtt-ms', default='100')
p.add_argument('--jitter-ms', default='10')
p.add_argument('--loss', default='0')
p.add_argument('--fps', default='60')
p.add_argument('snapshots', nargs='+')
a = p.parse_args()

tools = pathlib.Path(__file__).resolve().parent
integration = tools.parent
repo = integration.parent
base_config = json.loads((integration / 'local.config.json').read_text(encoding='utf-8-sig'))
harness = repo / 'Engine' / 'build' / 'interop'
out = pathlib.Path(a.out).resolve(); out.mkdir(parents=True, exist_ok=True)
scratch = out / 'roots'

configs = {}
for snap in a.snapshots:
    src = integration / 'build' / 'owner-native' / snap / 'source' / 'build'
    ident = json.loads((src / 'bomcore.build.json').read_text(encoding='utf-8-sig'))
    label = ident.get('source_commit', snap)[:8]
    root = scratch / label / 'build'
    (root / 'interop').mkdir(parents=True, exist_ok=True)
    for f in harness.iterdir():
        if f.is_file() and f.name.startswith('Interop'):
            shutil.copy2(f, root / 'interop' / f.name)
    shutil.copy2(src / 'bomcore.dll', root / 'interop' / 'bomcore.dll')
    for name in ('bomcore.dll', 'bomcore.build.json', 'BOM-server.exe'):
        shutil.copy2(src / name, root / name)
    cfg = dict(base_config); cfg['OdinRoot'] = str(root.parent)
    path = integration / f'local.config.bisect-{label}.json'
    path.write_text(json.dumps(cfg, indent=2), encoding='utf-8')
    configs[label] = path

rows = []
try:
    for r in range(a.rounds):
        for label, cfg in configs.items():
            log = out / f'r{r + 1}-{label}.log'
            cmd = [sys.executable, str(tools / 'Run-PredictionProfile.py'), '--config', str(cfg), '--evidence-stage', 'M9',
                   '--seconds', str(a.seconds), '--rtt-ms', a.rtt_ms, '--jitter-ms', a.jitter_ms, '--loss', a.loss,
                   '--fps', a.fps, '--seed', str(a.seed)]
            ac_start = on_ac()
            text = subprocess.run(cmd, capture_output=True, text=True).stdout
            log.write_text(text, encoding='utf-8')
            row = {'round': r + 1, 'build': label, 'ac': bool(ac_start and on_ac())}
            for line in text.splitlines():
                if line.startswith('{"status"'):
                    d = json.loads(line); res = d['result']; s = res['stats']
                    row.update(status=res['status'], resets=s['reset_count'], conservative_s=round(s['conservative_seconds'], 3),
                               fallback=res['fallbackFrames'], snaps=s['snap_count'], fps=round(res['actualPresentationFps'], 1))
                if line.startswith('Evidence: '):
                    row['evidence'] = line[10:]
            profile_log = pathlib.Path(row.get('evidence', '')) / 'profile.log'
            if row.get('evidence') and profile_log.exists():
                row['missing_command'] = len(re.findall(r'reason=Missing_Command', profile_log.read_text(encoding='utf-8', errors='replace')))
            rows.append(row); print(json.dumps(row), flush=True)
finally:
    for cfg in configs.values():
        cfg.unlink(missing_ok=True)
(out / 'summary.json').write_text(json.dumps(rows, indent=1), encoding='utf-8')
