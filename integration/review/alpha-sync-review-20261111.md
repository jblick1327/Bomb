# ALPHA-SYNC midpoint review (2026-11-11)

Reviewer: Claude Opus 5.5, read-only. No task claimed, nothing run except `git`, `grep` and small read-only Python checks.
Heads reviewed: Unity `e7d00ca` (`integration/odin-unity-20261105`), Odin `9eb164e` (`alpha-sync`, base `0c11f5e`).

## 1. Summary

- Native N1–N3 match `round-rules.md`. Versions agree everywhere that is live: protocol 8, round format 3, config 5, ABI 1.5,
  level 4, canonical 3. The shipped DLL hash matches both `bomcore.build.json` and `BomExpectedNativeIdentity.cs`.
- The authority boundary holds. Unity decides no outcome; limb loss copies a native count and never mutates a shared mesh.
- The **death and graze presentation is wired to the wrong signals**. Unity infers death from a pose disappearing, so the
  round-ending death never bursts (in a 2-player round, no death ever does), a quit looks like a death, and effects die with the terrain object.
- Gates do not exercise grazes or the burst at all, and two documented traps are still enforced only by failures.
- **Verdict: safe to continue the queue.** Before the owner does the E1-N3 owner check, do one small Lane U fix pack (findings 1–4).
  Without it the check will look like a failure when the cause is in presentation.

## 2. Ranked findings

No blockers. Severity: **SF** = should fix, **NH** = nice to have. Line numbers are at the heads above.

### 1. SF: The death burst never plays for the death that ends a round
- **Where:** Unity `Assets/BOMIntegration/Runtime/BomClientBehaviour.cs:1027` (`if (key.Item1 == 2 && client.Round.state == 2)`).
  Native `src/shared/round_server.odin:98-101`, `:48`.
- **What is wrong:** the burst requires the round to still be Playing when the pose vanishes. The death that ends the round
  switches the round to Finished on the same server tick, and its body is removed in that same `round_server_sync_bodies` call.
- **Failing scenario:** a 2-player round. P2 dies, so `alive<=1`, so `state=Finished`, and the body is removed on that tick. Unity
  copies `Round` from the latest received reliable snapshot (`src/ffi/round.odin:12`, `r:=s.client.round_snapshot`), which is
  not delayed to the presentation tick. Poses are delayed, so the pose vanishes after Unity already sees state 3. No burst is shown.
  Every death in a 2-player round, and both deaths in a draw, are round-ending deaths. This fits the C2 owner check note "burst not seen".
- **Verified by:** reading `round_finish_tick` (round_rules.odin:148-167), `round_server_finish`, `round_server_can_play` and
  the Unity condition. The timing claim (snapshot ahead of poses) is from code; it was not measured.
- **Fix:** trigger the burst from the copied roster instead: a `BomRoundPlayer` whose `alive` goes 1→0 within the same `round_id`
  and `session_id`/`generation`, with `death` = Blast(1) or Bounds(2). Spawn it at the player's last visual position (keep that position
  even after the pose is gone). Log `BOM UNITY BURST player= round= death=` so gates can see it. **Lane U, T2, S–M.**

### 2. SF: A disconnect or forfeit during Playing draws a death burst
- **Where:** `BomClientBehaviour.cs:1027-1037`. Native: `round_finish_tick` marks a disconnected participant `death=Disconnect`
  (round_rules.odin:155), and the next `round_server_sync_bodies` removes the body while other players are still alive.
- **Failing scenario:** a 3-player round where P3 quits. The P3 pose vanishes while state is 2, so clay chunks fly as if P3 were blasted.
  The same happens if a player's pose drops out for any other reason during Playing (there is no interest management today, so this
  is only a risk for the future).
- **Verified by:** code read.
- **Fix:** the same as finding 1: key on `death` and skip `Disconnect(3)`. Do it in the same task.

### 3. SF: Blast, burst and graze-chunk effects are children of the per-revision terrain object
- **Where:** `BomClientBehaviour.cs:1036` (burst), `:1079`/`:1092` (blast effects), and `PresentLimbLoss` (`:1148`) pass
  `terrain.transform`. `ClearScene(true)` at `:894` → `:672-677` calls `Destroy(terrain)` on every new topology revision.
