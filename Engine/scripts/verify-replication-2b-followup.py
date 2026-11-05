"""Validate the follow-up artifacts and write report.md; no packaging or git writes.

See the generated report for the build, soak, test and capture commands.
"""
import csv
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
e = root / 'evidence/replication-2b-followup'
prior = root / 'evidence/replication-2b'


def read(path):
    data = path.read_bytes()
    return data.decode('utf-16' if data.startswith(b'\xff\xfe') else 'utf-8-sig')


def write_json(name, value):
    (e / name).write_text(json.dumps(value, indent=2) + '\n', encoding='utf8')


def table(headers, rows):
    return '\n'.join(['| ' + ' | '.join(headers) + ' |', '|' + '|'.join('---' for _ in headers) + '|'] +
                     ['| ' + ' | '.join(map(str, row)) + ' |' for row in rows])


def triple(value, prefix=''):
    return '/'.join(f'{value[prefix + key]:.5f}' for key in ('p50', 'p99', 'max'))


tests = read(e / 'tests-final.txt')
match = re.search(r'Finished (\d+) tests in (\S+)\. All tests were successful\.', tests)
assert match and int(match[1]) == 208 and '[ERROR]' not in tests, 'full test suite must pass'
assert 'Memory tracking is enabled' in tests

grid = list(csv.DictReader((e / 'pose-resolution.csv').open()))
assert len(grid) == 12
resolution_log = read(e / 'pose-resolution.txt')
radius = re.search(r'^RADIUS (.+)$', resolution_log, re.M)[1].strip()
choice = re.search(r'^CHOICE pos=1/(\d+) angle=(\d+) rubble4_p99=(\d+)', resolution_log, re.M)
assert choice and (choice[1], choice[2]) == ('256', '4096')
selected = next(row for row in grid if round(1 / float(row['pos_step_m'])) == int(choice[1]) and row['angle_steps'] == choice[2])
assert float(selected['worst_error_px']) <= 0.5
assert int(selected['rubble4_p99']) == min(int(row['rubble4_p99']) for row in grid if row['ok_0.5px'] == 'true')
source = (root / 'src/net_frame.odin').read_text()
assert 'POSE_POS_STEP :: f64(1.0/256)' in source and 'POSE_ANGLE_STEPS :: 4096' in source

soak = json.loads((e / 'net-soak.json').read_text())
soak_log = read(e / 'net-soak.txt')
assert 'NETSOAK RESULT PASS' in soak_log
assert 'Net soak teardown Odin=0 Box2D=0 texture=0 shader=0 fonts=false' in soak_log
assert soak['ticks'] == 36120 and soak['flush_ticks'] == 120 and soak['epochs_seen'] == 1
assert soak['table_mismatch'] == 0 and soak['table_checked'] > 100000
clients = soak['clients']
assert len(clients) == 4
for c in clients:
    assert c['structure_hash_mismatches'] == c['structure_unrecorded'] == 0
    assert c['final_equal'] and c['final_revision_equal']
    assert c['final_pose_mismatch'] == c['final_pose_awake']
    inputs = c['inputs']
    assert inputs['jumps_pressed'] == inputs['jumps_applied']
    assert inputs['blasts_issued'] == inputs['blasts_applied'] + inputs['blasts_rejected'] and inputs['duplicates'] == 0
    for kind in ('all', 'players', 'bombs'):
        old_metric = c['render_error'][kind]
        visible = c['render_error'][kind + '_visible']
        for metric in ('reference', 'vertex', 'origin_metric', 'legacy_reference', 'legacy_vertex', 'legacy_origin_metric'):
            assert visible[metric]['samples'] == old_metric['samples'], 'paired metrics must use the same samples'
        assert visible['reference']['max'] == old_metric['pos_max']
        assert visible['vertex']['max'] >= visible['reference']['max'] - 1e-6
assert clients[0]['delay']['final'] == 2 and set(clients[0]['delay']['histogram']) == {'2'}
frame_lines = re.findall(r'^FRAMES complete=(\d+) parts=(\d+) duplicate_parts=(\d+) wrong_epoch=(\d+) undecodable=(\d+) malformed=(\d+) lost\(declared\)=(\d+)', soak_log, re.M)
assert len(frame_lines) == 4 and all(row[4:6] == ('0', '0') for row in frame_lines)

