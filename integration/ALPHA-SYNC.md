# Alpha sync: Odin integration + Darryn's AlphaV0.1

Written 2026-11-10 by Claude Opus 5.5. This file is the work queue. **One task per session.** Read the
"Rules for every task" section, then only your own task. Tick your box when you finish (rule 6).

## Where things stand (already done, do not redo)
- [x] AlphaV0.1 (72e67df) merged into `integration/odin-unity-20261105` as `d03d0d5`. The merge used
  `--merge-base=c3a7d53` because this branch holds rewritten copies of the team's commits up to
  "Menu Changes 0.1" (same trees, different hashes). It was clean. Later merges from AlphaV0.1 work normally.
- [x] Committed WebGL build outputs removed and git-ignored (`df391b2`). WebGL is not a target.
- [x] Protected-content baseline moved to Darryn's new originals: 1562 files (`865a1a5`).
- [x] `BomActorPool` exit-time NullReferenceException fixed (`da47625`). Not yet seen in a rebuilt player.
- [x] `integration/local.config.json` (git-ignored) rewritten to live paths. The old config pointed at deleted
  folders in `Downloads\BOM-Windows-Game`.

**What each side brings.** Odin (ours) brings server authority, deterministic destruction, prediction,
4-player rounds, cover and XP. Darryn brings the product shell: splash, menu, level select (Yard, Bridge,
Tower), a 15-colour character select and shop, gamepad/shared-keyboard local play, pause, music and SFX,
player labels, item glow, limb-loss chunks, 10° camera tilt, coins, items, and online play through
Netcode for GameObjects + Unity Relay.
The goal: **Odin rules everything; Darryn's shell and feel sit on top.** Keep Odin's netcode, rules and
bomb pacing. Take Darryn's presentation, menus, audio and levels. Bring his rules into Odin only after the
owner approves them (decisions below).

## Owner decisions (owner ticks these; tasks that need one stop until it is ticked)
Recommendations are Claude's. Tick = approved as written. To change a decision, edit the line.
- [x] **D1 Lethality.** (approved by owner 2026-11-10) Separate the lethal radius from the destruction radius. Keep the 5-unit craters.
  Kill within 1.2 units. Between 1.2 and 2.2 units is a graze: lose a limb, die on the 3rd graze. Cover
  still protects. *Why:* today the lethal radius equals the bomb radius (5), so every bomb kills in an
  ~11-unit circle inside a 40-unit arena, with bombs every 1–2.5 s. Darryn's near misses are where the fun is.
- [x] **D2 Movement feel.** (approved by owner 2026-11-10) Speed 4→7, jump height 2.5 units, player gravity 25 (snappy, ~0.9 s airtime)
  using a *player-only* gravity scale. World gravity stays 9.8, so debris is unchanged.
  *Why:* today jump 6.3 at g=9.8 gives a floaty 1.3 s airtime at walking pace.
- [ ] **D3 Online.** Keep Odin UDP with LAN or direct IP for now and drop Unity Relay/NGO. Design an
  internet relay later.
- [ ] **D4 Couch play.** Couch play moves to Odin later through task N6. Until then Darryn's local
  "Play" mode keeps its own Unity-physics rules (two rule sets, temporarily).
- [ ] **D5 Currency.** Odin's round award goes into Darryn's local shop wallet as coins. The formulas are
  already identical: 10 per bomb faced + 1 per second. The shop stays cosmetic and local.
- [ ] **D6 Items.** Coins, invincibility, speed and slow become native Odin items, using Darryn's
  durations and chances. Do this after N1–N2.
- [ ] **D7 Network cosmetics.** For now every player gets a slot colour (P1 blue, P2 red, P3 yellow,
  P4 green). Sending each player's chosen character over the wire comes later.
- [ ] **D8 Solo.** Add a native Survival mode (1–4 players; the round ends when all are dead), with
  optional native bots.
- [ ] **D9 Editing Darryn's files.** Integration tasks C5 and C7 may edit `Assets/Game/Scripts/MatchMenuUI.cs`,
  `Assets/Game/Online/*`, `Assets/Game/Scenes/MainMenuScene.unity` and `Packages/manifest.json`, then
  re-baseline those exact files. Without this, the menus cannot be joined up.
