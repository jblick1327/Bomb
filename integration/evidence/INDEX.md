# Evidence index

The raw run records for this branch (captures, logs, gate results, soak and perf runs) are not in the repository.
They were removed from the history of this PR branch to keep it small (5.1 GB on disk).

- Archive: `C:\Users\jblic\Documents\BOM-Release\evidence-archive-20261119` on the owner's machine (18,530 files;
  its `engine-evidence` folders belong to `Engine/evidence/INDEX.md`).
- Full history with the evidence still committed: local branch `integration/odin-unity-20261105` at 90ae1e61.
- `NPT` (native pump thread, prediction fixes, seam fix, settled-debris freeze; 2026-11-21 to 11-24) was added later from
  local branch `native-pump-thread` at 401f9ec2, where it is still committed.
- Every file is listed in `INDEX-files.tsv` (path, bytes, sha256, and whether it was committed `git` or only on disk `local`).
  Paths are relative to `integration/evidence/`, which is where `integration/ALPHA-SYNC.md` and the READMEs point.
- Kept in the repository as test inputs: `M6/yard-export/yard.json`, `M7/yard-export/yard.json` and
  `M7/source-export/fixtures.json` (read by the older `Test-UnityYard.ps1` and `Test-SourcePresentation.ps1`).

New runs still write here; `.gitignore` keeps them out of the repository.

| folder | files | size |
|---|---|---|
| `E1-G` | 170 | 117.4 MB |
| `E1-GN10` | 203 | 118.4 MB |
| `E1-GN11` | 18 | 0.0 MB |
| `E1-GN6` | 238 | 153.0 MB |
| `E1-GN9` | 198 | 121.2 MB |
| `F2` | 83 | 7.3 MB |
| `G1` | 136 | 85.1 MB |
| `G2` | 759 | 450.8 MB |
| `G2b` | 305 | 188.5 MB |
| `G3` | 306 | 210.3 MB |
| `G5` | 350 | 84.3 MB |
| `G5b` | 47 | 2.3 MB |
| `G6` | 67 | 40.4 MB |
| `G6b` | 8 | 0.4 MB |
| `G7G8` | 294 | 10.0 MB |
| `G8b` | 27 | 0.0 MB |
| `M0` | 253 | 4.3 MB |
| `M1` | 42 | 0.0 MB |
| `M2` | 126 | 13.0 MB |
| `M3` | 459 | 1.4 MB |
| `M4` | 236 | 6.7 MB |
| `M5` | 85 | 0.7 MB |
| `M6` | 246 | 8.1 MB |
| `M7` | 504 | 12.6 MB |
| `M8` | 12200 | 3090.4 MB |
| `M9` | 858 | 470.4 MB |
| `NPT` | 265 | 66.5 MB |
| `OD13` | 14 | 0.0 MB |
| `OD15` | 29 | 0.4 MB |
| `original-scenes` | 4 | 0.0 MB |

## Added after 2026-11-24 (not indexed above, not in this repository)

The P1 to P10 work (2026-11-24 to 11-27: round restarts, prediction gate, camera, glue, movement stutter, tower look) wrote
new run records. They are committed only on the owner's **local** branch `native-pump-thread` (tip 44db48e5) and are not
in `INDEX-files.tsv`. `integration/ALPHA-SYNC.md` cites them as `evidence/<folder>/...`. They are not pushed anywhere;
ask J for a copy.

| folder | files | size |
|---|---|---|
| `P1` | 9 | 0.0 MB |
| `P4` | 5 | 0.0 MB |
| `P4a` | 16 | 0.0 MB |
| `P4b` | 4 | 0.0 MB |
| `P5` | 36 | 11.6 MB |
| `P6` | 157 | 16.2 MB |
| `P9` | 85 | 6.7 MB |
| `STUTTER` | 28 | 0.1 MB |
| `TOWER-LOOK` | 19 | 0.4 MB |
| `VIS` | 486 | 238.6 MB |

## Commit hashes in the docs

`native-pump-thread` and this PR branch hold the same changes under different hashes (the PR history was rewritten on
2026-11-19 and later commits were replayed onto it). Docs written from 2026-11-23 on use the `native-pump-thread` hash
(the *old* column). Evidence-only commits have no counterpart here.

