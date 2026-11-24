"""Own-process supervisor for the real DLL + shared Odin reference client gate."""
import argparse,datetime,json,os,pathlib,re,secrets,socket,subprocess,time
from hash_coverage import analyze
p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--seconds',type=int,default=600);a=p.parse_args()
if not 1<=a.seconds<=3600:raise SystemExit('seconds must be 1..3600')
config_path=pathlib.Path(a.config).resolve();config=json.loads(config_path.read_text(encoding='utf-8-sig'))
r=pathlib.Path(config['OdinRoot']);stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
out=config_path.parent/'evidence/M3'/('live-'+stamp);out.mkdir(parents=True,exist_ok=False)
identity=json.loads((r/'build/bomcore.build.json').read_text(encoding='utf-8-sig'))
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
token=secrets.token_urlsafe(24)
commands={'server':[str(r/'build/BOM-server.exe'),'--port',str(port),'--seconds',str(a.seconds+6),'--host-token',token],'observer':[str(r/'build/BOM.exe'),'--bot-client',f'127.0.0.1:{port}','--seconds',str(max(1,a.seconds-3))],'native-clients':['dotnet',str(r/'build/interop/Interop.dll'),str(port),str(a.seconds)]}
environment=os.environ.copy();environment['BOM_TEST_HOST_TOKEN']=token;environment['BOM_EXPECT_BUILD_TAG']=str(identity['build_tag'])
processes={};files={};codes={}
try:
 for name in commands:
  files[name]=(out/(name+'.log')).open('w',encoding='utf-8')
  processes[name]=subprocess.Popen(commands[name],cwd=r,stdout=files[name],stderr=subprocess.STDOUT,env=environment if name=='native-clients' else None)
  time.sleep(.35)
 deadline=time.monotonic()+a.seconds+40
 for name in ['native-clients','observer','server']:
  try:codes[name]=processes[name].wait(timeout=max(1,deadline-time.monotonic()))
  except subprocess.TimeoutExpired:processes[name].kill();processes[name].wait();codes[name]=124
finally:
 for process in processes.values():
  if process.poll() is None:process.kill();process.wait()
 for file in files.values():file.close()
text=(out/'server.log').read_text();match=re.search(r'SERVER final hashes=(\d+) mismatches=(\d+) unrecorded=(\d+)',text)
native_log=(out/'native-clients.log').read_text()
passed=all(c==0 for c in codes.values()) and match and int(match[1])>0 and match[2]=='0' and match[3]=='0' and 'PASS real native clients' in native_log
coverage=analyze(text);passed=passed and coverage['status']=='passed'
(out/'hash-coverage.json').write_text(json.dumps(coverage,indent=2))
report={'status':'passed' if passed else 'failed','duration_seconds':a.seconds,'exit_codes':codes,'hash_checks':int(match[1]) if match else None,'hash_mismatches':int(match[2]) if match else None,'unrecorded_hashes':int(match[3]) if match else None,'commands':{n:[arg if arg!=token else '[REDACTED]' for arg in command] for n,command in commands.items()},'loaded_native_identity':identity,'scope':'Real DLL clients and shared-core Odin reference observer. Remaining M3 timing/lifetime gates and Unity gates remain separately tracked.'}
(out/'summary.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:v for k,v in report.items() if k not in ['commands','loaded_native_identity']}));print('Evidence: '+str(out))
raise SystemExit(0 if passed else 1)
