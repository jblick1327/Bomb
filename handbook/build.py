from pathlib import Path
import hashlib
import html
import json
import re

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'dist'
OUT.mkdir(exist_ok=True)
book=json.loads((ROOT/'handbook.json').read_text())
names=['BOM Architecture.md','BOM Decision Log.md','BOM Open Questions.md','BOM Model Interview Handoff.md','BOM-Team-Model-Handoff.md','BOM-Candidate-Component-Map.md']
sources={name:(ROOT/'sources'/name).read_text() for name in names}
arch=sources[names[0]]
arch_version=re.search(r'\*\*Version:\*\* (\S+)',arch)[1]
last_decision=re.findall(r'^### (DEC-\d{3})',sources[names[1]],re.M)[-1]
baseline=f'Architecture v{arch_version} · {last_decision}'

def parse_entries(text,pattern,kind):
    entries={}
    matches=list(re.finditer(pattern,text,re.M))
    for i,m in enumerate(matches):
        end=matches[i+1].start() if i+1<len(matches) else len(text)
        body=text[m.end():end]
        section_end=re.search(r'^## ',body,re.M)
        if section_end: body=body[:section_end.start()]
        status=re.search(r'\*\*Status:\*\* ([^\n]+)',body)
        entries[m[1]]={'id':m[1],'title':m[2],'kind':kind,'status':status[1].strip() if status else 'Open','markdown':body.strip()}
    return entries

rules=parse_entries(arch,r'^### ([A-Z]+-\d{3}) — (.+)$','rule')
decisions=parse_entries(sources[names[1]],r'^### (DEC-\d{3}) — (.+)$','decision')
questions=parse_entries(sources[names[2]],r'^### (OQ-[A-Z]+-\d{3}) — (.+)$','question')
entries={**rules,**decisions,**questions}
id_pattern=re.compile(r'\b(?:OQ-)?[A-Z]+-\d{3}\b')
esc=html.escape

def ref(id):
    assert id in entries,id
    route='rules' if id in rules else 'entry'
    return f'<a href="#reference/{route}/{esc(id)}">{esc(id)}</a>'

def ref_list(ids):
    return '<div class="source-links"><span>Rules</span>'+''.join(ref(x) for x in ids)+'</div>'

def inline(s):
    out=[]
    token=re.compile(r'(\[[^\]\n]+\]\(https://[^\s)]+\)|`[^`]+`|\*\*.+?\*\*|\b(?:OQ-)?[A-Z]+-\d{3}\b)')
    cursor=0
    for m in token.finditer(s):
        out.append(esc(s[cursor:m.start()]))
        t=m[0]
        if t.startswith('['):
            link=re.fullmatch(r'\[([^\]\n]+)\]\((https://[^\s)]+)\)',t)
            out.append('<a href="'+esc(link[2],quote=True)+'">'+esc(link[1])+'</a>')
        elif t.startswith('`'):
            t=t[1:-1]
            out.append(ref(t) if t in entries else '<code>'+esc(t)+'</code>')
        elif t.startswith('**'): out.append('<strong>'+inline(t[2:-2])+'</strong>')
        else: out.append(ref(t) if t in entries else esc(t))
        cursor=m.end()
    out.append(esc(s[cursor:]))
    return ''.join(out)

def md(text):
    lines=text.splitlines(); result=[]; i=0
    while i<len(lines):
        line=lines[i]
        if not line.strip(): i+=1; continue
        if line.startswith('```'):
            i+=1; code=[]
            while i<len(lines) and not lines[i].startswith('```'): code.append(lines[i]); i+=1
            result.append('<pre><code>'+esc('\n'.join(code))+'</code></pre>'); i+=1; continue
        if line.startswith('|'):
            rows=[]
            while i<len(lines) and lines[i].startswith('|'):
                rows.append([c.strip() for c in lines[i].strip('|').split('|')]); i+=1
            assert len(rows)>1 and len({len(r) for r in rows})==1,rows[0]
            result.append('<div class="table-wrap" tabindex="0" role="region" aria-label="'+esc(rows[0][0])+' table"><table><thead><tr>'+''.join('<th scope="col">'+inline(c)+'</th>' for c in rows[0])+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+inline(c)+'</td>' for c in row)+'</tr>' for row in rows[2:])+'</tbody></table></div>'); continue
        h=re.match(r'^(#{1,4}) (.+)',line)
        if h: level=len(h[1]); result.append(f'<h{level}>'+inline(h[2])+f'</h{level}>'); i+=1; continue
        if re.match(r'^[-*] |^\d+\. ',line):
            ordered=bool(re.match(r'^\d+\. ',line)); tag='ol' if ordered else 'ul'; items=[]
            p=r'^\d+\. ' if ordered else r'^[-*] '
            while i<len(lines) and re.match(p,lines[i]):
                items.append('<li>'+inline(re.sub(p,'',lines[i]))+'</li>'); i+=1
            result.append('<'+tag+'>'+''.join(items)+'</'+tag+'>'); continue
        if line.startswith('> '):
            quoted=[]
            while i<len(lines) and lines[i].startswith('> '): quoted.append(lines[i][2:]); i+=1
            result.append('<blockquote><p>'+inline(' '.join(quoted))+'</p></blockquote>'); continue
        para=[]
        while i<len(lines) and lines[i].strip() and not re.match(r'^(#|\||[-*] |\d+\. |>|```)',lines[i]):
            para.append(lines[i]); i+=1
        assert para,(i,lines[i])
        result.append('<p>'+'<br>'.join(inline(x) for x in para)+'</p>')
    return '\n'.join(result)

for entry in entries.values():
    display=entry['markdown']
    if entry['kind']=='rule' and entry['status']=='Accepted':
        display=re.sub(r'^\*\*Status:\*\* Accepted[ \t]*\n', '', display, count=1)
    entry['html']=md(display)