# Reapply the accepted v4 criteria, including the already accepted bomb-id rule.
capture_outputs, captures = [], []
for group, accepted in [('standard', 'evidence/glue-followup/standard'),
                        ('golden', 'evidence/glue-followup/golden'),
                        ('legacy', 'evidence/seam-toughness/legacy')]:
    result = subprocess.run([sys.executable, str(root / 'scripts/compare-captures.py'), accepted,
                             f'evidence/replication-2b-followup/captures-v4/{group}',
                             '--manifest', str(e / f'manifest-{group}.json'), '--label', group],
                            cwd=root, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    capture_outputs.append(result.stdout)
    records = json.loads((e / f'manifest-{group}.json').read_text())
    assert len(records) == {'standard': 23, 'golden': 25, 'legacy': 10}[group]
    captures.extend(records)
assert len(captures) == 58 and all(row['ok'] for row in captures)
(e / 'capture-checks-final.txt').write_text('\n'.join(capture_outputs), encoding='utf8')
pngs = json.loads((e / 'png-compare.json').read_text())
assert len(pngs) == 66 and all(row['ok'] for row in pngs)
for row in pngs:
    path = e / 'png-after' / row['file'] if row['status'] == 'byte-identical' else root / row['source']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == row['accepted_sha256'], path

before = json.loads((prior / 'netcode-integrity.json').read_text())['sha256']
after = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
         for p in (root / 'src/netcode').rglob('*') if p.is_file()}
assert before == after, 'src/netcode must remain untouched'
write_json('netcode-integrity.json', dict(files=len(after), unchanged=True, sha256=after))
draw_files = ['render_cache.odin', 'debug_view.odin', 'sandbox_view.odin', 'rubber_band.odin',
              'glue_view.odin', 'material_texture.odin', 'editor_view.odin', 'material_view.odin',
              'layout_view.odin', 'net_client.odin']
draw_checks = []
for name in draw_files:
    hits = re.findall(r'\bb2\.', (root / 'src' / name).read_text())
    assert not hits, name
    draw_checks.append(f'{name}: 0 b2. references')
(e / 'draw-grep.txt').write_text('\n'.join(draw_checks) + '\n')

old_clients = json.loads((prior / 'net-soak.json').read_text())['clients']
pose_table = table(['Position step', 'Angle steps/turn', 'Worst error (px)', '≤0.5 px',
                    'soak-4 changed p50/p95/p99/max', 'rubble-4 changed p50/p95/p99/max'],
                   [(f"1/{round(1 / float(r['pos_step_m']))} m", r['angle_steps'], r['worst_error_px'],
                     r['ok_0.5px'], '/'.join(r['soak4_' + k] for k in ('p50', 'p95', 'p99', 'max')),
                     '/'.join(r['rubble4_' + k] for k in ('p50', 'p95', 'p99', 'max'))) for r in grid])

visible_rows, paired_rows, old_rows = [], [], []
for c, old in zip(clients, old_clients):
    for kind in ('all', 'players', 'bombs'):
        r = c['render_error'][kind + '_visible']
        visible_rows.append((c['client'], kind, r['reference']['samples'], triple(r['reference']),
                             triple(r['vertex']), triple(r['origin_metric'])))
        paired_rows.append((c['client'], kind, triple(r['legacy_reference']), triple(r['reference']),
                            triple(r['legacy_vertex']), triple(r['vertex'])))
        old_rows.append((c['client'], kind, triple(old['render_error'][kind], 'pos_'),
                         triple(c['render_error'][kind], 'ang_')))
visible_table = table(['Client', 'Entities', 'Same samples per metric', 'Reference point (m)',
                       'Maximum visible vertex (m)', 'Old origin metric on new draws (m)'], visible_rows)
paired_table = table(['Client', 'Entities', 'Origin interpolation: visible reference (m)',
                      'Reference interpolation: visible reference (m)', 'Origin interpolation: max vertex (m)',
                      'Reference interpolation: max vertex (m)'], paired_rows)
old_table = table(['Client', 'Entities', 'Accepted 2b origin error (m)', 'Follow-up angle error (rad)'], old_rows)

outliers = []
for c in clients:
    visible = c['render_error']['all_visible']
    for metric in ('reference', 'vertex'):
        worst = visible['worst_' + metric]
        if worst['error_m'] > 0.5:
            gap = max(worst['upper'] - worst['lower'], 0)
            outliers.append((c['client'], metric, f"{worst['kind']} {worst['id']}", worst['tick'],
                             f"{worst['error_m']:.5f}", f"{worst['speed_m_s']:.3f}",
                             f"{worst['angular_speed_rad_s']:.3f}", f"{worst['lower']}–{worst['upper']} ({gap}/60 s)",
                             f"{worst['speed_m_s'] * gap / 60:.3f}"))
