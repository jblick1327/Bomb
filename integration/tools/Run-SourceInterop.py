"""Real exported-yard gate: native host, two Unity players, Odin observer."""
import argparse,datetime,hashlib,json,os,pathlib,re,secrets,shutil,socket,subprocess,sys,time
from hash_coverage import analyze
p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--layout',required=True);p.add_argument('--player',required=True);p.add_argument('--seconds',type=int,default=30);p.add_argument('--no-visual-registry',action='store_true');p.add_argument('--tier1-late',action='store_true');p.add_argument('--invalidate-jobs',action='store_true');a=p.parse_args()
if not 15<=a.seconds<=120:raise SystemExit('seconds must be 15..120')
cfg=pathlib.Path(a.config).resolve();config=json.loads(cfg.read_text(encoding='utf-8-sig'));root=pathlib.Path(config['OdinRoot']);layout=pathlib.Path(a.layout).resolve();player=pathlib.Path(a.player).resolve()
report=json.loads(pathlib.Path(str(layout)+'.native-report.json').read_text(encoding='utf-8-sig'));expected=report['gameplay_manifest_hash']
identity=json.loads((root/'build/bomcore.build.json').read_text(encoding='utf-8-sig'));plugin=next(player.parent.rglob('bomcore.dll'));plugin_hash=hashlib.sha256(plugin.read_bytes()).hexdigest()
if plugin_hash!=identity['dll_sha256']:raise SystemExit('Player DLL differs from the current native build identity')
runtime_assembly=player.parent/(player.stem+'_Data')/'Managed/Bom.Unity.Runtime.dll';runtime_hash=hashlib.sha256(runtime_assembly.read_bytes()).hexdigest();player_hash=hashlib.sha256(player.read_bytes()).hexdigest()
out=cfg.parent/'evidence/M7'/('source-live-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'));out.mkdir(parents=True)
shutil.copy2(layout,out/'layout-input.json');shutil.copy2(pathlib.Path(str(layout)+'.native-report.json'),out/'layout-native-report.json');layout=out/'layout-input.json'
server_hash=hashlib.sha256((root/'build/BOM-server.exe').read_bytes()).hexdigest();observer_hash=hashlib.sha256((root/'build/BOM.exe').read_bytes()).hexdigest()
start=out/'start.signal';late=out/'late.signal';stop=out/'stop.signal';render=out/'render.signal';requirements=json.loads(pathlib.Path(str(pathlib.Path(a.layout).resolve())+'.requirements.json').read_text(encoding='utf-8-sig'));required=[row for row in requirements['sources'] if row['expected']=='fragments']
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as reserve:reserve.bind(('127.0.0.1',0));port=reserve.getsockname()[1]
token=secrets.token_urlsafe(24);host_env=os.environ.copy();host_env.update(BOM_TEST_HOST_TOKEN=token,BOM_TEST_LEVEL_PROFILE='1',BOM_EXPECT_LEVEL_HASH=expected,BOM_LEVEL_START_FILE=str(start),BOM_LEVEL_LATE_READY_FILE=str(late),BOM_LEVEL_STOP_FILE=str(stop),BOM_EXPECT_BUILD_TAG=str(identity['build_tag']),BOM_EXPECT_SOURCE_COUNT=str(report['source_count']),BOM_EXPECT_MIN_CELLS=str(max(1,int(report['cell_count']*.8))),BOM_LEVEL_BLAST_X=str(requirements['blast_x']),BOM_LEVEL_BLAST_Y=str(requirements['blast_y']),BOM_LEVEL_EXTRA_BLASTS=json.dumps([[8,.5,4.2],[10,8.7,1],[11,3.5,2],[12,-8.5,7]]),BOM_LEVEL_RENDER_READY_FILE=str(render))
glue_sources=[int(row['source_id']) for row in requirements['sources'] if row['name'] in ['Glued source A','Glued source B']]
if glue_sources:host_env['BOM_EXPECT_GLUE_SOURCES']=json.dumps(glue_sources)
guest_env=os.environ.copy();guest_env.pop('BOM_TEST_HOST_TOKEN',None)
commands={
 'server':[str(root/'build/BOM-server.exe'),'--port',str(port),'--layout',str(layout),'--seconds',str(a.seconds+300),'--host-token',token],
 'host':['dotnet',str(root/'build/interop-source/Interop.dll'),str(port),str(a.seconds)],
 'unity':[str(player),'-batchmode','-force-d3d11','-screen-fullscreen','0','-screen-width','1280','-screen-height','720','--bom-port',str(port),'--bom-smoke-seconds','240','--bom-smoke-start-file',str(start),'--bom-smoke-stop-file',str(stop),'--bom-level-smoke','--bom-time-scale','0','--bom-expected-manifest',expected,'--bom-level-capture',str(out/'primary'),'--bom-source-failure-dir',str(out/'primary-failures'),'--bom-source-capture',str(out/'primary'),'-logFile',str(out/'unity.log')],
 'observer':[str(root/'build/BOM.exe'),'--bot-client',f'127.0.0.1:{port}','--seconds',str(a.seconds-1)]}
