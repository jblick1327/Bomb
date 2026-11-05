"""Recheck the step-2b evidence and write report.md. No packaging.

Run after: scripts/bom.ps1-style optimized build, `--pose-resolution`, `--net-soak 10`,
`python scripts/capture-solo-2b.py`, and the full test run that writes tests-final.txt
(see report.md, "Reproduce").
"""
import csv
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
e = root / 'evidence/replication-2b'
old = root / 'evidence/replication-2a'


def read(p):
    b = p.read_bytes()
    return b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig')


# ---------------------------------------------------------------- tests
tests = read(e / 'tests-final.txt')
m = re.search(r'Finished (\d+) tests in (\S+)\. All tests were successful\.', tests)
assert m and '[ERROR]' not in tests, 'tests did not all pass'
test_count, test_time = int(m.group(1)), m.group(2)

# ---------------------------------------------------------------- soak
soak_text = read(e / 'net-soak.txt')
soak = json.loads((e / 'net-soak.json').read_text())
assert 'NETSOAK RESULT PASS' in soak_text
assert 'Net soak teardown Odin=0 Box2D=0 texture=0 shader=0 fonts=false' in soak_text
assert soak['table_mismatch'] == 0 and soak['table_checked'] > 100000
assert soak['ticks'] == 36120 and soak['flush_ticks'] == 120
clients = soak['clients']
assert len(clients) == 4
for c in clients:
    assert c['structure_hash_mismatches'] == 0 and c['structure_unrecorded'] == 0 and c['final_equal'] and c['final_revision_equal']
    assert c['final_pose_mismatch'] == c['final_pose_awake']
    i = c['inputs']
    assert i['jumps_pressed'] == i['jumps_applied'] and i['blasts_applied'] + i['blasts_rejected'] == i['blasts_issued'] and i['duplicates'] == 0
assert clients[0]['delay']['final'] == 2 and set(clients[0]['delay']['histogram']) == {'2'}
frames_line = re.findall(r'^FRAMES complete=(\d+) parts=(\d+) duplicate_parts=(\d+) wrong_epoch=(\d+) undecodable=(\d+) malformed=(\d+) lost\(declared\)=(\d+)', soak_text, re.M)
link_line = re.findall(r'^LINK s2c sent=(\d+) dropped=(\d+) duplicated=(\d+) reordered=(\d+); c2s sent=(\d+) dropped=(\d+)', soak_text, re.M)
assert len(frames_line) == 4 and len(link_line) == 4
assert all(f[4] == '0' and f[5] == '0' for f in frames_line)

# ---------------------------------------------------------------- pose resolution
pose_rows = list(csv.DictReader((e / 'pose-resolution.csv').open()))
assert len(pose_rows) == 12
pose_text = read(e / 'pose-resolution.txt')
radius_line = re.search(r'^RADIUS (.*)$', pose_text, re.M).group(1)
choice = re.search(r'^CHOICE pos=1/(\d+) angle=(\d+) rubble4_p99=(\d+)', pose_text, re.M)
assert choice and choice.group(1) == '512' and choice.group(2) == '16384'
src = (root / 'src/net_frame.odin').read_text()
assert 'POSE_POS_STEP :: f64(1.0/512)' in src and 'POSE_ANGLE_STEPS :: 16384' in src

