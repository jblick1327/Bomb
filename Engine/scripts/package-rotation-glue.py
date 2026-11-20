"""Validate rotation/glue evidence and build the deliverables from the project root."""
from pathlib import Path
import hashlib,json,zipfile,struct
root=Path(__file__).resolve().parent.parent
e=root/'evidence/rotation-glue'
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig')
tests=read(e/'tests.txt');native=read(e/'native.txt')
assert 'Finished 167 tests' in tests and 'All tests were successful.' in tests and '[ERROR]' not in tests
assert 'Shape teardown Odin=0 Box2D=0 texture=0 shader=0 fonts=false' in native
assert 'glue link/unlink/floor/not-touching' in native and native.count('overflow=0')==3
assert native.count('defects=0')==2 and 'ratio=8.893585' in native
captures=[]
for area,before_root in [('golden',root/'evidence/material-library/rebaseline'),('standard',root/'evidence/material-library/after/standard')]:
 for before in sorted(before_root.rglob('*.json')):
  after=e/area/before.relative_to(before_root);a,b=before.read_bytes(),after.read_bytes();assert a==b,after
  captures.append(dict(fixture=area+'/'+before.relative_to(before_root).as_posix(),before=before.relative_to(root).as_posix(),after=after.relative_to(root).as_posix(),bytes=len(a),before_sha256=hashlib.sha256(a).hexdigest(),after_sha256=hashlib.sha256(b).hexdigest(),identical=True))
assert len(captures)==48
(e/'byte-identity-manifest.json').write_text(json.dumps(captures,indent=2)+'\n')
def decoded_json(data):
 return json.loads(data,parse_float=lambda v:struct.unpack("f",struct.pack("f",float(v)))[0])
def authored(x):
 return dict(seed=x['seed'],next_identity=x['next_identity'],materials=x.get('materials',[]),glue=x.get('glue',[]),objects=[dict(identity=o['identity'],material=o['material'],lo=o['lo'],hi=o['hi'],mortar=o.get('mortar',False),angle=o.get('angle',0),shape=o.get('shape','rect')) for o in x.get('objects',[])])
layouts=[]
for i in range(7):
 before=e/f'layouts/layout-{i}-before.json';after=e/f'layouts/layout-{i}-after.json';a,b=decoded_json(before.read_bytes()),decoded_json(after.read_bytes())
 assert a['version']==(1 if i<6 else 2) and b['version']==3 and authored(a)==authored(b)
 if i<6:
  oracle=decoded_json((root/f'evidence/textures-ui-followup/decode-before/{i}.json').read_bytes());assert authored(oracle)==authored(b)
 layouts.append(dict(index=i,input_version=a['version'],output_version=3,authored_state_equal=True,output_sha256=hashlib.sha256(after.read_bytes()).hexdigest()))
(e/'layout-manifest.json').write_text(json.dumps(layouts,indent=2)+'\n')
for p in list((root/'src').rglob('*.odin'))+list((root/'docs').rglob('*.md'))+[root/'README.md']:
 s=p.read_text(encoding='utf8');assert '\u00c3' not in s and '\u00e2\u20ac' not in s,p
 if p.suffix=='.odin':assert 'Authored_Rect' not in s and 'source_bytes' not in s and 'source_canonical' not in s,p