if a.no_visual_registry:commands['unity']+=['--bom-no-visual-registry']
commands['unity-late']=list(commands['unity']);commands['unity-late'][commands['unity-late'].index('-logFile')+1]=str(out/'unity-late.log');commands['unity-late'][commands['unity-late'].index('--bom-level-capture')+1]=str(out/'late');commands['unity-late'][commands['unity-late'].index('--bom-source-capture')+1]=str(out/'late');commands['unity-late'][commands['unity-late'].index('--bom-source-failure-dir')+1]=str(out/'late-failures')
if a.tier1_late:commands['unity-late']+=['--bom-tier1']
if a.invalidate_jobs:commands['unity']+=['--bom-source-job-gate',str(out/'release-jobs.signal')]
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
children={};streams={};codes={};failure=''
def read(path):return path.read_text(encoding='utf-8',errors='replace') if path.exists() else ''
def launch(name):
 streams[name]=(out/(name+'-stdout.log')).open('w',encoding='utf-8');children[name]=subprocess.Popen(commands[name],cwd=root,env=host_env if name=='host' else guest_env,stdout=streams[name],stderr=subprocess.STDOUT,startupinfo=startup)
def wait_for(name,path,text,seconds=120):
 deadline=time.monotonic()+seconds
 while time.monotonic()<deadline:
  if text in read(path):return
  if children[name].poll() is not None:raise RuntimeError(name+' exited before '+text)
  if children['server'].poll() is not None:raise RuntimeError('server exited during readiness')
  time.sleep(.1)
 raise TimeoutError(name+' did not report '+text)
try:
 launch('server');wait_for('server',out/'server-stdout.log','BOM staging server listening',180);launch('host');launch('unity')
 wait_for('host',out/'host-stdout.log','LEVEL HOST READY');wait_for('unity',out/'unity.log','BOM UNITY SNAPSHOT')
 start.write_text('start\n');wait_for('host',out/'host-stdout.log','LEVEL REQUEST kind=1 status=1',45)
 launch('unity-late');wait_for('unity-late',out/'unity-late.log','BOM UNITY SNAPSHOT');late.write_text('late ready\n');launch('observer')
 if a.invalidate_jobs:
  wait_for('unity',out/'unity.log','BOM SOURCE JOB GATE WAIT epoch=3 session=2',45)
  wait_for('unity',out/'unity.log','applies=0 epoch=3 session=2',20)
  render.write_text('reset while current-generation geometry workers are blocked\n')
  wait_for('unity',out/'unity.log','applies=0 epoch=4',30)
  (out/'release-jobs.signal').write_text('release fresh jobs\n')
 else:
  for row in required:
   for name in (['unity'] if a.tier1_late else ['unity','unity-late']):wait_for(name,out/(name+'.log'),'BOM SOURCE PRESENTATION source='+row['source_id']+' mode=fragments',min(100,a.seconds))
  render.write_text('all required source fixtures rendered through Tier 2\n')
 deadline=time.monotonic()+a.seconds+50
 for name in ['host','unity','unity-late','observer','server']:codes[name]=children[name].wait(timeout=max(1,deadline-time.monotonic()))
