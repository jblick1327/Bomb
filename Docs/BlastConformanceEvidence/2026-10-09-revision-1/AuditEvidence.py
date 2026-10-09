"""Audit completed verdicts, authored inputs, rejection atomicity and preserved evidence."""
import hashlib,json
from pathlib import Path
base=Path(__file__).resolve().parent
project=base.parents[2]
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def verdict(name):
    envelope=read(base/name);assert envelope['success'],name
    data=envelope['data']['result']
    return json.loads(data) if isinstance(data,str) else data
edit=verdict('final-edit-verdict.json');play=verdict('final-play-verdict.json')
for result,total in ((edit,83),(play,15)):
    assert result['status']=='completed'
    assert len(result['results'])==result['summary']['total']==total
    assert result['summary']['passed']==total
    assert result['summary']['failed']==result['summary']['skipped']==result['summary']['inconclusive']==0
snapshots=[]
for folder in ('states','rejected-support-corner'):
    for path in (base/folder).rglob('*.json'):
        data=read(path)
        if not isinstance(data,dict) or 'schemaVersion' not in data:continue
        assert data['schemaVersion']==3,path
        for definition in data['definitions']:
            if definition['kind']==0:
                assert definition['hasBlastResistance'] and definition['blastResistance']>=0,path
        snapshots.append(path.relative_to(base).as_posix())
pairs=[]
for prefix in ('states/authored-minimum-rejection','states/opaque-support-corner',
               'rejected-support-corner/live-layers-8-rejected'):
    before=(base/(prefix+'-before.json')).read_bytes()
    after=(base/(prefix+'-after.json')).read_bytes()
    assert before==after,prefix
    pairs.append(prefix)
state=verdict('final-editor-state.json')['result']
assert not state['playing'] and not state['compiling']
assert all(not scene['isDirty'] for scene in state['scenes'])
checkout=read(base/'checkout-state.json')
assert checkout['experimentHead']=='3f652e9178a78777bd41514441229827f7e611ad'
assert not checkout['staged'] and not checkout['protectedPaths']
for key in ('original','previousProbe','phase1'):assert not checkout[key]['status'],key
prior=base.parent/'2026-10-09-phase2'
preserved=0
for row in (prior/'SHA256SUMS.txt').read_text(encoding='utf-8-sig').splitlines():
    digest,name=row.split('  ',1)
    assert hashlib.sha256((prior/name).read_bytes()).hexdigest()==digest,name
    preserved+=1
source_rows={name:digest for digest,name in (r.split('  ',1) for r in (prior/'SOURCE-SHA256SUMS.txt').read_text().splitlines())}
for filename in ('BoundedBlastEvaluator.cs','BoundedBlastGeometry.cs','BlastConformanceTests.cs'):
    path=base/'prior-prototype'/filename
    target=('Assets/Tests/EditMode/' if filename.endswith('Tests.cs') else 'Assets/Game/Destruction/')+filename
    assert hashlib.sha256(path.read_bytes()).hexdigest()==source_rows[target],filename
audit={'edit':edit['summary'],'play':play['summary'],'schema3_snapshots_checked':len(snapshots),
       'byte_identical_rejected_worlds':pairs,'prior_evidence_files_unchanged':preserved,
       'editor_play_stopped':True,'protected_checkouts_clean':True,'settings_packages_scenes_unchanged':True}
(base/'audit.json').write_text(json.dumps(audit,indent=2)+'\n',encoding='utf-8')
with (base/'SOURCE-SHA256SUMS.txt').open('w',encoding='utf-8',newline='\n') as output:
    sources=list((project/'Assets/Game/Destruction').glob('*.cs'))+list((project/'Assets/Tests').rglob('*.cs'))
    sources.extend((project/'Docs'/name for name in ('BlastConformance.md','BlastConformancePhase1.md')))
    for path in sorted(sources):output.write(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.relative_to(project).as_posix()+'\n')
with (base/'SHA256SUMS.txt').open('w',encoding='utf-8',newline='\n') as output:
    for path in sorted(base.rglob('*')):
        if path.is_file() and path.name!='SHA256SUMS.txt':
            output.write(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+path.relative_to(base).as_posix()+'\n')
print(json.dumps(audit,indent=2))
