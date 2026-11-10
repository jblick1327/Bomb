"""Measure real UDP/native/Unity work; keep raw results, never infer a passing gate."""
import argparse,datetime,hashlib,json,os,pathlib,secrets,shutil,socket,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--player',required=True);p.add_argument('--layout',required=True);p.add_argument('--scene',choices=['PerformanceReference','PerformanceStress'],default='PerformanceReference');p.add_argument('--seconds',type=int,default=60);p.add_argument('--warmup',type=int,default=10);p.add_argument('--backend',default='Mono');p.add_argument('--tier1',action='store_true');a=p.parse_args()
cfg=pathlib.Path(a.config).resolve();integration=cfg.parent;c=json.loads(cfg.read_text(encoding='utf-8-sig'));native=pathlib.Path(c['OdinRoot']);player=pathlib.Path(a.player).resolve()
out=integration/'evidence/M9'/('performance-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'));out.mkdir(parents=True)
layout=pathlib.Path(a.layout).resolve();shutil.copy2(layout,out/'layout.json')
shutil.copy2(native/'build/bomcore.dll',integration/'build/interop-performance-host/bomcore.dll')
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
plugin=next(player.parent.rglob('bomcore.dll'));assert sha(plugin)==sha(native/'build/bomcore.dll'),'Mismatched native plugin'
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
token=secrets.token_urlsafe(24);env=os.environ.copy();env['BOM_TEST_HOST_TOKEN']=token;env['BOM_PERF_STOP_FILE']=str(out/'host-stop.signal');guest=os.environ.copy();guest.pop('BOM_TEST_HOST_TOKEN',None)
duration=a.seconds+a.warmup+90
commands={'server':[str(native/'build/BOM-server.exe'),'--port',str(port),'--layout',str(out/'layout.json'),'--seconds',str(duration),'--host-token',token,'--metrics',str(out/'server-metrics.json')],
 'host':['dotnet',str(integration/'build/interop-performance-host/PerformanceHost.dll'),str(port),str(duration-5)],
 'observer':[str(native/'build/BOM.exe'),'--bot-client',f'127.0.0.1:{port}','--spectator','--prediction-off','--seconds',str(duration-10)]}
for role in ['primary','guest']:
 commands[role]=[str(player),'-force-d3d11','-screen-fullscreen','0','-screen-width','1920','-screen-height','1080','--bom-auto-connect','--bom-prediction-off','--bom-port',str(port),'--bom-perf-out',str(out/(role+'.json')),'--bom-perf-scene',a.scene,'--bom-perf-seconds',str(a.seconds),'--bom-perf-warmup',str(a.warmup),'-logFile',str(out/(role+'.log'))]
 if a.tier1:commands[role].append('--bom-tier1')
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
render_startup=subprocess.STARTUPINFO();render_startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;render_startup.wShowWindow=4
children={};streams={};codes={};stopped=[];failure=''
def launch(role):
 streams[role]=(out/(role+'-stdout.log')).open('w',encoding='utf-8');children[role]=subprocess.Popen(commands[role],cwd=native,env=env if role=='host' else guest,stdout=streams[role],stderr=subprocess.STDOUT,startupinfo=render_startup if role in ['primary','guest'] else startup)
def wait_text(role,path,needle,seconds):
 deadline=time.monotonic()+seconds
 while needle not in (path.read_text(encoding='utf-8',errors='replace') if path.exists() else ''):
  if children[role].poll() is not None:raise RuntimeError(role+' exited before '+needle)
  if time.monotonic()>deadline:raise TimeoutError(role+' startup timeout')
  time.sleep(.2)
try:
 launch('server');wait_text('server',out/'server-stdout.log','BOM staging server listening',30)
 launch('host');wait_text('host',out/'host-stdout.log','PERF HOST READY',60)
 launch('primary');launch('guest');time.sleep(2);launch('observer')
 deadline=time.monotonic()+duration+30
 for role in ['primary','guest']:
  codes[role]=children[role].wait(timeout=max(1,deadline-time.monotonic()))
  if codes[role]!=0:raise RuntimeError(role+' exit '+str(codes[role]))
 (out/'host-stop.signal').write_text('measurement complete')
 codes['host']=children['host'].wait(timeout=10)
 codes['server']=children['server'].wait(timeout=15)
 if codes['host']!=0 or codes['server']!=0:raise RuntimeError('Host/server did not exit cleanly')
except Exception as exc:failure=str(exc).replace(token,'[REDACTED]')
finally:
 for role,child in children.items():
  if child.poll() is None:stopped.append(role);child.terminate();child.wait()
  codes.setdefault(role,child.returncode)
 for stream in streams.values():stream.close()
summary={'status':'measurement_failed' if failure else 'measured','failure':failure,'scene':a.scene,'tier':'extrusion' if a.tier1 else 'source','exit_codes':codes,'supervisor_stopped_after_measurement':stopped,'native_dll_sha256':sha(plugin),'layout_sha256':sha(layout),'resolution':[1920,1080],'backend':a.backend,'seconds':a.seconds,'warmup':a.warmup,'commands':{k:[v if v!=token else '[REDACTED]' for v in values] for k,values in commands.items()}}
for role in ['primary','guest']:
 path=out/(role+'.json')
 if path.exists():summary[role]={k:v for k,v in json.loads(path.read_text()).items() if k!='rows'}
resources=out/'server-metrics.json.resources.json'
if resources.exists():summary['server_resources']=json.loads(resources.read_text())
(out/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2));print('Evidence: '+str(out));raise SystemExit(1 if failure else 0)
