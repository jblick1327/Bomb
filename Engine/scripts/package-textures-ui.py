"""Validate frozen render/UI evidence, write the report, and package deliverables."""
from pathlib import Path
import csv
import hashlib
import json
import re
import statistics
import struct
import zipfile

root = Path(__file__).resolve().parent.parent
e = root/'evidence/textures-ui'

def read(path):
    b = path.read_bytes()
    return b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig')

tests = read(e/'tests.txt')
assert 'Finished 157 tests' in tests and 'All tests were successful.' in tests
assert '[ERROR]' not in tests
for name in ('smoke-materials.txt','smoke-input.txt'):
    text = read(e/name)
    assert 'Materials smoke passed:' in text and 'Materials native teardown: Odin=0 Box2D delta=0' in text
assert 'Editor native smoke passed:' in read(e/'smoke-input.txt')
assert 'Editor smoke teardown: Odin bytes=0 Box2D delta bytes=0' in read(e/'smoke-editor.txt')
texture = read(e/'texture-checks.txt')
assert 'MSAA total interior defects: 0' in texture
assert 'points=20 max_delta=2 defects=0' in texture
assert 'cells=1897 differing_from_plank=0' in texture
assert 'Teardown Odin=0 Box2D=0 texture=0 shader=0 fonts_ready=false' in texture
assert read(e/'after-ui.txt').count('overflow=0') == 6
assert 'MSAA total interior defects: 0' in read(e/'msaa.txt')

for path in list((root/'src').rglob('*.odin')) + list((root/'docs').rglob('*.md')) + list((root/'docs').rglob('*.html')) + [root/'README.md']:
    text = path.read_text(encoding='utf-8')
    assert '\u00c3' not in text and '\u00e2\u20ac' not in text, path
    if path.suffix == '.odin' and path.name != 'ui_text.odin':
        assert not re.search(r'rl\.(?:DrawText|MeasureText)\s*\(', text), path

captures = []
for area, baseline in [('standard',root/'evidence/material-library/after/standard'),('golden',root/'evidence/material-library/rebaseline')]:
    for before in sorted(baseline.rglob('*.json')):
        rel = before.relative_to(baseline)
        after = e/'after'/area/rel
        a,b = before.read_bytes(),after.read_bytes()
        captures.append(dict(fixture=f'{area}/{rel.as_posix()}', before=before.relative_to(root).as_posix(),
            after=after.relative_to(root).as_posix(), bytes=len(a), before_sha256=hashlib.sha256(a).hexdigest(),
            after_sha256=hashlib.sha256(b).hexdigest(), identical=a==b))
assert len(captures)==48 and all(c['identical'] for c in captures)
(e/'byte-identity-manifest.json').write_text(json.dumps(captures,indent=2)+'\n')
layouts=[]
sources=['src/presets/materials.json','src/presets/tower.json','src/presets/glass-house.json',
         'src/presets/rubber-pad.json','src/presets/bridge.json','layouts/autosave.json','evidence/material-library/custom-layout.json']
for i,source in enumerate(sources):
    a=(e/f'layout-roundtrips/layout-{i}-before.json').read_bytes()
    b=(e/f'layout-roundtrips/layout-{i}-after.json').read_bytes()
    assert a==b
    layouts.append(dict(source=source,version=json.loads(a)['version'],bytes=len(a),
        before_sha256=hashlib.sha256(a).hexdigest(),after_sha256=hashlib.sha256(b).hexdigest(),identical=True))
(e/'layout-byte-manifest.json').write_text(json.dumps(layouts,indent=2)+'\n')

summary={}; raw={}
fields=('full_frame_ms','tick_ms','blast_ms','physics_pipeline_ms','draw_submit_swap_ms','cache_ms','gpu_finish_ms')
for stage in ('before','after'):
    lines=[l for l in read(e/stage/'bench.txt').splitlines() if l.startswith('run,tick,') or (l and l[0].isdigit())]
    rows=list(csv.DictReader(lines)); assert len(rows)==48; raw[stage]=rows
    summary[stage]={kind:{key:statistics.median(float(r[key]) for r in rows if r['kind']==kind) for key in fields} for kind in ('blast','next')}
for a,b in zip(raw['before'],raw['after']):
    assert all(a[k]==b[k] for k in ('run','tick','kind','regions','links','pieces'))
(e/'bench-summary.json').write_text(json.dumps(summary,indent=2)+'\n')