- **Failing scenario:** each blast fractures terrain, which creates a new revision and a new terrain object. A burst (1.2 s life) or a
  blast effect from the previous bomb is destroyed at that moment. After the 90 s ramp, bombs fall every 0.4–1.0 s, so late-round
  effects are routinely cut short. A death right before the next blast loses its burst.
- **Verified by:** code read. The visible effect is not confirmed (see Needs a run).
- **Fix:** parent effects to one persistent `Native effects` root that `ClearScene(false)` clears and `ClearScene(true)` keeps.
  **Lane U, T2, S.** Do it in the same task as findings 1–2.

### 4. SF: A limb is removed before its blast is shown, and the "nearest limb" uses the previous blast
- **Where:** `BomClientBehaviour.cs:1072-1074` (`lastBlast` set when an event is presented), `:1112`/`:1118-1152`
  (`PresentLimbLoss` runs every sample from `client.RoundPlayers`). `BomLimbLoss.cs:110`.
- **What is wrong:** `graze_count` comes from the latest reliable round snapshot, but explosion events are presentation-gated
  (`e.tick > presentation_tick` throws). The count increments one interpolation delay before the explosion appears. At that moment
  `lastBlast` still points at the previous blast, or `hasBlast` is false and a fixed-order limb is taken.
- **Failing scenario:** a graze from a bomb on the player's left. The limb drops off before the explosion is drawn, and the right limb is
  chosen because the previous bomb landed on the right.
- **Verified by:** code read. The size of the lead is unmeasured.
- **Fix:** queue each count increase and present it when an explosion event with `tick >=` the round snapshot's `tick` is
  presented (or after a timeout). Use that event's centre. **Lane U, T2, S–M.** Do it in the same fix pack.

### 5. SF: IL2CPP builds will lose all game audio, and C4's wallet bridge will hit the same problem
- **Where:** `Assets/BOMIntegration/Runtime/link.xml` preserves only `BombBlastVisual`. `BomGameAudio.cs` binds
  `GameAudio.PlayBombExplosion/PlayWhistle/PlayButtonPopSound` by reflection.
- **Failing scenario:** F4 builds IL2CPP with managed stripping. If the methods are stripped, the player logs
  `BOM AUDIO could not bind GameAudio statics; game audio is off.` and stays silent. The C3 finding flagged this; it is not done yet.
  C4's `MatchMenuUI.AddShopCoins` via reflection needs the same protection.
- **Verified by:** reading `link.xml` and `BomGameAudio.cs`. Whether stripping actually removes them is under Needs a run.
- **Fix:** add `<type fullname="GameAudio" preserve="all"/>` (and `MatchMenuUI` in C4). **Lane U, T3, S.** Can be folded into C4.

### 6. SF: The Rounds gate does not re-export the yard, and the committed draw fixture is stale
- **Where:** `integration/tools/Test-NetworkRounds.ps1:29` calls `BomNetworkMenuBuilder.BuildWithDrawFixture`.
  `Assets/BOMIntegration/Editor/BomNetworkMenuBuilder.cs` has `BuildWithDrawFixture`, which exports only the draw fixture (`BuildMono` also exports the yard).
  `integration/fixtures/round-draw/draw.json` is still `"gameplay_config":{"version":3` (last touched by E1-N1).
- **Failing scenario 1:** the next N task that changes config. Rounds fails with "manifest mismatch" until someone remembers the Level trap. This has already cost
  E1-N2 a run.
- **Failing scenario 2:** `Test-NetworkRounds.ps1 -SkipBuild` uses the committed `fixtures/round-draw/draw.json` (line 37), which
  is config 3 and does not match the current draw registry.
- **The Native DLL trap is also enforced only by failure:** `Test-RealNativeInterop.ps1:23` rebuilds `bomcore.dll` into
  `<OdinRoot>/build` and never restores it. The identity guard and `Run-UnityRounds.py:8` then fail loudly, which is safe but costs time.
- **Verified by:** code and file reads.
- **Fix:** have `BuildWithDrawFixture` also call `BomYardBuilder.CreateAndExport()` (or add a `-ReexportYard` step to the tool),
  refresh `fixtures/round-draw/draw.json` from the gate output, and make `Test-RealNativeInterop.ps1` back up and restore the stage
  DLL, manifest and `interop/` copy. **Lane U, T2, S.**

