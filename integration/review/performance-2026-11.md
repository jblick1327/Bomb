# F2: why the game feels choppy (performance review, 2026-11-12)

Author: Claude Opus 5.5 (task F2, report only, **no code changed**). Target: package
`C:\Users\jblic\Documents\BOM-Release\BOM-Windows-2026-11-12b`, `Mono/Bomb.exe` (the C5 front-door game, native build tag
165566078179921899). Evidence: `integration/evidence/F2/` (one folder per run, harness and scripts in `tools/`).

## Summary

The game is **not** slow in steady play. Once a level has settled, every run, 1 or 2 windows, Classic Yard or Tower,
holds a flat 16.7 ms frame (the 60 fps cap), p99 under 18 ms, with no hitches over 33 ms, about 1 ms of GPU per frame and
**0 server tick overruns**. Choppiness has three measured sources:

1. **Classic Yard rebuilds all of its meshes on the main thread for 25–35 s after every join and every round start.** In that
   window frames are p50 18–20 ms, p95 23–34 ms, with up to 145 hitches over 33 ms per minute (worst 236 ms), and 5.8–7.0 GB/min
   of GC allocation. Elimination rounds are short, so much of a Yard round is played inside this window. Tower does not do this.
2. **The local player's prediction flaps** between Predicting and Conservative (the server's view) many times a second on
   Tower, even alone in Sandbox: 435 and 185 switches in two 100 s runs. Each switch to Conservative zeroes the visual
   offset, so your own character visibly snaps. This is a presentation problem with no frame-time cost.
3. **In normal play the frame rate has no cap and vSync is off** (the PC quality level has `vSyncCount: 0`, and nothing sets
   `targetFrameRate`). This is inferred, not measured, because the measurement drivers cap at 60 fps. The display is a
   60 Hz panel driven by the Intel iGPU with the RTX 4050 rendering (hybrid), so expect tearing and uneven pacing, with
   each window spinning a CPU core.

The HUD's per-frame garbage (finding #12) is real but small: 3.6 KB per frame, 13 MB/min. No hitch is attributable to it.
The server is not a cause: 0 overruns in 7 runs, 1–8 % of one core.

## Machine and method

| Item | Value |
| --- | --- |
| CPU | Intel Core i7-13620H, 10 cores / 16 threads (2.4 GHz base) |
| RAM | 15.6 GB total; 4.1–5.5 GB free at run start (rule 3 checked before each run) |
| GPU | NVIDIA GeForce RTX 4050 Laptop (5.9 GB), driver 32.0.15.8160; also Intel UHD (drives the panel) |
| Display | 1920x1200 at 60 Hz (on the Intel adapter; Unity renders on the RTX 4050, per player log) |
| Power | **On AC** (Win32_Battery status 2, 96 % at the start and end of every run). Windows plan: Balanced |
| OS | Windows 11 Home 10.0.26300 |
| Graphics API | Direct3D 11.0 (level 11.1) in every player log (D13) |
| Window | Windowed 1280x720 (`-screen-fullscreen 0 -screen-width 1280 -screen-height 720`), visible, normal z-order; the 2nd window overlaps the 1st |
| Shell | Windows PowerShell 5.1 (`powershell.exe`) |
| Sleep/gaps | 0 Kernel-Power 42 / Power-Troubleshooter 1 / 107 events in any run; largest gap between samples 2.1 s. No run was dropped |

**Drivers (flags only, no code).** `tools/Run-F2Perf.ps1` starts `Mono/Bomb.exe` with:
- `--bom-frontdoor-test`: the C5 scripted menu driver presses ONLINE > HOST/JOIN > level > START/JOIN, so the real front
  door, `BomHostServer` and `BOM-server.exe` are used. It sets `vSyncCount 0` and `targetFrameRate 60`.
- `--bom-perf-out`: the existing `BomPerformanceProbe`. It writes one row per frame: wall frame ms, Unity
  `FrameTimingManager` CPU/GPU ms, native update, copy, presentation and geometry ms, `GC Allocated In Frame`, source and
  job state, and prediction status. It drives held input of ±0.2 every 3 s and sets Log stack traces to None, so the logging
  cost is under-counted compared with real play.
