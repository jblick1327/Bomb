"""Real UDP native round diagnostic; does not replace the two-Unity M8 gate."""
import argparse,datetime,json,os,pathlib,secrets,socket,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--seconds',type=int,default=60);p.add_argument('--four-players',action='store_true');a=p.parse_args()
if not 30<=a.seconds<=300:raise SystemExit('seconds must be 30..300')
cfgpath=pathlib.Path(a.config).resolve();cfg=json.loads(cfgpath.read_text(encoding='utf-8-sig'));root=pathlib.Path(cfg['OdinRoot'])
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
out=cfgpath.parent/'evidence/M8'/('round-native-'+stamp);out.mkdir(parents=True)
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
token=secrets.token_urlsafe(24)
env=os.environ.copy();env['BOM_TEST_ROUNDS_FOUR' if a.four_players else 'BOM_TEST_ROUNDS']='1';env['BOM_TEST_HOST_TOKEN']=token
commands={'server':[str(root/'build/BOM-server.exe'),'--port',str(port),'--seconds',str(a.seconds+8),'--host-token',token],
          'native-clients':['dotnet',str(root/'build/interop/Interop.dll'),str(port),str(a.seconds)]}
processes={};files={};codes={};errors=[]
try:
 for name in commands:
  if name=='native-clients':
   deadline=time.monotonic()+30
   while 'BOM staging server listening' not in (out/'server.log').read_text(encoding='utf-8',errors='replace'):
    if processes['server'].poll() is not None or time.monotonic()>deadline:raise RuntimeError('server failed to become ready')
    time.sleep(.1)
  files[name]=(out/(name+'.log')).open('w',encoding='utf-8')
  processes[name]=subprocess.Popen(commands[name],cwd=root,stdout=files[name],stderr=subprocess.STDOUT,env=env)
 deadline=time.monotonic()+a.seconds+30
 for name in ['native-clients','server']:
  try:codes[name]=processes[name].wait(timeout=max(1,deadline-time.monotonic()))
  except subprocess.TimeoutExpired:processes[name].kill();processes[name].wait();codes[name]=124
except Exception as exc:errors.append(str(exc))
finally:
 for proc in processes.values():
  if proc.poll() is None:proc.kill();proc.wait()
 for stream in files.values():stream.close()
marker='PASS real UDP four-player round' if a.four_players else 'PASS real UDP round rules'
passed=not errors and len(codes)==2 and all(code==0 for code in codes.values()) and marker in (out/'native-clients.log').read_text(encoding='utf-8',errors='replace')
result={'status':'passed' if passed else 'failed','exit_codes':codes,'errors':errors,
 'scope':'Real UDP Odin server and four native C ABI client handles; Unity menu/art and two-Unity M8 gate still required.',
 'commands':{k:[v if v!=token else '[REDACTED]' for v in cmd] for k,cmd in commands.items()},
 'native_identity':json.loads((root/'build/bomcore.build.json').read_text(encoding='utf-8-sig'))}
(out/'summary.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k not in ['commands','native_identity']}));print('Evidence: '+str(out))
raise SystemExit(0 if passed else 1)