except Exception as error:failure=str(error).replace(token,'[REDACTED]')
finally:
 for name,child in children.items():
  if child.poll() is None:child.kill();child.wait()
  codes.setdefault(name,child.returncode)
 for stream in streams.values():stream.close()
coverage=analyze(read(out/'server-stdout.log'));(out/'hash-coverage.json').write_text(json.dumps(coverage,indent=2))
result=None
for line in read(out/'host-stdout.log').splitlines():
 if line.startswith('LEVEL_RESULT '):result=json.loads(line[len('LEVEL_RESULT '):])
first=re.search(r'BOM UNITY SNAPSHOT .*?revision=(\d+)',read(out/'unity.log'));late_first=re.search(r'BOM UNITY SNAPSHOT .*?revision=(\d+)',read(out/'unity-late.log'))
joined_fractured=bool(first and late_first and int(late_first.group(1))>int(first.group(1)))
unity_pass=all('BOM UNITY LIVE PASS' in read(out/(name+'.log')) for name in ['unity','unity-late'])
registry=all(('BOM VISUAL FALLBACK' if a.no_visual_registry else 'BOM REGISTRY MATCH') in read(out/(name+'.log')) for name in ['unity','unity-late'])
rendered=all(('BOM SOURCE PRESENTATION source='+row['source_id']+' mode=fragments') in read(out/(name+'.log')) for row in required for name in (['unity'] if a.tier1_late else ['unity','unity-late']))
captures=all((out/('primary-'+phase+'-'+angle+'.png')).exists() for phase in ['intact','fractured','moving','reset'] for angle in ['front','angle'])
tier1_verified=not a.tier1_late or 'BOM SOURCE ART OFF' in read(out/'unity-late.log')
stale_rows=re.findall(r'BOM SOURCE STALE DROP count=(\d+) applies=(\d+) epoch=(\d+) session=(\d+)',read(out/'unity.log'))
invalidation_verified=bool(stale_rows) and max(int(row[0]) for row in stale_rows)>=2 and all(int(row[1])==0 for row in stale_rows) and any(int(row[2])==4 for row in stale_rows) and 'BOM SOURCE JOB GATE WAIT epoch=3 session=2' in read(out/'unity.log') and (out/'primary-reset-front.png').exists()
visual_gate=invalidation_verified if a.invalidate_jobs else rendered and captures
passed=visual_gate and tier1_verified and not failure and all(c==0 for c in codes.values()) and result is not None and result['status']=='passed' and coverage.get('status')=='passed' and joined_fractured and unity_pass and registry
summary={'scope':'reset and disconnect during blocked geometry jobs' if a.invalidate_jobs else 'required Tier 2 fixtures and two-angle render captures','invalidate_jobs':a.invalidate_jobs,'invalidation_verified':invalidation_verified,'stale_rows':stale_rows,'status':'passed' if passed else 'failed','failure':failure,'seconds_after_late_readiness':a.seconds,'exit_codes':codes,'result':result,'joined_fractured':joined_fractured,'unity_pass':unity_pass,'runtime_registry_verified':registry,'required_tier2_fixtures':required,'required_rendered':rendered,'two_angle_captures':captures,'late_tier1':a.tier1_late,'tier1_verified':tier1_verified,'registry_mode':'missing lookup, visible native extrusion' if a.no_visual_registry else 'bundled direct mesh/material references','native_identity':identity,'plugin_sha256':plugin_hash,'runtime_assembly_sha256':runtime_hash,'player_sha256':player_hash,'server_sha256':server_hash,'observer_sha256':observer_hash,'expected_gameplay_manifest':expected,'commands':{name:[arg if arg!=token else '[REDACTED]' for arg in command] for name,command in commands.items()}}
(out/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in summary.items() if k not in ['commands','native_identity']}));print('Evidence: '+str(out));raise SystemExit(0 if passed else 1)
