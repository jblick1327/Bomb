"""C5 front-door gate: two Unity players start at Darryn's MainMenuScene. The host presses ONLINE -> HOST GAME -> START,
which starts BOM-server.exe from the player's Server folder (no launcher here). The guest joins 127.0.0.1 through the
menu. Odin plays one elimination round to Finished (guest forfeit, as in the Rounds gate). Then the host returns to
the menu (its server must stop), hosts again and quits (its server must stop). A third run hosts and is killed; the
job object must take the server with it. A UDP port held by this script proves the busy-port fallback.
--level (C6) picks the level in the host and join menus (index into BomFrontDoor.Levels, kept in step below)."""
import argparse,datetime,hashlib,json,os,pathlib,re,socket,subprocess,time
LEVELS={'ClassicYard':(0,'NetworkMenu','yard.json'),'Yard':(1,'NetworkYardTiles','YardLevel.json'),'Bridge':(2,'NetworkBridge','BridgeLevel.json'),'Tower':(3,'NetworkTower','TowerLevel.json')}
p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--player',required=True);p.add_argument('--level',default='ClassicYard',choices=sorted(LEVELS));a=p.parse_args()
level_index,level_scene,level_file=LEVELS[a.level]
cfg=pathlib.Path(a.config).resolve();config=json.loads(cfg.read_text(encoding='utf-8-sig'));root=pathlib.Path(config['OdinRoot']);player=pathlib.Path(a.player).resolve()
identity=json.loads((root/'build/bomcore.build.json').read_text(encoding='utf-8-sig'))
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
plugin=next(player.parent.rglob('bomcore.dll'));server_exe=player.parent/'Server/BOM-server.exe';layout=player.parent/'Server/levels'/level_file
if sha(plugin)!=identity['dll_sha256']:raise SystemExit('Player native library differs from the current manifest')
for path in (server_exe,layout):
 if not path.exists():raise SystemExit('Missing packaged file: '+str(path))
out=cfg.parent/'evidence/M8'/('frontdoor-'+('' if a.level=='ClassicYard' else a.level.lower()+'-')+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'));out.mkdir(parents=True)
def read(path):return path.read_text(encoding='utf-8',errors='replace') if path.exists() else ''
def servers():
 rows=subprocess.run(['tasklist','/FI','IMAGENAME eq BOM-server.exe','/FO','CSV','/NH'],capture_output=True,text=True).stdout
 return {int(m) for m in re.findall(r'"BOM-server\.exe","(\d+)"',rows)}
def alive(pid):return pid in servers()
def signal(role,name):
 path=out/f'{role}-{name}.signal';text=read(path)
 return dict(line.split('=',1) for line in text.splitlines()[1:] if '=' in line) if text else None
before=servers()
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
children={};streams={};codes={};checks={};failure='';timeline=[]
t0=time.monotonic()
def note(text):timeline.append(f'{time.monotonic()-t0:7.1f}s {text}');print(timeline[-1],flush=True)
def launch(name,role,port):
 command=[str(player),'-batchmode','-force-d3d11','-screen-fullscreen','0','-screen-width','1280','-screen-height','720',
  '--bom-frontdoor-test',str(out),'--bom-frontdoor-role',role,'--bom-frontdoor-port',str(port),'--bom-frontdoor-level',str(level_index),'-logFile',str(out/(name+'.log'))]
 streams[name]=(out/(name+'-stdout.log')).open('w',encoding='utf-8')
 children[name]=subprocess.Popen(command,cwd=player.parent,stdout=streams[name],stderr=subprocess.STDOUT,startupinfo=startup)
 note(f'started {name} pid={children[name].pid} port={port}');return command
def wait_signal(name,role,sig,seconds):
 deadline=time.monotonic()+seconds
 while (value:=signal(role,sig)) is None:
  if children[name].poll() is not None:raise RuntimeError(f'{name} exited ({children[name].returncode}) before {role}-{sig}')
  if time.monotonic()>deadline:raise TimeoutError(f'{name} did not signal {role}-{sig}')
  time.sleep(.2)
 note(f'signal {role}-{sig} {value}');return value
def gone_within(pid,seconds):
 deadline=time.monotonic()+seconds
 while alive(pid):
  if time.monotonic()>deadline:return False
  time.sleep(.2)
 return True
commands={}
held=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);held.bind(('127.0.0.1',0));busy=held.getsockname()[1]
try:
 # 1. Host + guest through the menu, with the first port held busy by this script.
 commands['host']=launch('host','host',busy)
 hosted=wait_signal('host','host','hosted',150);port=int(hosted['port']);first_pid=int(hosted['pid'])
 checks['busy_port_skipped']=port!=busy;checks['first_server_running']=alive(first_pid)
 commands['guest']=launch('guest','guest',port)
 wait_signal('host','host','finished',300);wait_signal('guest','guest','finished',120)
 menu=wait_signal('host','host','menu',120);checks['server_stopped_on_return_to_menu']=not alive(first_pid)
 rehosted=wait_signal('host','host','rehosted',150);second_pid=int(rehosted['pid'])
 for name in ['host','guest']:codes[name]=children[name].wait(timeout=120);note(f'{name} exited {codes[name]}')
 checks['server_stopped_on_quit']=gone_within(second_pid,10)
 # 2. Crash: kill a hosting player; the kill-on-close job object must end its server.
 held.close();held=None
 commands['crash']=launch('crash','crash',port)
 crash=wait_signal('crash','crash','hosted',150);crash_pid=int(crash['pid'])
 checks['crash_server_running_before_kill']=alive(crash_pid)
 children['crash'].kill();codes['crash']=children['crash'].wait(timeout=30);note(f'crash player killed exit={codes["crash"]}')
 checks['server_stopped_on_player_crash']=gone_within(crash_pid,10)
