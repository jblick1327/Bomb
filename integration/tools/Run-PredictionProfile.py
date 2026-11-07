"""Real native server/DLL profile through a bounded, seeded UDP impairment relay."""
import argparse,datetime,heapq,hashlib,json,os,pathlib,random,secrets,select,socket,subprocess,threading,time
p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--seconds',type=int,default=600);p.add_argument('--rtt-ms',type=float,default=100);p.add_argument('--jitter-ms',type=float,default=0);p.add_argument('--loss',type=float,default=0);p.add_argument('--fps',type=int,default=60);p.add_argument('--prediction-off',action='store_true');p.add_argument('--seed',type=int,default=57291);p.add_argument('--unity-player');a=p.parse_args()
if not 1<=a.seconds<=3600 or not 0<=a.loss<1 or not 0<=a.jitter_ms<=100 or not 0<=a.rtt_ms<=1000 or not 15<=a.fps<=1000:raise SystemExit('Invalid profile bounds')
config_path=pathlib.Path(a.config).resolve();config=json.loads(config_path.read_text(encoding='utf-8-sig'));root=pathlib.Path(config['OdinRoot']);integration=config_path.parent
out=integration/'evidence/M5'/('profile-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'));out.mkdir(parents=True)
identity=json.loads((root/'build/bomcore.build.json').read_text(encoding='utf-8-sig'))
plugin=next(pathlib.Path(a.unity_player).parent.rglob('bomcore.dll')) if a.unity_player else root/'build/interop/bomcore.dll'
plugin_hash=hashlib.sha256(plugin.read_bytes()).hexdigest();server_hash=hashlib.sha256((root/'build/BOM-server.exe').read_bytes()).hexdigest()
if plugin_hash!=identity['dll_sha256']:raise SystemExit('Build/copy the current DLL before running this profile; plugin identity differs.')
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as reservation:reservation.bind(('127.0.0.1',0));server_port=reservation.getsockname()[1]
relay=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);relay.bind(('127.0.0.1',0));relay.setblocking(False);relay_port=relay.getsockname()[1];server_address=('127.0.0.1',server_port)
if hasattr(socket,'SIO_UDP_CONNRESET'):relay.ioctl(socket.SIO_UDP_CONNRESET,False)
stopping=threading.Event();relay_error=[];counters={'received':0,'forwarded':0,'dropped':0,'peak_queued':0,'max_packet':0};rng=random.Random(a.seed)
def pump():
 queue=[];sequence=0;client=None
 try:
  while not stopping.is_set() or queue:
   now=time.monotonic()
   while queue and queue[0][0]<=now:
    _,_,data,to=heapq.heappop(queue);relay.sendto(data,to);counters['forwarded']+=1
   timeout=min(.01,max(0,queue[0][0]-now)) if queue else .01
   readable,_,_=select.select([relay],[],[],timeout)
   if not readable:continue
   while True:
    try:data,source=relay.recvfrom(2048)
    except BlockingIOError:break
    except ConnectionResetError:continue # ICMP from a cleanly closed UDP child is not a stream reset.
    counters['received']+=1;counters['max_packet']=max(counters['max_packet'],len(data))
    if len(data)>1200:raise RuntimeError('Native transport packet exceeded 1200 bytes')
    if source==server_address:
     if client is None:continue
     target=client
    else:client=source;target=server_address
    if rng.random()<a.loss:counters['dropped']+=1;continue
    delay=max(0,a.rtt_ms/2000+rng.uniform(-a.jitter_ms,a.jitter_ms)/1000)
    sequence+=1;heapq.heappush(queue,(time.monotonic()+delay,sequence,data,target));counters['peak_queued']=max(counters['peak_queued'],len(queue))
    if len(queue)>10000:raise RuntimeError('Relay queue exceeded its explicit bound')
 except Exception as error:relay_error.append(str(error))
worker=threading.Thread(target=pump,daemon=True);worker.start()
token=secrets.token_urlsafe(24);environment=os.environ.copy();environment.update(BOM_TEST_HOST_TOKEN=token,BOM_TEST_PROFILE='1',BOM_TEST_FPS=str(a.fps),BOM_TEST_PREDICTION='0' if a.prediction_off else '1',BOM_TEST_LOSSY='1' if a.loss else '0',BOM_EXPECT_BUILD_TAG=str(identity['build_tag']))
commands={'server':[str(root/'build/BOM-server.exe'),'--port',str(server_port),'--seconds',str(a.seconds+60),'--layout',str(integration/'fixtures/M5/static-layout.json'),'--host-token',token],'profile':['dotnet',str(root/'build/interop/Interop.dll'),str(relay_port),str(a.seconds)]}
if a.unity_player:
 commands['profile']=[str(pathlib.Path(a.unity_player).resolve()),'-batchmode','-force-d3d11','-screen-fullscreen','0','--bom-port',str(relay_port),'--bom-profile-seconds',str(a.seconds),'--bom-profile-fps',str(a.fps),'--bom-profile-out',str(out/'rendered-frame.png'),'-logFile',str(out/'unity-profile.log')]
 if a.prediction_off:commands['profile']+=['--bom-prediction-off']
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
children={};streams={};codes={};failure=''
try:
 for name,command in commands.items():
  streams[name]=(out/(name+'.log')).open('w',encoding='utf-8');children[name]=subprocess.Popen(command,cwd=root,env=environment if name=='profile' else None,stdout=streams[name],stderr=subprocess.STDOUT,startupinfo=startup);time.sleep(.2)
 codes['profile']=children['profile'].wait(timeout=a.seconds+70)
 codes['server']=children['server'].wait(timeout=25)
except Exception as error:failure=str(error)
finally:
 for name,child in children.items():
  if child.poll() is None:child.kill();child.wait()
  codes.setdefault(name,child.returncode)
 for stream in streams.values():stream.close()
 stopping.set();worker.join(timeout=2);relay.close()
profile=None
for line in (out/('unity-profile.log' if a.unity_player else 'profile.log')).read_text(encoding='utf-8',errors='replace').splitlines():
 if line.startswith('PROFILE_RESULT '):profile=json.loads(line[len('PROFILE_RESULT '):])
passed=not failure and not relay_error and all(code==0 for code in codes.values()) and profile is not None and profile['status']=='passed'
report={'status':'passed' if passed else 'failed','profile':vars(a),'exit_codes':codes,'failure':failure,'relay_errors':relay_error,'relay':counters,'result':profile,'native_identity':identity,'native_plugin_sha256':plugin_hash,'server_sha256':server_hash,'commands':{name:[arg if arg!=token else '[REDACTED]' for arg in command] for name,command in commands.items()},'scope':'Real UDP and actual Unity URP rendered-pose measurement, with a saved frame.' if a.unity_player else 'Real UDP server and exact native DLL at a controlled presentation sampling rate. Does not claim a GPU/Unity latency measurement.'}
(out/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in report.items() if k not in ['commands','native_identity']}));print('Evidence: '+str(out));raise SystemExit(0 if passed else 1)
