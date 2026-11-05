"""Step 2b solo check, part 1: regenerate every capture from the current optimized build.

Runs the studies that write the "standard" World/Scene captures and every command that writes
one of the 66 accepted PNGs, then compares each PNG with the accepted bytes recorded by step 2a
(evidence/replication-2a/png-manifest.json). Tracked evidence directories that the commands
overwrite are backed up first and restored if any regenerated file differs.

usage: python scripts/capture-solo-2b.py [exe] [evidence_directory]
"""
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parent.parent
exe = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/BOM-2b.exe'
e = Path(sys.argv[2]) if len(sys.argv) > 2 else root / 'evidence/replication-2b'
e = e.resolve()
accepted = json.loads((root / 'evidence/replication-2a/png-manifest.json').read_text())
fresh_png = e / 'png-after'
fresh_json = e / 'captures-v4/standard'
fresh_png.mkdir(parents=True, exist_ok=True)
fresh_json.mkdir(parents=True, exist_ok=True)

overwritten = ['evidence/world-v3', 'evidence/editor-step2', 'evidence/seam-toughness',
               'evidence/rotation-glue', 'evidence/textures-ui']
backup = Path(tempfile.mkdtemp(prefix='bom-evidence-'))
for d in overwritten:
    if (root / d).exists():
        shutil.copytree(root / d, backup / d)

commands = [
    ['--wood-study', str(fresh_json / 'wood')],
    ['--glass-study', str(fresh_json / 'glass')],
    ['--soak-fixture', str(fresh_json / 'soak')],
    ['--smoke'], ['--smoke-input'], ['--smoke-msaa'], ['--smoke-aim'], ['--smoke-editor'], ['--smoke-materials'],
    ['--check-textures'], ['--capture-textures'],
    ['--capture-ui', str(fresh_png / 'ui')],
    ['--capture-frames', str(fresh_png / 'frames')],
    ['--check-glue-followup'], ['--check-shapes'],
]
started = time.time() - 2
for args in commands:
    log = fresh_png / (args[0].lstrip('-') + '.txt')
    print('running', ' '.join(args), flush=True)
    if args[0] == '--capture-ui':
        # The command saves layouts into this scratch directory and the layouts screen lists them with
        # their age; stale files from an earlier run would change the picture, not the code under test.
        shutil.rmtree(root / 'output/ui-capture-layouts', ignore_errors=True)
    result = subprocess.run([str(exe)] + args, cwd=root, capture_output=True, text=True)
    log.write_text(result.stdout + result.stderr, encoding='utf8')
    if result.returncode != 0:
        print('FAILED', args, result.returncode)
        sys.exit(1)


def locate(group, name):
    if group == 'smoke':
        options = [root / 'output' / name, root / 'evidence/world-v3' / name, root / 'evidence/editor-step2' / name]
    elif group == 'textures':
        options = [root / 'evidence/textures-ui/after' / name]
    elif group == 'ui':
        options = [fresh_png / 'ui' / name]
    elif group == 'frames':
        options = [fresh_png / 'frames' / name]
    elif group == 'glue':
        options = [root / 'evidence/seam-toughness' / name]
    else:
        options = [root / 'evidence/rotation-glue' / name]
    for path in options:
        if path.exists() and path.stat().st_mtime >= started:
            return path
    return None


rows, bad = [], 0
for row in accepted:
    group, name = row['file'].split('/', 1)
    path = locate(group, name)
    if path is None and group == 'textures':
        # edit-hud, test-hud, layouts, materials-builtin, materials-custom and settings in evidence/textures-ui/after
        # are accepted files from the textures-ui step that no current command rewrites (--capture-ui goes elsewhere).
        kept = root / 'evidence/textures-ui/after' / name
        digest = hashlib.sha256(kept.read_bytes()).hexdigest() if kept.exists() else ''
        ok = digest == row['sha256']
        bad += 0 if ok else 1
        rows.append(dict(file=row['file'], source=str(kept.relative_to(root)), sha256=digest, accepted_sha256=row['sha256'],
                         status='accepted file unchanged on disk (no command rewrites it)' if ok else 'DIFFERENT', ok=ok))
        continue
    if path is None:
        rows.append(dict(file=row['file'], status='NOT REGENERATED', ok=False)); bad += 1
        continue
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    target = fresh_png / row['file']
    if target.resolve() != path.resolve():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    ok = digest == row['sha256']
    bad += 0 if ok else 1
    rows.append(dict(file=row['file'], source=str(path.relative_to(root)), sha256=digest, accepted_sha256=row['sha256'],
                     bytes=len(data), status='byte-identical' if ok else 'DIFFERENT', ok=ok))
(e / 'png-compare.json').write_text(json.dumps(rows, indent=1) + '\n')
regenerated = sum(r['status'] == 'byte-identical' for r in rows)
print(f'{len(rows) - bad}/{len(rows)} PNGs match the accepted captures ({regenerated} regenerated byte-identical, {len(rows) - bad - regenerated} unchanged accepted files)')
if bad:
    for row in rows:
        if not row['ok']:
            print(row['status'], row['file'])
    for d in overwritten:
        if (backup / d).exists():
            shutil.rmtree(root / d, ignore_errors=True)
            shutil.copytree(backup / d, root / d)
    print('Evidence directories restored from', backup)
    sys.exit(1)
shutil.rmtree(backup, ignore_errors=True)