| old (native-pump-thread) | this PR | subject |
|---|---|---|
| `314e3e63` | `b3e77530` | NPT: brief for the native pump thread (Codex + showrunner lanes) |
| `4a65c86e` | `229f6de7` | NPT: native network pump thread (ABI 1.7), opt-in per client |
| `58c67f09` | `0fa01492` | NPT: pump runs on the caller's timebase (Mono Stopwatch has its own origin) |
| `34b4489d` | `7464c0a6` | NPT: ship native pair 58c67f09 (ABI 1.7): DLL 78c1ab93, server 3a08b4a1 |
| `da53cafa` | `09e1c536` | NPT: A/B evidence (two pairs, both orders) and evidence README |
| `173ec0db` | `98a248f0` | NPT: fair A/B tools; pump at normal priority; main thread skips a frame the pump holds |
| `1039fccd` | `9c7aba8b` | NPT: ship native pair 173ec0db (ABI 1.7): DLL 60669e80, server 0208c2df |
| `829b3808` | `17d6c528` | NPT: held input also skips a slot the pump holds; all callers go through BomSession.SetHeldInput |
| `0ec90d08` | `e2e23a03` | NPT: per-sample stats cache for HUD/recorder; ship pair 829b3808; fair A/B evidence |
| `ee79b9b8` | `32fc0472` | Prediction: draw the predicted own player between ticks |
| `00ac32c6` | `138062d1` | Ship native pair ee79b9b8 (sub-tick own-player drawing): DLL 8786520a, server 452ef3a1 |
| `74df5ea8` | `11c6a042` | Prediction: keep an unbroken prediction on screen through short proxy uncertainty |
| `f5d0d282` | `493be928` | Ship native pair 74df5ea8 (prediction estimate window): DLL d6b728fc, server c4db2bfe |
| `3e2f1609` | `80997569` | Input: keep controls live through schedule resets |
| `250f6326` | `820fc5dd` | Ship native pair 3e2f1609 (live controls through resets): DLL cfb60594, server 645da9c2 |
| `8acac83b` | `c9e5d4f2` | NPT: clean 3-minute hitch trace (no injected hitches, scripted move) |
| `bd829c48` | `7b4bd9ae` | Blast permission check reads the per-sample stats copy |
| `8d0afe24` | `39d44668` | NPT diagnosis: scripted host blasts, server tick metrics, blast repro evidence (server froze ~50 s after repeated blasts) |
| `1828bee9` | `4b7f63bd` | NPT diagnosis: offline blast replay probe (earth ground shatters to ~11.5k dynamic bodies, ~200 ms physics ticks) |
| `868910a9` | `b64d1ac6` | NPT diagnosis: probe measures whether ground bodies move or sleep |
| `786f73ad` | `964df1e3` | NPT diagnosis: probe counts distinct dynamic bodies and shapes |
| `1996dcb3` | `437ec257` | Mortar welds stop colliding their glued pair (owner-approved): fixes the post-blast ground blow-up |
| `65baa46b` | `62952569` | Ship native pair 1996dcb3 (mortar welds without contact bearing): DLL bdb8f85d, server faca5ca8 |
| `31f22fa2` | `aae6c515` | NPT: live scripted-blast session on the seam-fix pair (no freeze, 68 blasts, hashes match); probe can drive two players |
| `8219b485` | `53eb372f` | Launcher play sessions keep vsync (--bom-frame-cap): uncapped windows starved the local server |
| `f35c18c0` | `3cd4f051` | Debug blaster follows each column's surface; dig sessions on the seam-fix pair |
| `24dda19b` | `0b6fd67f` | Settled debris freezes on the server (owner-approved); out-of-bounds sweep stops being quadratic |
| `401f9ec2` | `fad7bd33` | Host from the menu starts Elimination; ship native pair 24dda19b (settled-debris freeze): DLL 7aa87f01, server fba20ba5 |
| `904964db` | `28eca5fc` | TEAM.md: Host starts Elimination; known issues after the 2026-11-24 fixes |
| `64e358b1` | `52e25f83` | Round restarts 20-35x faster: level glue skips cell pairs out of glue reach; rebuild thread at Normal priority |
| `c7e51e27` | `12a80c17` | P1-P3: ship native pair 64e358b1 (DLL b98ff622, server 16d87e64), round-prep HUD, release builds |
| `715c4eaf` | `aa12e969` | P4: Prediction gate fails on b98ff622 (client falls behind its command schedule); open P4a |
| `1b56627a` | `ad5e8dd8` | P4a: no prediction regression since 11-19 (failures track machine stalls); gate refreshes the interop DLL and reports server overruns |
| `94a43490` | `7fbb07e7` | P4b: Prediction gate 6/6 on b98ff622; Run-WhenQuiet.py records AC and input during a run |
| `60c3faef` | `7e3c3cff` | P5: grey bars are the drawn bedrock (camera change reverted); P6 interim; P9: round start collapses on Bridge/Tower since 1996dcb3 |
| `59b51704` | `102ac21e` | P9: glue welds collide between placed objects again, not within one (Bridge/Tower round start restored) |
| `2e52c997` | `681a9bf2` | P9: ship native pair 59b51704 (DLL 13578414, server 2e022734); P5/P6 decisions; release package |
| `f856046e` | `dde43de8` | Join switches to the host's level; Tailscale for play between houses (firewall helper in the package) |
| `5c54ca77` | `5149240c` | Server loop: precise 1 ms waits, above-normal priority, catch up stalls under 250 ms (movement stutter) |
| `2279d755` | `00079067` | Prediction: bridge and estimate through missing commands instead of dropping to the authority (movement stutter) |
| `b46b00e3` | `0a5bd33b` | Prediction: keep the own player predicted near bombs, as an estimate (movement stutter) |
| `119eefd4` | `2bd5e541` | P10: ship native pair b46b00e3 (movement stutter fixes); package; TEAM.md |
| `9d5fbb2c` | `7a6b5a50` | Glue: a piece hanging by one glue seam gives way under its own weight (P6, glue bending) |
| `2d7ec321` | `6f33c25d` | P6: ship native pair 9d5fbb2c (shelves of glue give way); package; TEAM.md |
| `44db48e5` | `2f11fc9b` | Tower look: fill light and no sun shadows online; hitch trace reads CPU and GC |