map_text=sources[names[-1]]
records={}; record_groups=[]
group_names={'2':'Body and property records','3':'Character and bomb records','4':'Persistent physical relationships','5':'Canonical match dependencies'}
section=''; lines=map_text.splitlines(); i=0
while i<len(lines):
    h=re.match(r'^## (\d+)\. ',lines[i])
    if h: section=h[1]
    if lines[i].startswith('|'):
        rows=[]
        while i<len(lines) and lines[i].startswith('|'): rows.append([x.strip() for x in lines[i].strip('|').split('|')]); i+=1
        if rows[0][0] in ['Record grouping','Canonical match dependency']:
            group=[]
            for row in rows[2:]:
                name=row[0].strip('`')
                records[name]={'id':name,'title':name,'status':row[1],'group':group_names[section],'fields':[{ 'label':rows[0][j], 'text':row[j], 'html':inline(row[j])} for j in range(2,len(row))]}
                group.append(name)
            record_groups.append((group_names[section],group))
        continue
    i+=1
assert len(records)==12

def scene_svg(scene):
    split=scene=='split'; death=scene=='death'; held=scene in ['held','countdown','split']
    def g(id,content,description): return '<g class="scene-entity" data-entity="'+id+'" role="group" aria-label="'+esc(description)+'"><title>'+esc(description)+'</title>'+content+'</g>'
    descriptions={
        'initial':'A platform body is bonded to a fixed wall body through a separate structural connection.',
        'held':'A Claymate holds a point on the underside of the platform. The point remains attached to the platform material.',
        'countdown':'A bomb has landed on the platform and its fuse is active. The Claymate continues holding the platform.',
        'split':'The platform has split into two pieces. The bond remains on the left piece and the held material point survives on the right piece.',
        'death':'The Claymate body now behaves as environment. Its outgoing hold has ended; the wall and platform remain.'
    }
    def label(x,y,text,colour='#212934',size=28):
        return f'<text class="diagram-label" x="{x}" y="{y}" text-anchor="middle" font-size="{size}" fill="{colour}">{esc(text)}</text>'
    out=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 360" role="img" aria-labelledby="scene-title-{scene} scene-desc-{scene}"><title id="scene-title-{scene}">{esc(descriptions[scene])}</title><desc id="scene-desc-{scene}">{esc(descriptions[scene])}</desc><rect width="600" height="360" fill="#fff"/>']
    out.append(g('W','<rect x="40" y="126" width="70" height="200" rx="2" fill="#d3dbe5" stroke="#6d7f95" stroke-width="2"/>'+label(75,240,'Wall'),'fixed wall W'))
    if split:
        for id,x,w,name in [('P1',132,127,'Piece 1'),('P2',290,108,'Piece 2')]:
            out.append(g(id,f'<rect x="{x}" y="148" width="{w}" height="48" rx="2" fill="#f1d37a" stroke="#997400" stroke-width="2"/>'+label(x+w/2,181,name,'#493600'),f'new material piece {id}'))
    else:
        out.append(g('P','<rect x="132" y="148" width="266" height="48" rx="2" fill="#f1d37a" stroke="#997400" stroke-width="2"/>'+label(265,181,'Platform','#493600'),'platform body P'))
    out.append(g('C','<rect x="101" y="156" width="9" height="32" fill="#7650c4"/><rect x="132" y="156" width="9" height="32" fill="#7650c4"/><path d="M110 163h22m-22 18h22" stroke="#7650c4" stroke-width="4"/>'+label(132,113,'Bond','#6340ad'),'structural connector C joining W to '+('P1' if split else 'P')))
    if scene!='initial':
        fill='#d3dbe5' if death else '#3866d7'; stroke='#6d7f95' if death else '#1e43a3'
        text='Body' if death else 'Claymate'; colour='#212934' if death else '#fff'
        out.append(g('K',f'<rect x="419" y="253" width="150" height="68" rx="5" fill="{fill}" stroke="{stroke}" stroke-width="2"/>'+label(494,296,text,colour)+ (label(494,349,'Environment') if death else ''),'same body K, '+('now environment' if death else 'living Claymate')))
    if held:
        out.append(g('L','<path d="M434 269L358 196" fill="none" stroke="#7650c4" stroke-width="3"/><circle cx="434" cy="269" r="4" fill="#1e43a3"/><circle cx="358" cy="196" r="7" fill="#7650c4" stroke="#fff" stroke-width="2"/>'+label(455,224,'Hold','#6340ad'),'limb attachment L from K to the surviving material point on '+('P2' if split else 'P')))
    if scene=='countdown':
        out.append(g('B','<circle cx="265" cy="126" r="22" fill="#cc4856" stroke="#9e2437" stroke-width="2"/>'+label(350,123,'Bomb','#9e2437')+'<text class="diagram-note" x="311" y="98" font-size="23" fill="#9e2437">Fuse active</text>','live bomb B, resting on P with an active fuse'))
    out.append('</svg>')
    return ''.join(out)

