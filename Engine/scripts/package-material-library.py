"""Validate recorded material evidence, write the short report, and package source."""
from pathlib import Path
import hashlib
import json
import re
import statistics
import zipfile

root = Path(__file__).resolve().parent.parent
e = root / 'evidence/material-library'

def read(path):
    data = path.read_bytes()
    return data.decode('utf-16' if data.startswith(b'\xff\xfe') else 'utf-8-sig')

assert 'Finished 152 tests' in read(e/'final-tests.txt')
assert 'All tests were successful.' in read(e/'final-tests.txt')
assert '[ERROR]' not in read(e/'final-tests.txt')
assert 'Materials native teardown: Odin=0 Box2D delta=0' in read(e/'final-native.txt')
assert 'MSAA total interior defects: 0' in read(e/'final-msaa.txt')
assert 'Finished 150 tests' in read(e/'phase1-tests.txt')
assert 'All tests were successful.' in read(e/'phase1-tests.txt')
assert 'Materials native teardown: Odin=0 Box2D delta=0' in read(e/'phase1-native.txt')
assert 'MSAA total interior defects: 0' in read(e/'phase1-msaa.txt')
assert 'COVER_SHORTCUTS' not in (root/'src/cover.odin').read_text()

def counts(data):
    s = data.get('scene', data)
    return [len(s[k]) for k in ('subdivisions', 'connections', 'pieces')]

comparison = []
for p in sorted((e/'before/standard').rglob('*.json')):
    rel = p.relative_to(e/'before/standard')
    same = p.read_bytes() == (e/'phase1/standard'/rel).read_bytes()
    assert same, rel
    after = e/'after/standard'/rel
    comparison.append(dict(fixture=rel.as_posix(), phase1_byte_identical=same,
        before_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
        final_sha256=hashlib.sha256(after.read_bytes()).hexdigest(),
        before_counts=counts(json.loads(read(p))), final_counts=counts(json.loads(read(after)))))
assert len(comparison) == 23
for p in sorted((e/'legacy').glob('*.json')):
    after = e/'rebaseline'/p.name
    comparison.append(dict(fixture='golden/'+p.name,
        before_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
        final_sha256=hashlib.sha256(after.read_bytes()).hexdigest(),
        before_counts=counts(json.loads(read(p))), final_counts=counts(json.loads(read(after)))))
assert len(comparison) == 48
(e/'fixture-comparison.json').write_text(json.dumps(comparison, indent=2)+'\n')

timings = {}
for stage in ('before', 'after'):
    values = []
    for i in range(1, 4):
        text = read(e/f'{stage}/soak-{i}.txt')
        rows = [line.split(',') for line in text.splitlines() if line and line[0].isdigit()]
        assert len(rows) == 20 and 'after_destroy_odin_bytes=0,after_destroy_box2d_bytes=0' in text
        values.append(max(float(row[5]) for row in rows))
    timings[stage] = dict(worst_blast_pass_ms=values, median_ms=statistics.median(values))
(e/'soak-summary.json').write_text(json.dumps(timings, indent=2)+'\n')

def study(stage):
    text = read(e/f'{stage}/standard/wood.txt')
    fields = dict(re.findall(r'(\w+)=([\d.]+)', text.split('Grain pooled:')[1]))
    fields['plank_cells'] = re.search(r'Plank: cells=(\d+)', text)[1]
    return fields

b, a = study('before'), study('after')
bm, am = timings['before']['median_ms'], timings['after']['median_ms']
def fmt_values(stage):
    return ', '.join(f'{x:.4f}' for x in timings[stage]['worst_blast_pass_ms'])