### 7. SF: An unexplained input-schedule restart in the seed 137 / 200 ms / 5 % Prediction profile
- **Where:** evidence `integration/evidence/M9/profile-20261111T201552711944Z/profile.log:121-155`.
- **What happened:** two unscripted restarts at t=113 s and t=352 s. Each is `Warming/Uninitialized`, then `Conservative/Missing_Command`, and
  `input_generation` goes 1→2→3. Totals: resets 2, conservative 0.033 s. None of the other 11 profiles since N1b changed input generation.
  The pre-N1b failure (`profile-20261111T140152557313Z`, generations 1→4→6) has the same signature. N1b's analysis covered only
  `Unsafe_Position`. This is reason 1/7, a different path.
- **Is it a real signal:** yes. It is rare and tolerated by the thresholds, but it is not choreography. N3 does not touch Sandbox, so it is probably pre-existing
  and timing/loss related (server `starved=18` was the high end of the runs).
- **Also:** `evidence/M0/Test-Prediction-*.json` record `"checks": []`, so the suite record holds none of the per-profile numbers. Reviewers
  must open each `M9/profile-*` folder.
- **Verified by:** tabulating `summary.json` of all 20 profiles from today and reading the transition lines.
- **Fix:** first repeat the profile (Needs a run). If it recurs, it becomes a Lane N T1 M investigation of what makes the server re-offer a schedule under loss.
  Have the suite write per-profile resets/transitions/generations into its M0 record (**Lane U, T3, S**).

### 8. SF (rule question): A player whose near side is covered inside the kill zone gets nothing, even with the far side exposed in the graze zone
- **Where:** Odin `src/shared/sim_yard.odin:97` (`!round_capsule_hit(center,point,lethal_radius)` gates the graze).
- **Failing scenario:** the bomb lands 1.0 units from a player's capsule surface, behind a low wall. The lower body is covered and the head sticks up at 1.6 units, exposed.
  The lethal query sees no exposed part within 1.2, so the player does not die. The graze gate is skipped because the capsule surface is within 1.2. The player takes no damage, while a
  player standing further away is grazed. This matches the letter of `round-rules.md` ("an exposed capsule outside the effective lethal radius"),
  but it is probably not what D1 meant, and `graze_test.odin` does not test it.
- **Verified by:** code read.
- **Fix:** owner decides: "exposed portion inside the graze annulus counts even if the nearest point is inside the lethal radius" (recommended).
  Then a small native change and a test. **Lane N, T1, S.** Bundle it with N4 to avoid an extra E1.

### 9. SF: Stale version statements will reach the package and mislead agents
- `integration/README.md:57-58` says ABI 1.4, protocol 7, round format 2, config 2. This file becomes the packaged `DEVELOPER-README.md`.
- `integration/ALPHA-SYNC.md:292` (F3) tells the agent to "make it say protocol 7". That is now wrong (protocol 8).
- `integration/contracts/BomNative.cs`, `bom-abi.json` and `bom_client.h` are ABI 1.4 copies (`abi_minor: 4`, `reserved` where
  `graze_count` now is). No tool reads them, and `contracts/README.md` still says "Contract work pending M1".
- Odin `AGENTS.md:49` says "Passed on protocol 7". `round-rules.md:23-26` still says "E1-N3 must update…", but E1-N3 is done.
- **Fix:** edit F3 to "protocol 8 / ABI 1.5 / config 5". Then either refresh the contract copies from `Documents\BOM\bindings` in every E1 (add that to
  `Build-OwnerNative.py`), or delete them and point to the Odin path. **Lane U, T3, S.** The Odin AGENTS line is Lane N, T3.

### 10. NH: Slot labels and colours follow the connection index, not the participant
- **Where:** `BomPlayerLook.cs:39-55`, called with `(int)pose.id` at `BomClientBehaviour.cs:960`.
- **Scenario:** any spectator or observer that connects first holds slot 0, so the players read P2/P3 (seen in Rounds). In a 4-seat server a
  spectator also takes a seat (native has 4 connection slots for players and spectators together), so only 3 can play. If a resumed session reconnects into a different free slot, its colour and label change between rounds.
  (Unverified: whether native reuses the same slot on resume.)
- **Fix:** for elimination, number players by their order in the round roster (P1…Pn) and fall back to the slot in Sandbox. Spectator seats are
  an owner product question (see section 4). **Lane U, T2, S.**

### 11. NH: Network play is keyboard-only and binds fewer keys than Darryn's game
- **Where:** `BomClientBehaviour.cs:316-330`: A/D, arrows and Space only. Darryn's `ArenaPlayerController.cs:365-375` also jumps on W, the
  Up arrow and gamepad South. Network play has no gamepad at all. No ALPHA-SYNC task covers this.