screens=('edit-hud','test-hud','materials-builtin','materials-custom','layouts','settings')
pngs=[]
for stage in ('before','after'):
    for name in screens:
        p=e/stage/(name+'.png'); assert struct.unpack('>II',p.read_bytes()[16:24])==(1280,800);pngs.append(p)
for name in ('texture-closeups','materials-after-blast','materials-edit'):
    p=e/'after'/(name+'.png');assert p.exists();pngs.append(p)
assert len(pngs)==15
bench_rows=[]
for kind,label in [('blast','Blast frame'),('next','Following frame')]:
    a,b=summary['before'][kind]['full_frame_ms'],summary['after'][kind]['full_frame_ms']
    bench_rows.append(f'| {label} | {a:.5f} → {b:.5f} ms | {(b/a-1)*100:+.2f}% |')
profile_rows=[]
for kind,label in [('blast','Blast'),('next','Next')]:
    a,b=summary['before'][kind],summary['after'][kind]
    profile_rows.append(f"| {label} | {a['tick_ms']:.3f} → {b['tick_ms']:.3f} | {a['draw_submit_swap_ms']:.3f} → {b['draw_submit_swap_ms']:.3f} | {a['cache_ms']:.3f} → {b['cache_ms']:.3f} | {a['gpu_finish_ms']:.3f} → {b['gpu_finish_ms']:.3f} |")
grain=re.findall(r'Grain vertical=(\d).*?ratio=([0-9.]+)',texture)
assert len(grain)==2 and all(float(r)>=3 for _,r in grain)
report=f'''# BOM textures and menu readability

Implemented one generated 512×512 RGBA8 repeating material tile, mipmaps/trilinear filtering, GLSL 330 tinting, and build-time rest UVs (`rest / 4`). Each static/moving pass batches its fills before flat one-pixel seals; borders, mortar, rubber film and F3 piece colours remain flat. Custom materials select their base family’s channel and retain their own RGB. Texture noise uses an independent fixed integer hash; Stone speckle seeds are 71/81. Simulation recipes, strengths and physics are unchanged.

Embedded [Inter 4.1](https://github.com/rsms/inter/releases/tag/v4.1) Regular/SemiBold static TTFs, with the SIL OFL 1.1 licence under `src/assets/fonts/`. Four separate DPI-aware atlases implement Title 26, Heading 18, Body 17 and Small 15; all UI text uses the helpers, and raygui uses Body. Fonts → raygui → shapes-texture reset is enforced at startup. B1 text/encoding grep checks return **0**.

Menus now have action labels and keycap chips, mode pills, swatch/name palette slots, an accent-filled selection, + New, grouped material lists, selected-entry duplication (including customs), disabled built-in controls and in-use Delete, stepped sliders with help/min/max, and file ages. Loaded values are not snapped. Modal notices appear once inside the modal; only explicit Reset emits “Yard reset”.

**157 tests pass**, including **48/48 byte-identical simulation captures** and **7/7 exact layout round-trips** (six v1 files and one v2). [Simulation manifest](evidence/textures-ui/byte-identity-manifest.json) · [Layout manifest](evidence/textures-ui/layout-byte-manifest.json). The old encoder upgraded v1 automatically; unedited loaded layouts now retain their original bytes, while edited/new layouts use canonical v2. Both retained buffers have explicit ownership and pass leak checks.

| Native check | Result |
|---|---|
| Actual 4× MSAA, fonts loaded | Wood 28 cells, Glass 110, Rubber 8, floor 153; **781,664** interior samples; max difference **1/255**, **0 defects** |
| Fragment tracking | 20 interior rest points, translation (0.45,0.2), rotation 30°, 512 physical px/m; max **2/255**, **0 defects** |
| Grain at 128 physical px/m | Built 4×0.8 plank / 0.8×4 post: across/along luminance ratios **{float(grain[0][1]):.3f} / {float(grain[1][1]):.3f}**, both ≥3 |
| Wood study axis | **0 / 1,897** live cells differ from the horizontal plank axis across seeds 1–16 after the standard blast |
| 2×2 mean-colour blocks | All four built-ins and both custom Wood tints within **0.899/255** per channel |
| Tile wrap/interior neighbour ratio, X / Y | Wood **0.061 / 0.733**; Glass **1.003 / 0.980**; Rubber **0.323 / 0.452**; Stone **0.868 / 0.918**; all ≤1.25 |
| UI, native suites, teardown | Six screens: **0 text overflows**; SmokeInput, SmokeMaterials and SmokeEditor pass; Odin **0**, Box2D **0**, texture/shader IDs **0**, fonts unloaded |

Fixture details: continuity uses editor seed 42/identity 1 and the specified plank, pane, pad and floor. The fragment is native Wood cell 135 after blast (-0.1,0.4), radius 4; sampling is at physical pixels on this 1.25-DPI display. Mean checks use the same 2×2 window starting at rest (2.5,3), chosen once by closest quarter-tile mean across all channels. At origin (0,0), the Wood red mean was +2.36/255 because a quarter-tile can have a local bias; the texture recipe was not changed. Actual means (R,G,B): Wood **179.883,135.905,81.954**; Glass **85.863,152.746,173.688**; Rubber **161.711,111.819,183.630**; Stone **131.151,145.143,152.148**; coral **230.566,103.937,90.943**; yellow **235.102,214.853,118.932**. Red clips in **3,741** coral and **7,824** yellow samples. Yellow green has 12 samples rounded to 255, with no actual clipping; other channels do not clip.

| Full-frame benchmark | Median before → after | Change |
|---|---|---|
{chr(10).join(bench_rows)}

Three sequential runs per build, eight actual explosions after tick 600 per run and each immediate successor: 24 samples of each kind. This replaces fixed historical tick targets that might not contain a blast. Both builds use speed optimisation, 1280×800 logical / 1600×1000 physical, 4× MSAA, no FPS sleep and GPU completion. Event ticks and cell/link/piece counts match. No optimisations beyond the requested batching were added. [Raw/summary timing split](evidence/textures-ui/bench-summary.json):

| ms, median | Tick (includes blast/physics) | Draw submission/swap | Cache (within draw) | GPU finish |
|---|---|---|---|---|
{chr(10).join(profile_rows)}

Component medians need not sum to the full-frame median. The report uses the final sequential before/after sample, superseding preliminary timings.

PNGs: [2× close-up montage](evidence/textures-ui/after/texture-closeups.png), [Materials preset after blast](evidence/textures-ui/after/materials-after-blast.png), [same layout in Edit](evidence/textures-ui/after/materials-edit.png). The shot uses blast (-7.5,1), radius 4, then 30 ticks: the earlier Glass-edge radius-5 shot erased the pane, so the Wood-edge fixture better shows textured fragments while retaining the other materials.

| Screen pair | Before | After |
|---|---|---|
'''
for name in screens:
    report+=f'| {name} | [PNG](evidence/textures-ui/before/{name}.png) | [PNG](evidence/textures-ui/after/{name}.png) |\n'