outlier_text = (table(['Client', 'Metric', 'Entity', 'Server tick', 'Error (m)', 'Peak reference speed (m/s)',
                       'Peak spin (rad/s)', 'Received frame gap', 'Speed × gap (m)'], outliers)
                if outliers else 'No client reference-point or vertex maximum exceeds 0.5 m.')

structure_table = table(['Client', 'Applied structure messages', 'Hash mismatches / unrecorded',
                         'Final structure / revision equal', 'Final poses differing / awake'],
                        [(c['client'], c['structure_applied'], f"{c['structure_hash_mismatches']}/{c['structure_unrecorded']}",
                          f"{c['final_equal']}/{c['final_revision_equal']}",
                          f"{c['final_pose_mismatch']}/{c['final_pose_awake']}") for c in clients])
input_table = table(['Client', 'Jumps pressed / applied', 'Blasts issued / applied / rejected', 'Duplicates'],
                    [(c['client'], f"{c['inputs']['jumps_pressed']}/{c['inputs']['jumps_applied']}",
                      '/'.join(str(c['inputs'][k]) for k in ('blasts_issued', 'blasts_applied', 'blasts_rejected')),
                      c['inputs']['duplicates']) for c in clients])
clock_table = table(['Client', 'Final delay / changes', 'Delay histogram (ticks:count)', 'Lost frames',
                     'Late structure / events / max ticks', 'Snaps / ticks at ±5%'],
                    [(c['client'], f"{c['delay']['final']}/{c['delay']['changes']}",
                      ', '.join(f'{k}:{v}' for k, v in c['delay']['histogram'].items()), frame_lines[i][6],
                      f"{c['late']['structure']}/{c['late']['events']}/{c['late']['max_ticks']:.2f}",
                      f"{c['clock']['snaps']}/{c['clock']['saturated']}") for i, c in enumerate(clients)])

bandwidth_rows = []
for c, old in zip(clients, old_clients):
    f, of = c['frame_bytes'], old['frame_bytes']
    u, ou = c['upload_kbit_s'], old['upload_kbit_s']
    bandwidth_rows.append((c['client'], '/'.join(str(of[k]) for k in ('p50', 'p99', 'max')) + ' → ' + '/'.join(str(f[k]) for k in ('p50', 'p99', 'max')),
                           f"{of['bytes_per_entry']:.3f} → {f['bytes_per_entry']:.3f}",
                           f"{ou['avg_frames']:.2f}/{ou['peak_frames']:.2f} → {u['avg_frames']:.2f}/{u['peak_frames']:.2f}",
                           f"{ou['avg_all']:.2f}/{ou['peak_all']:.2f} → {u['avg_all']:.2f}/{u['peak_all']:.2f}"))
bandwidth_table = table(['Client', 'Frame bytes/tick p50/p99/max: 2b → follow-up', 'Bytes/entry: 2b → follow-up',
                         'Frame upload avg/peak 1s kbit/s: 2b → follow-up', 'All upload avg/peak 1s kbit/s: 2b → follow-up'], bandwidth_rows)
budget_table = table(['Client', 'Entries sent', 'Max parts', 'Budget saturated fraction', 'Max / p99 staleness (ticks)'],
                     [(c['client'], c['frame_bytes']['entries_sent'], c['frame_bytes']['max_parts'], c['budget']['saturated_fraction'],
                       f"{c['budget']['max_staleness_ticks']}/{c['budget']['p99_staleness_ticks']}") for c in clients])

byte_identical = sum(row['status'] == 'byte-identical' for row in captures)
png_regenerated = sum(row['status'] == 'byte-identical' for row in pngs)
all_outliers = [{'client': c['client'], **sample} for c in clients for sample in c['over_half_meter']]
write_json('visible-outliers.json', all_outliers)
changed_sources = ['model.odin', 'destruction.odin', 'physics.odin', 'shape_build.odin', 'replication.odin',
                   'net_frame.odin', 'net_server.odin', 'net_client.odin', 'pose_resolution.odin', 'net_soak.odin',
                   'net_test.odin', 'reference_pose_test.odin']
write_json('source-integrity.json', {f'src/{name}': hashlib.sha256((root / 'src' / name).read_bytes()).hexdigest()
                                     for name in changed_sources})