report = f'''# BOM material library

Implemented layout-owned custom materials, the Materials modal, eight palette buttons/shortcuts, twelve colour swatches, atomic validation, autosave, version-1 loading and version-2 layout files. Custom recipes inherit their base family; toughness scales both strengths. Used customs append in palette order after the unchanged ground Stone and four built-in records, as approved. Custom names are independently owned by the layout and World. Mortar rules and strengths are unchanged.

Checks 1–5 passed **before** the final Wood change: all **23 existing standard fixtures** and **25 additional fixture/preset captures**, including all five presets, were byte-identical; the 150-test suite passed with leak failures enabled. Four customs round-trip to identical layout and World bytes. Duplicate names, invalid ranges/RGB/base/references and a fifth custom are rejected atomically. Native automation exercised the actual name textbox, sliders, swatches, placement, Test/blast/Edit, blocked and allowed deletion, save/load, autosave and modal blocking/Tab/Escape. Native teardown: Odin **0**, Box2D **0**. Actual 4× MSAA: **0 seam defects**.

The final build passes **152 tests** with leak failures enabled; the strengthened knob check also confirms the Rubber fixture has no breaks and zero final cell speed. Final native smoke and MSAA checks pass again. Evidence includes raw logs, exact fixture bytes, a comparison manifest and an example [version-2 layout](evidence/material-library/custom-layout.json).

| Knob comparison | Measured result |
|---|---|
| Wood toughness 1 → 2 | Lost area **0.960075 → ~0** (pre-final default: 0.917228 → 0) |
| Wood thickness 0.3 → 0.15 | Maximum built width **0.200000 → 0.117176**; blasted-cell median width **0.200000 → 0.107846** |
| Glass shock loss 4 → 2 | Largest-piece fraction **0.727691 → 0.020877** |
| Stone resistance 3 → 6 | Wood lost area **0.121396 → ~0** (pre-final: 0.119495 → ~0) |
| Rubber flexibility 0.5 → 0.25 | Rest sag **0.252513 → 0.068255** |

Fixture choices: seed 42 throughout, immediate blasts. Toughness: Wood (0,0)–(6,0.8), blast (-0.1,0.4), radius 4. Thickness: (0,0)–(6,0.2), same blast; the shorter height exercises 0.15 within the existing 0.1 minimum-width rule (the 0.8-high version retains an unsplittable 0.196 cell). Glass: (0,0)–(5,2.5), blast (-0.6,1.25), radius 3. Cover: Stone (2,0)–(2.2,2.4), Wood (2.2,0)–(3.2,1.6), blast (1,1), radius 4.8; thinner wall and adjacent Wood avoid both variants being fully protected. Rubber: (0,1)–(1.6,1.4), two Stone supports (0,0)–(0.4,1) and (1.2,0)–(1.6,1), all mortar-enabled, 600 ticks. An unsupported long span fell to the floor, so the supported short span measures sag at rest. Near-zero areas are f32 rounding.

After those checks, built-in Wood changed from **0.3 to 0.2**. Missing snapshot thickness still means **0.3**; the new 0.2 value is explicit. Snapshots omit legacy-default thickness/colour. The `COVER_SHORTCUTS` compile switch is deleted, retaining its former default path. All 48 captures were re-baselined; [counts and hashes](evidence/material-library/fixture-comparison.json) record the changes. The cleanup fixture changed from 0.3×0.3 to 0.2×0.2 to retain its one-cell purpose. The long-cell assertion uses seed 47 (29 cells), because seed 42 now has one 0.9429-long cell; no generation or failure rule was changed.

| Wood study, before → after | Result |
|---|---|
| Built 6×0.8 plank, seed 42 / identity 1 | **{b['plank_cells']} → {a['plank_cells']} cells** |
| 16 seeds, pooled ≥3:1 share | **{float(b['elongated_pct']):.0f}% → {float(a['elongated_pct']):.0f}%** |
| Median width / length | **{b['median_width']} / {b['median_length']} → {a['median_width']} / {a['median_length']}** |
| Mean crater area | **{b['mean_crater']} → {a['mean_crater']}** |
| Median worst blast_pass, 3 runs | **{bm:.4f} → {am:.4f} ms** ({(am/bm-1)*100:+.1f}%) |

The Wood study retains seeds 1–16, a 6×4 piece and blast (-0.1,2), radius 5. Each timing run simulates 20 minutes at 60 Hz, four 1.6×2 materials, seed 42, falling bombs, radius 5 and two-minute refills. Three original runs then three final runs ran sequentially without competing builds/tests. Worst passes: before **{fmt_values('before')} ms**; after **{fmt_values('after')} ms**. All six teardown checks report zero Odin/Box2D bytes. Earlier concurrent timings were replaced.

PNGs: [Materials / custom Wood](evidence/material-library/materials-panel.png), [all eight entries at 900 px](evidence/material-library/edit-eight-materials.png), [custom colours after a blast](evidence/material-library/test-custom-blast.png).

Reproduce: `scripts/bom.ps1 Test`, `scripts/bom.ps1 SmokeMaterials`, optimized `odin build src -o:speed`, then `--wood-study`, `--glass-study`, `--soak-fixture`, `--smoke-msaa` and three `--soak 20` runs. Original and pre-default-change source archives are retained under `evidence/material-library/`.
'''
(root/'report.md').write_text(report, encoding='utf-8')

files = set()
for name in ('src','scripts','docs'):
    files.update(p for p in (root/name).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
files.update(root/n for n in ('README.md','AGENTS.md','report.md','.gitattributes','.gitignore'))
files.add(root/'evidence/world-v3/before-v2-ticked.json')
files.update(p for p in e.rglob('*') if p.is_file())
archive = root/'BOM-material-library-source.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted(files):
        z.write(p, p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
print(archive.name, archive.stat().st_size, 'bytes', hashlib.sha256(archive.read_bytes()).hexdigest())
print('Soak median worst blast_pass:', bm, '->', am, 'ms')