except Exception as exc:failure=str(exc)
finally:
 if held:held.close()
 for name,child in children.items():
  if child.poll() is None:child.kill();child.wait();note(f'killed leftover {name}')
  codes.setdefault(name,child.returncode)
 for stream in streams.values():stream.close()
 time.sleep(1)
 orphans=sorted(servers()-before)
 for pid in orphans:subprocess.run(['taskkill','/F','/PID',str(pid)],capture_output=True)
logs={name:read(out/(name+'.log')) for name in ['host','guest','crash']}
exceptions={name:[line for line in text.splitlines() if 'Exception' in line] for name,text in logs.items()}
checks['no_orphan_bom_server']=not orphans
checks['host_pass']=signal('host','pass') is not None;checks['guest_pass']=signal('guest','pass') is not None
checks['exit_codes_zero']=codes.get('host')==0 and codes.get('guest')==0
checks['no_exception_lines']=all(not lines for lines in exceptions.values())
checks['bad_join_input_rejected']='bad address rejected' in logs['guest'] and 'bad port rejected' in logs['guest']
checks['round_finished_both']=bool(re.search(r'BOM FRONTDOOR TEST role=host round=\d+ state=3 mode=1',logs['host'])) and bool(re.search(r'BOM FRONTDOOR TEST role=guest round=\d+ state=3 mode=1',logs['guest']))
checks['main_menu_first']='menu ONLINE' in logs['host'] and 'menu ONLINE' in logs['guest']
checks['job_kill_on_close']=all('BOM FRONTDOOR SERVER job kill_on_close=1' in logs[n] for n in ['host','crash'])
checks['no_host_token_env']='BOM_TEST_HOST_TOKEN' not in os.environ
checks['level_scene_loaded']=all(f'BOM FRONTDOOR LOAD scene={level_scene} ' in logs[n] for n in ['host','guest']) and all(f'level=' in logs[n] and f' scene={level_scene} level_id=' in logs[n] for n in ['host','guest'])
passed=not failure and all(checks.values())
summary={'status':'passed' if passed else 'failed','level':a.level,'level_scene':level_scene,'level_file':level_file,'scope':'C5: MainMenuScene -> Online host (player starts BOM-server.exe itself) + Online join 127.0.0.1 -> finished elimination round; server stops on return to menu, on quit and on player crash; busy port skipped',
 'failure':failure,'checks':checks,'exit_codes':codes,'busy_port_held':busy,'orphans_killed':orphans,'exception_lines':exceptions,'timeline':timeline,
 'native_identity':identity,'player_sha256':sha(player),'plugin_sha256':sha(plugin),'server_sha256':sha(server_exe),'layout_sha256':sha(layout),
 'runtime_sha256':sha(player.parent/(player.stem+'_Data')/'Managed/Bom.Unity.Runtime.dll'),'commands':commands}
(out/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps({k:summary[k] for k in ['status','failure','checks','exit_codes','orphans_killed']},indent=1));print('Evidence: '+str(out))
raise SystemExit(0 if passed else 1)
