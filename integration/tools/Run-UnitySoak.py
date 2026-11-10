"""Owned-process Unity/Odin soak with opaque, traced UDP impairments."""
import argparse,datetime,hashlib,json,os,pathlib,re,secrets,shutil,socket,subprocess,sys,time
from datagram_relay import DatagramRelay
from process_memory import sample as memory_sample

p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--primary-player',required=True);p.add_argument('--guest-player',required=True);p.add_argument('--layout',required=True);p.add_argument('--host-tool',required=True);p.add_argument('--seconds',type=int,default=1800);p.add_argument('--backend',choices=['Mono','IL2CPP','mixed'],default='mixed');a=p.parse_args()
if not 60<=a.seconds<=3600:raise SystemExit('Soak duration must be 60..3600 seconds')
cfg=pathlib.Path(a.config).resolve();integration=cfg.parent;c=json.loads(cfg.read_text(encoding='utf-8-sig'));native=pathlib.Path(c['OdinRoot'])
from hash_coverage import analyze
identity=json.loads((native/'build/bomcore.build.json').read_text(encoding='utf-8-sig'))
out=integration/'evidence/M9'/('soak-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'));out.mkdir(parents=True)
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
host_tool=pathlib.Path(a.host_tool).resolve();shutil.copy2(pathlib.Path(a.layout).resolve(),out/'layout.json');shutil.copy2(native/'build/bomcore.dll',host_tool.parent/'bomcore.dll')
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as reservation:reservation.bind(('127.0.0.1',0));port=reservation.getsockname()[1]
relays={role:DatagramRelay(port,out/(role+'-datagrams.jsonl.gz'),seed) for role,seed in [('primary',42),('guest',137)]}
token=secrets.token_urlsafe(24);host_env=os.environ.copy();host_env.update(BOM_TEST_HOST_TOKEN=token,BOM_PERF_STOP_FILE=str(out/'host-stop.signal'),BOM_PERF_SEED='2026');guest_env=os.environ.copy();guest_env.pop('BOM_TEST_HOST_TOKEN',None)
duration=a.seconds+240;commands={'server':[str(native/'build/BOM-server.exe'),'--port',str(port),'--layout',str(out/'layout.json'),'--seconds',str(duration),'--host-token',token,'--metrics',str(out/'server-metrics.json')],
 'host':['dotnet',str(host_tool),str(port),str(duration-10)],
 'observer':[str(native/'build/BOM.exe'),'--bot-client',f'127.0.0.1:{port}','--spectator','--prediction-off','--seconds',str(duration-5),'--stop-file',str(out/'observer-stop.signal')]}
players={};player_identity={}
for role in ['primary','guest']:
 backend=('Mono' if role=='primary' else 'IL2CPP') if a.backend=='mixed' else a.backend
 player=pathlib.Path(a.primary_player if role=='primary' else a.guest_player).resolve();players[role]=player
 plugin=next(player.parent.rglob('bomcore.dll'))
 if sha(plugin)!=identity['dll_sha256']:raise SystemExit('Player/native identity mismatch: '+role)
 assembly=player.parent/'GameAssembly.dll' if backend=='IL2CPP' else player.parent/'BombPerformance_Data/Managed/Bom.Unity.Runtime.dll'
 player_identity[role]=dict(backend=backend,executable_sha256=sha(player),native_dll_sha256=sha(plugin),runtime_sha256=sha(assembly))
 commands[role]=[str(player),'-force-d3d11','-screen-fullscreen','0','-screen-width','1920','-screen-height','1080','--bom-port',str(relays[role].port),'--bom-perf-out',str(out/(role+'.json')),'--bom-perf-scene','PerformanceReference','--bom-perf-seconds',str(a.seconds),'--bom-perf-warmup','5','--bom-perf-start-file',str(out/'measurement-start.signal'),'--bom-soak','--bom-soak-role',role,'--bom-soak-join-delay','15' if role=='guest' else '0','--bom-source-job-gate',str(out/'release-jobs.signal'),'--bom-source-job-gate-asset','performance/disconnected-group-4-v1','-logFile',str(out/(role+'.log'))]
 if role=='guest':commands[role].append('--bom-prediction-off')
hidden=subprocess.STARTUPINFO();hidden.dwFlags|=subprocess.STARTF_USESHOWWINDOW;hidden.wShowWindow=0
render=subprocess.STARTUPINFO();render.dwFlags|=subprocess.STARTF_USESHOWWINDOW;render.wShowWindow=4
memory_samples=[];children={};streams={};codes={};forced=[];failure='';measured_start=None;started=time.monotonic()
def read(name):
 path=out/name;return path.read_text(encoding='utf-8',errors='replace') if path.exists() else ''