- Every ~1 s the harness samples CPU, working set, private bytes and GPU-engine utilisation per process.
- Server overruns, RTT and input lateness come from the game-started server's log (`bom-server-*.log`, beside the player
  log). The server prints `server tick overrun` only when it falls more than five 60 Hz ticks behind.

**Modes.**
- **Sandbox**: host and guest use separate signal folders, so nobody starts Elimination and the windows sit connected in
  the level for ~100 s. Sandbox has no automatic bombs, so no terrain changed in these runs.
- **ElimManual**: the harness forwards the guest's "connected" signal to the host 3 s later. The host then applies
  Elimination and the server rebuilds the world (epoch 3 → 4). The guest forfeits at 150 ticks (its C5 choreography), the
  round finishes, and the host keeps recording in the Finished state.

Real bomb-heavy rounds longer than ~3 s could not be scripted without code, because the C5 guest always forfeits at
150 ticks. A **human play session is still needed** for long rounds with many blasts (see "Not measured").

Per-frame JSONs are gzipped (`host-perf.json.gz`). `analysis.json` in each folder holds the summary;
`tools/split.txt` holds the rebuild/steady split.

## Measurements

### Frame time per run (host window, 100 s after a 5 s warm-up)

| Run (folder `perf-…`) | Windows | Level | Mode | p50 ms | p95 ms | p99 ms | max ms | >33 ms per min | >50 ms count | GC MB/min |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 135102-1w-classicyard | 1 | Classic Yard | Sandbox | 16.7 | 21.0 | 23.7 | 114.4 | 1.2 | 1 | 2199 |
| 135453-1w-tower | 1 | Tower | Sandbox | 16.7 | 17.3 | 18.3 | 32.9 | 0.0 | 0 | 12.9 |
| 140840-1w-tower-stdout (repeat) | 1 | Tower | Sandbox | 16.7 | 17.1 | 17.7 | 29.0 | 0.0 | 0 | 13.1 |
| 135710-2w-classicyard | 2 | Classic Yard | Sandbox | 16.7 | 24.8 | 28.7 | 103.1 | 5.4 | 1 | 2212 |
| 135931-2w-tower | 2 | Tower | Sandbox | 16.7 | 17.2 | 17.6 | 27.3 | 0.0 | 0 | 12.9 |
| 140149-2w-classicyard-elim | 2 | Classic Yard | Elimination round | 16.7 | 29.3 | 35.9 | **236.0** | **54.6** | 10 | 2273 |
| 140412-2w-tower-elim | 2 | Tower | Elimination round | 16.7 | 17.2 | 17.8 | 82.2 | 1.8 | 1 | 19.7 |

### Classic Yard split: mesh-rebuild window vs settled

"Rebuild" counts frames with source geometry jobs active or pending, or more than 1 ms in `BomSourcePresentation.Pump`.

| Run | Part | Seconds | p50 | p95 | p99 | max | >33 ms per min | GC MB/min | geometry p95 ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1w Classic Yard | rebuild | 30.3 | 18.1 | 23.3 | 25.4 | 114.4 | 2.0 | 7011 | 20.4 |
| 1w Classic Yard | settled | 69.7 | 16.7 | 17.1 | 17.5 | 33.5 | 0.9 | 104 | 0.0 |
| 2w Classic Yard | rebuild | 34.6 | 19.9 | 27.6 | 30.8 | 103.1 | 15.6 | 6335 | 24.2 |
| 2w Classic Yard | settled | 65.5 | 16.7 | 17.3 | 21.5 | 30.0 | 0.0 | 32 | 0.0 |
| 2w Classic Yard, Elimination | rebuild (join + round start) | 37.7 | 19.4 | 33.9 | 43.6 | 236.0 | **144.9** | 5808 | 29.9 |
| 2w Classic Yard, Elimination | settled | 62.4 | 16.7 | 17.1 | 17.4 | 18.4 | 0.0 | 135 | 0.0 |
| Tower (all runs) | rebuild | ≤0.2 | — | — | — | 82.2 (one frame at the epoch switch) | — | — | ≤1.8 |