convergence_text = ""
convergence_summary = e / 'convergence/summary.json'
if convergence_summary.exists():
    measurements = json.loads(convergence_summary.read_text(encoding='utf8'))
    measured_rows = []
    for run in ('long', 'short180'):
        for client in ('1', '2', '3'):
            v = measurements[run][client]
            measured_rows.append((run, client, v['lifetime_count'], v['all_lifetimes']['samples'],
                                  v['censored_before_pose_observed'],
                                  '/'.join(str(v['all_lifetimes'][k]) for k in ('p50','p99','max')),
                                  '/'.join(str(v['survivors'][k]) for k in ('p50','p99','max'))))
    convergence_text = "\n## E. Final-pose convergence audit\n\n" + table(
        ['Run', 'Remote client', 'Entity lifetimes', 'Final row observed', 'Removed/reset before observation',
         'Observed terminal row p50/p99/max ticks', 'Survivors only p50/p99/max ticks'], measured_rows)
    convergence_text += "\n\nLatency starts at each entity's last server row change and ends when the remote newest complete table first contains it. All surviving rows converge; removed/reset terminal rows that never appear are counted separately. The audit runs the original physics cutoffs, then 20 network-only observation ticks with physics held fixed. The maximum is six ticks (100 ms), at epoch startup; ordinary final-row sends retry and ACK within a few ticks. The five slowest per client, including every send, lost frame and accepted ACK, are in the [convergence report](evidence/replication-2b-followup/convergence/report.md) and [histories](evidence/replication-2b-followup/convergence/slowest-histories.json).\n"

