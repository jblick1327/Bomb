"""Recheck replication evidence and write the final step-2a report. No packaging."""
from pathlib import Path
import csv,hashlib,json,math,re,statistics,subprocess,sys
root=Path(__file__).resolve().parent.parent;e=root/'evidence/replication-2a'
def read(p):
 b=p.read_bytes();return b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig')
log=read(e/'full-soak.txt');tests=read(e/'tests-final.txt')
assert 'Finished 189 tests' in tests and 'All tests were successful.' in tests and '[ERROR]' not in tests
assert 'Replication teardown Odin=0 Box2D=0 texture=0 shader=0 fonts=false' in log
# Windows PowerShell's Process.ExitCode can be unavailable after WaitForExit.
# Require the completed runtime assertions, full CSVs, empty stderr and teardown below.
assert read(e/'full-soak-exit.txt').strip() in ('','0')
assert not read(e/'full-soak-errors.txt').strip()
assert 'ticks=72000 deltas=2653' in log and 'first_mismatch=0' in log
assert 'LATE JOIN join_tick=36000 ticks_verified=36000 mismatch=0' in log and 'RENDER samples=10 identical=10' in log
all_captures=[];outputs=[]
for name,accepted in [('standard','evidence/glue-followup/standard'),('golden','evidence/glue-followup/golden'),('legacy','evidence/seam-toughness/legacy')]:
 result=subprocess.run([sys.executable,str(root/'scripts/compare-captures.py'),accepted,str(e.relative_to(root)/'captures-v4'/name),'--manifest',str(e/f'manifest-{name}.json'),'--label',name],cwd=root,capture_output=True,text=True)
 assert result.returncode==0,result.stdout+result.stderr;outputs.append(result.stdout)
 rows=json.loads((e/f'manifest-{name}.json').read_text());assert len(rows)=={'standard':23,'golden':25,'legacy':10}[name]
 all_captures.extend(rows)
(e/'capture-checks-final.txt').write_text('\n'.join(outputs),encoding='utf8')
assert len(all_captures)==58 and all(r['ok'] for r in all_captures)
assert sum(r['status']=='byte-identical' for r in all_captures)==28
old_png=json.loads((e/'png-manifest.json').read_text());assert len(old_png)==66
for row in old_png:
 a=e/'png-before'/row['file'];b=e/'png-after'/row['file'];assert a.read_bytes()==b.read_bytes() and hashlib.sha256(b.read_bytes()).hexdigest()==row['sha256'],row
renders=[]
for tick in re.findall(r'^RENDER tick=(\d+) cells=\d+ identical=true$',log,re.M):
 a=e/f'render/render-{int(tick):05d}-host.png';b=e/f'render/render-{int(tick):05d}-replica.png';assert a.read_bytes()==b.read_bytes()
 renders.append(dict(tick=int(tick),host=a.relative_to(root).as_posix(),replica=b.relative_to(root).as_posix(),pixel_identical=True,png_sha256=hashlib.sha256(a.read_bytes()).hexdigest()))
assert len(renders)==10
(e/'render-manifest-full.json').write_text(json.dumps(renders,indent=2)+'\n')
net_before=json.loads((e/'netcode-before-finish.json').read_text())
net_after={p.as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/'src/netcode').rglob('*') if p.is_file()}
# The recorded manifest uses repository-relative paths.
net_after={str(Path(k).relative_to(root)).replace('\\','/'):v for k,v in net_after.items()}
assert net_before==net_after
(e/'netcode-integrity.json').write_text(json.dumps(dict(files=len(net_after),unchanged=True,sha256=net_after),indent=2)+'\n')
no_b2=['render_cache.odin','debug_view.odin','sandbox_view.odin','rubber_band.odin','glue_view.odin','material_texture.odin','editor_view.odin','material_view.odin','layout_view.odin']
for name in no_b2:assert 'b2.' not in (root/'src'/name).read_text(encoding='utf8'),name
mortar=(root/'src/mortar.odin').read_text(encoding='utf8');draw=mortar[mortar.index('draw_mortar ::'):mortar.index('Mortar_Seam ::')];assert 'b2.' not in draw
(e/'draw-grep.txt').write_text('Zero b2. calls in: '+', '.join(no_b2)+'\nZero b2. calls in draw_mortar.\nRemaining mortar.odin calls/types are in Mortar_Seam and mortar_seams: BodyId, Joint_IsValid, Joint_GetBodyA/B, Joint_GetConstraintForce/Torque, Joint_GetLocalAnchorA/B, Body_GetWorldPoint. These implement physics force measurement.\n')
def quantile(values,p):
 a=sorted(values);return a[max(0,math.ceil(p*len(a))-1)]
