"""Verify the follow-up evidence and package source without PNGs or binaries."""
from pathlib import Path
import hashlib
import json
import re
import zipfile

root = Path(__file__).resolve().parent.parent
e = root / 'evidence/material-followup'

def read(path):
    data = path.read_bytes()
    return data.decode('utf-16' if data.startswith(b'\xff\xfe') else 'utf-8-sig')

before_log = read(e/'before.txt')
assert 'cells=[15, 28]' in before_log and 'outlines_bit_identical=false' in before_log
assert 'cells=[13, 23]' in before_log
assert '1 test failed' in before_log
tests = read(e/'all-tests.txt')
assert 'Finished 155 tests' in tests and 'All tests were successful.' in tests
assert '[ERROR]' not in tests
assert 'maximum built=[0.19617306, 0.2836345] cells=[28, 20]' in tests
assert 'Legacy v3 continuity-manual-S.json: 266812 bytes, exact roundtrip=true' in tests
assert 'Materials native teardown: Odin=0 Box2D delta=0' in read(e/'native-materials.txt')
assert 'MSAA total interior defects: 0' in read(e/'native-msaa.txt')

sources = {p.name: p.read_text() for p in (root/'src').glob('*.odin')}
joined = '\n'.join(sources.values())
assert not re.search(r'\bRecipe\s*\(|\b(?:cast|transmute)\s*\(\s*Recipe\s*\)', joined)
assert not re.search(r'\bPalette\b|\bmaterial_strip\s*::|\beditor_color\b', joined)
assert not (root/'src/material_followup_probe_test.odin').exists()
assert all('snapshot_legacy_color' not in text for name, text in sources.items() if name != 'state.odin')
assert '@(private="file")\nsnapshot_legacy_color' in sources['state.odin']
assert 'color: [3]u8,' in sources['model.odin']
assert 'STRIP_MIN :: 2*WOOD_MINIMUM_WIDTH' in sources['wood_generation.odin']

# The generation implementation must be the accepted implementation, with only
# explicit target access/signature and the minimum-width constants introduced.
generation_hash_file = e/'accepted-generation.sha256'
accepted_archive = root/'BOM-material-library-source.zip'
if accepted_archive.exists():
    with zipfile.ZipFile(accepted_archive) as z:
        old_generation = z.read('src/wood_generation.odin').decode().replace('\r\n', '\n')
    accepted_generation_hash = hashlib.sha256(old_generation.encode()).hexdigest()
    if generation_hash_file.exists():
        assert generation_hash_file.read_text().strip() == accepted_generation_hash
    else:
        generation_hash_file.write_text(accepted_generation_hash+'\n')
else:
    accepted_generation_hash = generation_hash_file.read_text().strip()
normalized = sources['wood_generation.odin'].replace(
    'WOOD_MINIMUM_WIDTH :: f32(0.1)\nSTRIP_MIN :: 2*WOOD_MINIMUM_WIDTH\n\n', '')
normalized = normalized.replace('strip: f32)', 'strip: f32 = 0.3)')
normalized = normalized.replace('recipe.strip_thickness', 'material_strip(recipe)')
assert hashlib.sha256(normalized.encode()).hexdigest() == accepted_generation_hash, 'Generation algorithm changed'

rows = []
baselines = [('standard', root/'evidence/material-library/after/standard'),
             ('golden', root/'evidence/material-library/rebaseline')]
for area, baseline in baselines:
    for original in sorted(baseline.rglob('*.json')):
        rel = original.relative_to(baseline)
        after = e/'after'/area/rel
        a, b = original.read_bytes(), after.read_bytes()
        rows.append(dict(fixture=f'{area}/{rel.as_posix()}',
            before=original.relative_to(root).as_posix(), after=after.relative_to(root).as_posix(),
            before_bytes=len(a), after_bytes=len(b),
            before_sha256=hashlib.sha256(a).hexdigest(), after_sha256=hashlib.sha256(b).hexdigest(),
            byte_identical=a == b))
assert len(rows) == 48 and all(x['byte_identical'] for x in rows)
legacy = root/'evidence/world-v3/continuity-manual-S.json'
manifest = dict(captures=48, byte_identical=48, fixtures=rows,
    legacy_v3=dict(file=legacy.relative_to(root).as_posix(), bytes=legacy.stat().st_size,
        sha256=hashlib.sha256(legacy.read_bytes()).hexdigest(), exact_roundtrip=True))
(e/'byte-identity-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')