def body(id,role,contents,records): return {'id':id,'role':role,'contents':contents,'records':records}
wall=body('W','Fixed environment body',['Geometry, fixed behaviour and identity resolve from level/world data.','Current body shape is local; position/rotation are world-space.'],['BodyMotion2D','BodyShape2D','MaterialProperties','DestructionBehaviour','InteractionPolicy'])
platform=body('P','Environment body',['Own shape, motion and selected material/response/appearance inputs.','A separate body, connected to W through C.'],['BodyMotion2D','BodyShape2D','MaterialProperties','DestructionBehaviour','InteractionPolicy'])
living=body('K','Living character body',['Own motion, shape and shared material inputs.','Character definition supplies fixed roots/reach and death configuration.','No accumulated health/damage value is required.'],['BodyMotion2D','BodyShape2D','MaterialProperties','CharacterState','InteractionPolicy'])
bomb=body('B','Live bomb body',['Own shape, motion and shared material inputs.','Selected bomb configuration and inactive or active remaining-duration countdown.'],['BodyMotion2D','BodyShape2D','MaterialProperties','BombState','InteractionPolicy'])
connector=body('C','Physical relationship; no body',['Endpoints W and P; paired endpoint-local attachment regions.','Intended rigid fit and authored strength/policies.','A lifetime reference is recoverable when percentage loss is used.'],['StructuralConnection'])
hold=body('L','Physical relationship; no body',['Character K, limb slot, target P and target-local held location.','Its own entity identity is metadata. Roots/reach are not copied here.'],['LimbAttachment'])
roster=body('R','Canonical participant record',['Stable participant identity; sole control assignment is its optional body reference, currently K.'],['ParticipantRecord'])
scenes={}
for scene in ['initial','held','countdown','split','death']:
    e=[dict(wall),dict(platform),dict(living),dict(connector),dict(roster)]; bodies=3; relationships=1
    if scene!='death' and scene!='split': e.append(dict(bomb)); bodies+=1
    if scene in ['held','countdown','split']: e.append(dict(hold)); relationships+=1
    if scene=='split':
        e=[x for x in e if x['id']!='P']
        e+=[body(id,'Resulting environment body',['Own current shape/motion and inherited material/response/reusable appearance inputs by default.','New identity; reconstructs without retired P.'],platform['records']) for id in ['P1','P2']]; bodies=4
        next(x for x in e if x['id']=='C')['contents']=['Endpoints W and P1; C keeps its ID and intended fit.','Its lifetime percentage reference stays unchanged if that policy is used.']
        next(x for x in e if x['id']=='L')['contents']=['Character K, same slot, target P2.','Held coordinates transform into P2 local space to identify the same surviving material.']
    if scene=='death':
        e=[x for x in e if x['id']!='K']+[body('K','Environment body after death',['Same surviving body ID; ordinary environment records.','Material, destruction, interaction and reusable appearance selections installed from the character definition.','No former living state is required for recovery.'],platform['records'])]
        next(x for x in e if x['id']=='R')['contents']=['Participant identity survives; its controlled-body reference is empty.']
    scenes[scene]={'svg':scene_svg(scene),'entities':e,'bodies':bodies,'relationships':relationships}


def list_html(items,tag='ul'):
    return '<'+tag+'>'+''.join('<li>'+inline(s)+'</li>' for s in items)+'</'+tag+'>'

def table(headers,rows,cls=''):
    return '<div class="table-wrap" tabindex="0" role="region" aria-label="'+esc(headers[0])+' table"><table class="'+cls+'"><thead><tr>'+''.join('<th scope="col">'+inline(x)+'</th>' for x in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join('<td>'+inline(x)+'</td>' for x in row)+'</tr>' for row in rows)+'</tbody></table></div>'

def table_from_source(first):
    rows=[]; collecting=False
    for line in map_text.splitlines():
        if line.startswith('| '+first+' |'): collecting=True
        if collecting:
            if not line.startswith('|'): break
            rows.append(line)
    assert rows,first
    return md('\n'.join(rows))

role_names={'simulation':'Unity / simulation','assets':'Asset authoring','level':'Level composition','networking':'Odin / networking','shared':'Exchange conventions'}
record_topics={n:('relationships' if n in ['StructuralConnection','LimbAttachment'] else 'control' if n in ['ParticipantRecord','MatchState'] else 'definitions' if n=='VisualBinding' else 'bodies') for n in records}
accepted=['BodyMotion2D','BodyShape2D','MaterialProperties','DestructionBehaviour','InteractionPolicy','CharacterState','BombState']
summaries={
'BodyMotion2D':('World-space local-frame pose; current COM linear velocity and angular velocity.','Environment, characters, bombs.'),
'BodyShape2D':('Current body-local gameplay shape.','Physical bodies.'),
'MaterialProperties':('Selected material inputs, including independently authored density and blast resistance.','Environment, characters, bombs.'),
'DestructionBehaviour':('Destructibility and independently selected response.','Applicable environment pieces.'),
'InteractionPolicy':('Effective interaction eligibility.','Applicable target bodies.'),
'CharacterState':('Character definition and selected lasting gameplay inputs.','Living characters.'),
'BombState':('Bomb configuration; inactive or active countdown with remaining duration.','Live bombs.')
}
record_rules={
'BodyMotion2D':['ECS-007','WORLD-006','AUTH-003'],
'BodyShape2D':['ECS-007','MAT-007','WORLD-006','IDENTITY-001','INTERACT-002'],
'MaterialProperties':['ECS-007','MAT-005','MAT-009','MAT-010'],
'DestructionBehaviour':['ECS-007','MAT-006','MAT-008'],
'InteractionPolicy':['ECS-007','INTERACT-002','LIMB-005','LIMB-007'],
'CharacterState':['ECS-007','CHAR-002','CHAR-004','CHAR-005','CHAR-006','LIMB-011','PLAYER-002'],
'BombState':['ECS-007','BOMB-001','BOMB-002','BOMB-003','BOMB-004'],
'StructuralConnection':['CON-004','CON-008','CON-009','CON-010','CON-011','CON-013','CON-014'],
'LimbAttachment':['LIMB-001','LIMB-002','LIMB-008','LIMB-009','LIMB-010','LIMB-011','LIMB-012'],
'VisualBinding':['MAT-007','MAT-008','ECS-007'],
'ParticipantRecord':['PLAYER-001','PLAYER-002'],
'MatchState':['ECS-006','PLAYER-002']
}
for refs in record_rules.values():
    assert all(id in rules for id in refs), refs
