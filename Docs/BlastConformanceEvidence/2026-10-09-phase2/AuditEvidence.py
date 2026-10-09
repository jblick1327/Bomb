"""Validate recorded verdicts and rejection captures, then hash evidence/source files."""
import hashlib, json
from pathlib import Path

base=Path(__file__).resolve().parent
project=base.parents[2]
def verdict(name):
    envelope=json.loads((base/name).read_text(encoding='utf-8-sig'))
    assert envelope['success'],name
    result=envelope['data']['result']
    return json.loads(result) if isinstance(result,str) else result
edit=verdict('edit-complete-status.json'); play=verdict('play-final-status.json')
for result in (edit,play):
    assert result['status']=='completed'
    assert len(result['results'])==result['summary']['total']
    assert result['summary']['skipped']==result['summary']['inconclusive']==0
rejections=[]; snapshots=0
for path in (base/'states').glob('*.json'):
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    if 'schemaVersion' not in data: continue
    assert data['schemaVersion']==3,path.name
    for definition in data['definitions']:
        if definition['kind']==0:
            assert definition['hasBlastResistance'],path.name
            assert definition['blastResistance']>=0,path.name
    snapshots+=1
for outcome in (base/'states').glob('*-outcome.txt'):
    if 'accepted=False' not in outcome.read_text(): continue
    name=outcome.name.removesuffix('-outcome.txt')
    before=(base/'states'/f'{name}-before.json').read_bytes()
    after=(base/'states'/f'{name}-after.json').read_bytes()
    assert before==after,name
    rejections.append(name)
state=verdict('final-editor-state.json')['result']
assert not state['playing'] and not state['compiling']
assert all(not s['isDirty'] for s in state['scenes'])
audit={'edit':edit['summary'],'play':play['summary'],'schema3_snapshots_checked':snapshots,
    'byte_identical_rejected_worlds':sorted(rejections),'editor_play_stopped':True}
(base/'audit.json').write_text(json.dumps(audit,indent=2)+'\n',encoding='utf-8')
sources=list((project/'Assets/Game/Destruction').glob('*.cs'))+list((project/'Assets/Tests').rglob('*.cs'))
with (base/'SOURCE-SHA256SUMS.txt').open('w',encoding='utf-8',newline='\n') as output:
    for path in sorted(sources): output.write(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.relative_to(project).as_posix()+'\n')
with (base/'SHA256SUMS.txt').open('w',encoding='utf-8',newline='\n') as output:
    for path in sorted(base.rglob('*')):
        if path.is_file() and path.name!='SHA256SUMS.txt':
            output.write(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.relative_to(base).as_posix()+'\n')
print(json.dumps(audit,indent=2))