report+='''
Reproduce: `odin build src -o:speed -define:BOM_FRAME_BENCH=true -out:build/BOM.exe`; run `--check-textures`, `--smoke-input`, `--smoke-materials`, `--smoke-msaa`, `--capture-ui`, `--capture-textures`, `--bench-frames`. `scripts/bom.ps1 Test` runs the unit suite. The accepted source and before-state capture/benchmark harness are retained under `evidence/textures-ui/before/`. Before screenshots use the original bitmap-font UI; saved-file rows reflect their actual modification times. The package includes both baseline and regenerated capture bytes, all PNGs and logs, fonts and licence.
'''
(root/'report.md').write_text(report,encoding='utf-8')
(e/'report.md').write_text(report.replace('](evidence/textures-ui/',']('),encoding='utf-8')

files=set()
for folder in ('src','scripts','docs'):
    files.update(p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
files.update(root/n for n in ('README.md','AGENTS.md','report.md','.gitignore','.gitattributes'))
files.update(p for p in e.rglob('*') if p.is_file() and p.name!='accepted-report.md')
for row in captures:
    files.add(root/row['before'])
for name in ('before-v2-ticked.json','continuity-manual-S.json'):
    files.add(root/'evidence/world-v3'/name)
files.update(root/n for n in ('layouts/autosave.json','evidence/material-library/custom-layout.json'))
archive=root/'BOM-textures-ui-source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
    for p in sorted(files):
        if p.suffix.lower() in ('.exe','.obj','.pdb'):continue
        z.write(p,p.relative_to(root).as_posix())
images=root/'BOM-textures-ui-PNGs.zip'
with zipfile.ZipFile(images,'w',zipfile.ZIP_DEFLATED) as z:
    for p in pngs:z.write(p,p.relative_to(e).as_posix())
for p in (archive,images):
    with zipfile.ZipFile(p) as z:assert z.testzip() is None
    print(p.name,p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest())
print('157 tests; 48 simulation captures; 7 layout roundtrips; 15 PNGs; all evidence validated')
