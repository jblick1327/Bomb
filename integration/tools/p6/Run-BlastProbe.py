"""P9: run blast_storm_probe (yard, 30 deep ground blasts, debris freeze on as shipped) on a candidate's staged source.
Usage: Run-BlastProbe.py <candidate-dir> <log>. Run from the repo root (the probe reads integration/fixtures)."""
import json, os, pathlib, subprocess, sys
cfg = json.loads((pathlib.Path(__file__).resolve().parents[2] / 'local.config.json').read_text(encoding='utf-8-sig'))
env = dict(os.environ, PATH=cfg['LinkerDirectory'] + os.pathsep + os.environ['PATH'], LIB=';'.join(cfg['LibraryDirectories']))
stage = pathlib.Path(sys.argv[1]) / 'stage' / 'shared'
cmd = [cfg['OdinCompiler'], 'test', str(stage), '-o:speed', '-ignore-vs-search', '-define:BOM_BLAST_PROBE=true',
       '-define:BOM_BLAST_PROBE_DEEP=true', '-define:BOM_BLAST_PROBE_FREEZE=true', '-define:ODIN_TEST_NAMES=shared.blast_storm_probe',
       '-out:' + str(pathlib.Path(sys.argv[1]) / 'probe.exe')]
with open(sys.argv[2], 'w', encoding='utf-8') as h:
    h.write(' '.join(cmd) + '\n'); h.flush()
    sys.exit(subprocess.run(cmd, stdout=h, stderr=subprocess.STDOUT, env=env).returncode)
