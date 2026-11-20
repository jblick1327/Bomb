# Step 2b follow-up: reference poses

Each rigid piece now replicates its own immutable rest reference point. **208 tests pass**, including all 205 existing tests and three reference-pose tests. The original 10-minute soak passes: **126,580 checked tables, zero mismatches**, equal structure on every client, exact inputs, and local delay always 2. Solo snapshots meet the accepted v4 criteria and all 66 PNG comparisons pass. `src/netcode/` is SHA-256 unchanged (13 files). No commit or archive was made.

Remote visible vertex maxima are **0.386 / 0.131 / 0.116 m**, compared with the accepted origin-metric maxima of 6.215 / 2.033 / 2.381 m. No follow-up visible maximum exceeds 0.5 m. Local frame payload averages 215.09 kbit/s (2b: 298.4); remote payload averages about 284.89 kbit/s (2b: 379.7).

## Implementation

`Piece.ref_rest` is the area-weighted rest centroid of its initial cells, computed with f64 polygon sums. The existing builder reserves an id before adding its cells; the reference is sealed when construction finishes, before physics, structural publication or damage. Regrouping creates new ids with their own centroids. Authored rotation is part of construction and transforms the new geometry and its reference together. Subsequent same-id cell-list changes preserve the reference.

Canonical structure version 2 and Baseline/Delta pieces-added encode `id varint · material varint · ref_rest.x f32 · ref_rest.y f32 · cell-id list`. This adds 8 bytes per added piece. Pieces-changed still carries only id and membership, so a client preserves the original reference. A late-join Baseline carries that same reference. The server's shared index asserts its immutability.

The wire position is `frame.position + rotate(ref_rest, frame.angle)`. Quantization, deltas, proximity/speed priority, budgeting and interpolation use that reference pose. The client subtracts `rotate(ref_rest, angle)` before passing the body frame to the existing draw path. Rubber, players and bombs retain their previous pose definitions. The reference is network structure; solo snapshot fields and the physics body frame are unchanged. Loading a solo snapshot reconstructs references for the loaded world's new epoch.

## A. Resolution sweep

Same scenarios and seeds as 2b: soak-4 is 72,000 ticks (20 minutes), rubble-4 is 18,000 ticks (5 minutes), after the same six blasts and 1,200 settling ticks. The lever arm is now the largest distance from a piece's immutable `ref_rest` to any of its vertices.

Measured: `soak rigid=1.3163 (piece 86494) rubber=0.2828; rubble rigid=0.7747 (piece 2859) rubber=0.2828; used=1.3163 m; 2560x1440 view scale=151.1905 px/m`.

The maximum is **1.3163 m**, versus 2b's 9.4454 m. As in 2b, the comparison rule is `(0.5 × position_step + π / angle_steps × lever_arm) × 151.1905 px/m`, at 2560×1440. The same measured maximum is used for all 12 pairs.

| Position step | Angle steps/turn | Worst error (px) | ≤0.5 px | soak-4 changed p50/p95/p99/max | rubble-4 changed p50/p95/p99/max |
|---|---|---|---|---|---|
| 1/1024 m | 65536 | 0.08336 | true | 128/255/286/353 | 100/172/195/233 |
| 1/1024 m | 16384 | 0.11198 | true | 106/226/262/341 | 70/138/160/233 |
| 1/1024 m | 4096 | 0.22646 | true | 85/195/237/321 | 48/109/129/233 |
| 1/1024 m | 1024 | 0.68438 | false | 71/174/219/303 | 36/92/110/233 |
| 1/512 m | 65536 | 0.15719 | true | 128/254/285/353 | 99/171/195/233 |
| 1/512 m | 16384 | 0.18581 | true | 104/223/259/340 | 68/136/156/233 |
| 1/512 m | 4096 | 0.30029 | true | 81/187/230/313 | 43/102/121/233 |
| 1/512 m | 1024 | 0.75820 | false | 64/159/204/296 | 28/79/97/233 |
| 1/256 m | 65536 | 0.30483 | true | 127/254/284/353 | 98/171/193/233 |
| 1/256 m | 16384 | 0.33345 | true | 104/221/257/340 | 67/134/154/233 |
| 1/256 m | 4096 | 0.44793 | true | 79/183/225/304 | 40/97/116/233 |
| 1/256 m | 1024 | 0.90585 | false | 60/149/193/289 | 23/69/85/233 |

