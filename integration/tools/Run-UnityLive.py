"""Own-process Unity gate with readiness-synchronized native host controls."""
import argparse,datetime,hashlib,json,os,pathlib,re,secrets,socket,subprocess,sys,time

p=argparse.ArgumentParser()
p.add_argument('--seconds',type=int,default=24);p.add_argument('--capture',action='store_true');p.add_argument('--config');p.add_argument('--player');p.add_argument('--editor',action='store_true');p.add_argument('--two-unity',action='store_true');p.add_argument('--host-runner');p.add_argument('--time-scale',type=float,default=1);p.add_argument('--prediction-off',action='store_true')
a=p.parse_args()
if not 1<=a.seconds<=3600:raise SystemExit('seconds must be 1..3600')
if a.capture and (a.two_unity or a.editor):raise SystemExit('capture is a separate single-player gate')
w=pathlib.Path(__file__).resolve().parent
if (w/'integration-stage/tools').is_dir():sys.path.insert(0,str(w/'integration-stage/tools'))
from hash_coverage import analyze
config=json.loads(pathlib.Path(a.config).read_text(encoding='utf-8-sig')) if a.config else {}
r=pathlib.Path(config.get('OdinRoot',w/'odin-source/BOM'))
player=pathlib.Path(a.player or config.get('UnitySlicePlayer',w/'unity-slice-player/BombNativeSlice.exe')).resolve()
host=pathlib.Path(a.host_runner or config.get('UnityHostRunner',r/'build/interop-unity/Interop.dll')).resolve()
evidence=pathlib.Path(a.config).resolve().parent/'evidence/M4' if a.config else w
out=evidence/('unity-live-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'));out.mkdir(parents=True)
if a.editor:a.seconds=max(a.seconds,100)
signal=out/'start.signal'
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
token=secrets.token_urlsafe(24);host_env=os.environ.copy();host_env['BOM_TEST_HOST_TOKEN']=token
guest_env=os.environ.copy();guest_env.pop('BOM_TEST_HOST_TOKEN',None)
if not a.editor:host_env['BOM_HOST_SIGNAL_FILE']=str(signal)
commands={
 'server':[str(r/'build/BOM-server.exe'),'--port',str(port),'--seconds',str(a.seconds+180),'--host-token',token],
 'host':['dotnet',str(host),str(port),str(a.seconds+10),str(15 if a.two_unity else 5),'single'],
 'unity':[str(player),'-batchmode','-force-d3d11','-screen-fullscreen','0','-screen-width','1280','-screen-height','720','--bom-port',str(port),'--bom-smoke-seconds',str(0 if a.capture else a.seconds),'--bom-smoke-start-file',str(signal),'--bom-time-scale',str(a.time_scale),'-logFile',str(out/'unity.log')],
 'observer':[str(r/'build/BOM.exe'),'--bot-client',f'127.0.0.1:{port}','--seconds',str(a.seconds)]}
if a.capture:commands['unity']+=['--bom-capture',str(out/'scene.png')]
if a.editor:commands['unity']=[config['UnityEditor'],'-batchmode','-projectPath',config['UnityValidationProject'],'-executeMethod','BomEditorLifecycle.Run','--bom-port',str(port),'-logFile',str(out/'unity.log')]
if a.prediction_off and not a.editor:commands['unity']+=['--bom-prediction-off']
if a.two_unity:
 commands['unity-late']=list(commands['unity']);commands['unity-late'][commands['unity-late'].index('-logFile')+1]=str(out/'unity-late.log')
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
processes={};streams={};codes={};failure=''
def read(path):return path.read_text(errors='replace') if path.exists() else ''
def launch(name):
 streams[name]=(out/(name+'-stdout.log')).open('w')
 processes[name]=subprocess.Popen(commands[name],env=host_env if name=='host' else guest_env,stdout=streams[name],stderr=subprocess.STDOUT,cwd=r,startupinfo=startup)
 time.sleep(.2)
def ready(name):
 log=out/(name+'.log');deadline=time.monotonic()+100
 while time.monotonic()<deadline:
  if 'BOM UNITY SNAPSHOT' in read(log):return
  if processes[name].poll() is not None:raise RuntimeError(name+' exited before receiving a usable snapshot')
  if processes['host'].poll() is not None:raise RuntimeError('native test host exited during Unity startup')
  time.sleep(.1)
 raise TimeoutError(name+' did not receive a usable snapshot within 100 seconds')
try:
 launch('server');launch('host');launch('unity')
 if not a.editor:
  ready('unity')
  if a.two_unity:time.sleep(5);launch('unity-late');ready('unity-late')
 launch('observer')
 signal.write_text('start\n')
 deadline=time.monotonic()+a.seconds+70
 for name in ['unity']+(['unity-late'] if a.two_unity else [])+['observer','host','server']:
  codes[name]=processes[name].wait(timeout=max(1,deadline-time.monotonic()))
except Exception as error:failure=str(error)
finally:
 for name,child in processes.items():
  if child.poll() is None:child.kill();child.wait()
  codes.setdefault(name,child.returncode)
 for stream in streams.values():stream.close()
server=read(out/'server-stdout.log');unity=read(out/'unity.log')
match=re.search(r'SERVER final hashes=(\d+) mismatches=(\d+) unrecorded=(\d+)',server)
marker='BOM EDITOR LIFECYCLE PASS' if a.editor else 'BOM UNITY SNAPSHOT' if a.capture else 'BOM UNITY LIVE PASS'
coverage=analyze(server);(out/'hash-coverage.json').write_text(json.dumps(coverage,indent=2))
passed=not failure and all(code==0 for code in codes.values()) and match and int(match[1])>0 and match[2]=='0' and match[3]=='0' and marker in unity and coverage['status']=='passed'
if a.two_unity:passed=passed and 'BOM UNITY LIVE PASS' in read(out/'unity-late.log')
identity=re.search(r'Native (\d+) / protocol (\d+)',unity)
plugin=pathlib.Path(config['UnityValidationProject'])/'Assets/BOMIntegration/Plugins/x86_64/bomcore.dll' if a.editor else next(player.parent.rglob('bomcore.dll'))
report={'status':'passed' if passed else 'failed','seconds_after_readiness':a.seconds,'capture_only':a.capture,'two_unity':a.two_unity,'time_scale':a.time_scale,'failure':failure,'exit_codes':codes,'hash_checks':int(match[1]) if match else None,'hash_mismatches':int(match[2]) if match else None,'hash_coverage':'hash-coverage.json','unity_native_tag':identity[1] if identity else None,'unity_plugin_sha256':hashlib.sha256(plugin.read_bytes()).hexdigest(),'commands':{name:[arg if arg!=token else '[REDACTED]' for arg in command] for name,command in commands.items()}}
(out/'summary.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k!='commands'}));print('Evidence: '+str(out));raise SystemExit(0 if passed else 1)