- [ ] **D10 Shadows.** Raise the additional-light shadow atlas in `Assets/Settings/PC_RPAsset.asset` from 2048
  to 4096. This should fix the colour shifting in shadows.
- [ ] **D11 PR prep.** Before the PR, rewrite this branch so the 273 MB of `integration/evidence` leaves
  history. This needs a force-push.

## Models and lanes
| Tier | Use for | Claude | ChatGPT (Codex) |
| --- | --- | --- | --- |
| **T1** | Native rules, wire/ABI, identity rebuilds, design-heavy Unity work, spikes | Opus 5.5 | strongest model, reasoning high |
| **T2** | Well-specified Unity features | Sonnet 5.5 | default model, reasoning medium |
| **T3** | Mechanical edits, running gates, doc fixes | Haiku 5.5 | small/mini model, reasoning low |

- **Lane U** (Unity) runs in `C:\Users\jblic\Desktop\Bomb-integration` on branch `integration/odin-unity-20261105`.
  Only one Lane U session at a time, ever.
- **Lane N** (native) runs in `C:\Users\jblic\Documents\BOM` on branch `alpha-sync` (N1 creates it from `master`).
  One Lane N session at a time. It may run alongside a Lane U session that is *only editing code*, but
  never while any Unity Editor, build or soak is running (the machine has ~4 GB free RAM).
- Native changes reach Unity only through task **E1**, which is Lane U and T1.
- Budget split: Lane N goes to Codex, Lane U T1 to Claude Opus, T2 to Sonnet (or Codex medium when Claude
  is low), and T3 to whichever has headroom. Sizes: S < 1 h, M 1–3 h, L = several sessions.

## Order (the orchestrator follows this)
1. A1 → A2 → A3, strictly in order (Lane U). Nothing else starts until A2 is ticked.
2. Owner ticks decisions. Then two lanes run in parallel:
   Lane U: C1 → C2 → C3 → C4 → (D9) C5 → C6 → C7 → F1 → F3.
   Lane N: (D2) N1 → (D1) N2 → N3 → (D6) N4 → (D8) N5. N6 can start any time after A2.
3. Run E1 after each Lane N task, taking the Lane U slot between two C tasks.
4. F2 runs after C1–C4. F4 runs after C7 and E1. F5 comes last (needs D11).

### Prompt to paste into each session (fill in the ID)
> You are doing task **<ID>** in `C:\Users\jblic\Desktop\Bomb-integration\integration\ALPHA-SYNC.md`.
> Read `AGENTS.md` in the repo you work in, then that file's "Rules for every task" and task <ID> only.
> Claim it, do exactly its steps, verify with its "Done when", tick it, and stop. Do not start another task.

## Rules for every task
1. **Claim before working.** Change `[ ]` to `[~]` on your task and append `claimed: <model> <YYYY-MM-DD>`.
   Then run `git -C C:\Users\jblic\Desktop\Bomb-integration commit -m "Claim <ID>" -- integration/ALPHA-SYNC.md`.
   If the box is already `[~]` or `[x]`, stop.
2. **Never** do any of these:
   - push, open a PR, or merge into `main`;
   - edit a protected file (anything in `integration/baselines/unity-content.json`) unless your task says
     so *and* its decision is ticked;
   - set `Time.timeScale`, or add Rigidbody, CharacterController or Unity physics to Odin scenes;
   - weaken or delete a test, or hand-edit `bomcore.dll`, `BomNative.cs` or `BomExpectedNativeIdentity.cs`.
3. **Before any Unity run:** `Get-Process Unity -ErrorAction SilentlyContinue` must return nothing. Free RAM
   must be ≥ 4 GB and C: must have ≥ 15 GB free. If not, wait or stop with `[!]`. Run one Unity process at a time.
4. **Configs.** Use `integration/local.config.owner-validation.json` for build and test tools (A1 creates it).
   Use `integration/local.config.json` only for `Build-OwnerNative.py`. Always pass `-ConfigPath` explicitly.
5. **Unity code in this repo is dense, single-line style.** Keep each edit small. New code goes in new files
   under `Assets/BOMIntegration/Runtime/` with a `.meta` file and a fresh GUID. Never change an existing
   GUID. Never edit Darryn's scripts unless your task allows it.