**Adopted: 1/256 m and 4096 angle steps per turn**, 0.44793 px worst error. This passing pair minimizes rubble-4 p99 changes (116, previously 165), with the existing p95/finer-pair tie breaks. All 1024-angle pairs fail the 0.5 px rule. [CSV](evidence/replication-2b-followup/pose-resolution.csv), [sweep log](evidence/replication-2b-followup/pose-resolution.txt).

## B. Visible render error

All triples below are **p50/p99/max**. The sampler retains the old metric's eligibility: every drawn entity present in both true history ticks around the same fractional render tick R, in the same epoch. There is no speed cutoff or outlier removal. All representations use exactly those same keys and times. Truth interpolates the actual reference positions of the two adjacent simulation ticks, plus the shortest angle arc; each vertex then uses its rest offset from the reference. For rubber the offsets are from its cell center; player/bomb positions keep their existing definition. “Maximum visible vertex” includes the reference point and every live piece/cell vertex, so it is at least the reference error.

The last column deliberately retains the old origin metric: the drawn body origin versus the true origins interpolated independently at R. It is a diagnostic; the visible columns measure what is drawn.

| Client | Entities | Same samples per metric | Reference point (m) | Maximum visible vertex (m) | Old origin metric on new draws (m) |
|---|---|---|---|---|---|
| 0 | all | 7109560 | 0.00160/0.00260/0.05576 | 0.00170/0.00270/0.05576 | 0.00200/0.00640/0.05576 |
| 0 | players | 144453 | 0.00160/0.00260/0.05576 | 0.00160/0.00260/0.05576 | 0.00160/0.00260/0.05576 |
| 0 | bombs | 48577 | 0.00150/0.00260/0.00274 | 0.00150/0.00260/0.00274 | 0.00150/0.00260/0.00274 |
| 1 | all | 7104495 | 0.00150/0.00260/0.38095 | 0.00160/0.00260/0.38628 | 0.00200/0.00880/2.17231 |
| 1 | players | 144396 | 0.00150/0.00250/0.12812 | 0.00150/0.00250/0.12812 | 0.00150/0.00250/0.12812 |
| 1 | bombs | 48576 | 0.00140/0.00250/0.06438 | 0.00140/0.00250/0.06438 | 0.00140/0.00250/0.06438 |
| 2 | all | 7102404 | 0.00150/0.00260/0.13138 | 0.00160/0.00260/0.13138 | 0.00190/0.00950/1.77187 |
| 2 | players | 144400 | 0.00140/0.00250/0.13138 | 0.00140/0.00250/0.13138 | 0.00140/0.00250/0.13138 |
| 2 | bombs | 48568 | 0.00140/0.00250/0.07612 | 0.00140/0.00250/0.07612 | 0.00140/0.00250/0.07612 |
| 3 | all | 7105797 | 0.00150/0.00260/0.11504 | 0.00160/0.00260/0.11631 | 0.00200/0.00920/1.73438 |
| 3 | players | 144396 | 0.00140/0.00250/0.06247 | 0.00140/0.00250/0.06247 | 0.00140/0.00250/0.06247 |
| 3 | bombs | 48572 | 0.00140/0.00250/0.11094 | 0.00140/0.00250/0.11094 | 0.00140/0.00250/0.11094 |

The local all-entity maximum is player 1 just after the epoch reset: tick 18,003, R=18,001, with only frame 18,003 available and no lower bracket. The client follows the existing hold-first-frame rule. This is a player startup sample; it is unchanged by the piece reference conversion. The largest remote vertex sample is piece 23,007 on client 1, moving at a peak 12.038 m/s across frames 29,262–29,265 (50 ms, about 0.602 m of travel available), with 0.38628 m error. This is consistent with fast debris moving/colliding inside a lost-frame gap.

To separate the interpolation representation from changes in packet delivery, the next comparison reconstructs origin interpolation on **the same received table endpoints, brackets and samples** as the reference interpolation. Piece endpoints are converted back to origins and rounded to 2b's 1/512 m / 16384-angle grid, then origins and angles are interpolated separately and converted to visible positions. Those endpoints have already passed through the new grid; this is a paired diagnostic of interpolation geometry, not a second old-protocol transport soak. Non-piece poses are identical on the two sides.

