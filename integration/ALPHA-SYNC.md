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
- [x] **D7 Network cosmetics.** (approved by owner 2026-11-11) For now every player gets a slot colour (P1 blue, P2 red, P3 yellow,
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
- [ ] **D12 Graze next to cover.** (from the midpoint review, finding 8) Today a player whose capsule surface is inside the 1.2 lethal
  radius, but whose exposed part is only in the graze zone, takes nothing (the graze gate is skipped, and the lethal query sees nothing exposed).
  Recommended: an exposed part inside the 1.2 to 2.2 band counts as a graze even when the nearest point is inside 1.2. This is a small Lane N rule change plus a test;
  bundle it with N4 so one E1 covers it. Review: `integration/review/alpha-sync-review-20261111.md`.

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
   Lane U: C1 → C2 → C3 → C2c → (E1-N3 owner check) → A4 → C4 → (D9) C5 → C6 → C7 → F1 → F3. (C2c and A4 come from the 2026-11-11 midpoint review.)
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
- [x] **C2 Player look** (T2, Sonnet, M) claimed: Claude Sonnet 5.5 2026-11-11; done: Claude Sonnet 5.5 2026-11-11 416352c — Build and Rounds Yard+Draw pass, logs clean; owner check still open
  - Slot colours (D7): use Darryn's first 4 colours from `MatchMenuUI.characterColors`; copy the values.
  - Floating `P1`–`P4` labels, the way `ArenaPlayerController.CreatePlayerLabel` does it.
  - Facing flip and the Animator `Running` bool from native velocity. First check whether `BomActorView` already does this.
  - Death burst: clay chunks on a native death event, like `PlayerBodyDamage.Burst`. Presentation only;
    give the chunks no colliders and no Rigidbody (animate them in code).
  - Done when: Build and Rounds pass. [x] Owner check (ticked for the owner at their request, 2026-11-11; burst not seen, colours/labels/round confirmed).
- [x] **C2b Yard stands at rest** (T2, Sonnet, S) claimed: Claude Sonnet 5.5 2026-11-11; done: Claude Sonnet 5.5 2026-11-11 8cd400d — cause: ground overlapped the side walls (allowed_overlaps), not a regression; ground trimmed to x ±18 (builder migration 3→4), yard re-exported; two-window run: revision constant and 0 pieces moved for ~48 s; Build, Content (1562), Rounds Yard+Draw pass; owner check still open
  - The owner saw the starting stack of slabs collapse almost at once. Find why (compare the pre-merge yard layout with the current one,
    N1 gravity scale, E1-N1 re-export), make the smallest change that lets it stand until something blasts it, and re-export the level (Level trap, rule 7).
  - Native source in `C:\Users\jblic\Documents\BOM` is Lane N: don't edit it. If the fix needs a native change, stop and report.
  - Done when: after 30 s in a two-window local run (`C:\Users\jblic\Documents\BOM-Release\launch-c2-check.ps1`) the structure is still standing,
    and Build and Rounds pass. [x] Owner check (ticked for the owner at their request, 2026-11-11).
- [x] **C2c Death and graze presentation fix pack** (T2, Sonnet, M; from the midpoint review, findings 1-4; do before the E1-N3 owner check) claimed: Claude Sonnet 5.5 2026-11-11; done: Claude Sonnet 5.5 2026-11-11 19265ce — Build, Content (1562) and Rounds Yard+Draw pass; Draw primary and guest logs each have 4 `BOM UNITY BURST` (both players, both rounds); Yard has 0 (both rounds end by guest forfeit, death=3, logged as `BOM UNITY NOBURST ... reason=disconnect`); owner check still open
  - Why: Unity infers a death from a player pose vanishing while the round is Playing. The death that ends a round flips the round to Finished and removes
    the body on the same server tick, so the burst never plays in a 2-player round; a quit looks like a death; and effects are children of the per-revision
    `terrain` object, which `ClearScene(true)` destroys on every new topology revision. Read `integration/review/alpha-sync-review-20261111.md`, findings 1-4.
  - Effects root: create one persistent `Native effects` object that `ClearScene(false)` clears and `ClearScene(true)` keeps. Parent the death burst,
    the blast effects (`BomClientBehaviour` `Instantiate(BlastPrefab, terrain.transform)` and `SetParent(terrain.transform`) and the graze chunks (`PresentLimbLoss`) to it.
  - Burst from the roster: replace the "pose gone while `Round.state == 2`" trigger with the copied `RoundPlayers`: a player whose `alive` goes 1 to 0 within the same
    `round_id` and session/generation, with `death` Blast(1) or Bounds(2); never Disconnect(3) (`Round_Death :: None, Blast, Bounds, Disconnect`). Remember each player's last
    `VisualPosition` every frame so the burst has a position after the pose is gone; one burst per (round, session, generation, player). Log `BOM UNITY BURST player= round= death=`.
  - Limb timing: do not remove a limb the moment the snapshot count rises. Queue each increase and present it when an explosion event with `tick >=` the round snapshot's tick is
    shown (use that event's centre for the nearest limb), with a short unscaled-time timeout fallback. Keep `BOM UNITY GRAZE` logging.
  - New code goes in a new file under `Runtime/` with a fresh-GUID `.meta`; edit `BomClientBehaviour.cs` minimally. No colliders, no Rigidbody, no Unity-side outcome decisions.
  - Done when: Build, Content (1562) and Rounds Yard+Draw pass, and the Rounds primary and guest logs contain a `BOM UNITY BURST` line for the round-ending death of each run and none for a quit.
    [ ] Owner check: the last death of a two-player round bursts; quitting a window does not; a limb drops as its blast is drawn.
- [x] **C2d Pointer stays visible in the network scenes** (T2, Sonnet, S; owner report 2026-11-11) claimed: Claude Sonnet 5.5 2026-11-11; done: Claude Sonnet 5.5 2026-11-11 4202ffc — Build, Content (1562) and Rounds Yard+Draw pass, 0 Exception lines; revised in 2d50ebd (the first guard flipped the pointer every frame, so it flickered); pointer not yet seen on screen
  - Darryn's `Assets/Game/UI/MenuCursor.cs` sets `Cursor.visible = false` every frame and draws its own ring only when an `ArenaSession` menu is open; the network scenes have no `ArenaSession`,
    so the pointer vanished (the connection menu and the host's click-to-blast were hard to use). Do not edit his script: new `Runtime/BomCursorGuard.cs` shows the OS pointer in `LateUpdate`, added by `BomNetworkHud`.
  - Done when: Build and Rounds pass. [ ] Owner check: the pointer is visible in NetworkMenu and NetworkYard, over the Esc menu, and the host can click to blast.
- [x] **C2e Owner-test fixes: blast, game-over buttons, process cleanup** (T2, Sonnet, S; owner report 2026-11-11) claimed: Claude Sonnet 5.5 2026-11-11; done: Claude Sonnet 5.5 2026-11-11 2b68059 — Build, Content (1562) and Rounds Yard+Draw pass, 0 Exception lines; scripted run: blasts accepted, same events on both windows; launcher kill test leaves no process
  - Blast: the host click was stamped `c.time + inputOffset`, ~0.75 s behind the native clock, over the native 0.5 s limit, so every request was `Expired`. It now uses `BomSession.Now`.
  - `BomNetworkHud` wires Darryn's `replay-button` (host restart command; `WAITING FOR HOST` without permission) and `return-button` (disconnect, show the menu). This is the button part of C4; the wallet part still needs D5.
  - `Documents/BOM-Release/launch-e1n3-graze-check.ps1` puts the server and both windows in a kill-on-close job object and kills a player 8 s after its window closes.
  - Follow-up e272202: the host's REPLAY read `WAITING FOR HOST` because the server rebuilds the world after the click and the host loses restart permission for a few seconds (round flags bit 2 is set at Finished and the click worked). It now reads `STARTING…` for the host, `WAITING FOR HOST` only for non-hosts. The connection menu used to cover the RETURN button, so it now hides when an Elimination round enters Countdown or Finished (Esc reopens it).
    Verified by scripted two-window run: round 1 ended naturally, REPLAY, round 2 reached Playing on both windows in ~22 s, RETURN left the server. `BOM UNITY HUD round= state= mode= flags= host= requested= can_restart=` is logged on every change.
  - Done when: Build and Rounds pass. [ ] Owner check: the host's click blasts in Sandbox; REPLAY starts the next round for the host and RETURN leaves; after closing both windows nothing is left in Task Manager.
- [x] **C2f Guest crash on window focus change** (T1, Opus, S; owner report 2026-11-11) claimed: Claude Opus 5.5 2026-11-11; done: Claude Opus 5.5 2026-11-11 3900518 — Build (0 error CS), Content and Rounds Yard+Draw pass, 0 Exception lines
  - Cause (from the crash log's native stack): the Input System soft-resets keyboard and mouse inside `Application.focusChanged`, which Windows runs from its message pump; that reset crashed (`ResetDevice` -> `NativeArray` Temp -> `MemClear`).
  - `Runtime/BomFocusGuard.cs` (added by `BomNetworkHud`): `backgroundBehavior = IgnoreFocus` while a network HUD lives, so that path returns early; the keyboard and mouse are re-enabled or reset from `Update` after every focus change. Unity's default comes back in `OnDisable`. `--bom-focus-default` turns it off.
  - First version broke movement in the window that started in the background (its keyboard stayed disabled); caught by an A/B key test and fixed before the commit. Scripts: `Documents/BOM-Release/diag/focus-keys.ps1`, `focus-keys2.ps1` (`-Extra --bom-focus-default` for the A/B), `focus-flip-rebuild.ps1`.
  - Not proven: the crash never reproduced by script (before or after), so only owner play can show it is gone. Log line `BOM UNITY FOCUS ...` on every focus change.
  - Done when: Build, Content and Rounds pass, and keys still move only the focused window. [ ] Owner check: play a two-window round clicking back and forth between the windows a lot; no window crashes or stops responding; each window's keys move only its own player; nothing keeps walking after you switch windows.
- [x] **C3 Audio** (T3 can do this; Haiku, S) claimed: Claude Haiku 5.5 2026-11-11; done: Claude Haiku 5.5 2026-11-11 6beaeac — Build and Rounds Yard+Draw pass; no "Game audio prefab" error; whistle once per round state (4 per client per run); NetworkMenu/NetworkYard: no music (GameAudio's scene list has neither); owner check still open
  - Call Darryn's public statics in `Assets/Game/Scripts/GameAudio.cs` without editing that file:
    `PlayBombExplosion(pos)` on each native explosion, `PlayWhistle()` when a round goes Playing and again when it goes Finished,
    and `PlayButtonPopSound()` on our UI Toolkit buttons in `BomNetworkHud`.
  - Read how `GameAudio` picks music by scene name, and write what happens in `NetworkMenu`/`NetworkYard` into your tick line.
  - Done when: Build and Rounds pass, and the player log has no `Game audio prefab could not be loaded`. [ ] Owner check.
- [ ] **A4 Tool and doc fixes from the midpoint review** (T2, Sonnet, S; Lane U; after C2c)
  - Level trap: make `Test-NetworkRounds.ps1`/`BomNetworkMenuBuilder.BuildWithDrawFixture` also re-export the yard (`BomYardBuilder.CreateAndExport`), and refresh
    `integration/fixtures/round-draw/draw.json` (it still says gameplay config 3) from the gate output (review finding 6).
  - DLL trap: make `Test-RealNativeInterop.ps1` back up and restore the stage `bomcore.dll`, `bomcore.build.json` and the `build/interop/` copy itself, so rule 7's manual restore is no longer needed.
  - Stale versions: `integration/README.md:57-58` (ABI 1.4, protocol 7, round format 2, config 2) must say ABI 1.5, protocol 8, round format 3, config 5. Refresh or delete the
    `integration/contracts/BomNative.cs`, `bom-abi.json`, `bom_client.h` ABI 1.4 copies (prefer: have `Build-OwnerNative.py` refresh them from `Documents\BOM\bindings`) and fix
    `contracts/README.md` ("pending M1") and `round-rules.md:23-26` ("E1-N3 must update").
  - Exporter: `BomLevelAuthoring.GrazesToDie` gets `[Range(1,255)]` and `BomLevelExporter` rejects values outside 1..255 with a clear message (finding 13).
  - HUD guard: re-run `BomNetworkHud.DisableDuplicateArenaHud` on `SceneManager.sceneLoaded` (finding 16).
  - Prediction record: make the Prediction suite write per-profile resets, transitions and input generations into its `evidence/M0` record (it records `"checks": []` today).
  - Done when: Build, Content and Rounds pass without any manual yard re-export, and `git grep -n "protocol 7" -- integration/README.md` is empty.
- [ ] **C4 HUD, pause and results** (T2, Sonnet, M; needs D5)
  - `BomNetworkHud` still queries `level-fill`, `result-xp`, `current-level` and `next-level`, which Darryn's
    new `ArenaHud.uxml` removed. Map the HUD to his elements instead:
    - `result-coins` = Odin `xp_gained`, plus `result-bombs`, `result-time` and `result-total-coins` (the wallet total);
    - `pause-panel` = our Esc menu (the game does **not** pause in network play);
    - `replay-button` = host restart command (shown to the host only);
    - `return-button` = disconnect.
  - Wallet: call `MatchMenuUI.AddShopCoins(xp_gained)` exactly once per finished round. Key it on the round id;
    reconnects must not pay twice. Log `BOM WALLET round=<id> +<n>` at the moment you pay.
  - Review notes (2026-11-11): `AddShopCoins` takes an `int` but `xp_gained` is `ulong`, so clamp to `int.MaxValue`. Bind it by reflection like C3 did and add `MatchMenuUI`
    to `Assets/BOMIntegration/Runtime/link.xml`; also add `GameAudio` there now (`<type fullname="GameAudio" preserve="all"/>`) or IL2CPP stripping will silence C3's audio.
    Also tell the owner: `MatchMenuUI.RestartCurrentScene` resets the wallet to 250, which would wipe coins earned here.
  - Done when: Build and Rounds pass, and each finished round logs exactly one `BOM WALLET` line. [ ] Owner check.
- [ ] **C5 One front door** (T1, Opus, L; needs D3 and D9)
  - Darryn's `MainMenuScene` becomes the first scene. "Play" keeps his local mode (D4). "Online" opens Odin play:
    - **Host:** pick a level and start `BOM-server.exe` from the player's folder with `--bind`, `--port`,
      `--layout` and a random `--host-token` (copy the logic in `BOM-Windows/Launch-Bom.ps1`). Then connect.
      Kill the server when the host quits.
    - **Join:** enter an IP and port.
  - Reuse the existing `NetworkMenu` code. Edit only the files D9 lists, then re-baseline exactly those files.
    Copy the hash-update approach in commit `865a1a5`'s message, and list every re-baselined file in your commit.
  - Review notes (2026-11-11): pass the host token to the server in memory through `ConnectTo(..., token)`; do not rely on the `BOM_TEST_HOST_TOKEN` environment variable
    (children inherit it and its name invites removal). Plan for firewall prompts, port conflicts, and killing the server on crash or quit. The Rounds gate drives the network scene
    directly, not the main menu, so write the check below as an automated run, not only a manual one.
  - Done when: Build, Content and Rounds pass, an automated run goes from `MainMenuScene` to a finished round, and a two-window run (host and join on 127.0.0.1) goes from
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
- [x] **N1b Prediction regression after N1** (Opus, M) done: Claude Opus 5.5 2026-11-11, Odin `ef08405`; evidence: Documents/BOM/evidence/N1b/REPORT.md
  - Real cause: not the collision window (that hypothesis was wrong; no `Outside_Collision_Window` transitions were seen). A test-only
    `PROFILE TRANSITION` log showed every transition was `Unsafe_Position`: the profile's scripted input walked the faster N1 player
    off the legacy floor, so the server respawned it and prediction reset/snapped. The engine was correct.
  - Fix (harness only, `tests/interop/PredictionProfile.cs`): symmetric left/right walk that stays on the floor, jumps spaced out;
    pass/fail thresholds unchanged. The transition diagnostic stays in for future triage. No native engine code changed (DLL unchanged).
  - Full Prediction suite: all 6 profiles pass (seeds 42/137/2026 × typical/adverse), conservative_seconds 0, transitions 0, resets 0,
    snaps 0, correction p99 ≤ 0.002 — identical to pre-N1.
- [x] **N2 Lethal radius** (D1, M) done: GPT-6 Codex 2026-11-11 b8b1074 — game 220, transport 27, shared 101, FFI 20, Content 1562 PASS; lethal 1.2 / graze config 2.2 / crater 5; config v4 migration; evidence: Documents/BOM/evidence/N2/REPORT.md; E1-N2 pending. Scope: add config `lethal_radius` (1.2) and `graze_radius` (2.2), separate from
  `bomb_radius`. Kill only inside `lethal_radius`, still using `blast_capsule_visible` cover.
- [x] **N3 Grazes** (D1, L); claimed: Codex GPT-6 2026-11-11; done: Codex GPT-6 2026-11-11 9eb164e — exposed grazes, third-hit death, round reset and native limb state; game 220 / shared 112 / FFI 21 / transport 27 / C+.NET ABI pass / Content 1562; evidence: Documents/BOM/evidence/N3/REPORT.md; E1-N3 pending
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
- [x] **E1-N1** done: Claude Opus 5.5 2026-11-11. Native checkpoint 35482a8 (+ N1b harness ef08405, same DLL f591e8a1…), exporter v3,
  yard/draw re-export, Build, Content (1562), Rounds Yard+Draw and the full Prediction suite (6/6, `evidence/M0/Test-Prediction-20261111T143426524Z.json`)
  all pass. Rounds was not re-run after N1b: neither the DLL nor any Unity file changed. Pre-fix failure kept at `evidence/M9/profile-20261111T140152557313Z`.
- [x] **E1-N2** claimed: Claude Opus 5.5 2026-11-11; done: Claude Opus 5.5 2026-11-11 2090459 — native b8b1074 (DLL ffe2d206…), exporter/tuning config v4
  (lethal 1.2, graze 2.2), yard + draw re-exported; Build, Content (1562), Rounds Yard+Draw and Prediction 6/6 (`evidence/M0/Test-Prediction-20261111T172644051Z.json`)
  pass. First Rounds run failed on a stale yard manifest (kept: `evidence/M8/unity-rounds-20261111T171928558289Z`); see Findings.
- [x] **E1-N3** claimed: Claude Opus 5.5 2026-11-11; done: Claude Opus 5.5 2026-11-11 d090f83 — native 9eb164e (227baf9, DLL 0887c0b1…), config v5
  (grazes_to_die 3), yard + draw re-exported, limb loss from `graze_count` (`Runtime/BomLimbLoss.cs`); Build, Content (1562), Rounds Yard+Draw
  and Prediction 6/6 (`evidence/M0/Test-Prediction-20261111T194433351Z.json`) pass, 0 Exception lines. No graze occurred in the Rounds runs, so limb removal
  is unverified in a player (see Findings). Failed first export kept: `evidence/M8/e1-n3-yard-export-20261111T142922`.
  [ ] Owner check: a graze visibly removes a limb; two grazes remove two; the third kills; limbs are back next round.
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
  - Package `DEVELOPER-README.md` (from `integration/README.md`): make it say protocol 8 (ABI 1.5, round format 3, config 5; recheck against `Documents\BOM\AGENTS.md`) and that
    PowerShell 5.1 or 7 works, and remove references to files that aren't in the package.
  - `Package-BomWindows.ps1` must not copy a `Logs` folder.
  - Done when: `git grep -n -e "protocol 6" -e "protocol 7" -- integration/README.md` returns only lines marked as history.
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
- 2026-11-11 Claude (N1b): when a Prediction profile regresses, read the `PROFILE TRANSITION ... reason=` lines before touching
  `prediction_client.odin`. reason=8 (`Unsafe_Position`) means the scripted player left safe ground (harness choreography);
  reason=10 (`Outside_Collision_Window`) would point at the window margin. Any future speed/jump change (N4 speed x1.5 item!) must keep
  the profile's walk on the legacy floor.
- 2026-11-11 Claude (C2b): the yard stack collapsing was NOT a regression from the merge, N1 or E1-N1. The pre-merge native server (`BOM-Release\BOM-Windows`)
  with the pre-merge yard collapses identically (same revisions at the same ticks), and every yard source is byte-identical to the M7 export.
  Cause: the ground proxies (x -20..20 and -20.5..20.5) overlapped the side walls (x 18..18.6), which the layout allowed (`allowed_overlaps`). Odin ejects the
  overlapped dynamic ground cells on tick 4, the shock cracks the ground (revision +62 at tick 18) and the stack topples within about 1 s, with no player
  or bomb. Bisect on the real server: walls removed, or ground trimmed to x -18..18 with no overlap allowance, leave the revision unchanged for 35 s.
  Fix: `BomYardBuilder` migration 3 to 4 trims the ground to the walls' inner faces and drops the allowance. Players never reach beyond the walls.
  Rule for C6 (Darryn's levels): a dynamic or anchored part must never overlap a Fixed wall, even with an `allowed_overlaps` entry; trim the part to the wall face.
  Check for any level: a spectator client on the real server must see the world revision stay constant while nothing blasts it
  (harness source: `side-session-notes/.../settle-harness`). The yard must be re-exported again at E1-N2 (N2 changes the gameplay manifest); the migration is already in the scene.
- 2026-11-11 Claude (E1-N2): the Rounds gate does NOT re-export the yard. Its build calls `BomNetworkMenuBuilder.BuildWithDrawFixture`,
  which regenerates only the draw fixture, so after any gameplay-config change Rounds fails with "manifest mismatch" until
  `BomYardBuilder.CreateAndExport` is run by hand (rule 7, Level trap). Run it before Rounds in every E1. The performance, source-fixture and
  editor-export fixture registries are still pre-N1 (see E1-N1 finding); they now also lack config v4.
- 2026-11-11 Claude (E1-N2): in elimination rounds `BomClientBehaviour` sizes Darryn's blast ring by the round snapshot's `lethal_radius`,
  so after N2 the ring shows the 1.2 kill zone, not the 5-unit crater. No code changed (N2 named no presentation change). Owner: judge it at
  the next play; N3 may want a second ring for the 2.2 graze zone.
- 2026-11-11 Haiku (C3): `Bom.Unity.Runtime` (asmdef) cannot reference Assembly-CSharp, where Darryn's `GameAudio` compiles. C3 therefore calls
  the three statics through `Runtime/BomGameAudio.cs` (bound once by name; one warning if missing). C4's `MatchMenuUI.AddShopCoins` call hits
  the same wall: use the same bridge pattern, or keep that call outside the asmdef.
- 2026-11-11 Haiku (C3): IL2CPP risk for F4. Reflection can lose methods that managed stripping removes, and the bridge then logs
  `BOM AUDIO could not bind`. Before packaging IL2CPP, add a `link.xml` that preserves `GameAudio` (its three statics).
- 2026-11-11 Haiku (C3): music gap. A2 said C3 must start music itself, but C3's steps do not include it, so C3 does not. `GameAudio` only
  switches music for MainMenuScene, LevelSetupScene, Arena, YardLevel, BridgeLevel and TowerLevel. NetworkMenu and NetworkYard get no track
  from it. Owner: decide whether a menu or game track belongs there, and whether C5 covers it.
- 2026-11-11 Haiku (C3): the first Build run returned exit 1 with no script output, while its batch Unity (PID 26852) was still running. That
  Unity later logged `BOM PERFORMANCE BUILD PASS Mono`. Cause not found. The rerun returned `BUILD_EXIT=0`. The failed attempt's log is kept at
  `integration/evidence/M8/c3-build-failed-20261111T184229Z`. Separately, the Yard run logged no `BOM UNITY EVENT` lines (the draw run logged
  two per client), so the explosion sound is not yet confirmed in logs. Owner check: listen for it.
- 2026-11-11 Haiku (C3): `Get-Process Unity` also matches Unity Hub's helper `C:\Program Files\Unity Hub\resources\unity.exe` (about 1 MB,
  parent Unity Hub). I treated it as Unity Hub under rule 3. Editors run from `C:\Program Files\Unity\Hub\Editor\6000.2.14f1\Editor\Unity.exe`.
- 2026-11-11 Codex (N3): native `9eb164e` adds persistent `graze_count` per round participant; default third graze kills. Versions are
  protocol 8 / round format 3 / config 5 / ABI 1.5. `BomRoundPlayer.graze_count` replaces its reserved u32 at offset 28, retaining stride 64.
  E1-N3 must build the clean native checkpoint, refresh generated SDK/identity, export config 5 with `grazes_to_die=3`, re-export level
  manifests (including yard), and port `PlayerBodyDamage` presentation from copied counts within the round/session/generation.
  All N3 gates passed: game 220, shared 112, FFI 21, transport 27, real C/.NET layouts/lifetimes, Content 1562. Raw evidence and fixtures:
  `C:/Users/jblic/Documents/BOM/evidence/N3/REPORT.md`. No Unity build, Editor or soak was run; E1-N3 remains pending.
- 2026-11-11 Claude (E1-N3): player `pose.id` and `BomRoundPlayer.slot` are the same native server client index (native keys player poses
  `ent_key(.Player, i)` and reads grazes from `world.players[p.slot]`), so no offset. Rounds shows slots 1 and 2 because the observer
  connection holds slot 0 (guest logs `local=2` and `slot=2`). Note `BomPlayerLook` labels id 0 as P1, so Rounds players read P2/P3.
- 2026-11-11 Claude (E1-N3): no graze ring. `BomRoundInfo` (ABI 1.5) carries `lethal_radius` only; `graze_radius` is not exposed natively,
  so `BomClientBehaviour` cannot read it and I did not guess it from Unity tuning. A Lane N task would need to add `graze_radius` to
  `BomRoundInfo` (ABI 1.6) before a second, fainter ring can be drawn.
- 2026-11-11 Claude (E1-N3): neither Rounds run produced a graze (yard deaths reason 3, draw deaths reason 1), so `BomLimbLoss` ran only with
  count 0 in the gate. Each presented change logs `BOM UNITY GRAZE player= round= session= count= presented= limbs_lost=n/m`; look for it in
  the owner play. The Claymate rig gives limbs from `Bone.003.L/R` and `Bone.006.L/R` chains (mesh is Read/Write enabled). A live graze takes
  the limb nearest the last blast; a rebuilt or late-seen actor takes limbs in a fixed order and throws no chunks.
- 2026-11-11 Claude (E1-N3): my first by-hand export with `Start-Process -Wait` hung for 10+ min after Unity had exited (likely waiting on a child process; not proven);
  use `$p.WaitForExit()` on the returned process instead when running `CreateAndExport` by hand.
- 2026-11-11 Claude (midpoint review, report `integration/review/alpha-sync-review-20261111.md`, Opus 5.5, read-only, verdict: safe to continue the queue):
  native N1-N3 match `round-rules.md`; versions agree (protocol 8, round format 3, config 5, ABI 1.5); the authority boundary holds. Findings 1-4 (round-ending death never bursts,
  a quit draws a burst, effects die with the per-revision terrain object, limb drops before its blast) became **C2c** (verified in code for 1 and 3 on `BomClientBehaviour.cs:1027`, `:1036`, `:672-677`, `:894`);
  findings 6, 9, 13, 16 and the empty Prediction record became **A4**; finding 8 became **D12**; finding 5, 14 and 15 notes were added to C4 and C5; F3 now says protocol 8.
  Not turned into tasks (decide later): finding 7 (the seed 137 / 200 ms / 5 % Prediction profile had 2 unscripted input-schedule restarts; repeat it 3x before treating it as noise, command in the report),
  10 (slot labels follow the connection index, so a spectator holding slot 0 makes players read P2/P3), 11 (network play is keyboard-only and lacks W, Up and gamepad), 12 (HUD allocates garbage every frame, an input to F2).
  Report also lists alpha features with no task (gamepad in network play, music in NetworkMenu/Yard, chosen character over the wire, wallet reset by `RestartCurrentScene`, graze HUD) and
  says D9 and D3 block the most work, with `graze_radius` best folded into N4's ABI bump.
- 2026-11-11 Claude (C2d): the owner's first two-window run with the first cursor guard flickered, then both windows went `Not Responding` (Windows `Application Hang` events for `BombNetwork.exe`
  at 16:47:27 and 16:47:32; the shared `Player.log` shows nothing after startup). Not reproduced: two scripted two-window runs (hover, clicks, Esc, ~70 s each) stayed responsive, before and after the guard was revised.
  One player thread runs at about 92 % of a core (uncapped frame rate; the machine has 16 logical processors). The revised guard no longer toggles the pointer. If a freeze recurs, `launch-e1n3-graze-check.ps1` now writes
  per-window player logs and a responsiveness/CPU sampler to `Documents/BOM-Release/logs/` (spinning CPU means a busy loop, flat CPU a blocked thread). Also noted: scripted clicks on the host sent blast requests that all came back `status=3` (`Request_Status.Expired`) with no explosion event (cause not investigated; the owner's real clicks are the test).
- 2026-11-11 Claude (C2e): input event timestamps are ~0.75 s behind the native clock on the owner's machine (`BOM UNITY BLAST click_age_s=0.753..0.764`, constant across clicks, so it looks like an offset error in `inputOffset = start - InputState.currentTime` computed at `OnEnable`, not latency). Only blasts are age-bounded (native `Expired` at > 0.5 s), so only they broke; move and jump timestamps use the same offset and are only compared with `next_tick`. Cause not proven; if timing of held input or jumps ever matters, derive the offset again on first input.
  After the owner's long run both windows also took ~12 s to exit (flat CPU after Unity's last shutdown log line); a simple two-window run exits in ~1 s and the server stops itself. Not reproduced, so the launcher now kills a lingering player 8 s after its window closes. `BOM UNITY GRAZE ... presented=0` lines repeat on every terrain revision (log noise only).
- 2026-11-11 Claude (owner test after C2e): one player window stopped responding. It was a real crash, not a hang: the guest log shows `An abnormal situation has occurred: the PlayerLoop internal function has been called recursively` (twice) then `Crash!!!`, right after `BomSourcePresentation.Commit` (from `BomClientBehaviour.Update`), ~25 s after launch and as the host applied Elimination; Windows logged Application Error 1000 for `BombNetwork.exe` at 17:47:12. The process then sat in the crash handler (CPU frozen, `Responding=False`); the host stayed responsive.
  Evidence outside the repo (BOM-Release is not a repo): `Documents/BOM-Release/crash-20261111/` (`guest-crash.dmp`, guest and host logs, `watch.csv`). Not reproduced: scripted two-window runs (hover, clicks, Esc, Elimination switch x6, REPLAY, RETURN, window dragging x4) never crashed. The owner's first freeze (16:47, both windows, first cursor guard) may be the same bug. Handoff with hypotheses and next steps: `Documents/BOM-Release/HANDOFF-opus-main-chat.md`.
- 2026-11-11 Claude Opus (crash follow-up): the guest crash's native stack (end of `crash-20261111/20261111-174641-guest.log`) is inside the Input System, not our code: Windows message pump
  (`PeekMessageW` -> window proc) -> `Application.InvokeFocusChanged` -> `InputManager.OnFocusChanged` -> `EnableOrDisableDevice` -> `ResetDevice` -> `new NativeArray<byte>(.., Allocator.Temp)` -> `MemClear` -> access violation.
  So a window focus change (the owner clicking the other window) triggered it. The project has no Input System settings asset, so `backgroundBehavior` is the default `ResetAndDisableNonBackgroundDevices`, and with
  `runInBackground = true` every focus loss soft-resets the keyboard and mouse from inside that callback. Input System 1.16.0. Unity's own PR (InputSystem #2365) moves this focus handling out of `Application.focusChanged`.
  Not reproduced: 400 plain focus flips and 5 runs x ~70 flips during the Elimination rebuild (`BOM-Release/diag/focus-flip*.ps1`) all stayed up. Proposed fix: set `backgroundBehavior = IgnoreFocus` at runtime in the network
  scenes (the crashing path then returns early) and reset the keyboard ourselves from `Update` when focus comes back, so no key sticks.
- 2026-11-11 Claude Opus (owner play after C2f): the crash is NOT fixed. The host crashed at 18:39:59 with the same `PlayerLoop ... called recursively` (twice) + `Crash!!!`, preceded by four `Undefined ManagedTempMemScopePolicy.`
  lines (Temp-memory scope missing, which also fits the first crash dying in a Temp `NativeArray`). This stack has no Input System frames: Unity's window procedure -> `SendMessageW` -> uxtheme (window frame/activation drawing) -> nested window procedure -> deep `UnityPlayer` frames.
  Before it, from 18:39:24 the host ran no frames (watch.csv CPU flat at 27.1 s) while Windows still said Responding, the server dropped it ("The host left"), and ~35 s later it crashed. Last host lines: a click-blast, its request (status 1) and its event.
  So the real bug is Unity's main thread being re-entered from window messages; C2f closed one path into it (kept: A/B-tested harmless). Not reproduced: 40 s title-bar drag, 40 s minimize, maximize/restore, click switching (`diag/long-drag.ps1`, `diag/minmax.ps1`); in all of them the host kept running frames.
  Evidence: `Documents/BOM-Release/crash-20261111-2/` (logs, watch.csv, `Crash_2026-11-11_233959469.dmp`). Next: ask the owner exactly what they did to the host window around 18:39:24; name the UnityPlayer frames from both dumps with WinDbg + Unity's symbol server (needs the owner's OK to install WinDbg); consider a newer Unity 6000.2 patch.