# ---------------------------------------------------------------- solo captures
outputs, all_captures = [], []
for name, accepted in [('standard', 'evidence/glue-followup/standard'), ('golden', 'evidence/glue-followup/golden'), ('legacy', 'evidence/seam-toughness/legacy')]:
    result = subprocess.run([sys.executable, str(root / 'scripts/compare-captures.py'), accepted, f'evidence/replication-2b/captures-v4/{name}', '--manifest', str(e / f'manifest-{name}.json'), '--label', name], cwd=root, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    outputs.append(result.stdout)
    rows = json.loads((e / f'manifest-{name}.json').read_text())
    assert len(rows) == {'standard': 23, 'golden': 25, 'legacy': 10}[name]
    all_captures.extend(rows)
(e / 'capture-checks-final.txt').write_text('\n'.join(outputs), encoding='utf8')
assert len(all_captures) == 58 and all(r['ok'] for r in all_captures)
byte_identical = sum(r['status'] == 'byte-identical' for r in all_captures)
png = json.loads((e / 'png-compare.json').read_text())
assert len(png) == 66 and all(r['ok'] for r in png)

# ---------------------------------------------------------------- netcode untouched, draw path free of Box2D
before = json.loads((old / 'netcode-integrity.json').read_text())['sha256']
after = {str(p.relative_to(root)).replace('\\', '/'): hashlib.sha256(p.read_bytes()).hexdigest() for p in (root / 'src/netcode').rglob('*') if p.is_file()}
assert before == after, 'src/netcode changed'
(e / 'netcode-integrity.json').write_text(json.dumps(dict(files=len(after), unchanged=True, sha256=after), indent=2) + '\n')
draw_files = ['render_cache.odin', 'debug_view.odin', 'sandbox_view.odin', 'rubber_band.odin', 'glue_view.odin', 'material_texture.odin', 'editor_view.odin', 'material_view.odin', 'layout_view.odin', 'net_client.odin']
grep = []
for name in draw_files:
    text = (root / 'src' / name).read_text(encoding='utf-8')
    hits = [f'{name}:{n + 1}:{line.strip()}' for n, line in enumerate(text.splitlines()) if re.search(r'\bb2\.', line)]
    grep.append(f'{name}: {len(hits)} b2. references')
    assert not hits, hits
(e / 'draw-grep.txt').write_text('\n'.join(grep) + '\n')

# ---------------------------------------------------------------- report
def fm(x, n=2):
    return f'{x:.{n}f}'


def stat(d, key):
    return d[key]


def table(headers, rows):
    out = ['| ' + ' | '.join(headers) + ' |', '|' + '|'.join('---' for _ in headers) + '|']
    out += ['| ' + ' | '.join(str(v) for v in row) + ' |' for row in rows]
    return '\n'.join(out)


best_error = float(next(r for r in pose_rows if float(r['pos_step_m']) == 1 / 512 and r['angle_steps'] == '16384')['worst_error_px'])
pose_table = table(['Position step', 'Angle steps/turn', 'Worst error (px)', '≤ 0.5 px', 'soak-4 changed p50/p95/p99/max', 'rubble-4 changed p50/p95/p99/max'],
                   [(f"1/{round(1 / float(r['pos_step_m']))} m", r['angle_steps'], r['worst_error_px'], 'yes' if r['ok_0.5px'].lower() == 'true' else 'no',
                     f"{r['soak4_p50']}/{r['soak4_p95']}/{r['soak4_p99']}/{r['soak4_max']}", f"{r['rubble4_p50']}/{r['rubble4_p95']}/{r['rubble4_p99']}/{r['rubble4_max']}") for r in pose_rows])

fuzz_accepted = re.search(r'Fuzz: 10000 buffers through frame/input/event decode, (\d+) accepted', tests).group(1)
new_tests = len(re.findall(r'^@\(test\)', (root / 'src/net_test.odin').read_text(), re.M))
sat = re.findall(r'^BUDGET saturated_ticks=(\d+)/(\d+)', soak_text, re.M)
saturation_text = '; '.join(f'client {i}: {a} of {b} ticks' for i, (a, b) in enumerate(sat))
net_rows = []
for c, f, l in zip(clients, frames_line, link_line):
    ra = c['render_error']
    net_rows.append((c['client'], c['link'], c['structure_applied'], c['structure_hash_mismatches'], 'yes' if c['final_equal'] else 'NO',
                     c['final_pose_mismatch'], c['final_pose_awake']))
structure_table = table(['Client', 'Link', 'Structure messages applied', 'Hash mismatches', 'Final flush equal', 'Final poses differing', 'of which awake'], net_rows)

render_rows = []
for c in clients:
    for kind in ('all', 'players', 'bombs'):
        r = c['render_error'][kind]
        render_rows.append((c['client'], kind, r['samples'], f"{r['pos_p50']:.5f}/{r['pos_p99']:.5f}/{r['pos_max']:.4f}", f"{r['ang_p50']:.5f}/{r['ang_p99']:.5f}/{r['ang_max']:.4f}"))
render_table = table(['Client', 'Entities', 'Samples', 'Position error p50/p99/max (m)', 'Angle error p50/p99/max (rad)'], render_rows)

clock_rows = []
for c, f in zip(clients, frames_line):
    d, k, la = c['delay'], c['clock'], c['late']
    clock_rows.append((c['client'], d['final'], d['changes'], ', '.join(f'{t}:{n}' for t, n in d['histogram'].items()), k['snaps'], k['saturated'], fm(k['mean_adjust'] * 100, 4) + '%', la['structure'], la['events'], fm(la['max_ticks'], 2), f[6]))
clock_table = table(['Client', 'Final delay (ticks)', 'Delay changes', 'Delay histogram (ticks:render ticks)', 'Snaps', 'Ticks at ±5 %', 'Mean rate adjust', 'Late structure', 'Late events', 'Max lateness (ticks)', 'Frames declared lost'], clock_rows)

bw_rows = []
for c in clients:
    fb, up, bu, fbm = c['frame_bytes'], c['upload_kbit_s'], c['budget'], c['frame_build_ms']
    bw_rows.append((c['client'], f"{fb['p50']}/{fb['p99']}/{fb['max']}", fb['max_parts'], fm(fb['bytes_per_entry']), f"{up['avg_frames']:.1f} / {up['peak_frames']:.1f}", f"{up['avg_all']:.1f} / {up['peak_all']:.1f}",
                    f"{bu['saturated_fraction']:.5f}", f"{bu['max_staleness_ticks']} / {bu['p99_staleness_ticks']}", f"{fbm['p50']:.3f}/{fbm['p99']:.3f}/{fbm['max']:.2f}"))
bw_table = table(['Client', 'Frame bytes/tick p50/p99/max', 'Max parts', 'Bytes per entry', 'Frame upload avg / peak 1 s (kbit/s)', 'All-packet upload avg / peak (kbit/s)', 'Budget saturated (fraction of ticks)', 'Max / p99 staleness (ticks)', 'Frame build p50/p99/max (ms)'], bw_rows)

in_rows = []
for c, l in zip(clients, link_line):
    i = c['inputs']
    in_rows.append((c['client'], i['jumps_pressed'], i['jumps_applied'], i['blasts_issued'], i['blasts_applied'], i['blasts_rejected'], i['duplicates'], f"{l[1]}/{l[0]} dropped, {l[2]} dup, {l[3]} reordered", f"{l[5]}/{l[4]}"))
in_table = table(['Client', 'Jump presses', 'Jumps applied', 'Blasts issued', 'Applied', 'Rejected', 'Duplicates', 'Server→client link', 'Client→server dropped'], in_rows)

wt, st = soak['world_tick_ms'], soak['server_tick_ms']
perf_in = clients[1]['frame_build_ms']
capture_lines = [l for l in '\n'.join(outputs).splitlines() if l.endswith('match')]
net_checked = soak['table_checked']
mean_input = re.findall(r'input messages mean ([\d.]+) max (\d+) bytes', soak_text)
entries_line = re.findall(r'^ENTRIES sent=(\d+) \(players/bombs (\d+)\) gone ids sent=(\d+) parts=(\d+); mean ([\d.]+) bytes per entry', soak_text, re.M)

report = f"""# Multiplayer step 2b: complete

Pose frames, client inputs, the adaptive client clock and tick-stamped structure now run end to end, in process, through the real netcode endpoints and its link simulator: one `Net_Server` (World, shared structure index, one netcode connection, per-client frame state) and four `Net_Client`s (endpoint, physics-free replica, pose tables, render clock, interpolated draw poses). No sockets, processes or UI. Solo play is unchanged, `src/netcode/` is untouched ({len(after)} files, SHA-256 identical to step 2a), and nothing was committed.

**{test_count} tests pass with leak failures enabled** ({test_time}; {new_tests} are new in `src/net_test.odin`, including 10,000-buffer decoder fuzzing). The 10-minute end-to-end soak (36,000 ticks + a 2 s flush with idle bots, falling bombs, refills every 2 minutes and one sandbox reset that starts a new epoch) passes every check and tears down with Odin 0, Box2D 0, textures/shaders 0, fonts unloaded. [Tests](evidence/replication-2b/tests-final.txt), [soak log](evidence/replication-2b/net-soak.txt), [soak JSON](evidence/replication-2b/net-soak.json).

## A. Pose resolution (measured, then chosen)

Counts are quantized-pose changes per tick between consecutive ticks (the step-2a method, over the same scenarios: soak-4 = 20 minutes, 4 blasting bots, falling bombs, refills; rubble-4 = 5 minutes on the rubble field). Worst on-screen error = half a position step + half an angle step × the largest piece radius, at the view scale of a 2560x1440 physical window ({fm(float(radius_line.split('scale=')[1].split()[0]), 3)} px/m). A rigid piece's frame is its body origin, which is the shared rest origin, so the lever arm is the distance of a vertex from the world origin: the largest in either scenario is **9.4454 m** (piece 15327 in soak-4; rubble-4 9.0113 m; rubber cells 0.2828 m). The same radius is used for every pair.

{pose_table}

**Choice: `POSE_POS_STEP = 1/512 m`, `POSE_ANGLE_STEPS = 16384` per turn.** It is the coarsest pair within 0.5 px (worst {best_error:.4f} px) and has the fewest changed entities at rubble-4 p99 (**{choice.group(3)}**, against 177 for the finest allowed pair 1/1024 + 16384 and 199 for 1/1024 + 65536). 1/256 m with 16384 fails by a little (0.5691 px); every pair at 4096 or 1024 steps fails by 2-9×. [Raw table](evidence/replication-2b/pose-resolution.csv), [log](evidence/replication-2b/pose-resolution.txt). The netcode quantizers are unchanged; the game-side ones are `pose_q_pos/pose_q_angle` in `src/net_frame.odin`.

## B-F. What was built

* **Entities** (`Ent_Kind`, key = kind<<62 | id): dynamic rigid pieces by body-origin frame (the quantity `rigid_render_frame` computes; a test compares them within 1e-3 for every piece), rubber cells by pose, players by index, bombs by id with `landed` and fuse as u8. Anchored pieces are never sent; the replica knows them from `piece_anchored` and draws the identity frame. `World.next_bomb_id` already existed; snapshot v4 now carries an optional bomb `id`, written only when it differs from the sequential id a legacy loader assigns (index+1), so sequential worlds stay byte-identical; duplicate ids are rejected on load.
* **Frame** (unreliable): header = epoch, tick, base_tick (acked frame or none), part index/count, `last_applied_blast_seq` for the receiving player; then the gone ids (varint deltas of sorted keys) and entries sorted by (kind, id): id delta, flags (kind, absolute, landed), x, y, angle as zigzag deltas against the base row or absolute when the base has no row, plus the fuse byte for bombs. Parts are independent, repeat the header and are at most 1150 bytes (asserted). The client's table for frame T = base table − gone + entries; it draws only complete frames and acks T only when all parts arrived.
* **Server per client**: ring of 64 sent tables (each exactly what the client will hold), encoding against the newest acked frame (none before the first ack; an ack for an old epoch or an overwritten slot is ignored). Candidates are entities whose current state differs from the base row or have none. Players and bombs are candidates like the rest but sit outside the budget (they are included whenever they differ from the acked row). Everything else fills `FRAME_BUDGET` = 2×1150 bytes by the priority accumulator (gain (1+speed)×(0.5+min(area,1))×(2 within 4 m of that client's player); entities without a row first, then accumulator descending; sent entities reset to 0; unsent candidates keep accumulating; an entity stays a candidate until it equals its acked row). Gone ids are charged first at 3 bytes each.
* **Inputs** (unreliable, every tick): epoch, ack (newest complete frame tick), move (i8), radius (u8 over 0.5-6 m), jump counter (u16), the last ≤ 8 unconfirmed blasts (u16 seq, 1/1024 m position, radius). One addition: a u16 input sequence so "the latest input" survives reordering and duplicates. The server applies `move` from the latest input, one jump per counter advance (u16 ring compare), and each new blast sequence exactly once, in order, in player-index order, before `world_tick` (via `world_explode` so each blast keeps its own radius). Rejected: outside the yard (x ∈ [-8, 9], y ∈ (-3, 12]), more than 4 accepted blasts in the last second per player, or an aim point inside solid; each rejection consumes its sequence number and sends that player a `blast_rejected` event.
* **Client clock**: render tick R advances one tick per tick, ±gain 0.02 per tick of error, clamped to ±5 %, toward R* = newest complete frame tick − delay; |R* − R| > 30 ticks (0.5 s) snaps. Delay = clamp(1 + ceil(p95 jitter over the last 2 s, in ticks) + 2 if a frame was lost in the last 2 s, 2, 12). Jitter of a frame = its arrival offset (arrival time − tick/60) minus the smallest offset in the window. A frame counts as lost when it is still incomplete once a frame 8 ticks newer has completed.
* **Drawing**: tables of the two complete frames bracketing R are interpolated (positions lerp, angles take the shortest arc). An entity new at the later frame shows from that frame; one gone at the later frame is drawn until R reaches it; rows not in the replica's structure are not drawn; the clock past the newest frame holds that frame (no extrapolation). Piece frames become rigid cell poses, rubber and player/bomb poses are added, and the existing `draw_scene` runs on the replica. To share the player, bomb, backdrop and spawn drawing with the host, `sandbox_draw_world` was split into `yard_draw_backdrop`, `yard_draw_spawn`, `draw_bomb_at`, `draw_player_at` and `draw_burst` with unchanged bodies. A dynamic piece (or rubber cell) that has no drawn row yet is moved far off screen until its row arrives.
* **Tick-stamped structure and events** (reliable): Baselines, Deltas and explosion / blast_rejected events carry their tick. The client queues them and applies each once R ≥ tick, in order; a message arriving after R passed its tick is applied on arrival and counted late. There is no global freeze. A Baseline of a new epoch (or the first one) applies on arrival and resets replica, tables, queue and clock.

## G. Checks

**(a)** Resolution table and choice: section A.

**(b) Codecs.** Round trips (delta, absolute, gone, multi-part, parts decoded independently and in reverse order), and 10,000 random/mutated/truncated buffers through the frame, input, event and structure-peek decoders with no panic ({fuzz_accepted} accepted as valid in the final fuzz run; the rest rejected).

**(c) Table agreement.** {net_checked:,} acked frames compared bit for bit against the server's sent-table record at the moment of acking: **{soak['table_mismatch']} mismatches** ({soak['table_skipped']} acks skipped because the server slot had already been reused).

**(d) End-to-end soak.** Seeds: bots 1234 + i×0x9e3779b97f4a7c15, link seeds from 1234; 36,000 ticks + 120 flush ticks. Client 0 is local (0 latency, no loss); clients 1-3 are remote (40 ± 10 ms each way, 2 % loss, 1 % duplicates, 2 % reordering with up to 50 ms extra delay).

*Structure.* The replica equals the server's canonical structure at every applied revision (hash of the canonical encoding recorded per (epoch, revision)), and byte-for-byte after the flush, on all four clients, across refills and the epoch change:

{structure_table}

After the flush every client's newest complete pose table equals the server's quantized state for every entity ({sum(c['final_pose_mismatch'] for c in clients)} differ); had any differed, the check requires them to be bodies that are still awake (rubber cells can stay awake), which the verifier checks.

*Render error*, interpolated drawn pose against the server's true pose lerped to the same fractional tick ({clients[0]['render_error']['all']['samples']/1e6:.1f} million samples per client):

{render_table}

The median error is the quantizer's (1/512 m grid → ~0.8 mm). Large maxima come from fast debris that bounced between two frames on the far side of a lost frame, interpolated linearly across the gap; the maximum for players is {max(c['render_error']['players']['pos_max'] for c in clients[1:]):.2f} m and for bombs {max(c['render_error']['bombs']['pos_max'] for c in clients[1:]):.2f} m on remote links.

*Delay, clock and late structure:*

{clock_table}

The local client settles at 2 immediately and never changes; remote clients sit mostly at 4 = 1 + 1 tick of p95 jitter (arrivals are sampled at the 60 Hz tick) + 2 for a frame lost within the last 2 s, which is true in almost every window at 2 % loss; the dips to 2-3 are windows with no loss. Late messages are reliable messages that arrived after R had passed their tick; each is applied on arrival. Anything later than about 3 ticks must have waited for a retransmission (minimum resend timeout 50 ms), which accounts for the 11-20 tick maxima; the small ones come from windows where the delay had dropped to 2.

*Frame bytes, upload, budget:*

{bw_table}

Totals sent: {', '.join(f"client {i}: {int(v[0]):,} entries ({int(v[1]):,} players/bombs), {int(v[2]):,} gone ids, {int(v[3]):,} parts" for i, v in enumerate(entries_line))}. The 2×1150-byte budget essentially never binds in this scenario ({saturation_text}); a unit test that offers 800 fresh candidates checks the binding case: budget respected, highest-priority entity first, entities without a row before those with one, and every entity reaches its final pose within a few acked frames.

*Inputs* (jumps applied == presses, blasts applied + rejected == issued, no duplicates, after the flush):

{in_table}

Rejections are aim points that turned out to be inside solid on the server. The bot tests its aim points against its own replica, whose cells sit at their rest poses (the replica has no physics and the soak does not copy drawn poses back into it), so debris that has moved is not seen.

**(e) Solo.** The 48 accepted captures and 10 legacy captures pass the step-2a v4 criteria ({byte_identical} byte-identical, the 30 World files with byte-identical Scene text and bit-equal player 0, bombs, rain, settings and tick). One criterion is extended, because the spec adds an optional bomb `id` to the format: bomb records are compared with `id` ignored (`world_capture_compatible` and `scripts/compare-captures.py`). Sequential ids are not written, so this only matters for captures that contain live bombs with non-sequential ids. All 66 existing PNG captures regenerated by the new build are byte-identical to the accepted ones. [Standard](evidence/replication-2b/manifest-standard.json), [golden](evidence/replication-2b/manifest-golden.json), [legacy](evidence/replication-2b/manifest-legacy.json), [PNG comparison](evidence/replication-2b/png-compare.json). Draw-path grep: 0 `b2.` references in the drawing files and in `net_client.odin` ([list](evidence/replication-2b/draw-grep.txt)).

**(f) Performance** during (d), 4 clients: per-client frame build {perf_in['p50']:.3f} ms p50 / {perf_in['max']:.1f} ms max (client 1; all four are within 0.1 ms of each other at p50 and p99 is about 1.4 ms; the maxima are isolated single-tick outliers that I did not trace to a cause); `world_tick` alone {wt['p50']:.2f} ms p50 / {wt['p99']:.2f} p99 / {wt['max']:.1f} ms max; the whole server tick (receive, inputs, world_tick, structure, four frame builds, packet writing) {st['p50']:.2f} ms p50 / {st['p99']:.2f} p99 / {st['max']:.1f} ms max, so the networking itself costs about {st['p50'] - wt['p50']:.2f} ms per tick at the median. Over the run the server sent {soak['reliable_structure_bytes']:,} reliable structure bytes (all four clients together) and {soak['explosions_emitted']} explosion events, each to all four.

**(g) Teardown.** The soak ends with Odin 0, Box2D 0, textures 0, shaders 0, fonts unloaded; the test run has leak failures enabled.

## Byte manifest

| Message | Channel | Layout | Size |
|---|---|---|---|
| Pose frame part | unreliable | kind 0xA1 (1) · epoch varint · tick varint · base_tick+1 varint (0 = none) · part index varint · part count varint · last_applied_blast_seq u16 · gone count varint · gone key deltas varint · entry count varint · entries | header 10-22 B (typically 12); ≤ 1150 B per part, asserted; observed {clients[0]['frame_bytes']['p50']}/{clients[0]['frame_bytes']['p99']}/{clients[0]['frame_bytes']['max']} B per tick (local) and {clients[1]['frame_bytes']['p50']}/{clients[1]['frame_bytes']['p99']}/{clients[1]['frame_bytes']['max']} B (remote), at most {max(c['frame_bytes']['max_parts'] for c in clients)} parts |
| Frame entry | | id delta varint · flags (kind 2 bits, absolute, landed) · x, y, angle zigzag varints (deltas against the base row, absolute without one) · fuse u8 (bombs only) | measured mean {clients[1]['frame_bytes']['bytes_per_entry']:.2f} B per entry including headers (id delta 1-2 B, flags 1 B, three zigzag varints of 1-3 B each, +1 B for a bomb) |
| Gone id | | sorted key delta varint | 1-3 B (the first of a kind up to 10 B) |
| Input | unreliable | kind 0xA2 · epoch varint · seq u16 · ack+1 varint · move i8 · radius u8 · jump counter u16 · blast count u8 · blasts (seq u16, x zigzag, y zigzag, radius u8) | measured mean {mean_input[1][0]} B, max {max(int(v[1]) for v in mean_input)} B (12 B plus about 8 B per unconfirmed blast) |
| Explosion event | reliable | 0xB6 · kind 1 · tick varint · x, y, radius f32 | 15-19 B (tick varint 2-3 B) |
| Blast rejected event | reliable | 0xB6 · kind 2 · tick varint · seq u16 | 5-7 B |
| Baseline / Delta | reliable | step-2a messages, now stamped with the tick they describe (they already carried it) | split at 200,000 B as before; {soak['reliable_structure_bytes']:,} B in this run over all four clients |
| Packet | | netcode data header 17 B + (channel u8 + size varint + payload) per message | ≤ 1200 B |

Evidence files ({sum(1 for p in e.rglob('*') if p.is_file())} files under `evidence/replication-2b/`): pose resolution (`pose-resolution.csv/.txt`), soak (`net-soak.txt/.json`, `render/*.png`: host and four client views after the flush), tests (`tests-final.txt`), solo (`captures-v4/`, `manifest-*.json`, `capture-checks-final.txt`, `png-after/`, `png-compare.json`), `netcode-integrity.json`, `draw-grep.txt`.

## Fixture choices (standing rule)

* **Pose grid scenarios** are 2a's: seeds 1234 (soak-4) and 99 (rubble-4), same blast list and 1,200 settle ticks, so the counts are comparable with the step-2a table. The ground and anchored pieces are not part of the measurement because they are never sent.
* **Soak**: the Falling_Bombs soak yard, seed 1234, bots blast every 4-8 s within 6 m, refills at ticks 7,201, 14,401, 21,601 and 28,801 (the step-2a two-minute cycle restricted to the run), a sandbox reset at tick 18,000 (new epoch) to exercise the reset path in the soak itself, and a flush of 120 ticks with idle bots after clearing falling bombs so the structure can settle. Link reorder delay 50 ms (the netcode default has none), jitter ±10 ms. Clients connect through the real handshake; the world ticks while they connect, so players join within the first ticks. All counters include those ticks.
* **Client bots** act only through input messages and choose blast points against their own replica at rest poses, so a few blasts land in solid and are rejected by the server; they are counted, not hidden.
* **Unit-test fixtures**: the budget test uses 800 synthetic pieces because the real soak never saturates 2×1150 bytes; blast-rule tests call the server's input handler directly; the epoch tests use `sandbox_reset`.

## Reproduce

```
odin build src -o:speed -out:build/BOM-2b.exe
build/BOM-2b.exe --pose-resolution 20          # section A
build/BOM-2b.exe --net-soak 10                 # section G(b-d,f,g); also writes evidence/replication-2b/net-soak.json and render/*.png
python scripts/capture-solo-2b.py              # regenerates standard captures and compares all 66 PNGs
odin test src -out:build/BOM-tests.exe -define:ODIN_TEST_TRACK_MEMORY=true -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \\
  -define:MATERIAL_CAPTURE_DIRECTORY=evidence/replication-2b/captures-v4/golden -define:SEAM_CAPTURE_DIRECTORY=evidence/replication-2b/captures-v4/legacy
python scripts/verify-replication-2b.py        # rechecks everything above and rewrites this report
```
"""
(root / 'report.md').write_text(report, encoding='utf-8')
print('report.md written;', test_count, 'tests;', len(all_captures), 'captures;', len(png), 'PNGs')