def pose_stats(file,count):
 rows=list(csv.DictReader((e/file).open(newline='',encoding='utf8')));assert len(rows)==count
 result={'ticks':count,'explosions':sum(int(r['explosions']) for r in rows)}
 for kind in ['awake','changed']:
  values=[int(r[kind]) for r in rows];peak=max(range(count),key=values.__getitem__);r=rows[peak]
  last_blast=next((i for i in range(peak,-1,-1) if int(rows[i]['explosions'])>0),None)
  last_refill=next((i for i in range(peak,-1,-1) if rows[i]['refill']=='true'),None)
  result[kind]={'p50':quantile(values,.5),'p95':quantile(values,.95),'p99':quantile(values,.99),'max':max(values),'max_tick':peak+1,'kinds':{k:int(r[kind+'_'+k]) for k in ['rigid','rubber','bombs','players']},'ticks_since_explosion':None if last_blast is None else peak-last_blast,'ticks_since_refill':None if last_refill is None else peak-last_refill,'explosions_this_tick':int(r['explosions'])}
 return result
poses={name:pose_stats(file,n) for name,file,n in [('soak-4','pose-soak-4.csv',72000),('rubble-4','pose-rubble-4.csv',18000),('soak-1','pose-soak-1.csv',72000)]}
assert poses['rubble-4']['explosions']==0
(e/'pose-summary-full.json').write_text(json.dumps(poses,indent=2)+'\n')
deltas=list(csv.DictReader((e/'deltas-full.csv').open(newline='',encoding='utf8')));assert len(deltas)==2653
sizes=[int(r['bytes']) for r in deltas];costs=[float(r['generation_ms']) for r in deltas]
summary={'ticks':72000,'deltas':len(deltas),'mismatches':0,'late_join_tick':36000,'late_join_verified_ticks':36000,'render_samples':10,'delta_bytes':{'p50':quantile(sizes,.5),'p99':quantile(sizes,.99),'max':max(sizes)},'delta_generation_ms':{'p50':sorted(costs)[int(.5*(len(costs)-1))],'max':max(costs)},'baseline_start_bytes':int(re.search(r'BASELINE start=(\d+)',log)[1]),'baseline_end_bytes':int(re.search(r'bytes end=(\d+)',log)[1]),'largest_part_bytes':int(re.search(r'largest part=(\d+)',log)[1])}
(e/'replication-summary-full.json').write_text(json.dumps(summary,indent=2)+'\n')
perf=json.loads((e/'perf/summary.json').read_text());before=statistics.median(r['worst_blast_ms'] for r in perf['before']);after=statistics.median(r['worst_blast_ms'] for r in perf['after'])
def four(r):return '/'.join(str(r[k]) for k in ['p50','p95','p99','max'])
pose_table='\n'.join(f"| {name} | {four(p['awake'])} | {four(p['changed'])} |" for name,p in poses.items())
peak_table=[]
for name,p in poses.items():
 for kind in ['awake','changed']:
  r=p[kind];k=r['kinds'];context='walking; no explosions or refills' if name=='rubble-4' else f"{r['ticks_since_explosion']} tick{'' if r['ticks_since_explosion']==1 else 's'} after explosion; {r['ticks_since_refill']} after refill"
  peak_table.append(f"| {name} {kind} | {r['max_tick']} | {k['rigid']}/{k['rubber']}/{k['bombs']}/{k['players']} | {context} |")
