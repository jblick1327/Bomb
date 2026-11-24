"""Validate glue follow-up evidence and package the reviewed source and PNGs."""
from pathlib import Path
import hashlib,json,zipfile,struct
root=Path(__file__).resolve().parent.parent;e=root/'evidence/glue-followup'
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig')
tests=read(e/'tests.txt');native=read(e/'native.txt')
assert 'Finished 169 tests' in tests and 'All tests were successful.' in tests and '[ERROR]' not in tests
assert native.count('defects=0')==2 and native.count('render_world_identical=true')==3
assert 'Ridge PNG interior rows=440 gaps=0' in native and 'Ridge actual4x interior rows=550 gaps=0' in native
assert 'Follow-up teardown Odin=0 Box2D=0 texture=0 shader=0 fonts=false' in native
assert native.count('right_floor=76 right_brace=135 ridge=180')==2
rows=[]
for area in ['golden','standard']:
 base=root/'evidence/rotation-glue'/area
 for before in sorted(base.rglob('*.json')):
  after=e/area/before.relative_to(base);a,b=before.read_bytes(),after.read_bytes();assert a==b,after
  rows.append(dict(fixture=area+'/'+before.relative_to(base).as_posix(),before=before.relative_to(root).as_posix(),after=after.relative_to(root).as_posix(),bytes=len(a),before_sha256=hashlib.sha256(a).hexdigest(),after_sha256=hashlib.sha256(b).hexdigest(),identical=True))
assert len(rows)==48
for before in sorted((e/'before').glob('*.json')):
 after=e/'after'/before.name;a,b=before.read_bytes(),after.read_bytes();assert a==b,after
 rows.append(dict(fixture='legacy-seam/'+before.name,before=before.relative_to(root).as_posix(),after=after.relative_to(root).as_posix(),bytes=len(a),before_sha256=hashlib.sha256(a).hexdigest(),after_sha256=hashlib.sha256(b).hexdigest(),identical=True))
assert len(rows)==58
(e/'byte-identity-manifest.json').write_text(json.dumps(rows,indent=2)+'\n')
assert (e/'before-calibrate.txt').read_bytes()==(e/'after-calibrate.txt').read_bytes()
original=read(e/'original-ticks.txt');fixture=read(e/'fixture-ticks.txt')
for text in [original,fixture]:
 for run in ['quiet','blast']:
  for tick in range(31):assert f'BRACE run={run} tick={tick} ' in text
assert 'posed_max=0.000147464' in original
images=[e/name for name in ['demo-test-600.png','demo-test-blast-20.png','ridge-closeup.png']]
for p in images:assert struct.unpack('>II',p.read_bytes()[16:24])==(1280,800)
for p in list((root/'src').glob('*.odin'))+[root/'README.md']:
 text=p.read_text(encoding='utf8');assert '\u00c3' not in text and '\u00e2\u20ac' not in text,p
