"""P6 measurement only: build BOM-server variants with candidate glue rules from the shipped staged source.

Never touches Engine/src. Copies the 64e358b1 staged frontend package, applies one candidate, builds the server with
the same odin flags as Build-OwnerNative.py, and writes <out>/<name>/BOM-server.exe plus the applied diff.
Candidates (owner picks one as an OD; see ALPHA-SYNC P6):
  base       : no change (control; must equal the shipped server's behaviour)
  torque<N>  : (a) the seam torque capacity is N% of today's (bending gives way sooner); round start included
  shock<N>   : (b) a glue seam an explosion reaches but does not break keeps N% of its strength from then on
"""
import argparse, difflib, json, os, pathlib, re, shutil, subprocess, sys

_config = json.loads((pathlib.Path(__file__).resolve().parents[2] / 'local.config.json').read_text(encoding='utf-8-sig'))
ODIN = _config['OdinCompiler']
# Same toolchain environment as Build-OwnerNative.py (Git Bash's link must not shadow the MSVC linker).
ENV = dict(os.environ, PATH=_config['LinkerDirectory'] + os.pathsep + os.environ['PATH'], LIB=';'.join(_config['LibraryDirectories']))
p = argparse.ArgumentParser()
p.add_argument('--source', required=True, help='staged frontend-package of the shipped build')
p.add_argument('--out', required=True)
p.add_argument('candidates', nargs='+')
a = p.parse_args()
source = pathlib.Path(a.source).resolve()
out = pathlib.Path(a.out).resolve()


def edit(path, old, new):
    text = path.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise SystemExit(f'{path.name}: expected one match for {old[:60]!r}, found {text.count(old)}')
    path.write_text(text.replace(old, new), encoding='utf-8')


def apply(stage, name):
    mortar = stage / 'shared' / 'sim_mortar.odin'
    m = re.fullmatch(r'torque(\d+)', name)
    if m:
        pct = int(m.group(1))
        edit(mortar, 'math.abs(seam.torque)/(0.5*strength*seam.length*seam.length)',
             f'math.abs(seam.torque)/(0.5*strength*seam.length*seam.length*f32({pct})/100) // P6 candidate (a)')
        return
    m = re.fullmatch(r'shock(\d+)', name)
    if m:
        pct = int(m.group(1))
        edit(stage / 'shared' / 'model.odin', ' damage: f32, //',
             ' shock: f32, // P6 candidate (b): strength share left after a blast reached this seam (0 = untouched)\n damage: f32, //')
        edit(mortar, ' strength:=MORTAR_STRENGTH*mortar_seam_toughness(s,seam)\n',
             ' strength:=MORTAR_STRENGTH*mortar_seam_toughness(s,seam)\n'
             ' for id in seam.members { k:=s.connections[s.conn_rows[id]].shock; if k>0 { strength=min(strength,MORTAR_STRENGTH*mortar_seam_toughness(s,seam)*k) } } // P6 (b)\n')
        destruction = stage / 'shared' / 'sim_destruction.odin'
        edit(destruction, '  load:=blast_load(cover_failure_distance(a,sample,blast,strength),blast.radius)\n  if fails(load,strength) { append(&f.connections,id) }\n',
             '  load:=blast_load(cover_failure_distance(a,sample,blast,strength),blast.radius)\n  if fails(load,strength) { append(&f.connections,id) }\n'
             f'  else if c.mortar && load>0 {{ s.connections[s.conn_rows[id]].shock=f32({pct})/100 }} // P6 (b): reached, not broken\n')
        return
    if name != 'base':
        raise SystemExit('unknown candidate ' + name)


for name in a.candidates:
    target = out / name
    stage = target / 'stage'
    if stage.exists():
        shutil.rmtree(stage)
    shutil.copytree(source, stage)
    apply(stage, name)
    diff = []
    for f in sorted(stage.rglob('*.odin')):
        rel = f.relative_to(stage)
        old = (source / rel).read_text(encoding='utf-8').splitlines(keepends=True)
        new = f.read_text(encoding='utf-8').splitlines(keepends=True)
        if old != new:
            diff += difflib.unified_diff(old, new, 'shipped/' + str(rel), name + '/' + str(rel))
    (target / 'candidate.diff').write_text(''.join(diff), encoding='utf-8')
    log = target / 'build-server.log'
    with open(log, 'w', encoding='utf-8') as handle:
        code = subprocess.run([ODIN, 'build', str(stage / 'server'), '-o:speed', '-out:' + str(target / 'BOM-server.exe'),
                               '-ignore-vs-search', '-debug'], stdout=handle, stderr=subprocess.STDOUT, env=ENV).returncode
    print(name, 'exit', code, 'diff_lines', len(diff), flush=True)
    if code != 0:
        sys.exit(code)