| Client | Entities | Origin interpolation: visible reference (m) | Reference interpolation: visible reference (m) | Origin interpolation: max vertex (m) | Reference interpolation: max vertex (m) |
|---|---|---|---|---|---|
| 0 | all | 0.00170/0.00320/0.05576 | 0.00160/0.00260/0.05576 | 0.00170/0.00330/0.05576 | 0.00170/0.00270/0.05576 |
| 0 | players | 0.00160/0.00260/0.05576 | 0.00160/0.00260/0.05576 | 0.00160/0.00260/0.05576 | 0.00160/0.00260/0.05576 |
| 0 | bombs | 0.00150/0.00260/0.00274 | 0.00150/0.00260/0.00274 | 0.00150/0.00260/0.00274 | 0.00150/0.00260/0.00274 |
| 1 | all | 0.00160/0.00640/1.99519 | 0.00150/0.00260/0.38095 | 0.00170/0.00650/1.99524 | 0.00160/0.00260/0.38628 |
| 1 | players | 0.00150/0.00250/0.12812 | 0.00150/0.00250/0.12812 | 0.00150/0.00250/0.12812 | 0.00150/0.00250/0.12812 |
| 1 | bombs | 0.00140/0.00250/0.06438 | 0.00140/0.00250/0.06438 | 0.00140/0.00250/0.06438 | 0.00140/0.00250/0.06438 |
| 2 | all | 0.00160/0.00690/1.84155 | 0.00150/0.00260/0.13138 | 0.00170/0.00700/1.84174 | 0.00160/0.00260/0.13138 |
| 2 | players | 0.00140/0.00250/0.13138 | 0.00140/0.00250/0.13138 | 0.00140/0.00250/0.13138 | 0.00140/0.00250/0.13138 |
| 2 | bombs | 0.00140/0.00250/0.07612 | 0.00140/0.00250/0.07612 | 0.00140/0.00250/0.07612 | 0.00140/0.00250/0.07612 |
| 3 | all | 0.00160/0.00670/1.91454 | 0.00150/0.00260/0.11504 | 0.00170/0.00680/1.91454 | 0.00160/0.00260/0.11631 |
| 3 | players | 0.00140/0.00250/0.06247 | 0.00140/0.00250/0.06247 | 0.00140/0.00250/0.06247 | 0.00140/0.00250/0.06247 |
| 3 | bombs | 0.00140/0.00250/0.11094 | 0.00140/0.00250/0.11094 | 0.00140/0.00250/0.11094 | 0.00140/0.00250/0.11094 |

For historical context, the accepted 2b run's original origin metric is below, alongside this run's angle error. Its sample counts and received brackets differ because the changed frame sizes change the seeded link simulator's packet sequence; these historical numbers are not the paired comparison above.

| Client | Entities | Accepted 2b origin error (m) | Follow-up angle error (rad) |
|---|---|---|---|
| 0 | all | 0.00080/0.00130/0.05766 | 0.00040/0.00080/0.00584 |
| 0 | players | 0.00080/0.00130/0.05766 | 0.00010/0.00010/0.00000 |
| 0 | bombs | 0.00080/0.00130/0.00138 | 0.00010/0.00080/0.00077 |
| 1 | all | 0.00080/0.00270/6.21497 | 0.00040/0.00080/0.45366 |
| 1 | players | 0.00080/0.00180/0.13479 | 0.00010/0.00010/0.00000 |
| 1 | bombs | 0.00080/0.00150/0.06908 | 0.00010/0.00080/0.35137 |
| 2 | all | 0.00080/0.00260/2.03292 | 0.00040/0.00080/0.51017 |
| 2 | players | 0.00070/0.00180/0.13137 | 0.00010/0.00010/0.00000 |
| 2 | bombs | 0.00080/0.00150/0.10942 | 0.00010/0.00080/0.25284 |
| 3 | all | 0.00080/0.00260/2.38091 | 0.00040/0.00080/0.42971 |
| 3 | players | 0.00070/0.00180/0.08121 | 0.00010/0.00010/0.00000 |
| 3 | bombs | 0.00080/0.00160/0.07247 | 0.00010/0.00080/0.21755 |

### Maxima above 0.5 m

No client reference-point or vertex maximum exceeds 0.5 m.

Speed is the peak reference-point speed over the received frame bracket, using both true tick-to-tick travel and Box2D's velocity at the reference point. Spin includes Box2D angular velocity. `speed × gap` is the distance scale available during that missing-frame interval, not an interpolation-error bound. Remaining visible error can include collisions/acceleration between endpoints, frame holding when the clock passes the newest complete frame, and shortest-arc spin interpolation over a gap. The former shared-origin chord is removed. [Every entity exceeding 0.5 m, with its largest sample](evidence/replication-2b-followup/visible-outliers.json); [complete measurements and maxima](evidence/replication-2b-followup/net-soak.json).

