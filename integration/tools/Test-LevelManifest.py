"""Reject a known wrong gameplay manifest in a real standalone before play."""
import argparse,datetime,json,os,pathlib,secrets,socket,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--layout',required=True);p.add_argument('--player',required=True);a=p.parse_args()
cfg=pathlib.Path(a.config).resolve();c=json.loads(cfg.read_text(encoding='utf-8-sig'));root=pathlib.Path(c['OdinRoot']);out=cfg.parent/'evidence/M6'/('manifest-reject-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'));out.mkdir(parents=True)
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
startup=subprocess.STARTUPINFO();startup.dwFlags|=subprocess.STARTF_USESHOWWINDOW;startup.wShowWindow=0
env=os.environ.copy();env.pop('BOM_TEST_HOST_TOKEN',None)
commands={'server':[str(root/'build/BOM-server.exe'),'--port',str(port),'--layout',str(pathlib.Path(a.layout).resolve()),'--seconds','45'],'unity':[str(pathlib.Path(a.player).resolve()),'-batchmode','-force-d3d11','--bom-port',str(port),'--bom-smoke-seconds','25','--bom-expected-manifest','0'*63+'1','-logFile',str(out/'unity.log')]}
children={};streams={};codes={};error=''
try:
 for name,command in commands.items():streams[name]=(out/(name+'-stdout.log')).open('w');children[name]=subprocess.Popen(command,cwd=root,env=env,startupinfo=startup,stdout=streams[name],stderr=subprocess.STDOUT)
 codes['unity']=children['unity'].wait(timeout=35);codes['server']=children['server'].wait(timeout=50)
except Exception as e:error=str(e)
finally:
 for name,child in children.items():
  if child.poll() is None:child.kill();child.wait()
  codes.setdefault(name,child.returncode)
 for stream in streams.values():stream.close()
unity=(out/'unity.log').read_text(encoding='utf-8',errors='replace') if (out/'unity.log').exists() else '';server=(out/'server-stdout.log').read_text(encoding='utf-8',errors='replace')
passed=not error and codes=={'unity':3,'server':0} and 'gameplay level/config manifest mismatch' in unity.lower() and 'HELLO REJECT' in server and 'BOM UNITY SNAPSHOT' not in unity and 'HELLO OK' not in server
report={'status':'passed' if passed else 'failed','failure':error,'exit_codes':codes,'known_wrong_manifest':'0'*63+'1','no_presented_snapshot':'BOM UNITY SNAPSHOT' not in unity,'no_player_admitted':'HELLO OK' not in server,'commands':commands}
(out/'summary.json').write_text(json.dumps(report,indent=2));print(json.dumps(report));print('Evidence: '+str(out));raise SystemExit(0 if passed else 1)