6. **Finish.**
   - Commit your work with a message that includes the key "Done when" output lines.
   - Change your box to `[x]` and append `done: <model> <date> <commit> — <one-line result>`.
   - Commit the doc as in rule 1.
   - If you are still blocked after two honest attempts: mark `[!]`, add the reason and the evidence path, commit, and stop.
7. **Gates:**
   - **Content**: `powershell -File integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content -ConfigPath integration/local.config.json`
   - **Build**: `powershell -File integration/tools/Build-BomPlayers.ps1 -Backend Mono -ConfigPath integration/local.config.owner-validation.json`.
     The player is written to `integration/build/validation/Mono/BombPerformance.exe`. On failure, read `error CS` lines in that folder's `editor-*.log`.
   - **Rounds**: `powershell -File integration/tools/Test-NetworkRounds.ps1 -ConfigPath integration/local.config.owner-validation.json`
     (no `-SkipBuild`). It builds its own `integration/build/validation/Network-Mono/BombNetwork.exe` and runs two clients for two rounds. Evidence lands in `integration/evidence/M8/unity-rounds-*`.
   - **Native DLL trap** (cost an hour on 2026-11-11): the NativeInterop suite *rebuilds* `bomcore.dll` and rewrites
     `bomcore.build.json` inside the native stage (`OdinRoot` in the owner-validation config). The bytes differ even from
     the same source, so later player builds fail the identity guard ("Native DLL SHA-256 differs"). After running NativeInterop,
     restore both files from `Assets/BOMIntegration/Plugins/x86_64/` into `<OdinRoot>/build/`, and copy the same
     `bomcore.dll` into `<OdinRoot>/build/interop/` (the Prediction suite checks that copy).
   - **Level trap**: a level's `VisualRegistry.asset` holds the manifest hash the client sends. If gameplay config or the layout
     changes, re-export the level in the validation project (`-executeMethod BomYardBuilder.CreateAndExport` with
     `BOM_YARD_LAYOUT_OUT` and `BOM_NATIVE_SERVER_EXE` set). Then copy the changed registry and scene back into the repo and commit them,
     or the server answers "gameplay level/config manifest mismatch".
   - **Sync**: `Build-BomPlayers.ps1` only copies `Assets/BOMIntegration` into an existing validation copy.
     If you changed files outside it, mirror them first. From the repo root, run
     `robocopy Assets <validation>\Assets /MIR /XD BOMIntegration Library`, then
     `robocopy Packages <validation>\Packages /MIR` and `robocopy ProjectSettings <validation>\ProjectSettings /MIR`.
     `<validation>` is `UnityValidationProject` in the config.
8. **Presentation tasks** end with an *Owner check* box. Models never tick it; the owner plays the build and ticks it.

---

## Phase A: restore the pipeline (Lane U, strictly in order)
- [x] **A1 Native checkpoint from Odin `master`** (T1, Codex high or Opus, S) done: Claude Opus 5.5 2026-11-10 b868ce7 — tag 1072309867234513910 from master 0c11f5e, clean; NativeInterop PASS
  1. `cd C:\Users\jblic\Desktop\Bomb-integration`, then `python integration/tools/Build-OwnerNative.py --config integration/local.config.json`.
  2. It rebuilds the server and DLL from `Documents\BOM` and copies the plugin, `BomNative.cs`,
     `bomcore.build.json` and `BomExpectedNativeIdentity.cs`. It also writes `integration/local.config.owner-validation.json`.
     The build tag changes; the source now matches commit 0c11f5e instead of the deleted dirty worktree.
  3. `powershell -File integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite NativeInterop -ConfigPath integration/local.config.owner-validation.json`
  - Done when: the script prints `built-and-copied` with `source_dirty: false`, NativeInterop passes, and the 4 changed SDK files are committed.
  - Don't: edit Odin source. If `source_dirty` is true, stop and report `git -C C:\Users\jblic\Documents\BOM status`.
