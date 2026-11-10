"""Two standalone Unity clients, one native host, one Odin round observer."""
import argparse,datetime,hashlib,json,os,pathlib,re,secrets,shutil,socket,subprocess,time
from hash_coverage import analyze
p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--layout',required=True);p.add_argument('--player',required=True);p.add_argument('--draw',action='store_true');p.add_argument('--evidence-stage',choices=['M8','M9'],default='M8');a=p.parse_args()
cfg=pathlib.Path(a.config).resolve();config=json.loads(cfg.read_text(encoding='utf-8-sig'));root=pathlib.Path(config['OdinRoot']);layout=pathlib.Path(a.layout).resolve();player=pathlib.Path(a.player).resolve()
identity=json.loads((root/'build/bomcore.build.json').read_text(encoding='utf-8-sig'))
plugin=next(player.parent.rglob('bomcore.dll'))
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
if sha(plugin)!=identity['dll_sha256']:raise SystemExit('Player native library differs from the current manifest')
host=root/'build/interop-rounds/Interop.dll';shutil.copy2(root/'build/bomcore.dll',host.parent/'bomcore.dll')
out=cfg.parent/'evidence'/a.evidence_stage/('unity-rounds-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'));out.mkdir(parents=True)
shutil.copy2(layout,out/'layout-input.json');layout=out/'layout-input.json'
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
token=secrets.token_urlsafe(24);env=os.environ.copy();env.update(BOM_TEST_HOST_TOKEN=token,BOM_TEST_UNITY_ROUNDS='1',BOM_ROUND_SIGNAL_DIR=str(out),BOM_EXPECT_BUILD_TAG=str(identity['build_tag']))
env['BOM_ROUND_EXPECT_DRAW']='1' if a.draw else '0'
guest_env=os.environ.copy();guest_env.pop('BOM_TEST_HOST_TOKEN',None)
commands={'server':[str(root/'build/BOM-server.exe'),'--port',str(port),'--layout',str(layout),'--seconds','290','--host-token',token],
 'host':['dotnet',str(host),str(port),'240'],
 'observer':[str(root/'build/BOM.exe'),'--bot-client',f'127.0.0.1:{port}','--seconds','200','--spectator','--observe-rounds','2','--prediction-off']}
for role in ['primary','guest']:
 commands[role]=[str(player),'-batchmode','-force-d3d11','-screen-fullscreen','0','-screen-width','1280','-screen-height','720','--bom-prediction-off','--bom-port',str(port),'--bom-round-test',str(out/role),'--bom-round-role',role,'-logFile',str(out/(role+'.log'))]
 if a.draw:commands[role]+=['--bom-round-draw']
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
children={};streams={};codes={};failure=''
def read(path):return path.read_text(encoding='utf-8',errors='replace') if path.exists() else ''
def launch(name):
 streams[name]=(out/(name+'-stdout.log')).open('w',encoding='utf-8')
 children[name]=subprocess.Popen(commands[name],cwd=root,stdout=streams[name],stderr=subprocess.STDOUT,env=env if name=='host' else guest_env,startupinfo=startup)
def wait_for(name,path,needle,seconds):
 deadline=time.monotonic()+seconds
 while needle not in read(path):
  if children[name].poll() is not None:raise RuntimeError(name+' exited before '+needle)
  if time.monotonic()>deadline:raise TimeoutError(name+' did not produce '+needle)
  time.sleep(.1)
try:
 launch('server');wait_for('server',out/'server-stdout.log','BOM staging server listening',30)
 launch('host');wait_for('host',out/'host-stdout.log','ROUND HOST',30)
 launch('primary');launch('guest')
 wait_for('host',out/'host-stdout.log','state=2',180);launch('observer')
 deadline=time.monotonic()+180
 for name in ['primary','guest','host','observer','server']:codes[name]=children[name].wait(timeout=max(1,deadline-time.monotonic()))
except Exception as exc:failure=str(exc).replace(token,'[REDACTED]')
finally:
 for name,child in children.items():
  if child.poll() is None:child.kill();child.wait()
  codes.setdefault(name,child.returncode)
 for stream in streams.values():stream.close()
coverage=analyze(read(out/'server-stdout.log'));(out/'hash-coverage.json').write_text(json.dumps(coverage,indent=2))
states={name:re.findall(r'BOM ROUND UNITY role=\w+ round=(\d+) state=(\d+) tick=(\d+) winner=(\d+) draw=(\d+)',read(out/(name+'.log'))) for name in ['primary','guest']}
results={name:{(int(row[0]),int(row[3]),int(row[4])) for row in rows if row[1]=='3'} for name,rows in states.items()}
observer_results={(int(i),int(w),1 if draw=='true' else 0) for i,w,draw in re.findall(r'ROUND SNAPSHOT id=(\d+) epoch=\d+ state=Finished tick=\d+ winner=(\d+) draw=(true|false)',read(out/'observer-stdout.log'))}
agreed=results['primary']==results['guest']==observer_results and len(observer_results)==2
captures=all((out/(role+'-'+phase+'.png')).exists() for role in ['primary','guest'] for phase in ['menu','sandbox','disconnected'])
capture_check=subprocess.run(['pwsh','-NoProfile','-File',str(pathlib.Path(__file__).with_name('Test-RenderCaptures.ps1')),'-Directory',str(out),'-ReportPath',str(out/'render-capture-check.json')],capture_output=True,text=True)
captures=captures and capture_check.returncode==0
passed=not failure and len(codes)==5 and all(code==0 for code in codes.values()) and agreed and captures and coverage['status']=='passed' and all('BOM ROUND UNITY PASS' in read(out/(role+'.log')) for role in ['primary','guest'])
summary={'status':'passed' if passed else 'failed','scope':'two Unity menu/art clients, native host and independent Odin observer across two elimination rounds; additional M8 draw/event/visual acceptance gates remain separately required',
 'failure':failure,'exit_codes':codes,'results_agreed':agreed,'result_rows':{k:[list(row) for row in sorted(v)] for k,v in results.items()},'observer_results':[list(row) for row in sorted(observer_results)],'menu_art_disconnect_captures':captures,'hash_coverage':coverage,
 'prediction_mode':'off for the round/presentation gate; prediction profiles and dynamic-yard performance remain separate M9 requirements','fixture':'same-tick falling-bomb draw' if a.draw else 'preserved yard forfeit',
 'native_identity':identity,'player_sha256':sha(player),'plugin_sha256':sha(plugin),'runtime_sha256':sha(player.parent/'GameAssembly.dll' if (player.parent/'GameAssembly.dll').exists() else player.parent/(player.stem+'_Data')/'Managed/Bom.Unity.Runtime.dll'),
 'server_sha256':sha(root/'build/BOM-server.exe'),'observer_sha256':sha(root/'build/BOM.exe'),
 'commands':{k:[v if v!=token else '[REDACTED]' for v in command] for k,command in commands.items()}}
(out/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps({k:v for k,v in summary.items() if k not in ['commands','native_identity','hash_coverage']}));print('Evidence: '+str(out));raise SystemExit(0 if passed else 1)
