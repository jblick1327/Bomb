"""Build a matching native checkpoint from read-only source, then copy its SDK/plugin.

python integration/tools/Build-OwnerNative.py --config integration/local.config.json

Requires the pinned Odin compiler/MSVC/SDK, Python 3 and .NET 10. The source root
is never checked out, cleaned or written. All generation/builds use a fresh copy.
Previous build attempts and their raw logs are retained, including failures.
"""
import argparse, datetime, hashlib, json, os, pathlib, re, shutil, subprocess, sys, uuid

def sha(path):
    with pathlib.Path(path).open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()

def main():
    integration=pathlib.Path(__file__).resolve().parents[1]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=pathlib.Path,default=integration/'local.config.json')
    args=parser.parse_args();config=json.loads(args.config.read_text(encoding='utf-8-sig'))
    source=pathlib.Path(config.get('OwnerOdinSourceRoot',config['OdinRoot'])).resolve()
    compiler=pathlib.Path(config['OdinCompiler']);linker=pathlib.Path(config['LinkerDirectory'])
    libraries=[pathlib.Path(p) for p in config['LibraryDirectories']]
    for path in [source/'src/main.odin',compiler,linker,*libraries]:
        if not path.exists():raise RuntimeError('Required source/tool path is missing: '+str(path))
    stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S')+'-'+uuid.uuid4().hex[:8]
    output=integration/'build/owner-native'/stamp
    output.mkdir(parents=True);stage=output/'source';stage.mkdir()
    # The source repository's .git and its live generated build/output directories
    # are not copied. All original source/fixture bytes are retained as supplied.
    for folder in ['src','bindings','scripts','diagnostics','tests','layouts','evidence']:
        shutil.copytree(source/folder,stage/folder)
    (stage/'build').mkdir();(stage/'output').mkdir()
    env=dict(os.environ,PATH=str(linker)+os.pathsep+os.environ['PATH'],LIB=';'.join(map(str,libraries)),GIT_OPTIONAL_LOCKS='0')
    state=integration/'build/tool-state';state.mkdir(parents=True,exist_ok=True)
    env.update(DOTNET_CLI_HOME=str(state),NUGET_PACKAGES=str(state/'packages'),DOTNET_CLI_TELEMETRY_OPTOUT='1',DOTNET_GENERATE_ASPNET_CERTIFICATE='false',DOTNET_ADD_GLOBAL_TOOLS_TO_PATH='false')
    results=[]
    def run(name,command,cwd=stage):
        log=output/(name+'.log');print(name,flush=True)
        p=subprocess.run(list(map(str,command)),cwd=cwd,env=env,capture_output=True)
        log.write_bytes(p.stdout+b'\n--- STDERR ---\n'+p.stderr)
        results.append({'name':name,'command':list(map(str,command)),'exit_code':p.returncode,'log':str(log)})
        (output/'commands.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        if p.returncode:
            print(p.stdout.decode(errors='replace'));print(p.stderr.decode(errors='replace'),file=sys.stderr)
            raise RuntimeError(name+' failed with exit '+str(p.returncode)+'; raw output: '+str(log))
        return p.stdout.decode('utf-8-sig',errors='replace')
    version=run('compiler-version',[compiler,'version']).strip()
    if 'dev-2026-05-nightly:ea5175d' not in version:raise RuntimeError('Compiler is not pinned ea5175d: '+version)
    run('generate-abi',[sys.executable,stage/'scripts/generate-client-abi.py'])
    text=run('source-fingerprint',['dotnet','run','--project',integration/'tools/NativeFingerprint/NativeFingerprint.csproj','--configuration','Release','--verbosity','quiet','--',stage])
    fingerprint=None
    for line in text.splitlines():
        try:
            candidate=json.loads(line)
            if isinstance(candidate,dict) and 'source_sha256' in candidate:fingerprint=candidate
        except json.JSONDecodeError:pass
    if fingerprint is None:raise RuntimeError('Fingerprint tool did not produce its JSON identity; see raw log')
    arguments=list(config.get('CompilerArguments',['-ignore-vs-search','-debug']))
    if arguments!=['-ignore-vs-search','-debug']:raise RuntimeError('Use the reviewed pinned compiler arguments: -ignore-vs-search -debug')
    # A frontend package contains the diagnostics named by src/main.odin. Leave
    # this generated staging directory available for debugging, never delete it.
    frontend=stage/'build/frontend-package';shutil.copytree(stage/'src',frontend)
    for path in (stage/'diagnostics').glob('*.odin'):shutil.copyfile(path,frontend/path.name)
    run('build-server',[compiler,'build',frontend/'server','-o:speed','-out:'+str(stage/'build/BOM-server.exe'),*arguments])
    run('build-dev-client',[compiler,'build',frontend,'-o:speed','-out:'+str(stage/'build/BOM.exe'),*arguments])
    dll=stage/'build/bomcore.dll'
    run('build-client-library',[compiler,'build',stage/'src/ffi','-build-mode:dll','-o:speed','-out:'+str(dll),'-define:BOM_CORE_BUILD_TAG='+str(fingerprint['build_tag']),*arguments])
    schema=json.loads((stage/'bindings/bom-abi.json').read_text(encoding='utf-8-sig'))
    protocol=int(re.search(r'GAME_PROTOCOL_VERSION\s*::\s*u32\((\d+)\)',(stage/'src/shared/net_session.odin').read_text()).group(1))
    canonical=int(re.search(r'REPL_CANON_VERSION\s*::\s*u8\((\d+)\)',(stage/'src/shared/replication.odin').read_text()).group(1))
    commit=subprocess.run(['git','-C',str(source),'rev-parse','HEAD'],env=env,capture_output=True,text=True)
    dirty=subprocess.run(['git','-C',str(source),'status','--porcelain','--untracked-files=all','--','src','bindings','scripts','tests'],env=env,capture_output=True,text=True)
    identity=dict(abi_major=schema['abi_major'],abi_minor=schema['abi_minor'],source_commit=commit.stdout.strip(),source_dirty=bool(dirty.stdout.strip()),source_root=str(source),**fingerprint,dll_sha256=sha(dll),compiler=version,compiler_arguments=arguments,optimization='speed',game_protocol=protocol,canonical_version=canonical)
    (stage/'build/bomcore.build.json').write_text(json.dumps(identity,indent=2),encoding='utf-8')
    sdk=integration.parent/'Assets/BOMIntegration'
    plugin=sdk/'Plugins/x86_64/bomcore.dll'
    if plugin.exists():
        try:
            with plugin.open('r+b'):pass
        except PermissionError as error:raise RuntimeError('Close the Editor using this plugin before copying it. Restart the Editor after the DLL changes. Built artifacts are retained at '+str(output)) from error
    shutil.copyfile(dll,plugin)
    shutil.copyfile(stage/'bindings/BomNative.cs',sdk/'Runtime/BomNative.cs')
    shutil.copyfile(stage/'build/bomcore.build.json',plugin.with_name('bomcore.build.json'))
    expected='''// Generated by integration/tools/Build-OwnerNative.py with the matching plugin.
namespace Bom.Unity {
public static class BomExpectedNativeIdentity {
 public const uint AbiMajor=%d,AbiMinor=%d,GameProtocol=%d,CanonicalVersion=%d;
 public const ulong BuildTag=%dUL;
 public const string DllSha256="%s";
}
}
'''%(identity['abi_major'],identity['abi_minor'],protocol,canonical,fingerprint['build_tag'],identity['dll_sha256'])
    (sdk/'Runtime/BomExpectedNativeIdentity.cs').write_text(expected,encoding='utf-8')
    if sha(plugin)!=identity['dll_sha256']:raise RuntimeError('Copied plugin failed SHA-256 verification')
    runtime_config=dict(config,OdinRoot=str(stage),OwnerOdinSourceRoot=str(source),NativeBuildIdentity=identity,NativeBuildOutput=str(output))
    # Existing profile tools resolve fixtures relative to the config directory.
    runtime_path=integration/'local.config.owner-validation.json'
    runtime_path.write_text(json.dumps(runtime_config,indent=2),encoding='utf-8')
    (integration/'build/owner-native/latest.json').write_text(json.dumps({'output':str(output),'config':str(runtime_path),'identity':identity},indent=2),encoding='utf-8')
    print(json.dumps({'status':'built-and-copied','source_root_unchanged_by_build':str(source),'validation_config':str(runtime_path),'identity':identity},indent=2),flush=True)
    print('Restart the Unity Editor before using the updated native DLL.',flush=True)

if __name__=='__main__':
    try:main()
    except Exception as error:print(str(error),file=sys.stderr);raise SystemExit(1)