- [x] **A2 First build after the merge** (T1, Opus, M) done: Claude Opus 5.5 2026-11-11 1d65bc0 — Build, Content (1562), Rounds Yard+Draw pass; logs clean incl. exit; stale yard/draw registries re-exported (see Findings)
  1. Run Build (rule 7). The first run creates `Documents\BOM-validation\alpha-merge` and imports ~7 GB,
     including Darryn's NGO packages (needs internet). Allow 30+ minutes; run it in the background.
  2. Run Content, then Rounds.
  3. In the Rounds player logs, check: `BOM UNITY AUTHORITY PASS` is present; there are no `Exception` lines,
     including on exit (this verifies the `da47625` fix); and Darryn's global objects don't break our scenes.
     `MatchMenuUI`, `MenuCursor` and `GameAudio` all start themselves in every scene. Report what each one does in `NetworkMenu`/`NetworkYard`.
  4. Fix only what blocks the gates, with the smallest change in `Assets/BOMIntegration`. List anything else
     under "Findings" at the bottom of this file.
  - Done when: Build, Content and Rounds pass, and the log check results are written into your tick line or into Findings.
- [x] **A3 Make the integration C# readable** (T2, Sonnet, S) done: Claude Opus 5.5 2026-11-11 43f41b4 — 54 files, lines >300 chars 131→0, Build passes
  - Re-run after big edits: `csharpier format Assets/BOMIntegration/Runtime Assets/BOMIntegration/Editor`, then
    `git checkout -- Assets/BOMIntegration/Runtime/BomNative.cs Assets/BOMIntegration/Runtime/BomExpectedNativeIdentity.cs` (generated files).
  - Note: `git diff --ignore-all-space` cannot prove a reformat (lines get split). The proof used was "file text with all whitespace removed
    is identical, apart from trailing commas and `using` order" (see the commit message).

## Phase C: presentation synthesis (Lane U, in order; T2 unless marked)
In every C task, read native state from `BomClientBehaviour`/`BomSession` and draw it. Never decide outcomes in Unity.
- [x] **C1 Camera rig** (T2, Sonnet, M) claimed: Claude Sonnet 5.5 2026-11-11; done: Claude Sonnet 5.5 2026-11-11 9bb7780 — Build, Content (1562) and Rounds Yard+Draw pass with the rig active (guest running_frames=516, native_jump=True); owner check still open
  - New `Runtime/BomCameraRig.cs`. It replaces the static framing in `BomClientBehaviour` (search `orthographicSize=`).
  - Frame every living player's native position with Darryn's defaults: padding 0.5, smooth time 0.12,
    minimum view height 16, maximum = the whole `camera_bounds`, tilt 10° (an inspector field), clamped
    inside `camera_bounds`. Darryn's `Assets/Game/Arena/ArenaCamera.cs` is the reference; don't reuse the class.
  - Add a shake on native explosion events. Amplitude falls off with the distance to the local player:
    at most 0.35 units, 0.25 s, nothing beyond 3× the blast radius.
  - Done when: Build and Rounds pass and the zoom values are serialized fields. [ ] Owner check: framing feels right with 1, 2 and 4 players.
- [ ] **C2 Player look** (T2, Sonnet, M)
  - Slot colours (D7): use Darryn's first 4 colours from `MatchMenuUI.characterColors`; copy the values.
  - Floating `P1`–`P4` labels, the way `ArenaPlayerController.CreatePlayerLabel` does it.
  - Facing flip and the Animator `Running` bool from native velocity. First check whether `BomActorView` already does this.
  - Death burst: clay chunks on a native death event, like `PlayerBodyDamage.Burst`. Presentation only;
    give the chunks no colliders and no Rigidbody (animate them in code).
  - Done when: Build and Rounds pass. [ ] Owner check.
- [ ] **C3 Audio** (T3 can do this; Haiku, S)
  - Call Darryn's public statics in `Assets/Game/Scripts/GameAudio.cs` without editing that file:
    `PlayBombExplosion(pos)` on each native explosion, `PlayWhistle()` when a round goes Playing and again when it goes Finished,
    and `PlayButtonPopSound()` on our UI Toolkit buttons in `BomNetworkHud`.
  - Read how `GameAudio` picks music by scene name, and write what happens in `NetworkMenu`/`NetworkYard` into your tick line.
  - Done when: Build and Rounds pass, and the player log has no `Game audio prefab could not be loaded`. [ ] Owner check.