report = '''# BOM material library follow-up

Implemented the requested range and representation fixes. `STRIP_MIN = 2 * WOOD_MINIMUM_WIDTH = 0.2` is shared by validation, the slider and its error text. Layout decoding rejects 0.15 atomically, without clamping; the new regression failed on the accepted build and passes now. Generation arithmetic and partition rules are unchanged.

`Recipe` contains only Wood/Glass/Rubber/Stone. Authored references and palette controls use `Slot`, a distinct integer. Reverse lookup visits valid Recipe members; there are no integer-to-Recipe casts. Built-in colours are explicit in PALETTE_MATERIALS. Material RGB is a plain array, rendering uses that value, and strip targets are explicit (Wood 0.2, custom Wood's value, non-grained materials 0). The private name-colour lookup and missing grained-strip default 0.3 exist only in snapshot encoding/decoding. Non-grained snapshot materials reject a present strip field. Encoding keeps the accepted omission rules.

Before-change check a was measured in native Odin and is retained only as a report/log, not a test. **The outlines were not identical**, contrary to the expected result:

| Pre-change 6×0.8 plank | Strip 0.12 | Strip 0.2 |
|---|---:|---:|
| Layout seed 42, object identity 1: cells | 15 | 28 |
| Maximum built width | 0.19617306 | 0.19617306 |
| Direct piece seed 42: cells | 13 | 23 |
| Maximum built width | 0.21775562 | 0.21775562 |

Both seed conventions were checked to remove ambiguity. Width is the shorter axis-aligned bounding extent, as in the existing Wood study. The native generator can block an impossible thickness cut before trying a length cut; equal maximum widths do not establish identical outlines. No generation rule was changed to obtain the expected result.

Replacement check c uses the normal editor build: layout seed 42, object identity 1, rectangle (0,0)–(6,0.8), no blast. Strip **0.2** builds **28 cells**, maximum width **0.19617306 ≤ 0.2**. Strip **0.4** builds **20 cells**, maximum width **0.28363450 > 0.2**. This replaces the old 0.2-high special-case fixture; no further geometry or seed adjustment was needed.

All **48/48 accepted captures are byte-identical**, including all five presets and the 600-tick replay. [The manifest](evidence/material-followup/byte-identity-manifest.json) lists byte counts and matching before/after SHA-256 hashes for every file; no baseline was rewritten. The pre-library v3 snapshot `evidence/world-v3/continuity-manual-S.json` decodes/re-encodes to its exact **266,812 bytes**. It replaces the suggested `before-v2-ticked.json` as the v3 fixture because that file is a v2 Scene snapshot.

**155 tests pass** with leak failures enabled. Native Materials smoke verifies both slider endpoints (0.2 and 0.6), all eight palette shortcuts, edit/test, validation, save/load and teardown: **Odin 0; Box2D delta 0**. Actual 4× MSAA still has **0 interior defects**. No new soak was needed: simulation output and all accepted fixture bytes are unchanged.

Reproduce: `scripts/bom.ps1 Test`; `scripts/bom.ps1 SmokeMaterials`; optimized build plus `--wood-study`, `--glass-study`, `--soak-fixture`, `--smoke-msaa`; then `python scripts/package-material-followup.py`. Source archive includes the before-change log, final logs, all 48 before/after capture pairs, and both required legacy snapshot fixtures. No PNGs or binaries are included.
'''
(root/'report.md').write_text(report, encoding='utf-8')
(e/'report.md').write_text(report.replace('](evidence/material-followup/byte-identity-manifest.json)', '](byte-identity-manifest.json)'), encoding='utf-8')

files = set()
for folder in ('src','scripts','docs'):
    files.update(p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
files.update(root/n for n in ('README.md','AGENTS.md','report.md','.gitattributes','.gitignore'))
files.update(root/'evidence/world-v3'/n for n in ('before-v2-ticked.json','continuity-manual-S.json'))
files.update(p for p in e.rglob('*') if p.is_file() and p.name != 'accepted-report.md')
for _, baseline in baselines:
    files.update(baseline.rglob('*.json'))
files = {p for p in files if p.suffix.lower() not in ('.png','.exe','.zip')}
archive = root/'BOM-material-followup-source.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for p in sorted(files):
        z.write(p, p.relative_to(root).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
print('48/48 byte-identical; 155 tests pass; generation rules unchanged')
print(archive.name, archive.stat().st_size, 'bytes', hashlib.sha256(archive.read_bytes()).hexdigest())
