#!/usr/bin/env python3
"""Build, validate and run serialized native measurements. No dependencies beyond GCC/Python."""
import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
FLAGS = ['-std=c++20', '-O3', '-march=native', '-DNDEBUG', '-fno-math-errno', '-ffp-contract=off']

def command(args, **kwargs):
    subprocess.run(args, cwd=ROOT, check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sanitize', action='store_true')
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--rounds', type=int, default=2, choices=[1, 2])
    args = parser.parse_args()
    (ROOT/'results').mkdir(exist_ok=True)
    env = {'platform': platform.platform(), 'compiler': subprocess.check_output(['g++', '--version'], text=True),
           'flags': ' '.join(FLAGS), 'cpu_affinity': sorted(os.sched_getaffinity(0)),
           'cpu_info': subprocess.check_output(['lscpu', '-J'], text=True),
           'method': 'serialized, one permitted CPU, 9 interleaved samples per timing row',
           'node_bytes': 64, 'hot_bytes': 32, 'cold_bytes': 32, 'geometry_vertex_bytes': 16,
           'local_anchor_pair_bytes': 16}
    (ROOT/'environment.json').write_text(json.dumps(env, indent=2))
    for name in ['bench', 'seeds', 'audit']:
        command(['g++', *FLAGS, f'{name}.cpp', '-o', name])
    if args.sanitize:
        for name in ['bench', 'audit']:
            command(['g++', '-std=c++20', '-O1', '-g', '-fsanitize=address,undefined',
                     '-fno-omit-frame-pointer', f'{name}.cpp', '-o', f'{name}-sanitize'])
        sanitize_env = os.environ | {'ASAN_OPTIONS': 'detect_leaks=0'}
        # LeakSanitizer is disabled: this execution host runs under ptrace.
        for name in ['bench', 'audit']:
            with (ROOT/'results'/f'sanitizer-{name}.log').open('w') as out:
                command([str(ROOT/f'{name}-sanitize'), *(['--verify-only'] if name=='bench' else [])],
                        env=sanitize_env, stdout=out, stderr=subprocess.STDOUT)
    command([str(ROOT/'bench'), '--verify-only'])
    command([str(ROOT/'audit')])
    if args.verify_only:
        return
    os.sched_setaffinity(0, {min(os.sched_getaffinity(0))})
    for round_id in range(args.rounds):
        command([str(ROOT/'bench')])
        if round_id+1 < args.rounds:
            for name in ['events.csv', 'queries.csv', 'construction.csv', 'stages.csv']:
                shutil.copy2(ROOT/'results'/name, ROOT/'results'/f'round1_{name}')
    command([str(ROOT/'seeds')])
    command(['python3', 'validate_results.py'])

if __name__ == '__main__':
    main()