topic_pages={}
def team_section(title):
    body=sources['BOM-Team-Model-Handoff.md'].split('## '+title+'\n',1)[1]
    return body.split('\n## ',1)[0].strip()

body_rows=[]
for name in accepted:
    body_rows.append(['[RECORD:'+name+']',*summaries[name]])
def resolve_record_links(s):
    return re.sub(r'\[RECORD:([^\]]+)\]',lambda m:'<a href="#reference/map/'+esc(m[1])+'"><code>'+esc(m[1])+'</code></a>',s)
topic_pages['bodies']=resolve_record_links('<h1>Body components</h1><p class="section-intro">These seven groupings are accepted. Reusable definitions supply selected inputs; engine objects derive from current records.</p>'+table(['Component','Stores or selects','Applies to'],body_rows,'record-index')+'''<h2>Fixed supports</h2><p>Level/world data supplies fixed wall geometry, fixed behaviour and stable endpoint identities. A connector restricts the attached piece’s motion. Fixedness is not inferred from zero velocity.</p><h2>Appearance</h2><p>Colour can vary independently of physical material. Current bodies and resulting pieces need recoverable appearance inputs. A separate <a href="#reference/map/VisualBinding"><code>VisualBinding</code></a> component remains unaccepted.</p><h2>Physical configuration</h2><p>Environment pieces, living characters and live bombs derive mass from density × current 2D gameplay area and resolve independently authored blast resistance from the shared material-property source. COM/inertia and further physical derivations remain open.</p><p><a href="#reference/blast">Blast reach and the complete destruction result.</a></p><p>Attachment restrictions derive from their relationships. <code>BodyPhysics</code> is not an accepted component; further physical inputs must have recoverable sources without duplicating those restrictions.</p>'''+ref_list(['ECS-007','WORLD-005','MAT-005','MAT-009','WORLD-006','MAT-007']))
topic_pages['relationships']='''<h1>Relationships</h1><p>Structural connectors and limb attachments have identities and persistent state, but no physics bodies.</p>'''+table(['Relationship','Stored facts','Derived objects'],[
['[RECORD:StructuralConnection]','Endpoint IDs; paired endpoint-local regions sufficient to recover the intended rigid fit; authored strength and applicable failure inputs.','Rigid constraint and effective force/torque limits.'],
['[RECORD:LimbAttachment]','Character ID, limb slot, target ID and target-local held location.','Reach constraint, visible held-limb pose and slot lookup.']
])+'''<h2>Ownership</h2><p>Each character slot has at most one live hold. The attachment alone owns the relationship; the character does not store another authoritative attachment reference.</p><h2>Rigid fit</h2><p>Paired and oriented connector regions may already encode the intended relative position and angle. Store additional rest data only when the chosen representation leaves that arrangement ambiguous. Temporary body displacement must not become a new rest fit.</p><h2>Connector strength and attachment loss</h2><p>Connector strength is authored per unit of surviving attachment length. Destruction that shortens the attachment reduces its load capacity. For strength per unit length S and surviving length L, limits are Fmax = S × L and Tmax = ½ × S × L². Halving L halves force capacity and quarters torque capacity. Paired length measurement, load conversion, units and authored values remain open.</p><p>Authors may configure a minimum surviving attachment percentage. Falling below it breaks the connector independently of current load; without that setting, this percentage condition does not apply. Configured percentage failure uses the following reference-lifetime rules:</p>'''+table_from_source('Outcome')+'''<p>A smaller new bond at 100% has not recovered the old bond’s absolute strength. Actual cutoff values are authored tuning; no universal percentage is selected.</p><h2>Hold eligibility and release</h2><p>One authored Boolean eligibility policy governs hand and deliberate foot holds, including live bombs. Eligibility permits an attempt; the host still validates geometry, reach, obstruction and other interaction conditions. Ordinary foot contact is unaffected.</p><p>Applied force alone does not release holds in the current build. Deliberate release and applicable destruction, retirement and death outcomes still apply. Holding or throwing an active bomb preserves its continuous countdown; support loss and later landings do not pause, restart or extend it. Expiry detonates at the current position, and bomb retirement ends holds targeting it.</p>'''+ref_list(['CON-004','CON-009','CON-010','CON-013','CON-014','LIMB-002','LIMB-005','LIMB-006','LIMB-007','LIMB-012','BOMB-003','BOMB-004'])
topic_pages['relationships']=resolve_record_links(topic_pages['relationships'])
topic_pages['control']='''<h1>Control assignment</h1><p>The canonical match roster stores participant identity and the sole optional controlled-body reference. Interaction validation reads that assignment; character death clears it in the same complete outcome.</p>'''+table(['Canonical fact','Owner','Derived lookup'],[
['Participant identity and optional controlled-body ID.','Canonical match roster; working record name [RECORD:ParticipantRecord].','Body-to-participant lookup.'],
['Which limb slot holds which target.','[RECORD:LimbAttachment].','Character-slot-to-attachment lookup.']
])+'''<p>The character does not duplicate participant ownership or hold references. Connection mapping, scoring and respawn rules remain open.</p><h2>Match progression</h2><p>Lasting round/spawn facts belong to canonical state when selected mechanics require them. Broad <code>MatchState</code> contents are outside this body-and-relationship catalogue. The accepted bomb countdown needs no shared deadline clock.</p>'''+ref_list(['PLAYER-001','PLAYER-002','LIMB-002','BOMB-004'])
topic_pages['control']=resolve_record_links(topic_pages['control'])
topic_pages['definitions']='''<h1>Definitions and compositions</h1><p>Definitions supply reusable inputs selected by current state. Reconstruction must resolve the same effective values. A changed piece must not need its retired parent to recover its properties or appearance.</p>'''+table_from_source('Definition/configuration source')+'''<h2>Body compositions</h2>'''+table(['Role','Required semantic contents'],[
['Environment piece','Identity, motion, shape, material, destruction behaviour, applicable interaction eligibility and recoverable appearance inputs.'],
['Living character','Identity, motion, shape, shared material inputs, CharacterState, applicable interaction eligibility and appearance inputs.'],
['Live bomb','Identity, motion, shape, shared material inputs, BombState, applicable interaction eligibility and appearance inputs.'],
['Structural connector','Identity and relationship state; no body.'],
['Limb hold','Identity and minimum LimbAttachment contents; no body.']
])+'''<p>Authored composites expand into pieces and connectors. There is no additional canonical assembly entity. Concrete fields, encodings and implementation boundaries remain open where the source model leaves them unspecified.</p>'''+ref_list(['MAT-002','MAT-007','MAT-008','MAT-009','CHAR-004','STATE-001','ECS-007'])
topic_pages['coordinates']='''<h1>Coordinates and motion</h1>'''+table_from_source('Information')+'''<h2>Motion through geometry changes</h2><p>Body pose locates its local frame; linear velocity describes its current centre of mass, which may differ from the frame origin. Angular velocity is the rate of change of body angle.</p><p>When a geometry or frame change is intended to preserve motion, preserve the instantaneous movement of surviving material, including same-ID results. A COM shift can require a velocity correction without changing the body frame. This does not select universal motion inheritance or a blast-impulse policy.</p><h2>Split remapping</h2><p>Changing a piece’s local frame must preserve the same surviving material location. Convert a held point or connector region through the old pose into the new piece’s local frame; do not choose a nearby replacement point to preserve a destroyed hold.</p><p>For a surviving held point, the world location before and after remapping agrees:</p><pre><code>old body pose × old local point
  = new body pose × new local point</code></pre><p>Body-local origins, units, shape/visual alignment, numeric encoding and tolerances still need implementation conventions.</p>'''+ref_list(['WORLD-006','LIMB-008','CON-013'])+'''<p><a href="#work/shared">Exchange conventions</a></p>'''