## C. Original soak checks and bandwidth comparison

Fixture: 36,000 ticks plus the original 120-tick idle flush; Falling_Bombs yard; seed 1234; client bot seeds `1234 + i×0x9e3779b97f4a7c15`; link seeds `1234×31 + i×2 + 1/2`. Client 0: zero latency/loss. Clients 1–3: 40±10 ms each way, 2% loss, 1% duplicates, 2% reorder with up to 50 ms extra delay. Refills at 7,201/14,401/21,601/28,801; reset at 18,000 creates the new epoch. These settings match 2b.

**Tables:** 126,580 checked, 0 mismatches, 9 checks skipped because the sent ring slot was reused. Every applied structure revision is checked against its recorded canonical hash, then canonical bytes are compared after the flush:

| Client | Applied structure messages | Hash mismatches / unrecorded | Final structure / revision equal | Final poses differing / awake |
|---|---|---|---|---|
| 0 | 1365 | 0/0 | True/True | 0/0 |
| 1 | 1365 | 0/0 | True/True | 0/0 |
| 2 | 1365 | 0/0 | True/True | 0/0 |
| 3 | 1365 | 0/0 | True/True | 0/0 |

| Client | Jumps pressed / applied | Blasts issued / applied / rejected | Duplicates |
|---|---|---|---|
| 0 | 236/236 | 97/97/0 | 0 |
| 1 | 232/232 | 98/96/2 | 0 |
| 2 | 232/232 | 99/94/5 | 0 |
| 3 | 237/237 | 102/99/3 | 0 |

| Client | Final delay / changes | Delay histogram (ticks:count) | Lost frames | Late structure / events / max ticks | Snaps / ticks at ±5% |
|---|---|---|---|---|---|
| 0 | 2/0 | 2:36119 | 0 | 2/0/1.00 | 2/0 |
| 1 | 4/250 | 2:2312, 3:7, 4:33063, 5:637, 6:95 | 754 | 55/30/9.52 | 2/92 |
| 2 | 4/235 | 2:3261, 3:17, 4:32236, 5:510, 6:90 | 760 | 74/38/10.59 | 2/138 |
| 3 | 4/195 | 2:3112, 3:3, 4:32569, 5:430 | 772 | 69/24/11.18 | 2/93 |

The clock/loss/late-message rules are unchanged. Every frame decoder reports zero malformed and undecodable frames. Reliable messages arriving behind the clock apply on arrival and are counted. Frame parts remain ≤1150 bytes by the encoder assertion; the dynamic-entity budget remains 2×1150 bytes, with players/bombs included whenever their acked row differs. The existing stress tests still check priority, fresh rows first, budget binding and eventual convergence.

| Client | Frame bytes/tick p50/p99/max: 2b → follow-up | Bytes/entry: 2b → follow-up | Frame upload avg/peak 1s kbit/s: 2b → follow-up | All upload avg/peak 1s kbit/s: 2b → follow-up |
|---|---|---|---|---|
| 0 | 630/1399/1764 → 433/1083/1464 | 5.578 → 5.371 | 298.41/765.65 → 215.09/504.29 | 319.06/827.52 → 236.24/611.18 |
| 1 | 825/1661/2062 → 591/1353/1717 | 5.969 → 5.562 | 379.66/911.74 → 284.89/638.41 | 402.15/973.74 → 306.79/721.66 |
| 2 | 827/1665/2062 → 591/1354/1740 | 5.969 → 5.562 | 379.66/912.12 → 284.86/639.78 | 402.02/974.13 → 306.77/718.28 |
| 3 | 826/1664/2062 → 592/1353/1725 | 5.968 → 5.561 | 379.56/912.38 → 284.88/636.46 | 401.99/974.38 → 306.77/719.28 |

| Client | Entries sent | Max parts | Budget saturated fraction | Max / p99 staleness (ticks) |
|---|---|---|---|---|
| 0 | 3013487 | 2 | 0.0 | 0/0 |
| 1 | 3854642 | 2 | 0.0 | 0/0 |
| 2 | 3854177 | 2 | 0.0 | 0/0 |
| 3 | 3854705 | 2 | 0.0 | 0/0 |

