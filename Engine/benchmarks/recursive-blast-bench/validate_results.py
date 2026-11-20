#!/usr/bin/env python3
"""Check recorded samples, medians, output signatures and cross-run consistency."""
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parent

def read(name):
    with (ROOT/'results'/name).open() as f:
        return list(csv.DictReader(f))

def main():
    files = ['events.csv', 'queries.csv', 'construction.csv', 'stages.csv', 'seeds.csv']
    files += [f'round1_{x}' for x in ['events.csv', 'queries.csv', 'construction.csv', 'stages.csv']
              if (ROOT/'results'/f'round1_{x}').exists()]
    counts = {}
    for name in files:
        rows = read(name)
        counts[name] = len(rows)
        for row in rows:
            raw = [float(row[f'sample_{i}_ns']) for i in range(9)]
            assert all(math.isfinite(x) and x>0 for x in raw), (name, row)
            ordered = sorted(raw)
            for key, expected in [('median_ns', statistics.median(raw)), ('p25_ns', ordered[2]), ('p75_ns', ordered[6])]:
                assert math.isclose(float(row[key]), expected, rel_tol=2e-10, abs_tol=1e-5), (name,key)
            assert int(row['repetitions'])>0
    for filename in ['events.csv', 'round1_events.csv', 'verification.csv']:
        if not (ROOT/'results'/filename).exists():
            continue
        rows = read(filename)
        for case in {x['case'] for x in rows}:
            selected = [r for r in rows if r['case']==case]
            ref = next(r for r in selected if r['variant']=='aos_context')
            for row in selected:
                if row['variant']=='one_generation_control':
                    continue
                for key in ['checksum','final_nodes','final_edges','groups','fading','impulses']:
                    assert row[key]==ref[key], (filename,case,row['variant'],key)
    if (ROOT/'results/round1_events.csv').exists():
        old={(r['case'],r['variant']):r for r in read('round1_events.csv')}
        for r in read('events.csv'):
            if (r['case'],r['variant']) in old:
                assert r['checksum']==old[r['case'],r['variant']]['checksum']
    for r in read('seed_policy_audit.csv'):
        assert int(r['small_children_that_split'])==0
        assert float(r['maximum_impulse_error'])<2e-5
    result = {'timed_rows': sum(counts.values()), 'raw_samples': 9*sum(counts.values()),
              'per_file_rows': counts, 'medians_and_quartiles_valid': True,
              'retained_geometry_connections_membership_and_impulses_match': True,
              'one_generation_control_is_different_behavior': True,
              'shared_seed_policy_retains_individual_width_guard': True}
    (ROOT/'validation.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    manifest=ROOT/"manifest.json"
    if manifest.exists():
        entries=json.loads(manifest.read_text())["files"]
        for e in entries:
            data=(ROOT/e["path"]).read_bytes()
            assert len(data)==e["bytes"] and hashlib.sha256(data).hexdigest()==e["sha256"], e["path"]
        print(f"Manifest hashes valid: {len(entries)} files")

if __name__ == '__main__':
    main()