def launch(role):
 streams[role]=(out/(role+'-stdout.log')).open('w',encoding='utf-8');children[role]=subprocess.Popen(commands[role],cwd=native,env=host_env if role=='host' else guest_env,stdout=streams[role],stderr=subprocess.STDOUT,startupinfo=render if role in players else hidden)
def wait_text(role,name,needle,seconds):
 deadline=time.monotonic()+seconds
 while needle not in read(name):
  if children[role].poll() is not None:raise RuntimeError(role+' exited before '+needle)
  if time.monotonic()>deadline:raise TimeoutError(role+' startup timeout waiting for '+needle)
  time.sleep(.2)
def progress(phase):
 report=dict(phase=phase,elapsed_seconds=round(time.monotonic()-started,2),measured_seconds=round(time.monotonic()-measured_start,2) if measured_start else 0,pids={k:v.pid for k,v in children.items()},exit_codes={k:v.poll() for k,v in children.items()},relays={k:v.counters.copy() for k,v in relays.items()})
 memory_samples.append(dict(elapsed=report['elapsed_seconds'],processes={k:memory_sample(v.pid) for k,v in children.items() if v.poll() is None}));(out/'process-memory.json').write_text(json.dumps(memory_samples,indent=2))
 temporary=out/'progress.tmp';temporary.write_text(json.dumps(report,indent=2));temporary.replace(out/'progress.json')
try:
 print('Evidence: '+str(out),flush=True)
 launch('server');wait_text('server','server-stdout.log','BOM staging server listening',30)
 launch('host');wait_text('host','host-stdout.log','PERF HOST READY',60)
 launch('primary');launch('guest');launch('observer');progress('joining')
 wait_text('primary','primary.log','BOM SOURCE JOB GATE WAIT',90)
 wait_text('guest','guest.log','BOM SOURCE JOB GATE WAIT',120)
 reset_before=max(map(int,re.findall(r'PERF RESET requested=(\d+)',read('host-stdout.log'))),default=0)
 wait_text('host','host-stdout.log','PERF RESET requested='+str(reset_before+1)+' ',90)
 wait_text('primary','primary.log','BOM SOURCE STALE DROP',90)
 wait_text('guest','guest.log','BOM SOURCE STALE DROP',90)
 (out/'release-jobs.signal').write_text('release after live reset with pending geometry work')
 time.sleep(5);(out/'measurement-start.signal').write_text('begin common measured interval');measured_start=time.monotonic();progress('measuring')
 deadline=measured_start+a.seconds+120;next_report=0
 while any(children[role].poll() is None for role in players):
  now=time.monotonic()
  for role in ['server','host','observer']:
   if children[role].poll() is not None:raise RuntimeError(role+' exited during measured interval')
  for relay in relays.values():
   if relay.errors:raise RuntimeError('; '.join(relay.errors))
  if now>deadline:raise TimeoutError('Unity soak did not finish')
  if now>=next_report:
   progress('measuring');print('SOAK LIVE measured_seconds='+str(round(now-measured_start,1)),flush=True);next_report=now+30
  time.sleep(.2)
 for role in players:
  codes[role]=children[role].returncode
  if codes[role]!=0:raise RuntimeError(role+' failed with exit '+str(codes[role]))
 (out/'observer-stop.signal').write_text('clients finished; observer exits through its ordinary loop')
 codes['observer']=children['observer'].wait(timeout=15)
 (out/'host-stop.signal').write_text('observer finished; host closes normally')
 codes['host']=children['host'].wait(timeout=10);codes['server']=children['server'].wait(timeout=20)
 if any(codes.values()):raise RuntimeError('A supervised process did not exit cleanly')
except Exception as exc:failure=str(exc).replace(token,'[REDACTED]')
finally:
 for role,child in children.items():
  if child.poll() is None:forced.append(role);child.terminate();child.wait()
  codes.setdefault(role,child.returncode)
 for stream in streams.values():stream.close()
 for relay in relays.values():relay.close()
 progress('failed' if failure else 'analyzing')