Bytes per entry include frame headers, as in 2b. Upload includes packet headers and reliable structure in the “all” column; frame upload counts pose payload. This run sends 3,313,716 reliable structure bytes across four clients (2b: 2,984,068), including the new reference fields, and emits 729 explosion events. Changed frame sizes also alter packet splitting, loss/reorder draws, received inputs and later simulation activity; the bandwidth comparison is the specified seeded end-to-end run, rather than a claim of an identical physical trajectory.

Teardown: **Odin 0, Box2D 0, textures 0, shaders 0, fonts unloaded**. [Soak log](evidence/replication-2b-followup/net-soak.txt), [JSON](evidence/replication-2b-followup/net-soak.json), [host/client PNGs](evidence/replication-2b-followup/render/host.png).

## D. Tests and solo identity

**208 tests successful in 5m3.3878136s**, with memory tracking and failure on bad memory enabled. The three additions cover 5,000 frame/reference round trips and vertex agreement; an unequal-area centroid with same-id cell removal, Delta update, late-join Baseline and added-piece Delta; and a distant spinning piece whose visible center remains fixed between frames. The existing rigid-frame test now compares the reference pose to `rigid_render_frame` transformed by `ref_rest`. Existing codecs, 10,000-buffer fuzzing, clocks, inputs, budgets and replication tests all pass. [Full test log](evidence/replication-2b-followup/tests-final.txt).

**Short-soak correction:** the idle flush is restored to **180 ticks**. The previous 600-tick extension masked an awake-accounting bug: mismatching players/bombs were counted, but their awake bodies were omitted from the awake count. The measurement now checks those body types too. The original pre-resolution-choice failure comprised two pieces that had just gone to sleep at tick 1680 plus an awake player; their last changes were only 0-2 ticks old, and all three reached the remotes within 2-4 ticks. They had not waited three seconds. [Convergence measurements, p50/p99/max, and send/loss/ACK histories](evidence/replication-2b-followup/convergence/report.md). The required 10-minute soak retains its original 120-tick flush.

All **58 solo captures** pass the 2a/2b v4 criteria: 28 byte-identical Scene captures; 30 World captures retain byte-identical Scene text and bit-equal player 0, bombs, rain, settings and tick, using the already accepted v4 player-array and optional bomb-id comparison. No new exception. [Standard](evidence/replication-2b-followup/manifest-standard.json), [golden](evidence/replication-2b-followup/manifest-golden.json), [legacy](evidence/replication-2b-followup/manifest-legacy.json), [checks](evidence/replication-2b-followup/capture-checks-final.txt).

All **66 PNGs match**: 60 regenerated byte-identical; 6 accepted files without a current regeneration command remain SHA-256 identical. [PNG comparison](evidence/replication-2b-followup/png-compare.json), [capture run](evidence/replication-2b-followup/solo-capture.txt). [Netcode hashes](evidence/replication-2b-followup/netcode-integrity.json), [draw-path Box2D check](evidence/replication-2b-followup/draw-grep.txt), [changed-source hashes](evidence/replication-2b-followup/source-integrity.json).


## E. Final-pose convergence audit

| Run | Remote client | Entity lifetimes | Final row observed | Removed/reset before observation | Observed terminal row p50/p99/max ticks | Survivors only p50/p99/max ticks |
|---|---|---|---|---|---|---|
| long | 1 | 7215 | 6479 | 736 | 3/4/6 | 3/4/4 |
| long | 2 | 7215 | 6559 | 656 | 3/4/6 | 3/3/3 |
| long | 3 | 7215 | 6555 | 660 | 3/4/6 | 2/3/3 |
| short180 | 1 | 763 | 748 | 15 | 3/4/4 | 3/3/3 |
| short180 | 2 | 763 | 725 | 38 | 3/3/4 | 3/4/4 |
| short180 | 3 | 763 | 749 | 14 | 3/4/4 | 3/4/4 |

Latency starts at each entity's last server row change and ends when the remote newest complete table first contains it. All surviving rows converge; removed/reset terminal rows that never appear are counted separately. The audit runs the original physics cutoffs, then 20 network-only observation ticks with physics held fixed. The maximum is six ticks (100 ms), at epoch startup; ordinary final-row sends retry and ACK within a few ticks. The five slowest per client, including every send, lost frame and accepted ACK, are in the [convergence report](evidence/replication-2b-followup/convergence/report.md) and [histories](evidence/replication-2b-followup/convergence/slowest-histories.json).

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