- **Fix:** add the bindings plus gamepad stick/South. Input timing stays native. **Lane U, T2, S.**

### 12. NH: The HUD allocates garbage every frame
- **Where:** `BomNetworkHud.cs:350-430` in `Update`: `hud.Q<Label>("controls")`, the `Query(...).ForEach(lambda)` call, and about 8 string
  concatenations and `ToString` calls per frame, whether or not anything changed.
- **Fix:** cache the queried elements, and set text only when the round id, tick or values change. This matters for F2 (choppiness). **Lane U, T2, S.**

### 13. NH: Exporter accepts an invalid `GrazesToDie`
- **Where:** `BomLevelAuthoring.cs:77` (plain `int`), `BomLevelExporter.cs:384` (`Math.Max(0, …)`).
- **Scenario:** an artist types 0 or 300, which fails late in native validation with a generic error. Add `[Range(1,255)]` and an exporter check
  with a clear message. **Lane U, T3, S.**

### 14. NH: The host power hook is a "test" environment variable that the release launcher uses
- **Where:** `BomClientBehaviour.cs:296` reads `BOM_TEST_HOST_TOKEN`. `integration/tools/Launch-BomPackage.ps1:26-28` sets it for the host.
- **Not an escalation:** the server compares it with its own random `--host-token`, so setting it without the server's key grants nothing.
  The flag-4 and `mode==1` checks on blast clicks are convenience only; the server rejects manual blasts in elimination.
- **Risk for C5:** the in-player server launch should pass the key in memory through `ConnectTo(..., token)` and not use the environment. Environment
  variables are inherited by child processes, and the name invites removal as "test-only". Add this note to C5. **Lane U, T3, note only.**

### 15. NH: C4 has a type mismatch waiting
- `MatchMenuUI.AddShopCoins(int)` (MatchMenuUI.cs:280) receives Odin's `ulong xp_gained`, and it logs an error if `instance` is null.
  C4 should clamp to `int.MaxValue` and, as C3 did, bind by reflection with a `link.xml` entry. Add this to C4's text.