coverage=analyze(read('server-stdout.log'));(out/'hash-coverage.json').write_text(json.dumps(coverage,indent=2))
summaries={};memory={};issues=[]
for role in players:
 path=out/(role+'.json')
 if not path.exists():issues.append(role+' report missing');continue
 report=json.loads(path.read_text());rows=report.pop('rows');report['observed_measured_span_seconds']=rows[-1]['elapsed']-rows[0]['elapsed'] if rows else 0;summaries[role]=report
 if report['observed_measured_span_seconds']<a.seconds-.1:issues.append(role+' measured interval too short')
 if not report.get('resources_drained') or report.get('stale_applications')!=0:issues.append(role+' resources/stale application gate')
 if report.get('stale_results',0)<2:issues.append(role+' did not discard held work across a reset')
 if read(role+'.log').count('BOM SOAK RECONNECT')<1:issues.append(role+' did not reconnect')
 if not report.get('stable_pose_zero_allocation'):issues.append(role+' stable pose allocation gate')
 groups={}
 for row in rows:groups.setdefault((row['connection_generation'],row['epoch']),[]).append(row)
 cycles=[]
 for key,values in groups.items():
  ready=[v for v in values if v['cells']==475 and v['source_fallback']==0 and v['jobs_active']==0 and v['jobs_pending']==0 and v['buffers']==0]
  if ready:
   selected=ready[0];cycles.append(dict(connection=key[0],epoch=key[1],elapsed=selected['elapsed'],native_owned=selected['native_owned'],native_live=selected['native_live'],cache_cpu=selected['cache_cpu'],cache_gpu=selected['cache_gpu'],poses=selected['poses']))
 last=cycles[-10:];memory[role]=dict(equivalent_initial_state_cycles=cycles,last_ten=last,strictly_increasing_native_bytes=len(last)==10 and all(b['native_owned']>a['native_owned'] for a,b in zip(last,last[1:])),max_native_owned=max((v['native_owned'] for v in rows),default=0),max_cache_cpu=max((v['cache_cpu'] for v in rows),default=0),max_cache_gpu=max((v['cache_gpu'] for v in rows),default=0),max_job_buffers=max((v['buffers'] for v in rows),default=0))
 if a.seconds>=1800 and len(last)<10:issues.append(role+' lacks ten comparable restored-state cycles')
 if memory[role]['strictly_increasing_native_bytes']:issues.append(role+' increasing restored-state native bytes need review')
 if memory[role]['max_cache_cpu']>112*1024*1024 or memory[role]['max_cache_gpu']>128*1024*1024 or memory[role]['max_job_buffers']>64*1024*1024:issues.append(role+' exceeded a geometry resource cap')
resources_path=out/'server-metrics.json.resources.json';resources=json.loads(resources_path.read_text()) if resources_path.exists() else {}
if not resources.get('no_lost_world_bytes'):issues.append('Server physics teardown gate')
if coverage['status']!='passed':issues.append('Authoritative hash coverage gate')
reset_count=len(re.findall(r'PERF RESET requested=',read('host-stdout.log')))
if reset_count<10:issues.append('Fewer than ten reset requests')
requests=re.findall(r'PERF REQUEST id=(\d+) kind=(\d+) status=(\d+) effect_tick=(\d+) event=(\d+)',read('host-stdout.log'));blast_ticks={}
for request,kind,status,tick,event in requests:
 if kind=='1' and status=='1' and int(event)>0:blast_ticks.setdefault(tick,set()).add(event)
overlap_ticks=sum(len(events)>=2 for events in blast_ticks.values())
if not overlap_ticks:issues.append('No accepted overlapping same-tick blasts')
for role,relay in relays.items():
 if relay.errors:issues.append(role+' relay: '+'; '.join(relay.errors))
 if relay.counters['burst_drops']==0 or relay.counters['duplicates']==0 or relay.counters['reordered']==0:issues.append(role+' impairment trace lacks a required case')
if failure:issues.insert(0,failure)
passed=not issues and len(codes)==5 and all(code==0 for code in codes.values())
summary=dict(status=('passed' if a.seconds>=1800 else 'passed_preflight') if passed else 'failed',required_final_duration=a.seconds>=1800,requested_common_seconds=a.seconds,issues=issues,exit_codes=codes,forced_stops=forced,reset_requests=reset_count,accepted_same_tick_overlap_pairs=overlap_ticks,server_resources=resources,hash_coverage=coverage,clients=summaries,memory=memory,native_identity=identity,players=player_identity,relays={role:dict(configuration=relay.config,counters=relay.counters,trace_sha256=sha(relay.trace_path)) for role,relay in relays.items()},commands={k:[v if v!=token else '[REDACTED]' for v in values] for k,values in commands.items()},scope='Real dedicated server, two standalone Unity clients, native host controller and independent Odin observer. Two transparent UDP relays add traced bidirectional jitter, duplication, reordering and 500 ms bursts; packets use only the native codec.')
(out/'summary.json').write_text(json.dumps(summary,indent=2));progress(summary['status']);print(json.dumps({k:v for k,v in summary.items() if k in ['status','requested_common_seconds','issues','exit_codes','reset_requests','accepted_same_tick_overlap_pairs','server_resources']},indent=2),flush=True);print('Evidence: '+str(out),flush=True);raise SystemExit(0 if passed else 1)