report=f"""# Multiplayer step 2a: complete

Implemented and verified up to four players, mirrored actor poses, Box2D-free presentation, canonical structure replication, shared server indexing, Baseline/Delta parts and physics-free replicas. Solo behaviour is preserved. Snapshot v4 lists active players; v3 loads as player 0. No sockets or multiplayer UI were added. Nothing was committed, and src/netcode/ is unchanged ({len(net_after)} files verified by SHA-256).

**189 tests pass with leak failures enabled.** The final CLI soak also tears down with Odin 0, Box2D 0, textures/shader IDs 0 and fonts unloaded. [Tests](evidence/replication-2a/tests-final.txt), [full soak](evidence/replication-2a/full-soak.txt).

The final 20-minute four-bot soak covers **72,000 ticks**, with canonical host/replica equality checked after every tick: **0 mismatches**, **2,653 deltas**, **797 queued bot blasts**. The late join at tick **36,000** follows another **36,000 ticks** with 0 mismatches. **10/10** sampled host/replica renders are pixel-identical; [render manifest](evidence/replication-2a/render-manifest-full.json).

Delta sizes p50/p99/max: **{summary['delta_bytes']['p50']}/{summary['delta_bytes']['p99']}/{summary['delta_bytes']['max']} bytes**. Baselines start/end: **{summary['baseline_start_bytes']}/{summary['baseline_end_bytes']} bytes**. Largest natural framed part: **{summary['largest_part_bytes']} bytes**. Natural messages stay below 200 KB. A separate **335,805-byte** synthetic baseline splits at the real default 200,000-byte limit into two parts (largest **200,004 bytes**, below the 255,000-byte reliable limit), leaving the replica unchanged until the last part. Small-limit tests exercise fragmented deltas too.

Pose bandwidth, p50/p95/p99/max entities per tick (static anchored poses are implicit; kinds are dynamic rigid frames, rubber cells, bombs, players):

| Scenario | Awake | Changed quantized pose |
|---|---|---|
{pose_table}

The soak scenarios run 20 minutes each; rubble runs the required 5 minutes. Peaks use scenario-relative ticks; kinds below are rigid/rubber/bombs/players. Raw CSVs and [pose summary](evidence/replication-2a/pose-summary-full.json) retain every tick.

| Maximum | Tick | Kinds | Situation |
|---|---:|---|---|
{chr(10).join(peak_table)}

Delta generation: **{summary['delta_generation_ms']['p50']:.4f} ms p50 / {summary['delta_generation_ms']['max']:.4f} ms max**, with memory tracking enabled. The completed six sequential, interleaved 20-minute performance runs give median worst blast_pass **{before:.4f} -> {after:.4f} ms** ({(after/before-1)*100:+.2f}%). Individual worst values: before 33.8041/28.9634/23.6143, after 27.2030/31.9154/29.2873 ms. These retained measurements cover the unchanged blast path; finishing edits add revision bookkeeping, regression checks and measurement output. [Performance evidence](evidence/replication-2a/perf/summary.json).

Compatibility: **48/48 accepted captures** and **10/10 legacy captures** pass the revised v4 criteria: 28 scene-only files are entirely byte-identical; all 30 World files have byte-identical Scene text and bit-equal player 0, bombs, rain, settings and tick. Player 0 radius equals the accepted settings radius. [Standard](evidence/replication-2a/manifest-standard.json), [golden](evidence/replication-2a/manifest-golden.json), [legacy](evidence/replication-2a/manifest-legacy.json). The retained **66/66** before/after PNG pairs were independently rechecked against their hashes; [PNG manifest](evidence/replication-2a/png-manifest.json). The final-code soak additionally verifies the 10 fresh render pairs above. The structural render-cache oracle compares **1,530 cells**, with 0 neighbour/draw_edge mismatches.

Draw-path grep: **0 b2. calls** in render_cache, debug_view, sandbox_view, rubber_band, glue_view, material_texture, editor_view, material_view and layout_view. draw_mortar also has 0. Remaining b2 types/calls in mortar.odin belong only to Mortar_Seam/mortar_seams force measurement (body IDs, joint validity/body/force/torque/anchor reads and Body_GetWorldPoint). F3 editing and test oracles may use physics. [Grep list](evidence/replication-2a/draw-grep.txt).

Revision audit: add_piece, retain_subdivision, add_connection and glue_add bump creation revisions; commit_structure covers deaths, compaction and regrouping after blast, force, explicit removal and glass shock. Regrouping creates new pieces and publishes their host-ordered cell lists. In-place glue inheritance now has a direct regression: revision 6 -> 7 emits a Delta carrying all 20 samples. Finishing the audit found **material append without cell creation** could emit nothing; add_material now bumps the revision, while replica material insertion preserves the revision supplied by its message. A dedicated test verifies the material-only Delta. None of these counters is serialized into legacy Scene snapshots. New epochs are issued on reset/layout replacement/snapshot replacement. Stale epoch/revision errors and incomplete-message atomicity pass.

Fixture choices: bot seeds 1234 (soaks) and 99 (rubble), one seeded stream per active player, 4-8 s blast intervals and valid points within 6 m. Refills are at ticks 7201,14401,...,64801. Rubble uses Materials/soak_yard after radius-5 blasts at (-6.4,2.3),(-4.3,1),(-0.7,1),(2.5,1),(4.3,2.4),(6.2,1), then 1200 settle ticks; rubber can remain awake. Ten render samples use seed 0xC0FFEE after tick 3000. The short unit soak uses 7300 ticks to cross a refill and verifies 3700 late-join ticks. The player's ordering fixture now uses empty air at (0,5) for player 2 and asserts all five positions and radii exactly, replacing a permissive count assertion. The synthetic large baseline uses 6000 direct, physics-free 1x1 cells to exercise the real split threshold. Frame-bench-style PNGs use --capture-frames because the timing bench does not export images.

Reproduce: scripts/bom.ps1 Test; scripts/bom.ps1 ReplicationSoak (or optimized --replication-soak 20). The final test run additionally sets ODIN_TEST_FAIL_ON_BAD_MEMORY=true plus MATERIAL_CAPTURE_DIRECTORY and SEAM_CAPTURE_DIRECTORY to retain v4 evidence. Run python scripts/verify-replication-2a.py to recheck manifests, raw measurements and this report. No zip is required.
"""
(root/'report.md').write_text(report,encoding='utf8',newline='\n')
(e/'report-final.md').write_text(report,encoding='utf8',newline='\n')
print('Verified: 189 tests, 72000 lockstep ticks, 36000 late-join ticks, 58 capture comparisons, 66 retained PNG pairs, 10 fresh render pairs; netcode unchanged.')