topic_pages['systems']='''<h1>Systems</h1><p>Unity on the host evaluates gameplay and physics. Odin carries requests, committed results and recovery state.</p>'''+table_from_source('Responsibility')+'''<p>These are responsibilities. Their grouping does not prescribe tick order, callback order, commit frequency or a fixed pipeline. Contacts, measured loads, solver history and pending split plans are transient.</p>'''+ref_list(['AUTH-003','NET-001','ECS-005','ECS-006','COMMIT-002'])
topic_pages['lifecycles']='''<h1>Lifecycles</h1>'''+table(['Event','Identity and body outcome','Relationship/control outcome'],[
['Validated grab','Create one limb attachment.','The new attachment owns the chosen slot and target-local held location.'],
['Piece changes without splitting','Keep the piece ID and update its shape/state.','Resolve surviving attachment locations against the new geometry.'],
['Piece becomes disconnected children','Retire the original piece; assign new IDs to every child.','Keep/remap a single surviving connector or hold; retire lost relationships. Multiple valid connector results receive new connector IDs.'],
['Character dies','Keep shape, geometry revision and body ID through the killing explosion; install environment selections from the character definition.','Clear control and outgoing holds. Preserve incoming holds on surviving locations.'],
['Bomb detonates','Retire the bomb; produce no persistent bomb fragments.','Retire holds targeting the bomb and commit complete lasting world consequences.']
])+'''<h2>Complete structural outcomes</h2><p>Resolve geometry, identities, behaviour, control and relationships together. Commit the complete outcome with valid references. Engine objects, indexes and exposed semantic results derive from that committed state.</p><h2>Result properties</h2><p>Material, destruction response and reusable appearance inputs inherit by default unless the selected response changes them. Other component inheritance is not automatically settled. Each child needs its own motion and reconstructable inputs.</p><h2>Continuous bomb fuse</h2><p>The first valid landing starts the configured remaining-duration countdown. Holding, throwing, support loss and further landings do not pause, restart or extend it. Expiry detonates at the current position.</p><h2>Blast reach and character lethality</h2><p>Straight paths consume ordinary distance plus independently authored resistance × crossed thickness from original material. Carving must breach intervening layers; indestructible cover blocks carving and exposure through that path. Removing cover keeps its cost.</p><p>A qualifying blast causes immediate death without accumulated damage and leaves the new corpse uncarved. A later independent blast uses its current environment response. Exact power/radius mapping, character boundary lethality and production numerical geometry remain open.</p><p><a href="#reference/blast">Blast contract</a> · <a href="#reference/blast-evidence">Bounded evidence and implementation limits</a></p>'''+ref_list(['IDENTITY-001','MAT-008','CON-011','CON-014','LIMB-008','LIMB-009','CHAR-003','CHAR-004','CHAR-005','CHAR-006','BOMB-002','BOMB-003','BOMB-004','MAT-010','WORLD-007','WORLD-008','WORLD-009','WORLD-010','WORLD-011','COMMIT-002'])
topic_pages['unresolved']='''<h1>Unresolved details</h1><p>The following items remain implementation and authoring choices. They do not reopen the accepted identity, ownership, coordinate-frame or lifecycle rules.</p>'''+table(['Item','Settled boundary','Remaining work'],[
['Exchange conventions','World/body-local frame roles are accepted.','Record units, local origins, the first geometry format and definition lookup. Simulation and authoring own the fixture exchange.'],
['Additional physical inputs','Environment pieces, characters and bombs share MaterialProperties and all derive mass from density × current gameplay area. COM velocity semantics are settled.','Resolve remaining physical inputs and derivations. Do not silently rely on undocumented engine defaults or duplicate attachment restrictions.'],
['Appearance','Colour can vary; resulting pieces recover their own appearance inputs.','Choose definition/instance placement, shape alignment and regeneration. A separate VisualBinding is unaccepted.'],
['Connector failure','Rigid fit, identity outcomes, Fmax = S × L / Tmax = ½ × S × L² and optional percentage failure are accepted. References follow connector identity.','Choose explicit fixture values, paired length measurement, load conversion and encoding. No universal percentage cutoff is selected.'],
['Interaction and movement','Minimum holds, fixed roots, authored reach and shared Boolean hand/foot eligibility are accepted. Bombs use ordinary eligibility; applied force alone does not release holds.','Choose constraint realization, active controls, tuning, authoring defaults and eligibility encoding.'],
['Bomb activation and blasts','Continuous activated fuse; independent resistance; distance-plus-thickness cost; straight paths; breach continuity; opaque indestructible cover; uncarved killing-explosion corpse.','Choose landing classification, values/units/encoding, production geometry support/performance, character boundary lethality, power/radius mapping and general update order. See the bounded evidence for measured limits.'],
['Data and networking encoding','Current state and validated dependencies must reconstruct the world.','Choose formats, dependency validation, IDs/revisions and networking encoding without altering the semantic contracts.']
],'open-table')+'''<details><summary>All open questions</summary>'''+''.join('<details><summary>'+esc(q['id']+' — '+q['title'])+'</summary><div class="rule-body">'+q['html']+'</div></details>' for q in questions.values() if q['status']!='Resolved')+'''</details>'''
topic_pages['blast']='<h1>Blast reach and destruction</h1>'+md(team_section('Blast reach and destruction handoff'))+'<p><a href="#reference/blast-evidence">Reviewed conformance evidence and remaining implementation limits</a></p>'+ref_list(['MAT-010','WORLD-007','WORLD-008','WORLD-009','WORLD-010','WORLD-011','CHAR-006','COMMIT-002'])
topic_pages['blast-evidence']='<h1>Blast conformance</h1>'+md(team_section('Blast conformance evidence and implementation limits'))
topic_pages['rules']='<h1>Architectural rules</h1><div class="rule-index">'+''.join('<details id="rule-'+r['id']+'"><summary><code>'+esc(r['id'])+'</code><span>'+esc(r['title'])+'</span>'+('<span class="rule-status">'+esc(r['status'])+'</span>' if r['status']!='Accepted' else '')+'</summary><div class="rule-body">'+r['html']+'<p><a href="#reference/rules/'+r['id']+'">Permanent link</a></p></div></details>' for r in rules.values())+'</div>'
topic_pages['sources']='<h1>Source documents</h1><ul class="topic-list">'+''.join('<li><a href="#reference/sources/'+esc(name)+'">'+esc(name)+'</a><p>Version '+esc(re.search(r'\*\*Version:\*\* (\S+)',text)[1])+'</p></li>' for name,text in sources.items())+'</ul>'
record_pages={}
for name,r in records.items():
    if name in ['StructuralConnection','ParticipantRecord','MatchState','VisualBinding']:
        status=r['status']
    elif name=='LimbAttachment': status='Accepted minimum record.'
    else: status='Accepted grouping.'
    fields='<div class="component-fields">'+''.join('<h2>'+esc(f['label'])+'</h2><p>'+f['html']+'</p>' for f in r['fields'])+'</div>'
    extra=''
    if name=='StructuralConnection': extra='<h2>Reference lifetime</h2>'+table_from_source('Outcome')+'<p>Optional authored percentage failure is accepted. A new reference does not restore absolute bond strength.</p>'
    if name=='BodyShape2D': extra='<p>Geometry revisions supply evidence for interaction validation; a revision comparison alone is not a validity test.</p>'
    topic=record_topics[name]
    record_pages[name]='<p class="breadcrumb"><a href="#reference/'+topic+'">'+dict(book['topics'])[topic]+'</a></p><h1><code>'+esc(name)+'</code></h1><p class="reference-status">'+esc(status)+'</p>'+fields+extra+ref_list(record_rules[name])