- [ ] **C4 HUD, pause and results** (T2, Sonnet, M; needs D5)
  - `BomNetworkHud` still queries `level-fill`, `result-xp`, `current-level` and `next-level`, which Darryn's
    new `ArenaHud.uxml` removed. Map the HUD to his elements instead:
    - `result-coins` = Odin `xp_gained`, plus `result-bombs`, `result-time` and `result-total-coins` (the wallet total);
    - `pause-panel` = our Esc menu (the game does **not** pause in network play);
    - `replay-button` = host restart command (shown to the host only);
    - `return-button` = disconnect.
  - Wallet: call `MatchMenuUI.AddShopCoins(xp_gained)` exactly once per finished round. Key it on the round id;
    reconnects must not pay twice. Log `BOM WALLET round=<id> +<n>` at the moment you pay.
  - Done when: Build and Rounds pass, and each finished round logs exactly one `BOM WALLET` line. [ ] Owner check.
- [ ] **C5 One front door** (T1, Opus, L; needs D3 and D9)
  - Darryn's `MainMenuScene` becomes the first scene. "Play" keeps his local mode (D4). "Online" opens Odin play:
    - **Host:** pick a level and start `BOM-server.exe` from the player's folder with `--bind`, `--port`,
      `--layout` and a random `--host-token` (copy the logic in `BOM-Windows/Launch-Bom.ps1`). Then connect.
      Kill the server when the host quits.
    - **Join:** enter an IP and port.
  - Reuse the existing `NetworkMenu` code. Edit only the files D9 lists, then re-baseline exactly those files.
    Copy the hash-update approach in commit `865a1a5`'s message, and list every re-baselined file in your commit.
  - Done when: Build, Content and Rounds pass, and a two-window run (host and join on 127.0.0.1) goes from
    the main menu to a finished round with no PowerShell launcher. [ ] Owner check.
- [ ] **C6 Darryn's levels on Odin** (T1, Opus, L)
  - `Editor/BomYardBuilder.cs` expects the old yard paths (`YardLevel/Grass_Mesh`), which Darryn replaced
    with ~130 `Yard Ground Tile 0x` prefabs. Write `Editor/BomTileLevelBuilder.cs`. It exports any scene
    built from `DestructibleObject` tiles plus `Left Wall`/`Right Wall`/`Bottom Boundary` into a native layout
    under `integration/fixtures/levels/<name>.json`:
    - walls are Fixed + Indestructible stone (same rules as the yard);
    - spawns and camera bounds come from `ArenaLayout`;
    - tile behaviour `Carve` maps to Anchored; `CarveAndFragment` maps to Dynamic.
  - Export YardLevel, BridgeLevel and TowerLevel. Validate each one with
    `python integration/tools/Test-LevelManifest.py --config <owner-validation config> --layout <json> --player <exe>`.
  - Add all three to the host level picker from C5. Keep the old network yard as "Classic Yard".
  - Done when: all three validate and play one round each in Rounds-style runs. Also fix the `Left Wall`/`Right Wall`
    `BOM VISUAL FALLBACK` warning seen in every playtest. [ ] Owner check.
- [ ] **C7 Remove NGO/Relay** (T2, Sonnet, S; needs C5 and D9)
  - Delete `Assets/Game/Online/` and remove `com.unity.netcode.gameobjects` and `com.unity.services.multiplayer` from `Packages/manifest.json`. Re-baseline.
  - Done when: Build and Content pass, and `git grep -n "Unity.Netcode\|Services.Multiplayer" -- Assets` is empty.

## Phase N: native gameplay (Lane N, Codex high, in order). Each task ends with E1.
Every N task:
- keeps determinism (no floats from wall-clock, no unseeded random);
- adds unit tests next to the code it changes (`src/shared/*_test.odin`);
- bumps a version only when that layout changes (Odin `AGENTS.md`);
- records the new rule in the Unity repo's `integration/contracts/round-rules.md`.