On Classic Yard, the round start (epoch 4, the server's `REBUILD COMMIT build_ms=3200.7`) restarted the whole rebuild: 1,280
frames of geometry work over 24.3 s and 2.3 GB of GC, after the first-join rebuild had already finished. The 236 ms frame is
the epoch switch itself (CPU 27.5 ms in Unity's timing, geometry 8 ms, GPU 5 ms, so most of it falls outside the probe's
scopes). The source being rebuilt is the 3,549-cell fragmented yard source (`BOM SOURCE PRESENTATION … mode=fragments
cells=3549 batches=83`); 130 jobs are queued at a time. On Tower, the epoch switch rebuilt in 0.1 s (server rebuild 31 ms).

### Prediction (local player)

Prediction status per frame from the probe (1 = Predicting, 2 = Conservative/server view, 3 = Warming).

| Run | Predicting frames | Conservative frames | Mode switches in 100 s | Notes |
| --- | --- | --- | --- | --- |
| 1w Classic Yard | 5862 | 1 | 4 | warm-up only |
| 1w Tower | 5247 | 747 (12 %) | **435** | bursts every 0.1–0.2 s from t=13 s, recurring through the run |
| 1w Tower (repeat) | 5834 | 162 (3 %) | **185** | same pattern from t=17 s |
| 2w Tower | 5267 | 729 | 4 | Conservative for the first 12 s, then stable |
| 2w Classic Yard, Elimination | 495 | 4975 | 42 | epoch 3: flapping at 14.9–15.8 s; epoch 4: Conservative because the round finished (`Round_Inactive`, expected) |
| 2w Tower, Elimination | 682 | 5310 | 6 | mostly after the round finished (expected) |

Native code (`Documents/BOM/src/shared/prediction_client.odin:27–33`) zeroes `visual_offset` whenever the mode is not
Predicting and prints `PREDICTION mode=… reason=…` to stdout. The packaged player does not forward that stdout (a run with
stdout redirected captured 0 lines), so **the reason was not measured**. Candidates in code are `Missing_Command`,
`Wrong_Revision`, `Bomb_Contact_Uncertain` and static-world build/replay failures (lines 80–107).

### Server and network

| Run | Overruns | Hash mismatches | RTT (localhost) | Inputs late / starved / neutralized, per client (end of run) | World rebuild |
| --- | --- | --- | --- | --- | --- |
| 1w Classic Yard | 0 | 0 | 17–21 ms | 3 / 3 / 3 | — |
| 1w Tower | 0 | 0 | 16–19 ms | 0 / 4 / 4 | — |
| 2w Classic Yard | 0 | 0 | 16–26 ms | 20/3/3, 17/3/3 | — |
| 2w Tower | 0 | 0 | 16–19 ms | 29/3/3, 54/2/2 | — |
| 2w Classic Yard, Elimination | 0 | 0 | 16–**100** ms | 5/2/2, 0/0/0 | 3200.7 ms |
| 2w Tower, Elimination | 0 | 0 | 16–**100** ms | 19/3/3, 7/2/2 | 30.8 ms |

On localhost, RTT should be under 1 ms. A 16–21 ms RTT means the client sends and receives once per rendered frame, so at
60 fps the round trip is frame-quantised. The 100 ms peaks fall on the round-start rebuild hitches. Input lateness rises
with two windows (17–54 late inputs per client per run, against 0–3 with one window), consistent with two players
competing for frames.

### Processes (means over each run, samples every ~1 s)

| Run | Process | CPU, % of one core (mean / p95) | Working set max | Private max | GPU engine util mean |
| --- | --- | --- | --- | --- | --- |
| 1w Classic Yard | Bomb (host) | 62 / 128 | 723 MB | 997 MB | 59 % |
| 1w Classic Yard | BOM-server | 7.7 / 18.7 | 24 MB | 31 MB | — |
| 1w Tower | Bomb (host) | 32 / 52 | 661 MB | 946 MB | 32 % |
| 1w Tower | BOM-server | 1.0 / 3.6 | 10 MB | 10 MB | — |
| 2w Classic Yard | host / guest | 66 / 132, 74 / 135 | 755 / 753 MB | 995 / 928 MB | 57 % / 69 % |
| 2w Tower | host / guest | 31 / 42, 34 / 55 | 623 / 623 MB | 876 / 949 MB | 12 % / 11 % |
| 2w Classic Yard, Elimination | host / server | 62 / 128, 4.9 / 19.8 | 765 / 32 MB | 999 / 43 MB | 65 % |

The GPU-engine percentage includes the hybrid copy to the Intel panel. Unity's `FrameTimingManager` reports a GPU time of
**about 1 ms per frame** once settled (p50 1.09 ms on 1w Classic Yard). Each window needs about 1 GB of private memory, so
two windows plus the server use about 2 GB. That fits in the 4 GB free, but not with much margin.

### GC

| Phase | GC Allocated In Frame |
| --- | --- |
| Settled, any level (HUD + engine; finding #12) | 3.5–3.6 KB per frame (p50), 12.9 MB/min |
| Classic Yard mesh rebuild | 2.5–3.0 MB per frame on most frames, 5.8–7.0 GB/min |

The probe's own scoped counters show the native copy and presentation allocate 0 bytes in settled frames
(`stable_pose_zero_allocation=true`). The rebuild garbage does not appear in `geometry_gc` (max 28 KB), so it comes from the
geometry job builds and plan building rather than from the measured Pump scope (inferred).

## What is measured vs inferred

**Measured:**
- Every number in the tables above.
- The Classic Yard rebuild restarts at round start (epoch 3 → 4).
- Tower prediction flapping.
- 0 server overruns.
- Settled frames are flat at the cap.

**Inferred:**
- *Why the rebuild is slow.* `BomSourcePresentation.Pump` checks its 1.5 ms budget only between sources and upload steps.
  `Prepare`, `PrepareCells` and `MakePlans` for the 3,549-cell source run in full inside one step: they scan every cell,
  and `PrepareCells`/`MakePlans` queue at most 8 new cells per call. So each frame pays an O(cells) scan plus key and plan
  work until all cells are built. This matches geometry ms of 13–56 per frame for 25–35 s.
- *Why it repeats every round.* `SetTopology` treats any new epoch as fresh (`Clear()` + `Jobs.Reset`), even though the
  yard's revision was identical before and after the rebuild (24626 in both epochs).
- *The cause of the prediction flapping.* The reason code was not captured.
- *Cause 3 entirely* (uncapped and no vSync in normal play). The drivers forced a 60 fps cap. Support for it: the earlier
  finding of ~92 % of a core per player thread, the 1 ms GPU frame (which implies hundreds of fps uncapped), and
  `ProjectSettings/QualitySettings.asset` `vSyncCount: 0` for the PC level.
- *Input-timestamp offset* (~0.75 s, C2e finding). It only affects click blasts, which the drivers did not use. Not
  re-measured.

## Top 3 causes and fixes, ranked by gain per effort

| Rank | Cause (evidence) | Fix | Area / file | Size | Gain |
| --- | --- | --- | --- | --- | --- |
| 1 | Classic Yard mesh rebuild after every join and **every round start**: 25–35 s at p95 23–34 ms, up to 145 hitches over 33 ms per minute, worst 236 ms, 6–7 GB/min GC. (measured) | **1a.** Keep source plans, meshes and the geometry cache across an epoch change when the source and revision are unchanged (do not `Clear()`/`Jobs.Reset` a source whose content did not change), so a round start costs what Tower's does (0.1 s). **1b.** Make `Pump` honour its 1.5 ms budget inside `PrepareCells`/`MakePlans` (resume from a cursor; no full-cell scan per frame), and raise the 8-per-call queue limit so the first join finishes sooner. | `Assets/BOMIntegration/Runtime/BomSourcePresentation.cs` (`SetTopology`, `Clear`, `Pump`, `PrepareCells`, `MakePlans`), `BomGeometryJobs.cs` (`Reset`) | 1a **M**, 1b **S–M** | Highest: removes nearly all hitches on Darryn-style big sources, at every round start |
| 2 | Local prediction flaps Predicting ↔ Conservative 2–4 times a second on Tower (435 and 185 switches per 100 s, alone in Sandbox). Each switch zeroes `visual_offset`, so the own character snaps; it looks choppy at a flat 16.7 ms. (flapping measured, reason not) | First surface the reason: log `BomPredictionStats.reason` on mode changes in Unity (the native stdout is lost in players). Then in Odin, add hysteresis (stay Conservative for N ticks before returning, and require N good ticks before leaving Predicting) and blend `visual_offset` out over ~100 ms instead of zeroing it. Fix the underlying reason if it is a false "uncertain". | Unity: `BomClientBehaviour.cs` (status log, S). Odin, Lane N then E1: `src/shared/prediction_client.odin` `prediction_set_mode` / `prediction_update` | **S** (log) + **M** (Lane N + E1) | High for game feel; no frame-time cost |
| 3 | Normal play has no frame cap and vSync is off (`vSyncCount: 0`, no `targetFrameRate`), on a 60 Hz panel through hybrid graphics: tearing and uneven pacing, a core spinning per window, and two windows competing (input lateness 17–54 with 2 windows vs 0–3 with 1). (inferred; prior finding: 92 % core) | Set `QualitySettings.vSyncCount = 1` (or `targetFrameRate` = the display refresh rate) once at game start, e.g. in the front door. The PC quality asset is protected and Darryn's, so set it at runtime from our code rather than editing the asset. Then re-measure without a cap (needs a flag or a human run). | `Assets/BOMIntegration/Runtime/BomFrontDoor.cs` (or `BomClientBehaviour.Awake`) | **S** | Medium: removes tearing and cuts CPU/GPU use per window (amount unmeasured). Verify by eye. |

Lower value, for completeness:
- **HUD garbage (#12).** 13 MB/min of GC and no hitch attributed to it. The fix is S (`BomNetworkHud.Update`: set text
  only when it changes, cache the `controls` label, drop the per-frame `Query…ForEach` lambda).
- **Client network once per frame.** RTT 16–21 ms on localhost; it matters more on LAN than here (M).
- **Log stack traces** (`m_StackTraceTypes` ScriptOnly). A guest logged 857 stack-traced lines on joining Tower (two
  `BOM SOURCE` lines per source). It is only at join, so negligible.

## Not measured / limits

- **Long Elimination rounds with many blasts and terrain destruction (real play).** The scripted guest forfeits after 150
  ticks and Sandbox has no automatic bombs, so the terrain revision never changed except on Tower's round start. The cost
  of destruction-time re-meshing on Classic Yard is untested. **An owner or human run is needed**, ideally with
  `--bom-perf-out` added to `Launch-Bom.ps1`'s arguments by hand.
- **Uncapped frame times**, because both drivers cap at 60.
- **Guest-side frame data in the 2-window Sandbox runs.** The scripted guest hit `BOM FRONTDOOR TEST FAIL role=guest Object
  reference not set to an instance of an object` about 30 s into Sandbox, in the C5 test driver, not the game. The
  Elimination-mode guests passed. The host's records cover the 2-window load; guest CPU, RAM and GPU are in
  `process-samples.csv`.
- **Prediction reason codes** and **network corrections**: the player does not forward native stdout, and the probe has
  no correction counters in the front door (`BomPresentationProfile` only attaches to the first scene).
- **IL2CPP.** Not measured (Mono was the target).
- `FrameTimingManager` CPU and GPU values were reported although `enableFrameTimingStats` is 0. The CPU value includes the
  cap's wait.