def walk_page(c,result='split'):
    index=book['cases'].index(c); scene=result if c['id']=='recovery' else c['scene']
    intro=c['intro']; notice=c['notice']; facts=c['facts']
    if c['id']=='recovery' and result=='death':
        intro='Rebuild the death result using its current environment records and the definitions they select.'
        notice='The body reconstructs as environment under the same surviving ID.'
        facts=['Installed settings recover material, destruction behaviour, interaction eligibility and appearance. Control and outgoing holds remain absent.','Unity bodies, colliders, constraints, visuals and lookups derive from current state.']
    fig_key=[('W','fixed wall'),('P1 / P2','pieces') if scene=='split' else ('P','platform'),('K','environment') if scene=='death' else ('K','Claymate')]
    if scene not in ['split','death']: fig_key.append(('B','bomb'))
    fig_key+=[('C','connector'),('R','participant')]
    if scene in ['held','countdown','split']: fig_key.append(('L','hold'))
    if scene=='initial': fig_key=[('W','wall'),('P','platform'),('C','bond')]
    key=' · '.join('<code>'+esc(id)+'</code> '+esc(label) for id,label in fig_key)
    caption='The body reconstructed as environment, without its former living state or death history.' if c['id']=='recovery' and result=='death' else c['caption']
    details='<details class="walk-detail"><summary>Records and applicable rules</summary><p class="record-key">'+key+'</p>'+table(['Concern','Outcome'],c['changes'])+'<div class="detail-columns"><section><h2>Stored or selected</h2>'+list_html(c['remember'])+'</section><section><h2>Derived</h2>'+list_html(c['derive'])+'</section></div><p class="case-caveat">'+inline(c['caveat'])+'</p>'+ref_list(c['refs'])+'</details>'
    if c['id']=='explosion':
        details+='<section class="blast-example">'+md(team_section('Blast reach and destruction handoff'))+'<p><a href="#reference/blast-evidence">Measured evidence and remaining implementation limits</a></p></section>'
    if c['id']=='recovery' and result=='death':
        details='<details class="walk-detail"><summary>Records and applicable rules</summary><p class="record-key">'+key+'</p>'+list_html(['K: ordinary environment records; no former CharacterState is required.','R: participant identity survives and its controlled-body reference is empty.','The outgoing L is absent. Existing incoming holds on surviving locations retain their relationship state.','Validated definitions restore the same effective properties and behaviour.'])+ref_list(['STATE-001','STATE-003','CHAR-004','PLAYER-002','LIMB-009'])+'</details>'
    switch=''
    if c['id']=='recovery': switch='<div class="rebuild-switch" aria-label="Reconstruction result"><button type="button" data-rebuild="split" aria-pressed="'+str(result=='split').lower()+'">Split result</button><button type="button" data-rebuild="death" aria-pressed="'+str(result=='death').lower()+'">Death result</button></div>'
    def step_link(href,label,destination,cls,rel):
        return '<a class="'+cls+'" href="'+href+'" rel="'+rel+'" aria-label="'+esc(label+': '+destination)+'"><span class="pager-label">'+esc(label)+'</span><span class="pager-destination">'+esc(destination)+'</span></a>'
    previous=step_link('#walkthrough/'+book['cases'][index-1]['id'],'Previous',book['cases'][index-1]['title'],'pager-previous','prev') if index else ''
    next_link=step_link('#walkthrough/'+book['cases'][index+1]['id'],'Next',book['cases'][index+1]['title'],'pager-next','next') if index<len(book['cases'])-1 else step_link('#work/overview','Start work','First shared milestone','pager-next','next')
    controls=previous+next_link
    heading='<div class="step-top"><div class="step-heading"><h1>'+esc(c['title'])+'</h1><span class="step-number">Step '+str(index+1)+' of '+str(len(book['cases']))+'</span></div><nav class="pager pager-top" aria-label="Walkthrough navigation">'+controls+'</nav></div>'
    return heading+switch+'<div class="walk-canvas"><figure class="scene-figure"><div class="scene-diagram" tabindex="0" role="region" aria-label="Scene diagram">'+scenes[scene]['svg']+'</div><figcaption>'+caption+'</figcaption></figure><div class="explanation"><p>'+inline(intro)+'</p><p class="consequence">'+inline(notice)+'</p>'+list_html(facts)+'</div></div>'+details+'<nav class="pager pager-bottom" aria-label="Walkthrough navigation at end of step">'+controls+'</nav>'