provenance=dict(accepted_source_archive='BOM-rotation-glue-source.zip',accepted_source_sha256='c6f000d8e9d6245a38d97a9683f02c58ec9568c6124a2902cf07f028221eb723',observer='src/seam_compat_test.odin',observer_sha256=hashlib.sha256((root/'src/seam_compat_test.odin').read_bytes()).hexdigest(),baseline_command='odin test src -define:ODIN_TEST_NAMES=seam_followup_legacy_world_bytes -define:SEAM_BASELINE_WRITE=true -define:SEAM_CAPTURE_DIRECTORY=<baseline directory>',fixtures=['glued Stone cantilever: 0/600 ticks','unglued Stone cantilever: 0/600 ticks','short mortar cantilever: 0/600 ticks','long mortar cantilever: 0/240 ticks','Bridge preset: 0/600 ticks'])
(e/'baseline-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
report="""# Rotation/glue follow-up

Fixed flush glue rendering. **Simulation, joint collision settings, strengths and thresholds are unchanged.** The original radius-4 blast still produces force failures under the accepted rules. The support-preserving after-blast PNG uses the fixture adjustment described below; this is not a claim of a physics fix for the original blast.

Diagnosis: [original tick log](evidence/glue-followup/original-ticks.txt) records ticks 0-30 with body pairs, live mortar/glue counts, force ratio r, overload counters, brace displacement and death paths. The no-blast demo already passes on the accepted build: all **23 connections / 7 seams** survive 600 ticks; maximum centre movement is **0.000770723 m**, and maximum vertex movement **0.000939717 m**. Thus the requested expectation that this check fail before changes was not reproduced.

With the original blast (-3.8,0.5), radius 4:

| Seam | Failure tick | Path and r |
|---|---:|---|
| Left post / floor | 1 | Force, 7.057192326 |
| Right post / floor | 1 | Force, 3.699259281 |
| Left brace / post | 1 partial, 8 remaining | Force, 2.168455601 then 8.665056229 |
| Left roof / post | 8 | Force, 3.008141041 |
| Right roof / post | 8 | Force, 3.048999786 |
| Right brace / post | 8 | Force, 10.606233597 |
| Ridge | Survives | All 12 members live at tick 20; r=0.061381884, counter 0 |

These are force failures, not direct blast/deletion failures. Every weld already has **collideConnected=false**. The blast gives the left post velocity (0.94679475,0.060626559) m/s and angular velocity 0.9695723 rad/s, loading the connected structure. In the diagnostic control with **all contacts disabled**, the right floor still immediately fails at r=**2.718913794**. Erasing blast velocities only in a separate diagnostic control reduces its first-tick r to **0.704409003**. [No-contact log](evidence/glue-followup/no-contacts-ticks.txt), [velocity control](evidence/glue-followup/no-blast-velocity-ticks.txt). Neither control affects normal simulation.

The live ridge was also visually lost: its rest endpoint gap is **0.000000119 m**, but solver drift makes its posed gap **0.000147464 m**, exceeding the old 1e-5 flush test. The renderer then stopped drawing circles and emitted subpixel quads. Flush classification now uses rest geometry. Consecutive flush samples draw continuous mortar-width lines, with weighted half-step end extensions so runs meet across cell-pair boundaries. Fillet winding is evaluated once per quad and each of its two triangles is emitted once.

Fixture choice under the standing policy: keep the demo layout and seed 42; move the capture blast to **(-4.4,1.5), radius 3**. The original blast overdrives the supports rather than isolating remote seam preservation. The selected blast releases the nearby brace by force while retaining **17/17** connections whose geometry is more than 1 m beyond its radius at **20 ticks**. [Adjusted tick log](evidence/glue-followup/fixture-ticks.txt). Later force failures remain possible under the unchanged rules; this protection check is for the specified 20 ticks.

Checks: **169 tests pass** with memory tracking. All **48 accepted captures** and **10 additional cantilever/mortar/Bridge captures** are byte-identical; [manifest](evidence/glue-followup/byte-identity-manifest.json), [baseline provenance](evidence/glue-followup/baseline-provenance.json). The ten extra baseline captures were generated from the accepted source archive with the same observation-only test harness. `--calibrate-mortar` logs match byte-for-byte: N1 **160.772048950**, N2 **487.811828613**, ratio **3.034183025**, geometric mean **280.047332764**; the accepted N2 > 2*N1 condition holds.

At both 600-tick quiet and 20-tick adjusted-blast captures, cream pixels in the fixed ROIs are: right floor **76**, right brace **135**, ridge **180**. The ridge close-up has **0 gaps / 440 interior rows**; actual **4x MSAA** has **0 gaps / 550 rows**. Rotated plank/wedge texture continuity retains **0 defects / 90,014 interior pixels**, max difference **1/255**. Three captures have zero text overflows and leave World bytes unchanged. Teardown: **Odin 0, Box2D 0**, texture/shader IDs 0, fonts unloaded.

PNGs: [Test, no blast, 600 ticks](evidence/glue-followup/demo-test-600.png), [Test, adjusted blast, 20 ticks](evidence/glue-followup/demo-test-blast-20.png), [ridge close-up](evidence/glue-followup/ridge-closeup.png). Reproduce with `scripts/bom.ps1 Test`, optimized build, `--diagnose-demo`, `--calibrate-mortar`, and `--check-glue-followup`; SEAM_DIAG_FIXTURE=true selects the adjusted diagnostic fixture. `python scripts/package-glue-followup.py` validates the frozen evidence and builds both bundles.
"""
(root/'report.md').write_text(report,encoding='utf8',newline='\n');(e/'report.md').write_text(report.replace('](evidence/glue-followup/',']('),encoding='utf8',newline='\n')
files=set()
for folder in ['src','docs','scripts','evidence/glue-followup']:
 files.update(p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.name!='before-ticks.txt')
files.update(root/name for name in ['README.md','AGENTS.md','report.md','.gitignore','.gitattributes','layouts/autosave.json','evidence/material-library/custom-layout.json','evidence/world-v3/before-v2-ticked.json','evidence/world-v3/continuity-manual-S.json'])
files.update(root/row['before'] for row in rows)
files.update((root/'evidence/material-library/rebaseline').glob('*.json'))
files.update((root/'evidence/textures-ui-followup/decode-before').glob('*.json'))
source=root/'BOM-glue-followup-source.zip'
with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in sorted(files):
  if p.suffix.lower() not in ['.exe','.obj','.pdb']:z.write(p,p.relative_to(root).as_posix())
pngzip=root/'BOM-glue-followup-PNGs.zip'
with zipfile.ZipFile(pngzip,'w',zipfile.ZIP_DEFLATED) as z:
 for p in images:z.write(p,p.name)
for p in [source,pngzip]:
 with zipfile.ZipFile(p) as z:assert z.testzip() is None
 print(p.name,p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest())