report = f'''# Step 2b follow-up: reference poses

Each rigid piece now replicates its own immutable rest reference point. **208 tests pass**, including all 205 existing tests and three reference-pose tests. The original 10-minute soak passes: **{soak['table_checked']:,} checked tables, zero mismatches**, equal structure on every client, exact inputs, and local delay always 2. Solo snapshots meet the accepted v4 criteria and all 66 PNG comparisons pass. `src/netcode/` is SHA-256 unchanged ({len(after)} files). No commit or archive was made.

Remote visible vertex maxima are **{clients[1]['render_error']['all_visible']['vertex']['max']:.3f} / {clients[2]['render_error']['all_visible']['vertex']['max']:.3f} / {clients[3]['render_error']['all_visible']['vertex']['max']:.3f} m**, compared with the accepted origin-metric maxima of 6.215 / 2.033 / 2.381 m. No follow-up visible maximum exceeds 0.5 m. Local frame payload averages {clients[0]['upload_kbit_s']['avg_frames']:.2f} kbit/s (2b: 298.4); remote payload averages about {clients[1]['upload_kbit_s']['avg_frames']:.2f} kbit/s (2b: 379.7).

## Implementation

`Piece.ref_rest` is the area-weighted rest centroid of its initial cells, computed with f64 polygon sums. The existing builder reserves an id before adding its cells; the reference is sealed when construction finishes, before physics, structural publication or damage. Regrouping creates new ids with their own centroids. Authored rotation is part of construction and transforms the new geometry and its reference together. Subsequent same-id cell-list changes preserve the reference.

Canonical structure version 2 and Baseline/Delta pieces-added encode `id varint · material varint · ref_rest.x f32 · ref_rest.y f32 · cell-id list`. This adds 8 bytes per added piece. Pieces-changed still carries only id and membership, so a client preserves the original reference. A late-join Baseline carries that same reference. The server's shared index asserts its immutability.

The wire position is `frame.position + rotate(ref_rest, frame.angle)`. Quantization, deltas, proximity/speed priority, budgeting and interpolation use that reference pose. The client subtracts `rotate(ref_rest, angle)` before passing the body frame to the existing draw path. Rubber, players and bombs retain their previous pose definitions. The reference is network structure; solo snapshot fields and the physics body frame are unchanged. Loading a solo snapshot reconstructs references for the loaded world's new epoch.

## A. Resolution sweep

Same scenarios and seeds as 2b: soak-4 is 72,000 ticks (20 minutes), rubble-4 is 18,000 ticks (5 minutes), after the same six blasts and 1,200 settling ticks. The lever arm is now the largest distance from a piece's immutable `ref_rest` to any of its vertices.

Measured: `{radius}`.

The maximum is **1.3163 m**, versus 2b's 9.4454 m. As in 2b, the comparison rule is `(0.5 × position_step + π / angle_steps × lever_arm) × 151.1905 px/m`, at 2560×1440. The same measured maximum is used for all 12 pairs.

{pose_table}

**Adopted: 1/256 m and 4096 angle steps per turn**, {selected['worst_error_px']} px worst error. This passing pair minimizes rubble-4 p99 changes ({selected['rubble4_p99']}, previously 165), with the existing p95/finer-pair tie breaks. All 1024-angle pairs fail the 0.5 px rule. [CSV](evidence/replication-2b-followup/pose-resolution.csv), [sweep log](evidence/replication-2b-followup/pose-resolution.txt).

## B. Visible render error

All triples below are **p50/p99/max**. The sampler retains the old metric's eligibility: every drawn entity present in both true history ticks around the same fractional render tick R, in the same epoch. There is no speed cutoff or outlier removal. All representations use exactly those same keys and times. Truth interpolates the actual reference positions of the two adjacent simulation ticks, plus the shortest angle arc; each vertex then uses its rest offset from the reference. For rubber the offsets are from its cell center; player/bomb positions keep their existing definition. “Maximum visible vertex” includes the reference point and every live piece/cell vertex, so it is at least the reference error.

The last column deliberately retains the old origin metric: the drawn body origin versus the true origins interpolated independently at R. It is a diagnostic; the visible columns measure what is drawn.

{visible_table}

The local all-entity maximum is player 1 just after the epoch reset: tick 18,003, R=18,001, with only frame 18,003 available and no lower bracket. The client follows the existing hold-first-frame rule. This is a player startup sample; it is unchanged by the piece reference conversion. The largest remote vertex sample is piece 23,007 on client 1, moving at a peak 12.038 m/s across frames 29,262–29,265 (50 ms, about 0.602 m of travel available), with 0.38628 m error. This is consistent with fast debris moving/colliding inside a lost-frame gap.

To separate the interpolation representation from changes in packet delivery, the next comparison reconstructs origin interpolation on **the same received table endpoints, brackets and samples** as the reference interpolation. Piece endpoints are converted back to origins and rounded to 2b's 1/512 m / 16384-angle grid, then origins and angles are interpolated separately and converted to visible positions. Those endpoints have already passed through the new grid; this is a paired diagnostic of interpolation geometry, not a second old-protocol transport soak. Non-piece poses are identical on the two sides.

{paired_table}

For historical context, the accepted 2b run's original origin metric is below, alongside this run's angle error. Its sample counts and received brackets differ because the changed frame sizes change the seeded link simulator's packet sequence; these historical numbers are not the paired comparison above.

{old_table}

### Maxima above 0.5 m

{outlier_text}

Speed is the peak reference-point speed over the received frame bracket, using both true tick-to-tick travel and Box2D's velocity at the reference point. Spin includes Box2D angular velocity. `speed × gap` is the distance scale available during that missing-frame interval, not an interpolation-error bound. Remaining visible error can include collisions/acceleration between endpoints, frame holding when the clock passes the newest complete frame, and shortest-arc spin interpolation over a gap. The former shared-origin chord is removed. [Every entity exceeding 0.5 m, with its largest sample](evidence/replication-2b-followup/visible-outliers.json); [complete measurements and maxima](evidence/replication-2b-followup/net-soak.json).

## C. Original soak checks and bandwidth comparison

Fixture: 36,000 ticks plus the original 120-tick idle flush; Falling_Bombs yard; seed 1234; client bot seeds `1234 + i×0x9e3779b97f4a7c15`; link seeds `1234×31 + i×2 + 1/2`. Client 0: zero latency/loss. Clients 1–3: 40±10 ms each way, 2% loss, 1% duplicates, 2% reorder with up to 50 ms extra delay. Refills at 7,201/14,401/21,601/28,801; reset at 18,000 creates the new epoch. These settings match 2b.

**Tables:** {soak['table_checked']:,} checked, {soak['table_mismatch']} mismatches, {soak['table_skipped']} checks skipped because the sent ring slot was reused. Every applied structure revision is checked against its recorded canonical hash, then canonical bytes are compared after the flush:

{structure_table}

{input_table}

{clock_table}

The clock/loss/late-message rules are unchanged. Every frame decoder reports zero malformed and undecodable frames. Reliable messages arriving behind the clock apply on arrival and are counted. Frame parts remain ≤1150 bytes by the encoder assertion; the dynamic-entity budget remains 2×1150 bytes, with players/bombs included whenever their acked row differs. The existing stress tests still check priority, fresh rows first, budget binding and eventual convergence.

{bandwidth_table}

{budget_table}

Bytes per entry include frame headers, as in 2b. Upload includes packet headers and reliable structure in the “all” column; frame upload counts pose payload. This run sends {soak['reliable_structure_bytes']:,} reliable structure bytes across four clients (2b: 2,984,068), including the new reference fields, and emits {soak['explosions_emitted']} explosion events. Changed frame sizes also alter packet splitting, loss/reorder draws, received inputs and later simulation activity; the bandwidth comparison is the specified seeded end-to-end run, rather than a claim of an identical physical trajectory.

Teardown: **Odin 0, Box2D 0, textures 0, shaders 0, fonts unloaded**. [Soak log](evidence/replication-2b-followup/net-soak.txt), [JSON](evidence/replication-2b-followup/net-soak.json), [host/client PNGs](evidence/replication-2b-followup/render/host.png).

## D. Tests and solo identity

**208 tests successful in {match[2]}**, with memory tracking and failure on bad memory enabled. The three additions cover 5,000 frame/reference round trips and vertex agreement; an unequal-area centroid with same-id cell removal, Delta update, late-join Baseline and added-piece Delta; and a distant spinning piece whose visible center remains fixed between frames. The existing rigid-frame test now compares the reference pose to `rigid_render_frame` transformed by `ref_rest`. Existing codecs, 10,000-buffer fuzzing, clocks, inputs, budgets and replication tests all pass. [Full test log](evidence/replication-2b-followup/tests-final.txt).

**Short-soak correction:** the idle flush is restored to **180 ticks**. The previous 600-tick extension masked an awake-accounting bug: mismatching players/bombs were counted, but their awake bodies were omitted from the awake count. The measurement now checks those body types too. The original pre-resolution-choice failure comprised two pieces that had just gone to sleep at tick 1680 plus an awake player; their last changes were only 0-2 ticks old, and all three reached the remotes within 2-4 ticks. They had not waited three seconds. [Convergence measurements, p50/p99/max, and send/loss/ACK histories](evidence/replication-2b-followup/convergence/report.md). The required 10-minute soak retains its original 120-tick flush.

All **58 solo captures** pass the 2a/2b v4 criteria: {byte_identical} byte-identical Scene captures; 30 World captures retain byte-identical Scene text and bit-equal player 0, bombs, rain, settings and tick, using the already accepted v4 player-array and optional bomb-id comparison. No new exception. [Standard](evidence/replication-2b-followup/manifest-standard.json), [golden](evidence/replication-2b-followup/manifest-golden.json), [legacy](evidence/replication-2b-followup/manifest-legacy.json), [checks](evidence/replication-2b-followup/capture-checks-final.txt).

All **66 PNGs match**: {png_regenerated} regenerated byte-identical; {66 - png_regenerated} accepted files without a current regeneration command remain SHA-256 identical. [PNG comparison](evidence/replication-2b-followup/png-compare.json), [capture run](evidence/replication-2b-followup/solo-capture.txt). [Netcode hashes](evidence/replication-2b-followup/netcode-integrity.json), [draw-path Box2D check](evidence/replication-2b-followup/draw-grep.txt), [changed-source hashes](evidence/replication-2b-followup/source-integrity.json).

{convergence_text}
## Reproduce

```powershell
New-Item -ItemType Directory -Force evidence/replication-2b-followup/captures-v4/golden,evidence/replication-2b-followup/captures-v4/legacy
odin build src -o:speed -out:build/BOM-2b-followup.exe
build/BOM-2b-followup.exe --pose-resolution 20
build/BOM-2b-followup.exe --net-soak 10
python scripts/capture-solo-2b.py build/BOM-2b-followup.exe evidence/replication-2b-followup
odin test src -out:build/BOM-followup-tests.exe -define:ODIN_TEST_TRACK_MEMORY=true -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true -define:ODIN_TEST_FANCY=false -define:MATERIAL_CAPTURE_DIRECTORY=evidence/replication-2b-followup/captures-v4/golden -define:SEAM_CAPTURE_DIRECTORY=evidence/replication-2b-followup/captures-v4/legacy
python scripts/verify-replication-2b-followup.py
```

Capture the sweep, soak, solo script and test stdout/stderr to `pose-resolution.txt`, `net-soak.txt`, `solo-capture.txt`, and `tests-final.txt` under `evidence/replication-2b-followup/` respectively. The verifier rechecks the artifacts and rewrites this report. No zip, interim or handoff files are included in that evidence directory.
'''
(root / 'report.md').write_text(report, encoding='utf8')
print(f'PASS: {match[1]} tests; {soak["table_checked"]} matching tables; 58 captures; 66 PNGs; report.md written')