Native gates: `.\scripts\bom.ps1 Test` (220+), `.\scripts\bom.ps1 NetTest`, and
`.\scripts\test-client-core.ps1 -ConfigPath C:\Users\jblic\Desktop\Bomb-integration\integration\local.config.json`.
- [x] **N1 Movement feel** (D2, M) done: GPT-6 Codex 2026-11-11 35482a8 — game 220, transport 27, shared 95, FFI 20, Content 1562 PASS; speed 7 at 0.100 s, player g=25, config v3 migrates v2; evidence: Documents/BOM/evidence/N1/REPORT.md; E1-N1 pending
  - Add `gravity_scale` to `Player_Tuning`, applied to the player body only (Box2D per-body gravity scale).
  - Gameplay config version 2→3, with migration from 2.
  - New defaults: speed 7, jump_speed √(2·25·2.5) ≈ 11.18, gravity_scale 25/9.8. Retune acceleration so a
    standing start reaches full speed in ≤ 0.12 s.
  - Update the Unity exporter (`Editor/BomLevelExporter.cs`) in E1, not here.
- [~] **N1b Prediction window after N1** (Codex high or Opus, M; blocks E1-N1 and every later E1). claimed: Claude Opus 5.5 2026-11-11 The evidence is in E1-N1 above.
  - Likely cause (confirm first): `src/shared/prediction_client.odin` ~line 92. Large scenes build a 16×16 collision window around the
    owner (server-confirmed) position, and rebuild only when the owner gets within a *fixed* 3 units of the window edge. The predicted player runs
    `lead_ticks` (11–18 at 200 ms/5% loss) ahead of the owner. At speed 7 / jump 11.18 that's up to ~2 units sideways and ~3.4 up,
    so it can leave the window (`Outside_Collision_Window` → conservative) before a rebuild triggers. The margin was implicitly tuned for speed 4.
  1. Confirm: log the conservative reason on each transition (a test-only diagnostic) during the adverse profile:
     `python integration/tools/Run-PredictionProfile.py --config integration/local.config.owner-validation.json --evidence-stage M9 --seconds 600 --rtt-ms 200 --jitter-ms 30 --loss 0.05 --fps 144 --seed 42`
     (run from the Unity repo after an E1-style native rebuild, or the equivalent native-only harness in `tests/interop`).
  2. Fix: derive the rebuild margin (and the window half-size if needed) from the lead distance instead of a constant, e.g.
     `per-tick margin + (lead_ticks + pending_commands) * max(speed, jump_speed) / 60 + 1`, capped so the window stays within the
     existing collision-history capacity. Don't change thresholds in `tests/interop/PredictionProfile.cs`.
  3. Add a regression test: a player at speed 7 with an 18-tick lead never reports `Outside_Collision_Window` while the owner stays inside the window.
  - Done when: native gates pass and the adverse profile above shows `conservative_seconds` < 1 with transitions near 0. Then E1-N1 runs the full suite.
- [ ] **N2 Lethal radius** (D1, M): add config `lethal_radius` (1.2) and `graze_radius` (2.2), separate from
  `bomb_radius`. Kill only inside `lethal_radius`, still using `blast_capsule_visible` cover.
- [ ] **N3 Grazes** (D1, L)
  - Inside `graze_radius` with cover visible, a player gets +1 graze; on the 3rd graze they die.
  - Expose the graze count per player in the round snapshot. Bump the round format, and bump the protocol if the wire changes.
  - E1 then shows lost limbs in Unity (port the `PlayerBodyDamage` limb look).
- [ ] **N4 Items** (D6, L)
  - The server spawns items every 12–20 s: silver coin 25 % (+10), gold coin 15 % (+50), and
    invincibility, speed ×1.5 and slow ×0.5 for the rest, each lasting 10 s.
  - Pickup is a capsule overlap. Effects are server-side. Coins add to the round award.
  - Items reach clients as actors, so E1 can draw them with Darryn's item prefabs and `PlayerItemGlow` look.
- [ ] **N5 Survival mode + bots** (D8, L)
  - Add a Survival mode: 1–4 players, the round ends when all are dead, award as usual.
  - Promote `src/bots.odin` (now test-only) to optional server-side players with a `--bots N` server flag.
