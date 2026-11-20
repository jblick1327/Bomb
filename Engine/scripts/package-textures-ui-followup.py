"""Validate follow-up evidence and package source plus six after captures."""
from pathlib import Path
import json, zipfile, hashlib
root=Path(__file__).resolve().parent.parent
e=root/'evidence/textures-ui-followup'
tests=(e/'tests.txt').read_text(encoding='utf-8-sig')
assert 'Finished 158 tests' in tests and 'All tests were successful.' in tests and '[ERROR]' not in tests
assert (e/'ui.txt').read_text().count('overflow=0')==6
assert 'Materials native teardown: Odin=0 Box2D delta=0' in (e/'smoke.txt').read_text()
manifest=json.loads((e/'byte-identity-manifest.json').read_text());assert len(manifest)==48 and all(x['identical'] for x in manifest)
layouts=[]
for i in range(7):
 a=(e/f'layouts/layout-{i}-before.json').read_bytes(); b=(e/f'layouts/layout-{i}-after.json').read_bytes()
 assert json.loads(b)['version']==2
 if i<6:
  assert json.loads(a)['version']==1
  assert b==(e/f'decode-before/{i}.json').read_bytes()
 else: assert a==b
 layouts.append(dict(index=i,input_version=json.loads(a)['version'],output_version=2,decoded_state_unchanged=True,byte_identical=a==b,output_sha256=hashlib.sha256(b).hexdigest()))
(e/'layout-manifest.json').write_text(json.dumps(layouts,indent=2)+'\n')
assert not any('source_bytes' in p.read_text(encoding='utf8') or 'source_canonical' in p.read_text(encoding='utf8') for p in (root/'src').glob('*.odin'))
checks=json.loads((e/'slider-check.json').read_text());assert not checks[0]['passes'] and checks[1]['passes']
report="""# Textures/UI follow-up

Removed the retained layout byte buffers and encoder comparison. Layout owns only authored state; every save produces canonical v2. Six v1 inputs (five presets and the real autosave) match their pre-change decoded objects, identities, next_identity and seed, then save as v2. The custom v2 file round-trips byte-identically. The reference files were captured from the accepted decoder before this change; the regression compares the complete canonical authored state against them.

Raygui disabled borders/base/text now use the requested theme colours. Material slider fills use the accent when enabled and 45% accent over the disabled track when disabled. Materials, Layouts and Settings have Title headings in title case with a separate muted Small Paused label. Mode pills measure their text and add 12 px padding on each side.

158 tests pass with memory tracking; native Materials smoke passes with Odin 0 and Box2D delta 0. All six UI captures have zero text overflows. All 48 freshly generated simulation captures match accepted bytes: see [byte-identity manifest](evidence/textures-ui-followup/byte-identity-manifest.json). Layout results are in the [layout manifest](evidence/textures-ui-followup/layout-manifest.json).

Fixture: reused the accepted 1280x800 UI capture sequence, Wood selected in both material captures. Slider rectangles are x=436..1115, y=247..260, 345..358 and 443..456; the comparison includes every disabled track, border and fill pixel. Enabled fill is sampled inside the toughness bar away from its border. Rec.709 luminance in 0..255 units: before disabled maximum 232.362 vs enabled fill 99.285 (fails); after 109.449 vs 194.661 (passes). The dimmed fill RGB is (65,122,116). No simulation fixture adjustment was needed.

Six after PNGs are under evidence/textures-ui-followup/after/: materials-builtin, materials-custom, layouts, settings, edit-hud, test-hud. The PNG bundle contains these six files.

Reproduce: odin test src; optimized build then --wood-study, --glass-study and --soak-fixture for the standard captures. Use MATERIAL_CAPTURE_DIRECTORY for the other 25 fixture captures, UI_LAYOUT_CAPTURE_DIRECTORY for the layout outputs, --capture-ui for screenshots, and --smoke-materials for native control and teardown checks. Run scripts from the project root. Historical evidence and reports describe their original runs.
"""
(root/'report.md').write_text(report,encoding='utf8',newline='\n');(e/'report.md').write_text(report,encoding='utf8',newline='\n')
# Preserve the accepted source package file set, replacing source/docs with current files.
with zipfile.ZipFile(root/'BOM-textures-ui-source.zip') as old:
 names=set(old.namelist())
names.update(p.relative_to(root).as_posix() for p in e.rglob('*') if p.is_file())
names.update(p.relative_to(root).as_posix() for p in (root/'src').rglob('*') if p.is_file())
names.add('scripts/package-textures-ui-followup.py')
with zipfile.ZipFile(root/'BOM-textures-ui-followup-source.zip','w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for name in sorted(names):
  p=root/name
  if p.is_file():z.write(p,name)
with zipfile.ZipFile(root/'BOM-textures-ui-followup-PNGs.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted((e/'after').glob('*.png')): z.write(p,p.name)
for name in ['BOM-textures-ui-followup-source.zip','BOM-textures-ui-followup-PNGs.zip']:
 with zipfile.ZipFile(root/name) as z:assert z.testzip() is None
 print(name,(root/name).stat().st_size)