### 16. NH: `DisableDuplicateArenaHud` runs only in `OnEnable` and `Start`
- **Where:** `BomNetworkHud.cs:60-84`. A duplicate `UIDocument` that loads or is re-enabled later (additive scene, Darryn's script toggling it)
  would show his unstyled panels again. Unverified: no current script was found that re-enables it. Cheap guard: re-check on
  `SceneManager.sceneLoaded`. **Lane U, T3, S.**

### Unverified (kept out of the ranking)
- **U1.** Native graze query radius is `graze_radius + 1 ULP` (`sim_yard.odin:101`), while the cover snapshot is built for `graze_radius` (`:89`).
  This only matters if `cover_begin` culls occluders strictly by radius. It is at most a 1-ULP edge and probably harmless.
- **U2.** `bomcore.build.json` records compiler arguments `-debug` with `optimization: speed`. Check whether the F4 release DLL should drop `-debug`.
- **U3.** Four tracked `Assets/Polytope Studio/.../*.unitypackage.meta` files are not in the 1562-file baseline. This is likely intentional; confirm.

## 3. Needs a run

Run these only with Unity closed, ≥4 GB free RAM and no soak in progress (rule 3). One at a time.

1. **Is the burst missing on round-ending deaths?** (finding 1) Run a two-window local play and let one player die; then repeat with 3 players.
   `powershell -File C:\Users\jblic\Documents\BOM-Release\launch-c2-check.ps1`
   Expect: no burst for the last death. Today nothing logs a burst, so this needs eyes or a screen capture.
2. **Effect truncation** (finding 3): the same session, late in a round (after 90 s). Watch whether explosion and burst effects vanish when the next bomb lands.
3. **Limb-before-blast lead** (finding 4): the same session. Note the time between a `BOM UNITY GRAZE` log line and the matching `BOM UNITY EVENT` line in the player log:
   `Select-String -Path <player log> -Pattern "BOM UNITY GRAZE|BOM UNITY EVENT"`
4. **Any graze through Unity end to end** (area C: nothing exercises it today). Repeat Rounds until a graze occurs, or add a graze fixture:
   `powershell -File integration/tools/Test-NetworkRounds.ps1 -ConfigPath integration/local.config.owner-validation.json`
   then `Select-String -Path integration/evidence/M8/unity-rounds-*/primary.log,integration/evidence/M8/unity-rounds-*/guest.log -Pattern "BOM UNITY GRAZE"`
5. **Prediction reset recurrence** (finding 7). Repeat 3×:
   `python integration/tools/Run-PredictionProfile.py --config integration/local.config.owner-validation.json --seed 137 --rtt-ms 200 --jitter-ms 30 --loss 0.05 --seconds 600 --evidence-stage M9`
   then `Select-String -Path integration/evidence/M9/profile-*/profile.log -Pattern "PROFILE TRANSITION"`
6. **IL2CPP audio binding** (finding 5):
   `powershell -File integration/tools/Build-BomPlayers.ps1 -Backend IL2CPP -ConfigPath integration/local.config.owner-validation.json`, launch the
   player once, then `Select-String -Path <player log> -Pattern "BOM AUDIO could not bind"`.
7. **Stale performance, source-fixture and editor-export registries** (pre-N1, E1-N1 finding). They will fail Performance, Soak and the editor fixture suites. Before relying on those suites, re-export
   (`BomPerformanceBuilder.BuildMono` with `BOM_PERFORMANCE_LAYOUT_DIR`) and then run
   `powershell -File integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Performance -ConfigPath integration/local.config.owner-validation.json`.
8. **Release launcher on Windows PowerShell 5.1** (F4): `powershell -File <package>\Launch-Bom.ps1 -Clients 2`.
   Note that `Test-RealNativeInterop.ps1:23` calls `pwsh`, but AGENTS.md says PowerShell 7 is not installed. Check how A1's NativeInterop passed.

## 4. Insights on the plan (area D)

**Alpha features with no task in ALPHA-SYNC.md** (from `Assets/Game/**`):
- Gamepad and shared-keyboard input in network play (finding 11). D4 covers only couch play.
- Music in `NetworkMenu`/`NetworkYard`: open C3 finding, no owner decision and no task. C5 makes this mostly moot if `MainMenuScene` and Darryn's level
  scene names are used, but `NetworkYard` stays silent.
- The chosen character over the wire (D7 says "later", no task). The 15-colour select and shop are cosmetic-only until it exists.
- Settings screen: `MatchMenuUI.RestartCurrentScene` resets the wallet to 250 and the owned characters. Once C4 pays Odin rewards into the
  wallet, this "reset" also wipes earned network coins. The owner should know.
- Graze feedback in the HUD (graze count or hearts) and a graze ring (see below).
- `MenuCursor` in network scenes: A2 said "check visually in C5". It is not in C5's Done-when list.
- Darryn's local "Play" mode keeps Unity-physics rules (D4). That means two rule sets would ship. N6 is only a spike, with no follow-up build task.

**Which decisions block the most:**
1. **D9 (editing Darryn's files)**: blocks C5 and C7, so it also blocks F4 (after C7) and in practice C6's level picker. It blocks the most work.
2. **D3 (online = Odin UDP/LAN, drop NGO/Relay)**: blocks C5 and C7. Settle together with D9.
3. **D5 (currency)**: blocks only C4, but C4 is the next Lane U task in the order.
4. D6 → N4, D8 → N5, D10 → F1, D11 → F5 can wait.

**Recommended next order:**
- Lane U: **P1 presentation fix pack** (findings 1–4, plus a `BOM UNITY BURST` log; T2, M), then the **E1-N3 owner check**, then **tool fixes**
  (findings 6, 9, 5; T3/T2, S), then **C4** (needs D5), then **C5** (needs D3 and D9, L), then C6, then C7, then F1/F3.
- Lane N: **N4** in parallel. Fold in finding 8 (if the owner agrees) and `graze_radius` in `BomRoundInfo`, so one version bump and one E1 cover all three.
  Then N5. Run N6 any time Lane N is idle.
- F2 (choppiness) can start right after the fix pack; finding 12 is an input to it.

**Expose `graze_radius` natively (ABI 1.6) before N4?** Not on its own. Each native change costs a full E1: a checkpoint build, re-exporting every
level, and Build, Content, Rounds and Prediction (hours on this machine). N4 must bump ABI/protocol anyway for item actors, so add `graze_radius`
to `BomRoundInfo` there. The only reason to do it earlier is if the owner finds grazes unreadable in the E1-N3 owner check. Note that
`BomRoundInfo` has no reserved field, so this is an ABI minor bump that appends a field at the end, not a field swap like N3.

**Largest release risk:** C5 (one front door). It is the only L task that both edits protected originals and adds a new process lifecycle:
launching `BOM-server.exe` from the player, firewall prompts, port conflicts, and killing the server on crash or quit. There is no gate for
any of that yet, and the Rounds gate drives the network scene directly, not the main menu. Write C5's Done-when as an automated
menu-to-round run, not only a manual two-window check.

**Things the owner is probably not seeing:**
- The burst missing in the C2 owner check is very likely finding 1, not a rendering problem. In 2-player play it will never show.
- No automated gate has ever produced a graze or a burst. The E1-N3 "pass" proves the code compiles and does not throw, not that it looks right.
- A spectator uses one of the 4 seats.
- The Prediction suite's M0 record is empty (`checks: []`), so "Prediction 6/6 pass" hides a profile with 2 resets.
- `integration/evidence` keeps growing with PNGs from every Rounds run; D11 and F5 will have more to move each week.

## 5. Checked and fine

- **Versions and identity:** protocol 8 (`net_session.odin`), round rules 3 (`round_wire.odin`), config 5 (`gameplay_config.odin`, exporter
  `"version":5`), ABI 1.5 (`abi.odin`, Unity `BomNative.cs` byte-identical to Odin `bindings/BomNative.cs`), level 4, canonical 3. The DLL sha256 `0887c0b1…5deb8`
  matches `bomcore.build.json` (source `9eb164e`, `source_dirty:false`) and `BomExpectedNativeIdentity.cs`.
- **Graze field width:** u32 on the wire and in the ABI. The count stops at `grazes_to_die` (≤255) because of the skip at `sim_yard.odin:94`, so it cannot overflow. The offset-28
  swap keeps the 64-byte stride, and an FFI test covers it.
- **Config migration:** v1 → defaults with authored movement kept; v≤2 → gravity scale 1; v≤3 → lethal 1.2 and graze 2.2 with the crater kept; v4 keeps everything; all → `grazes_to_die`
  3. v5 is validated strictly. Default IDs v1..v5 resolve. Tests cover v2, v3 and v4.
- **Sandbox unchanged:** the whole damage block is inside `if w.elimination_playing` (`sim_yard.odin:81`), and `graze_sandbox_keeps_players_undamaged…` tests it.
- **Same-tick rules:** deaths accumulate across all explosions in a tick before a winner or draw is chosen. A pending death takes no further grazes. Simultaneous
  third grazes end in a draw (tested). A disconnect keeps the last copied count (tested).
- **Cover order:** the cover snapshot is taken before `blast_pass` destroys anything (tested).
- **Tangency:** lethal tangency is harmless and outer graze tangency counts. This matches the contract.
- **BomLimbLoss:** it instantiates a private damaged mesh (`BomLimbLoss.cs:257`), restores `sharedMesh` and destroys its copies on reset or destroy, and `ResetBody` runs on every
  pool rent (`BomClientBehaviour.cs:963`). The shared asset is never mutated, and no state carries over between rounds or actors. Late observers rebuild from the count without effects.
- **Pooling:** `BomActorPool.Rent` resets the view. `BomPlayerLook.Configure` re-applies the slot per rent through property blocks, so no shared material is modified.
- **Authority:** no Unity code decides hits, deaths, graze counts or round state. The audio, camera and HUD only read copied state. `Time.timeScale` is set only from a CLI flag
  for tests.
- **Prediction profiles run current tuning:** `fixtures/M5/static-layout.json` is a layout v1 with no config, so it resolves to the current defaults (speed 7). N1b
  confirms the N1 speed. All 6 profiles passed in E1-N1, E1-N2 and E1-N3.
- **Content baseline:** 1562 entries, every entry still tracked, and it covers `MatchMenuUI.cs`, `GameAudio.cs`, `Packages/manifest.json` and `PC_RPAsset.asset`
  (the files D9 and D10 would touch). Only the 4 `.unitypackage.meta` files are outside it (U3).
- **Scene tuning:** `NetworkYard`, `NetworkMenu` and `RoundDraw` serialize speed 7, gravity scale 2.551 and `GrazesToDie` 3. The yard fixture is config 5.
- **Native tests added:** graze (11), lethal radius (6), FFI graze layout (1), player tuning, prediction region. They test the contract, not just smoke.
