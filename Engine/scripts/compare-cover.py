from pathlib import Path
import json,collections,struct
root=Path('evidence/cover-performance')
# Compare serialized fixtures, and ID-free geometry, full poses, and piece partitions.
def scene(p):
 d=json.loads(p.read_text());return d.get('scene',d)
def freeze(v):
 if isinstance(v,dict):return tuple((k,freeze(x)) for k,x in sorted(v.items()))
 if isinstance(v,list):return tuple(map(freeze,v))
 if isinstance(v,(int,float)): return struct.pack("!f",float(v))
 return v
def signatures(s):
 outlines={x['id']:tuple(freeze(p) for p in sorted((p['x'],p['y']) for p in x['outline']['points'])) for x in s['subdivisions'] if x['live']}
 geom=collections.Counter(outlines.values())
 poses=collections.Counter((outlines[x['id']],freeze(x['pose'])) for x in s['subdivisions'] if x['live'])
 parts=collections.Counter(tuple(sorted(outlines[i] for i in p['subdivisions'])) for p in s['pieces'] if p['live'])
 return geom,poses,parts
pairs=[]
base=Path('evidence/blast-cover')
for a in sorted(base.rglob('*.json')):
 rel=a.relative_to(base).as_posix()
 if not rel.startswith('after'):continue
 suffix=rel[5:]
 for phase in ('part1','final','no-reach','no-delete','exact','rejected-reach'):
  b=root/(phase+suffix)
  if b.exists():
   sa,sb=signatures(scene(a)),signatures(scene(b))
   pairs.append({'phase':phase,'fixture':rel,'byte_identical':a.read_bytes()==b.read_bytes(),'outlines':sa[0]==sb[0],'poses':sa[1]==sb[1],'partition':sa[2]==sb[2], 'cell_symmetric_difference':sum((sa[0]-sb[0]).values())+sum((sb[0]-sa[0]).values())})
(root/'comparison.json').write_text(json.dumps(pairs,indent=2))
for phase in ('part1','final','no-reach','no-delete','exact','rejected-reach'):
 rows=[r for r in pairs if r['phase']==phase];print(phase,len(rows),'byte identical',sum(r['byte_identical'] for r in rows),'geometry',sum(r['outlines'] for r in rows),'poses',sum(r['poses'] for r in rows),'partition',sum(r['partition'] for r in rows))
 for r in rows:
  if not all(r[k] for k in ('outlines','poses','partition')):print(r)