- [ ] **N6 Couch-play spike** (D4, T1 Opus or Codex, M; report only)
  - Can one process run 2–4 `bom_client_create` handles against one local server, each with its own input?
    Check for global state in `src/ffi` and `src/shared/net_client.odin`.
  - Build a 2-handle console test using the existing .NET caller in `test-client-core`.
  - Write `integration/review/couch-play-spike.md`: works / doesn't, the blockers, and a plan. Don't build the Unity side yet.

## Phase E: bring native changes into Unity (Lane U)
- [ ] **E1 Native checkpoint + gates after each N task** (T1, Opus, M). Copy this line for each N task (E1-N1, E1-N2, ...).
- [!] **E1-N1** claimed: Claude Opus 5.5 2026-11-11 — **blocked on N1b** (2f554c6). Native checkpoint 35482a8, exporter v3, yard/draw
  re-export, Build, Content (1562) and Rounds Yard+Draw all pass. The Prediction suite fails: the adverse profile (seed 42, 200 ms, 5% loss,
  144 fps) has `conservative_seconds` 1.35 (limit < 1), with 5 transitions, 4 resets and 6 snaps (`evidence/M9/profile-20261111T140152557313Z`).
  Before N1 the same profile had 0/0/0/0 (`profile-20261110T203824*`). The typical profile still passes but regressed (0.22 s, 2 transitions; was 0).
  Seeds 137/2026 did not run (the suite stops at the first failure). After N1b: rebuild the native checkpoint, re-run the full
  Prediction suite and Rounds, then tick this line. (The Unity side doesn't change again unless N1b changes the config.)
  1. Lane N must be idle. `C:\Users\jblic\Documents\BOM` must have `alpha-sync` checked out with a clean
     `git status`. The build reads that working tree (`OwnerOdinSourceRoot` in `local.config.json`).
  2. Run A1 steps 1–3. Re-export every level (yard + C6 levels) so the gameplay config hash matches.
  3. Make the Unity presentation change the N task names.
  4. Run Build, Content, Rounds, and
     `Invoke-BomIntegration.ps1 -Task Test -Suite Prediction -ConfigPath integration/local.config.owner-validation.json`.
  - Done when: all of these pass. After N4, also run the 30-minute soak: `Test-UnitySoak.ps1 -Backend Mono -ConfigPath ...`.

## Phase F: polish and release
- [ ] **F1 Shadows** (D10; T3, Haiku, S). In the Unity Editor: PC_RPAsset → Lighting → Additional Lights →
  Shadow Atlas Resolution = 4096. Re-baseline that one file.
  - Done when: the log line `Reduced additional punctual light shadows resolution` is gone from a player log. [ ] Owner check.
- [ ] **F2 Why it's choppy** (T1, Opus, M). Run the packaged Mono build with 1 window, then with 2. Record frame times
  (`-logFile` plus Unity's frame-timing log) and the server overruns in `server-errors.log`. Report in
  `integration/review/performance-2026-11.md`, with the top 3 causes and fixes ranked by gain per effort. Change no code.
- [ ] **F3 Fix stale docs** (T3, Haiku, S)
  - Package `DEVELOPER-README.md` (from `integration/README.md`): make it say protocol 7 and that
    PowerShell 5.1 or 7 works, and remove references to files that aren't in the package.
  - `Package-BomWindows.ps1` must not copy a `Logs` folder.
  - Done when: `git grep -n "protocol 6" -- integration/README.md` returns only lines marked as history.
- [ ] **F4 Repackage** (T2, Sonnet, S; after C7 and the last E1). Build Both, then
  `Package-BomWindows.ps1 -OutputDirectory C:\Users\jblic\Documents\BOM-Release\BOM-Windows-<date>` (a new folder, never overwrite).
  Launch it with `Launch-Bom.ps1 -Clients 2` and play one round.
  - Done when: the package launches under Windows PowerShell 5.1 and the player logs have no exceptions.
- [ ] **F5 PR prep** (D11; T1, Opus, M; the owner does the push). Move `integration/evidence/**` to a release
  archive outside the repo and keep a `integration/evidence/INDEX.md` with hashes. Squash the branch onto
  `origin/AlphaV0.1` (or `main`, whichever the owner names) and hand the owner the force-push command.

## Findings (append here; newest last)
- 2026-11-10 Claude: both playtests had 0 hash mismatches, but the server overran its tick 9 and 4 times. Darryn's
  `PlayerItemGlow` adds point lights, which will press on the shadow atlas (see D10).
- 2026-11-11 Claude (A2): the committed yard and draw `VisualRegistry.asset` files were stale (pre gameplay config 2). The working
  ones existed only in the deleted validation copy, so every fresh checkout failed with "manifest mismatch". They are re-exported
  and committed now. See the "Level trap" in rule 7.
- 2026-11-11 Claude (A2): the NativeInterop suite overwrites the stage DLL and its manifest. See the "Native DLL trap" in rule 7.
  The A1 stage is `integration/build/owner-native/20261111T042359-125d1539`; its overwritten copies are kept as `*.interop-rebuild-90b247bc.*`.
- 2026-11-11 Claude (A2): the Rounds gate fails from memory starvation when free RAM is ~2.4 GB at start (server stalled 120 s, clients
  timed out). The same build passed with 5.5 GB free. A WSL/Docker VM (`vmmem`, ~1.6 GB) was running. Start Unity gates with ≥ 4 GB free.
- 2026-11-11 Claude (A2): Darryn's auto-start scripts in our scenes. `GameAudio` loads but plays nothing (its music switch only
  knows his scene names), so C3 must start music itself. `MatchMenuUI` only acts in `MainMenuScene`/`LevelSetupScene`; elsewhere it only
  fades. `MenuCursor` adds a gamepad cursor canvas in every scene (not seen in our logs; check visually in C5). None of them logged errors.
- 2026-11-11 Claude (C1): the Yard Rounds gate failed 3 times in a row at ~07:47–08:01 with "native movement/jump did not drive the
  original Claymate animation" (guest exit 4, host 0xE0434352 timeout), then passed 3 times from ~08:07. Same code, same hashes. A/B
  evidence kept: with C1 (`unity-rounds-…T124723`, `…T125344`), without C1 at HEAD (`…T130041`, identical failure), A2-era
  `Assets/BOMIntegration` (`…T130719` pass), C1 again (`…T131117` pass). So neither C1 nor the A3 reformat caused it. The owner pulled a
  power cable in that window and free RAM sat at 3.3–4.1 GB (below rule 3's 4 GB), so the cause is most likely machine load/throttling
  (not proven). Only the guest fails: it dies early in both rounds, so a small slowdown means it never sees its native jump.
  If this check flakes again, re-run once and keep both evidence folders; do not edit the check.
- 2026-11-11 Claude (C1): `BomCameraRig` needs `sceneHalfDepth` (default 1) to keep a tilted view from clipping the scene's depth. If the
  owner check shows the top or bottom cut off, raise it. Both players are still the same blue until C2 adds slot colours.
- 2026-11-11 Claude (E1-N1): N1 changes every level's manifest (Odin now hashes `gravity_scale`). The yard and draw levels are
  re-exported. The performance levels (`bom-performancereference-v1`, `bom-performancestress-v1`), `bom-source-fixtures-v1` and
  `editor-export-v4-fixture` still hold pre-N1 registries. They only matter for the Performance/Soak/editor-fixture suites;
  re-export them (`BomPerformanceBuilder.BuildMono` with `BOM_PERFORMANCE_LAYOUT_DIR`, and the fixture builders) before running those.
- 2026-11-11 Claude (E1-N1): Rounds Yard passes 4 of 5 after the choreography change. One failure ended round 1 by elimination
  ~1.8 s into play, before any bomb could land (the world revision never changed), so a player probably left the level bounds.
  The cause wasn't captured; `BOM ROUND PLAYER ... death=` (2 = bounds) now logs it. If it recurs with death=2, check the spawn
  platforms at x = ±8.5..14.5 with the faster N1 movement.
- 2026-11-11 Claude (E1-N1): C1 left five folders of untracked screenshots (`integration/evidence/M8/unity-rounds-20261111T12*`/`T130*`).
  They're kept on disk. To keep the repo small before F5, E1-N1 committed only text evidence (logs/json); its PNGs stay on disk too.