images=[e/(n+'.png') for n in ('demo-edit','demo-test-blast','glue-closeup')]
for p in images:assert struct.unpack('>II',p.read_bytes()[16:24])==(1280,800)
report="""# Rotation, wedges and glue

Implemented rotated rectangles and right-triangle wedges, contact snapping, sampled glue fillets, inheritance, v3 layouts, optional snapshot frame/glue fields, and frame-aligned textures. Near-contact samples project q onto the other boundary, including the approved 0.0005 m gap case. Glue uses the existing mortar strengths, weld lifecycle, blast and force failure paths. Zero-angle rectangles keep the legacy build path. Initial rotated builds refine in the object frame before transforming shared geometry once; later generations invert the actual float rotation matrix in double precision and restore parent vertices exactly.

**167 tests pass with memory tracking. All 48 accepted simulation captures are byte-identical.** [Byte manifest](evidence/rotation-glue/byte-identity-manifest.json) records before/after SHA-256 values and sizes. Six v1 inputs (five presets plus autosave) and the custom v2 input preserve their authored state, including identities, seed and next_identity; saves upgrade to v3. The six v1 results also match the accepted decoder's recorded state. Native v3 save/load is byte-exact with angles, a wedge, object glue and ground glue. [Layout manifest](evidence/rotation-glue/layout-manifest.json).

| Family | Built cells, 0 / 30 degrees | Blast cells, 0 / 30 | Lost area m2, 0 / 30 |
|---|---:|---:|---:|
| Wood | 11 / 11 | 5 / 5 | 1.815526128 / 1.815526247 |
| Glass | 26 / 26 | 21 / 21 | 0.657942176 / 0.657942176 |
| Rubber | 8 / 8 | 4 / 4 | 0.639999986 / 0.639999866 |
| Stone | 5 / 5 | 13 / 13 | 1.126118302 / 1.126118422 |

Frame fixtures are centred at (0,0), without floor or physics: 3x0.8 m except Rubber 1.6x0.8. Seed 42; Rubber keeps its recipe's disabled subdivision seed 0. All built vertex errors report 0 at nine decimal places. Blasts start at (-1.55,0), rotated correspondingly: radii 5 for Wood/Stone, 2 for Glass and 6 for Rubber. The weaker initial blast did not damage Wood/Stone/Rubber, so these radii exercise loss; all count pairs match and area differences are below 1%.

The 2x1 wedges validate and total exactly 1.000000000 m2 for each family: Wood 8 cells, Glass 11, Rubber 9, Stone 5. Rubber's minimum built width is 0.178885430 m, above 0.1. Clipped rubber slivers merge across their longest shared edge.

Glue lengths: flush stacked boxes **1.000**, rotated face-to-face boxes **1.000**, near-contact gap 0.0005 m **1.000**; the near-contact scene snapshot is byte-exact. The 60/30-degree leaning beams give **0.450 / 0.350** m. Fixtures use a wall (0,0)..(0.5,3), a 3x0.3 beam oriented 120/150 degrees, with vertex 2 translated to (0.5,2); these are geometry-only scenes without a floor. A 0.3 m gap is rejected. Snap gap 0.2 ends at distance 0 with no overlap; gap 0.4 stays unchanged (distance 0.399999976).

The 2x0.3 Stone cantilever sits at (0.5,2.1)..(2.5,2.4) beside the mortared 0.5x3 wall. The height crosses a wall-cell boundary to exercise two seam members. For this fixture, automatic wall-to-beam mortar is broken before adding glue; the wall's floor mortar remains. This isolates the glue check because the wall flag otherwise creates the same support automatically. Over 600 ticks, maximum movement is **0.000554381 m** glued versus **2.100377083 m** without glue. Blast (0.5,3.8), radius 5, breaks **2/2** members at tick 600 in one event.

Inheritance uses Stone wall (-0.5,0)..(0,3) and Wood beam (0,2)..(2,2.3), seed 42, blast (2.8,2.15), radius 4.7. It splits the glued cell while leaving the seam below its blast threshold: L **0.299999952**, deleted **0**, retained **0.299999952**, now in three members. A subsequent deliberate endpoint discard exercises sample deletion: removed **0.149999976**, retained **0.149999976**. Both conservation checks and scene validation pass.

The blasted demo World containing a rotated Wood plank, wedges and live glue round-trips exactly (**227,364 bytes**), after blast (-3.8,0.5), radius 4 and 15 ticks. Five layout rejections leave both layout and World bytes unchanged: non-touching glue, missing identity, duplicate glue, non-finite angle and overlapping wedge. Seven invalid snapshot sample/frame mutations are rejected.

Actual **4x MSAA**, with fonts loaded: 30-degree Wood plank (15 cells) **75,006** interior pixels and 30-degree Stone wedge (5 cells) **15,008** pixels, maximum difference **1/255**, **0 defects**. Grain in the 30-degree plank's frame at 128 physical px/m: along **0.273757**, across **2.434684**, ratio **8.893585** over 30,000 samples. Native smoke passes rotation, wedge, snap, rotated-overlap rejection, glue link/unlink/floor/not-touching, cancellation, deleting a glued object, save/load and Test/Edit. All three captures have zero text overflows. Teardown: **Odin 0, Box2D 0**, texture/shader IDs 0, fonts unloaded.

PNGs: [Edit demo](evidence/rotation-glue/demo-edit.png), [same layout after blast](evidence/rotation-glue/demo-test-blast.png), [leaning-beam glue close-up](evidence/rotation-glue/glue-closeup.png). The demo has two mortared Stone supports, two wedge roof halves joined at the ridge and two angled braces glued to the supports. The Test shot uses the snapshot fixture's blast, then 20 ticks to show the fragments; the layout is included as demo-layout.json.

Reproduce from the project root: `scripts/bom.ps1 Test`; `odin build src -o:speed`; then `--check-shapes`, `--wood-study`, `--glass-study` and `--soak-fixture`. MATERIAL_CAPTURE_DIRECTORY and UI_LAYOUT_CAPTURE_DIRECTORY retain test captures for the manifests. `python scripts/package-rotation-glue.py` validates frozen evidence and packages the source and PNGs. Logs and fixture sources are included.
"""
(root/'report.md').write_text(report,encoding='utf8',newline='\n')
(e/'report.md').write_text(report.replace('](evidence/rotation-glue/',']('),encoding='utf8',newline='\n')
files=set()
for folder in ['src','docs','scripts','evidence/rotation-glue']:
 files.update(p for p in (root/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
files.update(root/name for name in ['README.md','AGENTS.md','report.md','.gitignore','.gitattributes','layouts/autosave.json','evidence/material-library/custom-layout.json','evidence/world-v3/before-v2-ticked.json','evidence/world-v3/continuity-manual-S.json'])
files.update(root/c['before'] for c in captures)
files.update((root/'evidence/textures-ui-followup/decode-before').glob('*.json'))
source=root/'BOM-rotation-glue-source.zip'
with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for p in sorted(files):
  if p.suffix.lower() not in ['.exe','.obj','.pdb']:z.write(p,p.relative_to(root).as_posix())
pngzip=root/'BOM-rotation-glue-PNGs.zip'
with zipfile.ZipFile(pngzip,'w',zipfile.ZIP_DEFLATED) as z:
 for p in images:z.write(p,p.name)
for p in [source,pngzip]:
 with zipfile.ZipFile(p) as z:assert z.testzip() is None
 print(p.name,p.stat().st_size,hashlib.sha256(p.read_bytes()).hexdigest())