case_pages={c['id']:walk_page(c) for c in book['cases']}
recovery_pages={scene:walk_page(book['cases'][-1],scene) for scene in ['split','death']}
task_map={t['id']:t for t in book['tasks']}
first_tasks={'simulation':'UNITY-01','assets':'ASSET-01','level':'LEVEL-01','networking':'NET-01','shared':'SHARED-01'}
first_starts={
'UNITY-01':'Begin the loader with hand-authored wall, platform, Claymate and bomb inputs. Agree the prototype import contract with authoring, then consume the shared asset and level outputs. Derive the bond from its paired attachment regions.',
'ASSET-01':'Author one platform section. Declare its 2D silhouette and origin, align its appearance, and select a material with explicit density and independent blast resistance, plus an independently selected destruction response.',
'LEVEL-01':'Lay out the wall, platform and bond now. Mark attachment regions in each endpoint’s local space, and include a Claymate spawn and bomb configuration. Integrate the shared platform asset and exchange conventions as they become available.',
'NET-01':'Agree intent, committed-result and current-state recovery interfaces with Unity integration. Mock them against the same fixture while the simulation path develops.',
'SHARED-01':task_map['SHARED-01']['start']
}
def task_page(t,include_followups=False):
    id=t['id']
    intro='<p class="work-role">'+esc(role_names[t['role']])+' · <code>'+esc(id)+'</code></p><h1>'+esc(t['title'])+'</h1>'
    if id=='NET-01': intro+='<p>Networking is deferred for the immediate handoff. When it resumes, use the same scene and recovery boundary.</p>'
    start=first_starts.get(id,t['start'])
    out=intro+'<p class="delivery"><strong>Deliver:</strong> '+inline(t['deliverable'])+'</p><p class="first-action">'+inline(start)+'</p>'
    if id=='ASSET-01': out+='<p class="parallel-work">Begin <a href="#work/CHARACTER-01">character-definition inputs</a> alongside the platform. The hold and death checks will need them.</p>'
    if id=='SHARED-01':
        out+=table(['Convention','Record for the fixture','Coordinating roles'],[[c['title'],c['prompt'],c['roles']] for c in book['choices']],'choice-table')
    else:
        out+='<section class="work-inputs"><h2>Inputs</h2>'+list_html(t['inputs'])+'</section>'
    out+='<section class="completion"><h2>Done when</h2>'+list_html(t['checks'])+'</section>'
    if t['dependencies']:
        out+='<p class="task-dependencies">Before the integrated delivery: '+', '.join('<a href="#work/'+esc(dep)+'">'+esc(task_map[dep]['title'])+'</a>' for dep in t['dependencies'])+'.</p>'
    out+='<details class="work-details"><summary>Implementation steps and remaining choices</summary>'+list_html(t['steps'],'ol')+'<h2>Remaining choices</h2><p>'+inline(t['open'])+'</p>'+ref_list(t['refs'])+'</details>'
    if include_followups:
        later=[x for x in book['tasks'] if x['role']==t['role'] and x['id']!=id]
        if later:
            out+='<details class="work-order"><summary>'+('Subsequent simulation checks' if t['role']=='simulation' else 'Additional authoring delivery')+'</summary><ul class="followup-list">'+''.join('<li><a href="#work/'+x['id']+'">'+esc(x['title'])+'</a><p>'+inline(x['deliverable'])+'</p></li>' for x in later)+'</ul></details>'
        out+='<p class="work-return"><a href="#work/overview">First shared milestone</a></p>'
    return out
task_pages={t['id']:task_page(t) for t in book['tasks']}
role_pages={role:task_page(task_map[id],True) for role,id in first_tasks.items()}
implementation=book['implementation']
work_overview='<h1>'+esc(implementation['title'])+'</h1><p class="delivery">'+inline(implementation['goal'])+'</p><h2>Begin with the shared platform</h2><p class="body-text">'+inline(implementation['begin'])+' <a href="#work/shared">Record the exchange conventions.</a></p>'
work_overview+=table(['Role','First delivery'],[['[ROLE:'+x['role']+']',x['deliverable']] for x in implementation['contributions']],'milestone-table')
work_overview=re.sub(r'\[ROLE:([^\]]+)\]',lambda m:'<a href="#work/'+esc(m[1])+'">'+esc(role_names[m[1]])+'</a>',work_overview)
work_overview+='<section class="completion"><h2>Shared completion check</h2>'+list_html(implementation['checks'])+'</section><p class="body-text">Networking resumes against this same capture and reconstruction boundary. <a href="#work/networking">Networking delivery.</a></p>'
work_overview+='<details class="work-order"><summary>Checks after reconstruction</summary><ul class="followup-list">'+''.join('<li><a href="#work/'+id+'">'+esc(task_map[id]['title'])+'</a><p>'+inline(description)+'</p></li>' for id,description in implementation['followups'])+'</ul></details>'
source_data={name:{'name':name,'version':re.search(r'\*\*Version:\*\* (\S+)',text)[1],'markdown':text,'html':md(text),'sha256':hashlib.sha256(text.encode()).hexdigest()} for name,text in sources.items()}
signature=hashlib.sha256((json.dumps(book,sort_keys=True,ensure_ascii=False)+''.join(sources.values())).encode()).hexdigest()
data={**book,'baseline':baseline,'sourceHash':signature,'rules':rules,'entries':entries,'records':records,'sources':source_data,'scenes':scenes,'roleNames':role_names,'recordTopics':record_topics,'topicPages':topic_pages,'recordPages':record_pages,'casePages':case_pages,'recoveryPages':recovery_pages,'taskPages':task_pages,'rolePages':role_pages,'workOverview':work_overview}
initial_nav=''.join('<a href="#walkthrough/'+c['id']+'"'+(' aria-current="page"' if i==0 else '')+'>'+esc(c['short'])+'</a>' for i,c in enumerate(book['cases']))
initial_options=''.join('<option value="#walkthrough/'+c['id']+'">'+esc(c['short'])+'</option>' for c in book['cases'])
replacements={'@@BASELINE@@':esc(baseline),'@@VERSION@@':book['version'],'@@STYLE@@':(ROOT/'style.css').read_text(),'@@SCRIPT@@':(ROOT/'app.js').read_text(),'@@INITIAL_NAV@@':initial_nav,'@@INITIAL_OPTIONS@@':initial_options,'@@INITIAL_PAGE@@':case_pages[book['cases'][0]['id']],'@@NOSCRIPT@@':topic_pages['bodies']+topic_pages['relationships']+work_overview+''.join(role_pages.values()),'@@DATA@@':json.dumps(data,ensure_ascii=False).replace('<','\\u003c')}
page=(ROOT/'template.html').read_text()
for key,value in replacements.items(): page=page.replace(key,value)
assert '@@' not in page
(OUT/'index.html').write_text(page)
(OUT/'BOM-Team-Handbook.html').write_text(page)
(OUT/'handbook-data.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
parts=['# BOM — Simulation model',f'**Handbook:** {book["version"]}  \n**Date:** {book["date"]}  \n**Baseline:** {baseline}','## Walkthrough']
for c in book['cases']:
    parts+=['### '+c['title'],c['intro'],c['notice'], '\n'.join('- '+s for s in c['facts']),'| Concern | Outcome |\n|---|---|\n'+'\n'.join('| '+a+' | '+b+' |' for a,b in c['changes']),'Rules: '+', '.join(id for id in c['refs']),c['caveat']]
parts+=['## Body and relationship reference',map_text[map_text.index('## 1.'):map_text.index('## 9.')], '## Implementation deliveries','### '+implementation['title'],implementation['goal'],implementation['begin'],'| Role | First delivery |\n|---|---|\n'+'\n'.join('| '+role_names[x['role']]+' | '+x['deliverable']+' |' for x in implementation['contributions']),'**Shared completion check**\n\n'+'\n'.join('- '+x for x in implementation['checks']),'### Exchange conventions','| Convention | Record for the fixture | Coordinating roles |\n|---|---|---|\n'+'\n'.join('| '+c['title']+' | '+c['prompt']+' | '+c['roles']+' |' for c in book['choices'])]
for role in book['roleOrder']:
    parts+=['### '+role_names[role]]
    tasks=[task_map[first_tasks[role]]]+[t for t in book['tasks'] if t['role']==role and t['id']!=first_tasks[role]]
    for t in tasks:
        parts+=['#### '+t['id']+' — '+t['title'],'**Deliver:** '+t['deliverable'],first_starts.get(t['id'],t['start']),'**Inputs**\n\n'+'\n'.join('- '+x for x in t['inputs']),'**Done when**\n\n'+'\n'.join('- '+x for x in t['checks']),'**Remaining choices:** '+t['open'],'Rules: '+', '.join(t['refs'])]
(OUT/'BOM-Team-Handbook.md').write_text('\n\n'.join(parts)+'\n')
print(json.dumps({'baseline':baseline,'rules':len(rules),'records':len(records),'cases':len(book['cases']),'deliveries':len(book['tasks']),'version':book['version'],'bytes':len(page.encode())}))
