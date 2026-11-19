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
- [x] **D3 Online.** (approved by owner 2026-11-12) Keep Odin UDP with LAN or direct IP for now and drop Unity Relay/NGO. Design an
  internet relay later.
- [ ] **D4 Couch play.** Couch play moves to Odin later through task N6. Until then Darryn's local
  "Play" mode keeps its own Unity-physics rules (two rule sets, temporarily).
- [x] **D5 Currency.** (approved by owner 2026-11-12) Odin's round award goes into Darryn's local shop wallet as coins. The formulas are
  already identical: 10 per bomb faced + 1 per second. The shop stays cosmetic and local.
- [x] **D6 Items.** (approved by owner 2026-11-11) Coins, invincibility, speed and slow become native Odin items, using Darryn's
  durations and chances. Do this after N1–N2.
- [x] **D7 Network cosmetics.** (approved by owner 2026-11-11) For now every player gets a slot colour (P1 blue, P2 red, P3 yellow,
  P4 green). Sending each player's chosen character over the wire comes later.
- [ ] **D8 Solo.** Add a native Survival mode (1–4 players; the round ends when all are dead), with
  optional native bots.
- [x] **D9 Editing Darryn's files.** (approved by owner 2026-11-12) Integration tasks C5 and C7 may edit `Assets/Game/Scripts/MatchMenuUI.cs`,
  `Assets/Game/Online/*`, `Assets/Game/Scenes/MainMenuScene.unity` and `Packages/manifest.json`, then
  re-baseline those exact files. Without this, the menus cannot be joined up.
- [ ] **D10 Shadows.** Raise the additional-light shadow atlas in `Assets/Settings/PC_RPAsset.asset` from 2048
  to 4096. This should fix the colour shifting in shadows.
- [ ] **D11 PR prep.** Before the PR, rewrite this branch so the 273 MB of `integration/evidence` leaves
  history. This needs a force-push.
- [x] **D12 Graze next to cover.** (approved by owner 2026-11-11) (from the midpoint review, finding 8) Today a player whose capsule surface is inside the 1.2 lethal
  radius, but whose exposed part is only in the graze zone, takes nothing (the graze gate is skipped, and the lethal query sees nothing exposed).
  Recommended: an exposed part inside the 1.2 to 2.2 band counts as a graze even when the nearest point is inside 1.2. This is a small Lane N rule change plus a test;
  bundle it with N4 so one E1 covers it. Review: `integration/review/alpha-sync-review-20261111.md`.
- [x] **D13 Windows graphics API.** (approved by owner 2026-11-11) Players use Direct3D 11 on Windows: `ProjectSettings/ProjectSettings.asset` gets a `WindowsStandaloneSupport` entry
  (`m_APIs: 02000000`, `m_Automatic: 0`) and that one file is re-baselined. *Why:* on Direct3D 12 Unity 6000.2.14f1 handles window messages in the middle of a frame and crashed two owner runs (see Findings, 2026-11-11 crash root cause).
- [x] **OD-1 Boundary** (approved by owner 2026-11-17, design doc 3.5). B for the Bridge: no walls; leaving the arena is death by kill bounds, and debris past
  the cull bounds is deleted. C for the Yard and Tower: visible destructible bedrock walls (Stone base, toughness ≤ 1.4, high blast resistance),
  anchored at the bottom. No invisible or indestructible piece anywhere.
- [x] **OD-2 Material table** (approved by owner 2026-11-17, design doc 3.2 table, as proposed). Bridge decks Wood; Bridge truss, posts, girders and braces a
  new custom **steel** (Stone base, toughness 1.25, blast resistance 4, navy); Yard ground custom earth; Yard rocks Stone; Tower blocks and pillars Stone.
  Unblocks G-N1.
- [x] **OD-3 Bridge supports** (owner delegated to the orchestrator 2026-11-17; chosen: **(a) piles**, design doc 3.4). Anchor the five lowest post feet and draw
  piles going down into the water, so the support you see is the support you get. *Why:* already prototyped and measured in G1, and it keeps Darryn's
  deck extents (abutments would move the deck ends to new banks).
- [x] **OD-4 Band depth and backdrop** (approved by owner 2026-11-17 *for now*, design doc 4). Band 1.6, `d = clamp(√area, 0.1, band)`, terrain back wall.
  The owner may revisit the depth look later ("naive extrusion in general isn't optimal"), so G3 keeps the depth function in one place and
  the stock look behind a flag.
- [x] **OD-5 Classic Yard boundary** (raised by the orchestrator 2026-11-17; approved by owner 2026-11-18: **C, bedrock walls**). OD-1 names the Bridge (B), Yard and Tower (C), not Classic Yard, whose side walls
  are still hidden Fixed + Indestructible stone at x ±18 (yard rules, C2b). Recommended: **C (destructible bedrock)**, as on Darryn's Yard: its ground is a deep
  mass that meets both screen edges, and B would leave the ground ending in a cliff at ±18. G7 and G8 apply this only after it is ticked.
- [x] **OD-6 Settle rule I5, revised** (raised by the orchestrator 2026-11-18; approved by owner 2026-11-18). Old rule: world revision constant for 35 s from the first sample.
  It failed every layout on both natives, G1's own Bridge and the all-stone Tower included, because pieces seat in the first ~2 s (`evidence/G5/settle-pre-gn1`).
  **New I5:** spectator only, no players, no blasts. Ticks 0–120 (2 s) are a start-up window: cracks are allowed there. Then for 35 s: **no cell is lost**
  (cell count never drops below its value at tick 120) and **no piece moves more than 0.1 units** from its position at tick 120. Anything visible that falls,
  slides or breaks off still fails. The harness records revision changes after the window too (reported, not failing).
- [x] **OD-7 Exported geometry may be nudged for structure** (owner, 2026-11-18, in chat: "you can feel free to nudge bits around if they help the structure").
  The exporter or a level fixture may move, extend or trim pieces slightly (for example brace ends, deck bearing on piles) so structures carry load by geometry.
  Limits: Darryn's original Unity assets stay protected (Content gate); nudges are small, are listed per level with before and after values in the task's evidence, and keep the look.
  Not covered: new drawn pieces (gussets, caps), material or physics changes, which still need the owner.
- [x] **OD-8 Contact bearing + 60-tick start-up ramp, then nudge** (owner, 2026-11-18, after watching the G-N9 side-by-side viewer `Documents\BOM\evidence\G-N9\viz`).
  Glued pieces also collide with each other (mortar welds `collideConnected = true`), and structure gravity eases in over the first 60 ticks of each level start. Players are unchanged.
  Accepted costs (G-N9 report §4–5): slightly less Yard debris scatter, more contact pairs and CPU on the Bridges, and start-up cracking that is reduced but not gone.
  Then OD-7 nudges (G5) address the overloaded 0.047 brace corners. Order: G-N9b → E1-GN9 → G5 nudge + re-run.

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
   - **Native DLL trap**: the NativeInterop suite now backs up and restores the stage `bomcore.dll`, `bomcore.build.json` and `build/interop/bomcore.dll` itself (A4); no manual restore.
   - **Level trap**: the Rounds gate now re-exports the yard itself (A4, `BuildWithDrawFixture`). If the validation project's registries/scenes change, copy the changed ones back into the repo and commit them; the draw fixture `fixtures/round-draw/draw.json` is refreshed from `build/validation/round-draw/draw.json`.
   - **Sync**: `Build-BomPlayers.ps1` only copies `Assets/BOMIntegration` into an existing validation copy.
     If you changed files outside it, mirror them first. From the repo root, run
     `robocopy Assets <validation>\Assets /MIR /XD BOMIntegration Library`, then
     `robocopy Packages <validation>\Packages /MIR` and `robocopy ProjectSettings <validation>\ProjectSettings /MIR`.
     `<validation>` is `UnityValidationProject` in the config.
   - **Which gates to run** (owner decision 2026-11-17): match the gates to what changed.
     - The Prediction suite (about 1 hour) tests only the native DLL through the .NET harness. Run it **only when `bomcore.dll` changes** (E1 tasks, Phase E).
     - Unity-only tasks run Build, Content, Rounds and the front door. Add the perf matrix only if rendering or frame cost changed.
     - Record a skipped Prediction run as "not required: DLL unchanged since <task> 6/6", never as a pass.
     - Its fps-cadence check is sensitive to the machine's state: it failed after a laptop standby in G3. If only cadence fails while prediction stats are clean, check for standby or power changes before suspecting the code.
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
- [x] **A4 Tool and doc fixes from the midpoint review** (T2, Sonnet, S; Lane U; after C2c) claimed: Claude Sonnet 5.5 2026-11-11; done: Claude Sonnet 5.5 2026-11-11 355e3da — Content, Build x2, Rounds (stale yard registry replaced by the gate), NativeInterop (stage DLL restored), Prediction 6/6 with per-profile record; seed 137 adverse showed no restart this run (seed 2026 typical input_generation 2, resets 0)
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
- [x] **C4 HUD, pause and results** (T2, Sonnet, M; needs D5) claimed: Claude Sonnet 5.5 2026-11-12; done: Claude Sonnet 5.5 2026-11-12 dc860ff — Build (0 error CS), Content and Rounds Yard+Draw pass; each finished round logs exactly one `BOM WALLET` line per player (yard +12/+13, draw +23/+23, primary and guest alike), 0 Exception lines
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
  - Done when: Build and Rounds pass, and each finished round logs exactly one `BOM WALLET` line. [ ] Owner check: results show coins/bombs/time and the wallet total; the wallet goes up once per round; Esc opens the pause panel without pausing; REPLAY shows for the host only; RETURN disconnects.
- [x] **C5 One front door** (T1, Opus, L; needs D3 and D9) claimed: Claude Opus 5.5 2026-11-12; done: Claude Opus 5.5 2026-11-12 90b0673 — Build (0 error CS), Content (1562, MatchMenuUI.cs re-baselined), Rounds Yard+Draw and the new front-door gate (`Test-FrontDoor.ps1`, 16/16 checks, twice) pass; 0 Exception lines; no BOM-server left after any run
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
    the main menu to a finished round with no PowerShell launcher. [ ] Owner check: from the main menu, Online → Host starts a game another window can Join on 127.0.0.1 (and, if possible, from a second PC on the LAN); Play still runs Darryn's local mode; quitting the host leaves no BOM-server running.
  - Result: `MatchMenuUI.ShowOnlineMenu` (one marked line, D9) opens our `Runtime/BomOnlineMenu.cs` (Host: level, port, This PC only / LAN; Join: validated IPv4 + port). `BomFrontDoor` starts
    `Server/BOM-server.exe` next to the game exe (fallback `../Server`, as in BOM-Windows; README "Play from the main menu" documents layout, busy ports and the firewall prompt), waits for "listening",
    loads `NetworkMenu` and calls `ConnectTo(127.0.0.1, port, token)` with a fresh in-memory token. Server stop: kill-on-close job object (crash), `Application.quitting` (quit), main menu (RETURN/LEAVE GAME/Main menu; 6 s for the server's own host-left shutdown, then kill).
    The game player `Bomb.exe` is built by `Editor/BomFrontDoorBuilder.cs` into `build/validation/Game-Mono` (MainMenuScene, Darryn's 3 levels, NetworkMenu); EditorBuildSettings untouched. Evidence: `evidence/M8/frontdoor-20261112T143715768211Z` (1.5 s grace, server killed) and `…T144730281207Z` (final, server ended itself).
    Not covered by the gate: visible windows (players run `-batchmode`), the LAN bind/firewall dialog, a second PC, and a guest still connected when the host leaves (it gets the existing "The host left" error, which `BomClientBehaviour.Fail` logs as an exception).
- [x] **C6 Darryn's levels on Odin** (T1, Opus, L) claimed: Claude Opus 5.5 2026-11-12; done: Claude Opus 5.5 2026-11-12 159349e — Yard, Bridge and Tower export, validate (`Test-LevelManifest.py` x3) and finish a front-door round each (17/17 checks, 0 Exception, 0 visual fallback); Classic Yard front door, Rounds Yard+Draw, Build and Content pass
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
    `BOM VISUAL FALLBACK` warning seen in every playtest. [ ] Owner check: host each of Yard, Bridge and Tower from the main menu; each looks like Darryn's level, blasts carve it sensibly, and spawns/camera fit; Classic Yard still works.
  - Result: `Editor/BomTileLevelBuilder.cs` saves a *copy* of each of Darryn's scenes as `Assets/BOMIntegration/Network{YardTiles,Bridge,Tower}.unity` (his files are only opened), adds the native
    authoring and clones NetworkMenu's session/HUD/camera, and exports `integration/fixtures/levels/{Yard,Bridge,Tower}Level.json` plus a per-tile report `<json>.tiles.json`. It runs inside
    `BomFrontDoorBuilder` (`Test-FrontDoor.ps1`, new `-Level ClassicYard|Yard|Bridge|Tower`), which copies the layouts to `Server/levels/`. Picker order: CLASSIC YARD, YARD, BRIDGE, TOWER, on host *and* join
    (a guest must pick the host's level; the server refuses another level's manifest). Walls: `BomVisualEntry.Hidden` (no mesh, nothing drawn); the classic yard's walls migrate too (`YardBuilderVersion` 5).
    Mapping choices and numbers are in Findings (C6). Evidence (final player): `evidence/M8/frontdoor-yard-20261112T164606662867Z`, `frontdoor-bridge-…T164749357225Z`, `frontdoor-tower-…T164821923693Z`,
    `frontdoor-20261112T164930709737Z` (Classic), `unity-rounds-20261112T154122903920Z`/`…T154253245490Z`, `evidence/M6/manifest-reject-20261112T154539805017Z` (Yard), `…T154625093285Z` (Bridge), `…T164421116279Z` (Tower).
- [x] **C7 Remove NGO/Relay** (T2, Sonnet, S; needs C5 and D9) claimed: Claude Sonnet 5.5 2026-11-12; done: Claude Sonnet 5.5 2026-11-12 7a7f05d — Build 0 error CS, Content 1555, Rounds Yard+Draw and front-door gate pass; `git grep "Unity.Netcode|Services.Multiplayer" -- Assets` empty; also deleted orphan NGO-generated Assets/DefaultNetworkPrefabs.asset(+meta), outside D9 list, needed for the grep
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
- [x] **N4 Items** (D6, L) claimed: Claude Opus 5.5 2026-11-11; done: Claude Opus 5.5 2026-11-11 3aed89e — items (Darryn numbers), D12 band graze, graze_radius; protocol 9 / round 4 / ABI 1.6 / config 5; game 220, shared 124, FFI 22, transport 27, C+.NET ABI pass, Content 1562; contract ba83748; evidence: Documents/BOM/evidence/N4/REPORT.md; E1-N4 pending
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
- [x] **E1-N4** claimed: Claude Opus 5.5 2026-11-11; done: Claude Opus 5.5 2026-11-12 7aa3131 — native 3aed89e (DLL f87d0cd6…), protocol 9 / round 4 / ABI 1.6;
  items drawn with Darryn's models (`Resources/BomItem1..5`), `PlayerItemGlow` port, coin sound, faint graze ring, scripted runs muted; Build, Content (1562),
  Rounds Yard+Draw, Prediction 6/6 (`evidence/M0/Test-Prediction-20261112T032632412Z.json`) and the 30-minute soak (`evidence/M9/soak-20261112T043608868359Z`, 1800 s, 183 resets)
  pass, 0 Exception lines. Item drawn and landed in `evidence/M8/unity-rounds-20261112T032344202604Z` (evidence run, see Findings). Failed first Prediction and soak kept (see Findings).
  [ ] Owner check: items fall and land; touching one makes it vanish with a sound; coins raise the round award; the glow shows for invincible/speed/slow and ends after ~10 s; a faint outer ring shows the graze zone.
- [x] **E1-G** (native f3a4e48: G-N5 prediction hull cache + G-N2/G-N3 glue; guest perf harness fix; E1-G perf matrix) claimed: Claude Opus 5.5 2026-11-16; done: Claude Opus 5.5 2026-11-17 55fe0dac — native f3a4e48 (DLL f9651cd4…, `-o:speed -debug`);
  NativeInterop, Build, Content (1555), Rounds Yard+Draw, front door Yard/Bridge/Tower (17/17), Prediction 6/6 (`evidence/M0/Test-Prediction-20261117T040930729Z.json`) pass.
  Blast native_ms max (host 1w/2w) Classic 57/69→21/19, Yard 18/25→3/4, Bridge 50/54→3/6, Tower 27/36→11/11; guests now write `guest-perf.json` and exit 0
  (`evidence/E1-G/perf-20261117T051233`, doc section 9.1). First Prediction failed before any profile (fresh checkpoint had no `build/interop/bomcore.dll`; E1-N4 finding, record kept).
  [ ] Owner check: blasts on Bridge and Classic Yard feel smooth in play.
- [x] **E1-GN6** (native 3be3283: G-N1 glue capacity from materials + steel, G-N6 prediction flap fix with 100 ms correction fade; flip count and blast frames vs G2b) claimed: Claude Opus 5.5 2026-11-17 done: Claude Opus 5.5 2026-11-17 1e59381d — native 3be3283 (DLL 5b88bd1f…, `-o:speed -debug`);
  NativeInterop, NativeProof, Build, Content (1555), Rounds Yard+Draw, front door Yard/Bridge/Tower (17/17), Prediction 6/6 (`evidence/M0/Test-Prediction-20261117T124416709Z.json`) pass.
  Host Conservative entries per 100 s (G2b → now): Bridge 1w 148→4, Yard 2w 72→5, Tower 2w 46→19, Tower 1w 33→19, Yard 1w 10→5, Classic 8/9→5/5, Bridge 2w 6→4.
  Blast-window p95 and native max unchanged; one 2w first-blast frame higher on Yard (26→37/34 ms, native ≤1.7 ms, cause not found) (`evidence/E1-GN6/README.md`).
  [ ] Owner check: after a blast your own player no longer snaps (Bridge and Yard); Tower may still flip a little.
- [ ] **E1-GN9** (native G-N9b: contact bearing + 60-tick structure ramp, OD-8) (T1, Opus, M; Lane U; after G-N9b). Usual E1: checkpoint with `Build-OwnerNative.py`, update `bomcore.build.json`, `BomExpectedNativeIdentity.cs` and AGENTS.md versions line;
  NativeInterop, NativeProof, Build, Content, Rounds Yard+Draw, front door Yard/Bridge/Tower, **Prediction 6/6 (required: the DLL changes)**, and the E1-GN6 perf/flip comparison on the Bridge (contact pairs and never-sleeping Bridge may raise CPU and corrections).
  [ ] Owner check: levels stand at round start without visible cracking; blasts still look right; the Bridge does not visibly shimmer.
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
- [x] **F2 Why it's choppy** (T1, Opus, M). claimed: claude-opus-5-5 2026-11-12. Run the packaged Mono build with 1 window, then with 2. Record frame times
  (`-logFile` plus Unity's frame-timing log) and the server overruns in `server-errors.log`. Report in
  `integration/review/performance-2026-11.md`, with the top 3 causes and fixes ranked by gain per effort. Change no code.
  done: claude-opus-5-5 2026-11-12 79a76e2 — report `integration/review/performance-2026-11.md`, evidence `integration/evidence/F2` (7 clean runs, package 2026-11-12b Mono, 1280x720 windowed D3D11, on AC, 0 sleep events, 0 server overruns; settled p50 16.7/p99 <18 ms). Top 3: (1) Classic Yard rebuilds all source meshes on the main thread for 25-35 s after join and every round start (p95 23-34 ms, up to 145 hitches >33 ms/min, max 236 ms, 6-7 GB/min GC) - keep plans/cache across unchanged epochs + budget `PrepareCells`/`MakePlans` (`BomSourcePresentation.cs`, M/S); (2) Tower prediction flaps Predicting/Conservative 185-435 times per 100 s, zeroing the visual offset (own player snaps) - log the reason, add hysteresis/blend in `prediction_client.odin` (S+M, Lane N); (3) uncapped, no vSync in normal play (inferred) - set vSync/target fps at startup (`BomFrontDoor.cs`, S). HUD garbage (#12) is only 13 MB/min, no hitch. Needs a human long Elimination round with blasts on Classic Yard.
- [x] **F3 Fix stale docs** (T3, Haiku, S) claimed: claude-haiku-5-5 2026-11-12 (orchestrator a9fe185: restored the developer sections 305b1fb dropped; kept the version, PowerShell and Logs fixes)
  done: claude-haiku-5-5 2026-11-12 305b1fb — README says protocol 9 / round format 4 / config 5 / ABI 1.6; packager skips Logs. `git grep -n -e "protocol 6" -e "protocol 7" -e "protocol 8" -- integration/README.md` returned no lines; Content passed (1555 files).
  - Package `DEVELOPER-README.md` (from `integration/README.md`): make it say protocol 8 (ABI 1.5, round format 3, config 5; recheck against `Documents\BOM\AGENTS.md`) and that
    PowerShell 5.1 or 7 works, and remove references to files that aren't in the package.
  - `Package-BomWindows.ps1` must not copy a `Logs` folder.
  - Done when: `git grep -n -e "protocol 6" -e "protocol 7" -- integration/README.md` returns only lines marked as history.
- [x] **F4 Repackage** (T2, Sonnet, S; after C7 and the last E1). claimed: Claude Sonnet 5.5 2026-11-12 Build Both, then
  `Package-BomWindows.ps1 -OutputDirectory C:\Users\jblic\Documents\BOM-Release\BOM-Windows-<date>` (a new folder, never overwrite).
  Launch it with `Launch-Bom.ps1 -Clients 2` and play one round.
  - Done when: the package launches under Windows PowerShell 5.1 and the player logs have no exceptions.
  done: Claude Sonnet 5.5 2026-11-12 (commit below) — package `Documents\BOM-Release\BOM-Windows-2026-11-12b` (front-door `Bomb.exe`, Mono + IL2CPP, each with `Server/` + 4 level JSONs). `Launch-Bom.ps1 -Clients 2` runs under `powershell.exe` 5.1 for both backends (D3D11, 0 Exception). Scripted front-door round on the package: Mono `frontdoor-20261112T173748130972Z` and IL2CPP `frontdoor-20261112T173941004978Z`, 17/17 checks, 0 Exception, `BOM WALLET` paid, no `could not bind`/`prefab could not be loaded`, no BOM-server left. The first folder `BOM-Windows-2026-11-12` is superseded (its IL2CPP game could not start the server).
  - [ ] Owner check: unzip/copy nothing — run BOM-Windows-2026-11-12b, play Offline and Online (host + join) on Mono; quick look at IL2CPP. (Read `PACKAGE-NOTES.md` in it.)
- [ ] **F5 PR prep** (D11; T1, Opus, M; the owner does the push). Move `integration/evidence/**` to a release
  archive outside the repo and keep a `integration/evidence/INDEX.md` with hashes. Squash the branch onto
  `origin/AlphaV0.1` (or `main`, whichever the owner names) and hand the owner the force-push command.

## Phase G: Odin destruction in Darryn's 2.5D (owner priority, 2026-11-12)
Owner's principle (do not trade away): the destruction is the soul of the game. Every piece is a simulated, interactable body sent over the wire,
and **what's there is what you get**: what you see is exactly what you collide with, and it all fits together intuitively. Toughness comes from
the owner's tuned **materials** (Wood, Glass, Rubber, Stone and custom) and **connectors/glue**, never from an indestructible flag or decoration-only
status. C6's off-plane decoration (Bridge truss 88/110, Tower pillars 29, Yard 8), trimmed overlaps, indestructible walls, and the full-tile-depth
extrusion that turns debris into long sticks all violate it. F2 showed the explosion lag is Unity presentation (mesh rebuild + GC), not the native design.
- [x] **G1 Destruction design spike** (T1, Opus, L; report + opt-in prototype; the shipped game stays unchanged) claimed: Claude Opus 5.5 2026-11-12 done: Claude Opus 5.5 2026-11-16 da53d2c — design doc `integration/review/destruction-design-2026-11.md` (captures, design A/B/C, prototype + measured perf, Lane N G-N1..G-N5, task table G2…G10, owner decisions OD-1..OD-4); prototype `Runtime/BomG1Presenter.cs` behind `--bom-g1` (Classic Yard GC 2632 → 16 MB/min, p95 23.8 → 17.2 ms); flag off: Build, Content (1555), Rounds yard+draw and front door PASS (doc 6.4).
  - Owner try-out: `powershell -File integration/tools/g1/Start-BridgeG1.ps1 [-Clients 2]`, then ONLINE > HOST GAME > BRIDGE > START. Owner decisions for G2 onward are listed in doc section 8 (OD-1 boundary, OD-2 material table, OD-3 Bridge supports, OD-4 band/backdrop).
  1. Capture the same blasts in the raylib sandbox (`Documents\BOM`, `scripts\bom.ps1`), the pre-merge package `BOM-Release\BOM-Windows`, and the current
     package `BOM-Windows-2026-11-12b` (Classic Yard and Bridge/Tower). Write down what is lost: piece size/density, depth/stick look, tumble/settle,
     crater readability, standing on/pushing debris.
  2. Design: how Darryn's tiles become an Odin authored layout (tile → part with a real material; overlaps/contacts → glue connectors whose strength
     comes from materials; anchors only where something truly rests on ground/walls; off-plane truss/pillars brought onto the play plane, with front/back
     duplicates merged); how depth is drawn from the 2D sim (per-piece depth from its own shape/size; Darryn's extra depth as backdrop behind a play band);
     and a presentation architecture with no per-change mesh churn/GC (F2 cause 1). Name anything that needs Lane N.
  3. Prototype behind an opt-in flag or a separate level variant (e.g. `BridgeLevel-G1`): the Bridge rebuilt this way, plus the depth-from-shape drawing.
     Capture it next to the originals.
  - Done when: `integration/review/destruction-design-2026-11.md` has the captures, the design, the measured effect of the prototype and a task
    breakdown (models/lanes/sizes); Build, Content and Rounds still pass with the flag off. [ ] Owner check: the prototype feels like the original Odin game in Darryn's 2.5D.
- [x] **G2 Presentation core for every level** (T1, Opus, M; from design doc section 8) claimed: Claude Opus 5.5 2026-11-16 done: Claude Opus 5.5 2026-11-16 b3be0541 — `BomCellPresenter` is the only cell path (old path behind `--bom-clipped-source-art` for one release); GC 2682 → 14 MB/min on Classic Yard (68–235 → 14–19 elsewhere), Classic p95 24.1/41.4 → 17.4/17.5 ms (1w/2w), blast draw max 63–117 → 20–35 ms; Build, Content (1555), Rounds yard+draw, front door Yard/Bridge/Tower (17/17) and Prediction 6/6 pass (doc section 9). Look residual: Classic Yard grass/dirt edge follows cell outlines (zooms in `evidence/G2`).
  Make `BomG1Presenter`'s persistent, chunked, cached bodies the only cell path (no flag): remove the per-revision batch rebuild in `Accept`;
  keep bodies and caches across an epoch whose cells did not change (F2 fix 1a); assemble chunks with `Mesh.MeshData` / `NativeArray` for
  zero managed GC per blast; retire per-fragment prism clipping of Darryn's meshes in the play band. Keep the current look (depth/band is G3).
  - Done when: F2 protocol re-run on Classic Yard, Yard, Bridge and Tower with 1 and 2 windows (before/after GC MB/min, p95, blast draw cost);
    Content, Build, Rounds (yard + draw), front door `-Level` Yard/Bridge/Tower and Prediction (6/6) pass. [ ] Owner check: it looks the same and feels smoother.
- [x] **G2b First-blast hitch** (T1, Opus, S; after E1-G) claimed: Claude Opus 5.5 2026-11-17 done: Claude Opus 5.5 2026-11-17 346d7325 — causes proven with `--bom-hitch-trace`: (a) UI Toolkit first pointer dispatch 24.8 ms + Input System 3 ms, (b) first-use costs (explosion mp3 decode 4.6 ms, fragment chunk path 4.4 ms, blast view 1.2 ms); warmed at join. First-blast worst frame host 1w Yard 35.7→23.7, Bridge 37.1→23.7, Tower 38.8→22.9, Classic 49.0→42.1 (native-bound, as its later blasts); gates pass (doc 9.2, `evidence/G2b`).
  Only the first blast of a run hitches (E1-G perf: mouse-down frame 35-48 ms, first CELLS APPLY present 13-15 ms). Prove the causes, warm the
  blast input path and the first-change presenter path at join with no gameplay side effects, keep the look and zero per-blast presenter GC.
  - Done when: first-blast worst frame near blasts 2-8 (<= ~20-25 ms) on all 4 levels, 1 and 2 windows (`evidence/G2b`); Build, Content,
    Rounds yard+draw, front door Yard/Bridge/Tower (and Prediction 6/6 if input code changed) pass. [ ] Owner check: the first blast feels as smooth as the rest.
- [x] **G3 Depth from shape as the default look** (T1, Opus, M; needs G2, OD-4; design doc 4 and 8) claimed: Claude Opus 5.5 2026-11-17 done: Claude Opus 5.5 2026-11-17 c324aad0 — band look default (no flag), depth rule only in `Runtime/BomDepthLook.cs`, terrain back walls (Yard 91, Tower 41, Classic 2 sources), registry materials, exact grass/dirt edge; `--bom-stock-look` for one release;
  Build, Content (1555), NativeInterop, Rounds yard+draw, front door Yard/Bridge/Tower pass. Prediction: not required: DLL unchanged since E1-GN6 6/6 (owner decision 2026-11-17). Perf vs E1-GN6: p95/p99 within 0.1 ms, GC and >33 ms/min unchanged, first-blast present +1-3 ms; screenshots `evidence/G3/screenshots` (doc 9.3, `evidence/G3/README.md`).
  Band 1.6 and `d = clamp(√area, 0.1, band)` for every level with no flag, the depth rule in one swappable place; terrain back wall (darker, no top cap,
  never rebuilt); Darryn's material per source through the registry, not scene paths; stock look behind a flag for one release; per-material split if cheap.
  - Done when: Content, NativeInterop, Rounds yard+draw, Prediction 6/6 and front door Yard/Bridge/Tower pass; perf matrix shows no frame-time regression
    against E1-GN6; before/after screenshots on all four levels in `evidence/G3`. [ ] Owner check: debris reads as chunks, craters show dark earth behind, nothing looks walkable that is not.
- **G4 does not exist.** The design doc's task table (section 8) jumps from G3 to G5. This is a numbering gap, not a lost task: no G4 was ever defined in the doc or in chat.
- **Native G tasks done (Odin `alpha-sync`):**
  - G-N2/G-N3 and G-N5 merged in `f3a4e48`, brought in by E1-G.
  - G-N1 (glue capacity from materials, steel) merged in `498f6ab`.
  - G-N6 (prediction flap fix, not in the doc table; added 2026-11-17 for the owner's "the prediction isn't smooth") merged in `3be3283`.
  - G-N1 and G-N6 were brought in by E1-GN6.
  - The doc table's E1-G row still says it brings G-N1; that is stale, because E1-GN6 did it.
- [!] **G5 Tile exporter v2** (T1, Opus, L; Lane U; needs OD-1, OD-2, OD-3, all decided 2026-11-17). claimed: Claude Opus 5.5 2026-11-18 The design doc section 8 G5 row and section 3 define it:
  `Editor/BomTileLevelBuilder.cs` applies the section 3 mapping to any tile scene (merge duplicates, partition + glue, material table incl. steel,
  anchors at real supports only, Bridge piles per OD-3, invariants I1–I5 as export failures); reads mesh silhouettes; replaces the Python generator.
  - Scope (orchestrator, 2026-11-18): Darryn's three tile scenes (YardLevel, BridgeLevel, TowerLevel) only. Classic Yard is built by `BomYardBuilder`, not from tiles: that is G7.
    The side walls and bottom boundary stay as they are until G8 replaces them; material tuning with the owner is G6. Read design doc sections 3, 4 and 6.1 and `tools/g1/Build-BridgeG1.py` first.
  - Done when (each line is checked and its numbers go in the tick line or `evidence/G5/README.md`):
    1. One export path: `BomTileLevelBuilder` v2 writes `fixtures/levels/{Yard,Bridge,Tower}Level.json` plus `.tiles.json` from Darryn's scenes (opened, never saved).
       No build or launch path calls `Build-BridgeG1.py` any more (`Start-BridgeG1.ps1` still does today); the script stays on disk as G1 history.
    2. Invariants are export failures. I1: zero off-plane decoration entries; every in-arena tile is a part or a declared backdrop. I2: no `indestructible` source;
       `fixed` only on the existing boundary walls, listed by name in the report (G8 removes them). I3: anchor segments only on supported edges, never "every edge";
       the Bridge's anchors are exactly the five pile feet with piles drawn (OD-3). I4: every part has the OD-2 material (steel as specified); zero `allowed_overlaps`;
       `--validate-layout` reports no zero-sample glue link (G-N2).
    3. A negative test per invariant I1–I4: a small deliberately broken input fails the export with a message naming the tile and the invariant.
    4. Per level, record tiles, parts, backdrop tiles, merged duplicates, glue links and anchored parts; parts ≤ 1024 and glue links within the native budget (2048 after G-N3).
    5. `Test-LevelManifest.py` passes for all three layouts.
    6. I5 settle check as revised by OD-6 (2 s start-up window, then 35 s with no cell lost and no piece moving > 0.1) on all three: the Bridge must pass; a Yard or Tower failure is recorded as a G6 input, not hidden.
    7. Start and post-blast screenshots of each level in `evidence/G5`, next to the G1/G3 captures.
  - Gates: Build, Content, Rounds yard+draw, front door Yard/Bridge/Tower, 0 Exception lines. Prediction: not required, DLL unchanged since E1-GN6 6/6 (rule 7).
  - Machine: the owner may be on a Discord video call. Check rule 3 before every Unity run; if a Rounds timing check fails while the machine is busy, re-run it once and keep both evidence folders.
  - Blocked (2026-11-18, Claude Opus 5.5, after G-N7 and the brace-joinery check): **no exporter-side joinery fix exists; the Bridge needs an owner decision**
    (new drawn structure at the brace ends, or a G-N7 native or material option). Done-when 6 (I5, OD-6) fails for the Bridge on 3be3283 (`evidence/G5/settle-od6`).
    Yard and Tower pass. Lines 1-5 and 7 and all gates pass (`evidence/G5/README.md`).
    `evidence/G5/brace-joinery/README.md`: the braces are not corner-only. Each one already sits on the full faces its geometry allows:
    a post face w/cos θ = 0.232 (native seam 0.27–0.33) and, at a girder, w/sin θ = 0.687 (native 1.20–1.29).
    The 0.047 contact is an extra pin, because Darryn's brace ends at the post centreline and its lower edge meets the girder exactly at the post face.
    The face seams break too, measured with G-N4 at 0b1f765: 13 of 16 post faces (r up to 45.8) and 5 of 8 girder faces (r 15.8–31.7).
    Holding them would take seams 2.5–6.7× longer than any face in the art. Variants measured:
    - dropping the 8 corner links: fails, 23.957;
    - braces over posts: rejected by native (the centre braces overlap inside post 32), and it could add at most ~0.36 per edge.
    Outlines moved by at most 0.00005 swing the result from 22.3 to 0.389, the same knife edge G-N7 saw.
    Exporter and layouts are unchanged, so OD-6 and the gates were not re-run.
    Next (owner, 2026-11-18): G-N8 (start-up shock) runs first; G5 re-runs `Run-G5Settle.py` after its fix lands (G-N8b, E1-GN8).
    G-N8 found no start-up fix (standing load); the owner approved G-N9 (contact bearing) next. G5 re-runs after G-N9b and E1-GN9 if the owner picks a variant.
    OD-8 (2026-11-18): contact + ramp ships (G-N9b, E1-GN9). After E1-GN9, G5 resumes: OD-7 nudges for the 0.047 brace corners (and anything else the G-N4 report names), each nudge listed with before/after
    and its seam r, then the OD-6 settle on all three tiles and the G5 gates; tick if the Bridge passes.
  - [ ] Owner check: on the Bridge and Tower, the truss and pillars break when blasted, you can stand on debris, and nothing you see can be walked through.
- [x] **G-N7 Why the Bridge does not stand, and fix options** (Lane N, Codex high or Opus, M; owner asked 2026-11-18; unblocks G5). claimed: Codex gpt-6.1-sol 2026-11-18 (claim committed by the orchestrator; the Codex sandbox cannot write this repo's git index). Work in `C:\Users\jblic\Documents\BOM`,
  branch `alpha-sync` (clean `git status` first). No Unity process may run meanwhile, and Lane U stays idle (G5 is parked).
  - Facts so far (`Desktop\Bomb-integration\integration\evidence\G5\settle-pre-gn1\README.md`, `settle-od6\README.md`, `settle-bridge-experiments\README.md`): the G5 Bridge
    (`integration/fixtures/levels/BridgeLevel.json`: 52 parts, 22 wood + 30 steel, 97 glue links, 5 anchored pile feet) fails I5 as revised by OD-6 on both natives:
    on 3be3283 a lower-truss brace breaks off and falls 22 units; on f3a4e48 top-deck piece #830 at (-9.93, 6.33), the deck's unsupported left end, slides 0.594.
    Yard and Tower pass. Small layout changes flip which piece goes (non-monotonic in pile length).
  - **Correction for whoever reads G5's note:** G-N1 cannot have weakened a seam. `mortar_seam_toughness` takes the minimum of the two materials' `glue_toughness`, built-ins are 1 and steel is 1.25,
    so wood-steel seams are unchanged and steel-steel seams got 25 % stronger. The f3a4e48 → 3be3283 difference is therefore load moving to other seams, or sensitivity, not a capacity drop. Find out which.
    A likely suspect independent of G-N1: `mortar_seam_ratio`'s torque term divides by `0.5 * strength * length²`, so a 0.23-long brace-end seam has about 1/19 of the torque capacity of a 1-long seam.
  - Do (diagnosis first, no physics change on `alpha-sync`):
    1. G-N4: add the per-source settle report to `--validate-layout` (simulate N ticks headless, no players, no blasts; report per seam: the two sources, length, max load ratio `r`, force part vs torque part,
       damage, the tick it broke; and per source: cells lost, max displacement). Unit tests next to the code. This is a tool, not a rule change.
    2. Run it on the G5 Bridge (and G1's `fixtures/levels-g1/BridgeLevel.json`, Tower as a control) at f3a4e48 and 3be3283 (use `git worktree` for the old commit; do not move `alpha-sync`). Run each twice to prove determinism.
    3. Name the failing seams and why (torque from short length, a diagonal's own weight, the deck end with nothing under it, or something else).
    4. Fix options, ranked by how well they keep the owner's tuned materials and "what's there is what you get". At least: a native rule change (for example a torque-capacity floor for short seams, or measuring seam length including the glue fillet),
       a layout/support change for G6 (for example OD-3 (b) abutments under the deck ends), and material tuning for G6. Prototype native options only on a throwaway branch `g-n7-experiments` (never merged), with the settle report for each.
  - Done when: `Documents\BOM\evidence\G-N7\REPORT.md` has the per-seam tables for both commits, the determinism check, the cause, and the ranked options with measured effect; native gates (`.\scripts\bom.ps1 Test`, `NetTest`, `test-client-core.ps1`) pass on `alpha-sync` with the G-N4 tool merged.
    **Stop there.** Changing seam strength or any physics rule needs the owner's pick (Odin AGENTS rule 1); the chosen fix becomes G-N7b, then E1-GN7, then G5 re-runs `Run-G5Settle.py`.
  - done: Codex gpt-6.1-sol 2026-11-18, Odin `0b1f765` on alpha-sync (committed by the orchestrator) — G-N4 per-seam settle report in `--validate-layout`; 778 seam rows,
    16 byte-identical run pairs; Test 229 (re-run by the orchestrator), NetTest 27, shared 132, FFI 22 PASS. Report `Documents\BOM\evidence\G-N7\REPORT.md`. No production physics changed.
    Cause: the braces hang on corner contacts only 0.046–0.048 long; torque capacity scales with length², so each holds ~0.4 against ~175 for a 1-long seam. G-N1 only shifts the first break by one tick
    (a "pre-G-N1 capacity" toggle on 3be3283 reproduces f3a4e48 byte for byte). Measured options (G5 Bridge unless named; OD-6 rule): torque floor 1 passes (0.056) but fails G1 (1.677) and Tower (0.116);
    floors 0.25/0.5/2 fail (21.6/0.46/0.23, non-monotonic); steel 1.4 fails (18.5); fixed stone abutments fail (70). Experiments: branch `g-n7-experiments` `5dc2a87`, never merge.
    Sandbox: Codex's sandbox keeps every `.git` read-only and blocked writing `evidence/M0`, so Content was not run by Codex (no Unity file changed, so it is not needed).
- [x] **G-N8 Start-up shock: does easing structures in let the Bridge settle?** (Lane N, Opus, M; owner approved the investigation 2026-11-18; unblocks G5). claimed: Claude Opus 5.5 2026-11-18. Work in `C:\Users\jblic\Documents\BOM`.
  No Unity process may run meanwhile; Lane U stays idle (G5 is parked `[!]`).
  - Why: G5's brace-joinery check (`Desktop\Bomb-integration\integration\evidence\G5\brace-joinery\README.md`, table `reports/shipped.brace-seams.txt`) shows the brace seams, including full-face
    post (0.27–0.33) and girder (1.20–1.29) seams, mostly break in ticks 0–14 at r up to 46, and outline changes of 0.00005 flip the result (22.3 vs 0.389). That points to a start-up transient,
    not the standing load. The G-N7 "corner contacts only" cause is superseded by that finding.
  - Do:
    1. **Diagnose the transient first** with the G-N4 report (`--validate-layout ... --settle-ticks 2220`) on the G5 Bridge (`Desktop\Bomb-integration\integration\fixtures\levels\BridgeLevel.json`).
       Separate two candidate causes: (a) gravity applied at full strength on tick 0; (b) contact/overlap resolution between pieces that start touching or slightly overlapping
       (the 0.00005 sensitivity suggests this). For example, run with gravity 0 for the first ticks: if seams still see large r, it is (b), not gravity. Report per-tick peak r for the first ~30 ticks.
    2. **Prototype the fix that matches the cause**, on a throwaway branch `g-n8-experiments` from `alpha-sync` (never merged, worktree under `.claude\worktrees\`). For (a), try ramping gravity
       on structure bodies only (pieces, not players; player movement and prediction must not change) over, for example, 30 / 60 / 120 ticks, all inside the OD-6 start-up window (ticks 0–120).
       For (b), try the matching start-up fix (for example removing initial overlaps, or a short start-up damping/sleep), and say what it touches.
    3. Measure each variant with the OD-6 rule on the G5 Bridge, Yard and Tower, and on G1's `fixtures/levels-g1/BridgeLevel.json` (G-N7's floor-1 option failed G1 and the Tower; there is no G1 Tower fixture).
       Run each twice for determinism. Also check the Bridge with the outline-rounding control from `brace-joinery/` to show whether the knife edge is gone.
    4. Say what each variant costs: what changes for blasts and debris after start-up (it must not), gameplay config / protocol / ABI version bumps, and replay or prediction effects.
  - Done when: `Documents\BOM\evidence\G-N8\REPORT.md` has the transient diagnosis (per-tick r, cause a or b, with the evidence), and the variant table (OD-6 result per level, both runs), with costs, ranked by
    how well it keeps "what's there is what you get". `alpha-sync` is unchanged except for tools or tests if any were needed (native gates pass if so).
    **Stop there.** The owner picks; the chosen fix becomes G-N8b on `alpha-sync`, then E1-GN8 (Prediction gate required: the DLL changes), then G5 re-runs `Run-G5Settle.py`.
  - done: Claude Opus 5.5 2026-11-18, Odin `29cdea3` on alpha-sync — **cause is neither (a) nor (b): the standing load exceeds the seams.** Report `Documents\BOM\evidence\G-N8\REPORT.md`.
    (b) ruled out: gravity 0 for 2220 ticks leaves every level still (0.000000, max r 0.086); both Bridges have zero contact points in ticks 1–8, when 17 seams break.
    (a) only amplifies (1.4–5.6× at tick 1): under a 2220-tick ramp the deck–pile (0.34) and brace-corner seams carry 9–23× capacity statically (torque 90–95 % of r) and break at 7–11 % gravity.
    Variants (OD-6, both runs byte-identical, 35 pairs): ramp 30/60/120 and hold-30 all fail the G5 Bridge (0.165/0.315/25.1/26.4), regress G1 (31.8/32.1/1.93/0.955) and ramp 120 regresses the Tower (1.26);
    ramp 60 passes the rounded control only (0.056), so the knife edge stays. No prototype built (`g-n8-experiments` not created). Tool: `--settle-gravity-hold-ticks/-ramp-ticks/-trace-ticks` on `--validate-layout`, no rule change.
    Gates: client-core shared 133 + FFI 22, Test 229, NetTest 27 PASS. Owner options in report §5 (glued pieces bearing by contact, G-N7 options, visible bearing art), none measured.
- [x] **G-N9 Contact bearing: glued pieces also rest on each other** (Lane N, Opus, M; owner approved the measurement 2026-11-18; unblocks G5). claimed: Claude Opus 5.5 2026-11-18. Work in `C:\Users\jblic\Documents\BOM`.
  No Unity process may run meanwhile; Lane U stays idle (G5 is parked `[!]`).
  - Why (G-N8 report §1–2, §5 option 1): glue seams are Box2D weld joints made with `b2.DefaultWeldJointDef()` (`src/shared/sim_physics.odin`, the `c.mortar` branch and the flexibility branch),
    which leaves `collideConnected` false. Glued pieces never touch, so a deck resting on pile tops carries its weight through the glue as torque (9–23× capacity on the Bridge) instead of bearing on the piles.
    The Tower passes only after cracking ~100 seams at start-up, which also goes against "what's there is what you get".
  - Do (measurement first, no physics change on `alpha-sync`):
    1. Confirm the mechanism: list every reason two glued pieces cannot collide today (weld `collideConnected`, shape filters/groups, anything else), with file:line.
    2. Prototype on throwaway branch `g-n9-experiments` from `alpha-sync` (worktree under `.claude\worktrees\`, never merged). Variants, at least: (i) mortar welds collide;
       (ii) mortar and flexibility welds collide. Report tick-0 contact points and penetration (touching or overlapping pieces now fight their weld) and any jitter.
    3. Settle (OD-6 rule, two runs each, byte-identity): G5 Bridge, G5 Bridge rounded control (`brace-joinery/reports/round4.layout.json`), Yard, Tower, G1 Bridge.
       Also report start-up seams broken per level (target: close to 0 on Tower and Bridges) and peak r, so a pass that comes from cracking first is visible.
    4. Blast and debris regression, headless: with one fixed scripted blast per level after settle (same point and strength for base and variant), compare cells lost, fragment count and size spread,
       debris rest positions/spread, seams broken by the blast, and step time (contact pairs added). If the validator has no blast option, add a diagnostic one on `alpha-sync` (tool only, tests next to it, gates pass).
    5. Costs: what changes for players (they should be unaffected), gameplay config / protocol / ABI version bumps, prediction and replay effects, performance.
  - Done when: `Documents\BOM\evidence\G-N9\REPORT.md` has the mechanism (file:line), the variant tables (settle per level with both runs, start-up breaks, blast/debris comparison, step time), and the costs,
    ranked by how well each keeps "what's there is what you get". `alpha-sync` is unchanged except for tools or tests (native gates pass if so). If no variant passes, say so plainly with the data; do not tune toward a pass.
    **Stop there.** The owner picks; the chosen fix becomes G-N9b on `alpha-sync`, then E1-GN9 (Prediction gate required), then G5 re-runs `Run-G5Settle.py`.
  - done: Claude Opus 5.5 2026-11-18, Odin `4f2ae95` on alpha-sync (tool `8972ecb`: `--settle-blast TICK,X,Y,R` on `--validate-layout`, test next to it) — **contact bears the standing load, but no variant alone passes every level and start-up cracking stays.** Report `Documents\BOM\evidence\G-N9\REPORT.md`.
    Mechanism: mortar welds `sim_physics.odin:266/270` (and flexibility welds `:277/282`) leave `collideConnected` false; nothing else (default filters, no custom filter) stops glued pieces touching. No fixture has a working flexibility weld (steel/earth are stone-based; `sim_material_library.odin:28` applies flexibility to rubber only), so ii = i and iii = shipped byte for byte.
    i (mortar welds collide), OD-6, both runs byte-identical: G5 pass 0.020, rounded pass 0.020, Yard pass, Tower pass 0.002, **G1 FAIL 38.8** (shipped G1 also falls by tick 7212 in a 10-min run). Breaks 48/46/104/42 → 23/24/43/30; deck–pile seams still break on ticks 1–4, though their static load drops 9.4–18.7 → 0.73–1.26; corner pins stay 2–7×.
    Diagnostic only: i + ramp 30/60/120 passes all five (5–43 breaks move after tick 120). Costs: Yard blast debris scatters less (moved 57 → 49, farthest 5.58 → 3.40, seams broken 5 → 2); Bridges and Tower blasts unchanged; Bridge weld/contact chatter (r 0.01–5.5, never sleeps, no breaks in 10 min) and server step +57–65 % on Bridges, +27 % Tower.
    62 settle/blast pairs byte-identical. Gates with the tool: shared 134 + FFI 22, Test 229, NetTest 27 PASS. Prototype `g-n9-experiments` `882b3b2` (never merge). Not verified: replication/prediction near a chattering Bridge, snapshot-rebuild jolts, Unity.
- [~] **G-N9b Ship contact bearing + 60-tick structure ramp (OD-8)** (Lane N, Opus, M; after G-N9; then E1-GN9). Work in `C:\Users\jblic\Documents\BOM` on `alpha-sync` (clean `git status` first). claimed: Claude Opus 5.5 2026-11-18
  No Unity process may run meanwhile; Lane U stays idle.
  - Do:
    1. Mortar welds get `collideConnected = true` (`src/shared/sim_physics.odin`, `c.mortar` branch). Flexibility welds stay as they are (no fixture uses them; G-N9 §1).
    2. Structure gravity ramp: structure bodies (pieces and any fragments made during the ramp) get gravity scale `min(1, ticks_since_level_start / 60)`; players keep their own scale.
       It must be a pure function of the level/round start tick, so replays, snapshot rebuilds and every round restart give the same result. Wake bodies when the scale changes.
       Hard-coded constant, no gameplay-config field (so no config/manifest/protocol/ABI version change; if that turns out impossible, stop and say why).
    3. Client prediction: `prediction_static.odin` extrapolates proxies with config gravity. Make it use the same scale during the ramp if it knows the tick, or show with a test that the mismatch is limited to the first 60 ticks.
    4. The validator's default settle run uses the shipped rule (no flags). The G-N8 diagnostic flags stay and still work (a diagnostic ramp on top of the shipped one is the user's choice).
    5. Tests next to the code: mortar pair collides, ramp schedule (tick 0, 30, 60, 61, round restart), players unaffected, determinism (two runs byte-identical), and a rebuild mid-ramp matches an uninterrupted run.
       Existing tests whose expected values change: update only with the reason in the commit message; never weaken an assertion.
  - Done when: native gates pass (`.\scripts\bom.ps1 Test`, `NetTest`, `test-client-core.ps1`, bash redirection for logs). The G-N9 settle table re-run with the shipped build (OD-6 rule, both runs) is in `evidence\G-N9b\README.md`:
    G5 Bridge, rounded control, Yard, Tower and G1 Bridge, next to G-N9's `i + ramp 60` row (explain any difference: per-body scale vs world gravity), plus step time and one blast per level as in G-N9 §4.
    If any of the five fails, stop with the data; do not tune.
- [ ] **G6 Re-export Yard, Bridge and Tower with G5** (T2, Sonnet, M; Lane U; after G5). Settle check on each level (35 s, revision constant). Tune materials and glue with the owner, and capture each level next to G1.
- [ ] **G7 Classic Yard** (T2, Sonnet, S; Lane U; after G5).
  - Bring its 8 off-plane pillars (depth 1.06..1.76) onto the play plane, glue its tables, and apply OD-5 (C, destructible bedrock; decided 2026-11-18).
  - Classic's blast native cost (up to 19 ms, about 4150 cells) scales with cell count. Re-measure it after the re-author before any native profiling (see the 2026-11-17 orchestrator finding).
- [ ] **G8 Boundary per OD-1** (T2, Sonnet, S; Lane U). B (no walls) for the Bridge; C (destructible bedrock) for the Yard and Tower, and for Classic Yard (OD-5, 2026-11-18). Check the kill and fragment-cull bounds, and decide Darryn's 26 outside-arena Yard tiles (G3 finding).
- [ ] **G8b Frame cap in normal play** (F2 fix 3; T2, Sonnet, S; Lane U; any time before G9).
  - Every `vSyncCount`/`targetFrameRate` call today is in a scripted path (`BomClientBehaviour.cs:268` behind `--bom-level-smoke`, `BomRoundScenario`, `BomFrontDoorScenario`,
    `BomPerformanceProbe`, `BomPresentationProfile`), so owner play runs uncapped (one player thread at ~92 % of a core, C2d finding).
  - Set a cap at startup for normal play in a new or existing `Runtime/` file (F2 suggested `BomFrontDoor.cs`): vSync on, or `targetFrameRate` = the display's refresh rate.
    Scripted runs keep their own settings; perf numbers from before and after are not comparable, so say which in the evidence.
  - Done when: Build, Content, Rounds and front door pass, and a player started with no flags logs the cap it applied. [ ] Owner check: play feels at least as smooth, and the fan is quieter.
- [ ] **G9 Performance and feel pass** (T1, Opus, M; Lane U; after G2–G8b). Run the F2 protocol with 2 windows, a long human Elimination round with blasts on every level, the Prediction suite and the 30-minute soak.
- [ ] **G10 Repackage** (T2, Sonnet, S; Lane U; after G9 and the owner check). As F4, with the G look as the default.

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
- 2026-11-11 Claude Opus (crash root cause, WinDbg + Unity symbol server, outputs `BOM-Release/crash-20261111*/cdb-*.txt`): both crashes are the same Unity engine re-entrancy on **Direct3D 12**.
  The project sets no Windows graphics API, so players run D3D12 (`Version: Direct3D 12 [level 12.1]` in the player log). Inside the player loop, `GfxDeviceD3D12::WaitForLastPresentationAndGetTimestamp` ->
  `SwapChainWaitingContext::WaitOnSwapChain` calls `DispatchMessage`, so window messages run in the middle of a frame. Guest (17:47): a focus change -> `SetPlayerFocus` -> `InvokeFocusChanged` -> C# (Input System reset) -> `memset` access violation.
  Host (18:39): a click on the window frame (`WM_NCLBUTTONDOWN`, uxtheme) started Windows' modal move/close handling inside that wait (no frames for ~35 s), it ended in close -> `DoQuit` -> `PlayerCleanup` while the frame was still open -> heap corruption (`tlsf_free`/`block_remove`).
  "PlayerLoop called recursively" and "Undefined ManagedTempMemScopePolicy" are Unity noticing exactly this. C2f only closed the focus-callback way in.
  Workaround now: the owner launcher (`launch-e1n3-graze-check.ps1`) passes `-force-d3d11`. Checked on D3D11: log says `Direct3D 11.0`, keys move only the focused window, no stuck key, both windows close via X in 0.3 s with no crash lines.
  Permanent fix needs a choice: `ProjectSettings/ProjectSettings.asset` is protected, so either the owner approves setting Windows Graphics APIs to D3D11 there (and a re-baseline), or our build scripts set it in the validation copy only; F4's package launcher must pass `-force-d3d11` either way until then. The Rounds gate still runs D3D12.
- 2026-11-11 Claude Opus (owner play on D3D11, 18:52): owner reports no glitches and nothing looks different. Logs agree: both windows on `Direct3D 11.0`, 0 `Crash!!!`, 0 recursion or temp-scope warnings,
  21 focus changes handled, never `Responding=False` in watch.csv; the guest's only exception is "The host left" after the host window was closed first. The permanent D3D11 setting is still open (see the root-cause finding above).
- 2026-11-11 Claude Opus (D13): `ProjectSettings.asset` now lists Direct3D 11 for Windows (baseline entry updated: size 25575, sha256 0b98f3ec...5d23). Content, Build (0 error CS) and Rounds Yard+Draw pass, 0 Exceptions.
  Correction to the root-cause finding: the Rounds, Performance, Prediction and level-interop tools already pass `-force-d3d11`, so the gates never ran D3D12 (likely why they never crashed). Proof the setting works:
  a player started with no flag logs `Version: Direct3D 11.0` (`BOM-Release/diag/noforce*-p1.log`); close-by-X twice more exited in <=0.5 s. The owner launcher's `-force-d3d11` is now redundant but harmless.
  `robocopy ProjectSettings /MIR` into the validation copy also replaced its Unity-rewritten EditorBuildSettings, GraphicsSettings, ShaderGraphSettings and UnityConnectSettings with the repo versions; the builds passed afterwards.
- 2026-11-12 Claude Opus (E1-N4): A4's NativeInterop restore only restores files that existed before the run. In a fresh checkpoint folder from `Build-OwnerNative.py`,
  `build/interop/bomcore.dll` did not exist, so the suite left its own rebuilt DLL there (872b558b…) and the Prediction suite then refused to run ("plugin identity differs";
  failed record `evidence/M0/Test-Prediction-20261112T032546587Z.json`). Copying `build/bomcore.dll` over it fixed it (6/6 next run). Tool fix for A-lane: after NativeInterop,
  copy the stage `bomcore.dll` to `interop/` when it had no backup.
- 2026-11-12 Claude Opus (E1-N4): the M9 performance fixtures were still protocol 7 (pre-N1), so the first soak failed at startup in both players with
  `gameplay level/config manifest mismatch` (kept: `evidence/M9/soak-20261112T042936243816Z`). `Build-BomPlayers.ps1` calls `RebuildMono`, which does not re-export.
  I ran `BomPerformanceBuilder.BuildMono` by hand in the validation project (`BOM_NATIVE_SERVER_EXE`, `BOM_PERFORMANCE_LAYOUT_DIR=integration/fixtures/M9`,
  `BOM_PERFORMANCE_PLAYER_OUT=build/validation/Mono`) and committed the two registries, scenes and `fixtures/M9/*`; its 500 regenerated mesh assets differed only in `m_Name`
  and were reverted, and the validation copy's `Validation/Identity*.unity` (one with a changed `.meta` GUID) were not copied back. After any future gameplay-config change, rerun it.
- 2026-11-12 Claude Opus (E1-N4): no gate exercises items fully. Rounds ends before the first item (guest forfeits at 2.5 s; items start 3-8 s into Playing); Prediction profiles
  and the soak run Sandbox, so no items spawn there. An evidence run with the new opt-in `BOM_ROUND_FORFEIT_TICKS=720`
  (`Test-NetworkRounds.ps1 -SkipBuild -Scenario Yard -PlayerPath build/validation/Network-Mono/BombNetwork.exe`) passed and both clients logged
  `BOM UNITY ITEM drawn id=1 kind=4 type=slow prefab=BomItem4`, falling from y 36.6 to rest at 10.03. Nobody touched it, so pickup sound, glow and coins are unverified in a player:
  look for `BOM UNITY ITEM gone ... pickup=1` and `BOM UNITY EFFECT player= effects=` in the owner play. The graze ring logs nothing. Item ids restart each round, so `drawn` repeats per round (log only).
- 2026-11-12 Claude Opus (E1-N4, owner request): `Runtime/BomTestAudioMute.cs` mutes players started with `-batchmode`, `--bom-round-test`, `--bom-soak`, `--bom-perf-out`,
  `--bom-profile-out`, `--bom-mute` or `BOM_MUTE=1` (each logs `BOM AUDIO muted for scripted run (...)`); owner launches pass none of these and keep sound.
- 2026-11-12 Claude Sonnet (C4): **Owner, please note: `MatchMenuUI.RestartCurrentScene` (Darryn's "RESTART GAME" in his local match menu) resets the shop wallet to 250, which wipes coins earned in network rounds.** Not changed (his file).
  Mapping: `result-coins` = `xp_gained` (includes item coins), `result-bombs` = `bombs_faced`, `result-time` = alive time, `result-total-coins` = wallet read from PlayerPrefs `CharacterShop.Coins` (the key `AddShopCoins` writes; `MatchMenuUI.shopCoins` is private).
  `pause-panel` is shown by Esc together with the connection menu (RESUME closes both, RESTART = host command and host-only, LEAVE GAME = disconnect); the game never pauses. `replay-button` is hidden for non-hosts.
  Wallet: new `Runtime/BomWallet.cs`, paid once per round id; the paid set is cleared on RETURN/LEAVE GAME because another server may reuse round ids (a reconnect keeps it). Spectators (not in the round's players) are not paid.
  `link.xml` now preserves `MatchMenuUI` and `GameAudio`. All Darryn UXML elements in the C4 list exist; `level-fill`, `result-xp`, `current-level`, `next-level` queries were removed.
  First Rounds attempt (evidence `unity-rounds-20261112T140238368619Z` / `...T140421200332Z`, kept) paid only the surviving player and nothing in the draw: I had skipped clients with round flag 4, which is also set for a dead player. Fixed (the seated-player check suffices); not a sleep.
  Not verified in a player: the on-screen panels, `AddShopCoins` running under IL2CPP (Mono only), the wallet total on screen. In a Rounds run a window only logs the payment; the shop total was not read back.
- 2026-11-12 Claude Opus (C5): for C7, nothing outside `Assets/Game/Online/` references `OnlineMenuUI`/`OnlineSession` any more, so the folder can be deleted as written. For F4: package `Server/BOM-server.exe` and
  `Server/levels/yard.json` next to `Bomb.exe` (see `BomHostServer.FindServer`); the host token is on the server's command line (visible to local programs only), never in an environment variable.
  A guest still connected when its host leaves logs `InvalidOperationException: The host left…` through `BomClientBehaviour.Fail` (`Debug.LogError(exception)`); a gate that keeps a guest connected through that would count it. Music in NetworkMenu is still the open C3 finding (not checked here).
- 2026-11-12 Claude Opus (C6): how Darryn's tiles map to Odin (each tile's decision is in `fixtures/levels/<Level>.json.tiles.json`):
  - **Off-plane tiles are decoration.** A tile whose depth misses the player plane (z 0 +/- 0.45, his CharacterController radius) never touches his players, so it stays visible art and does not break on Odin:
    Bridge 88 of 110 (the whole front/rear truss: posts, braces, girders at z +/-2.08..2.42; only the 22 deck tiles are physical, all Carve -> Anchored), Yard 8 and Tower 29 pillars (z 1.06..1.76). Owner: the truss and pillars no longer carve.
  - **Seams.** Darryn's tiles overlap neighbours, which native rejects. Each overlapping box is trimmed on its shallowest side against tiles kept whole (higher top first): Yard 87 trimmed (max 0.39), Tower 61 (max 0.18), Bridge 0.
    The yard's 4 rocks (non-box meshes sunk into the ground) are clipped at the ground face (<= 0.222 area each). Tiles outside the walls stay art: Yard 26, Tower 10. Anything deeper than 0.5 or 25 % of a tile fails the export.
  - **CarveAndFragment that rests only on off-plane pillars** cannot be Dynamic (it would fall at tick 0), so it is Anchored at its pillar contacts and falls once a blast removes them (his fallWhenUnsupported):
    Tower 46 floor tiles, Yard 2 (`Cube (8)`, `Cube (10)`); 8 Tower tiles with nothing under them within 0.3 are anchored on their bottom edge. Dynamic as specified: Tower 32 (ground rows), Yard 4 (rocks).
    Carve tiles are anchored on every edge (pieces still touching the original outline stay). Materials: Yard custom `earth` (stone), Bridge `wood`, Tower `stone`; gameplay config copied from the classic yard.
  - Bounds: camera = his Level Bounds (-18,-25.36)..(18,34.64) in all three (his ArenaCamera uses the same); bombs drop at its top + 2 = 36.64 (his BombDropper, same as the classic yard); kill = inner wall faces x Level Bounds.
    Spawns: his ArenaSession spacing (2) for 4 players at x -3,-1,1,3, dropped onto the surface below his spawn height: Yard y 6.64, Bridge 10.11 (top deck), Tower 20.35 (fourth floor).
  - Not checked: the C2b settle check (world revision constant with no blasts) for Tower's dynamic ground and pillar-anchored floors; visuals and camera fit (no human looked; gate players run `-batchmode`).
- 2026-11-12 Claude Opus (C6): the first Bridge rounds (`frontdoor-bridge-20261112T153044009290Z`, `…T153424780227Z`, kept) threw `Outline could not triangulate` in `BomExtrusion` (fallback cell mesh) at connect: a native wood plank cell
  ends in a 4-vertex cluster 1e-4 apart that doubles back. `BomExtrusion` now retries only when the old ear clipping fails: drop vertices < 0.001 apart or collinear, strict interior test; the message now lists the outline.
- 2026-11-12 Claude Opus (C6): `Test-LevelManifest.py` timed out against `BombNetwork.exe` (menu player, never connects by itself; failed runs `manifest-reject-20261112T1543*`/`T1544*` kept); it now passes `--bom-auto-connect`.
  The Tower manifest run `…T160205673822Z` overlapped laptop standby (Kernel-Power 506 at 16:02:04Z, resume 507 at 16:42:18Z); rerun passed, not counted.
- 2026-11-12 Claude Opus (C6): the tile scenes are rebuilt from Darryn's scenes in every front-door build, so their YAML churns (file IDs) and regenerated `Source_*_Mesh_*.asset` differ only in `m_Name` (not copied back).
  `Build-BomPlayers.ps1` and the Rounds gate copy the repo's `Assets/BOMIntegration` over the validation copy, so after a front-door build copy `Levels/bomb-{yard-tiles,bridge,tower}-v1/VisualRegistry.asset` and the three
  `Network*.unity` back before running them, or the registries go stale against `fixtures/levels` (manifest mismatch). E1 after any gameplay-config change: rerun `Test-FrontDoor.ps1` to re-export these levels too.
- 2026-11-12 Claude Sonnet (F4): **IL2CPP has no working `System.Diagnostics.Process`.** The IL2CPP front-door player's `BomHostServer` threw `Win32Exception ... Native error= Success` from `Process.Start`, so ONLINE > HOST could not start the server (kept: `evidence/M8/frontdoor-20261112T171745165773Z`, first package `BOM-Windows-2026-11-12`; Mono passed `frontdoor-20261112T171535267349Z`). `BomHostServer` now starts the server with `CreateProcessW` for both backends (CREATE_SUSPENDED | CREATE_NO_WINDOW, stdout/stderr to the `bom-server-<time>.log` through an inheritable append handle, assigned to the kill-on-close job before ResumeThread) and tails that log for the "listening" and "Could not bind UDP port" lines. Mono gates after the change: Build, Content (1555), front-door Classic Yard + Bridge, Rounds Yard+Draw all pass. Any other player code using `System.Diagnostics.Process` will fail under IL2CPP (`BomFrontDoorScenario.ProcessGone` uses `GetProcessById`; only in the scripted test path, which passed on IL2CPP).
- 2026-11-12 Claude Sonnet (F4): the package now ships the front-door game: `Build-BomGame.ps1 -Backend Mono|IL2CPP|Both` (new, also used by `Test-FrontDoor.ps1 -Backend`), `BomFrontDoorBuilder.BuildIl2Cpp`, `Package-BomWindows.ps1` (takes `Game-Mono`/`Game-IL2CPP`, checks server hash and levels), `Launch-Bom.ps1` (just opens N main-menu windows; the game runs its own server, so `-Bind`/server flags are gone). `Run-FrontDoor.py` crashed building its summary for IL2CPP (no `Managed/Bom.Unity.Runtime.dll`); it now hashes `GameAssembly.dll` there. The scripted run mutes audio, so the audio prefab is not heard in it: owner, listen for music in IL2CPP.
- 2026-11-17 Claude Opus (E1-GN6): after G-N6, Tower still has 14-18 `Dynamic_History_Required` entries per 100 s (others 2-3), the remaining triggers the G-N6 hand-over names. Yard 2-window first-blast host frame was 37 and 34 ms in two runs (G2b 26) with native ≤ 1.7 ms; not chased (one frame, not native). Passing `-Levels 1,3` from bash to `powershell -File` gives level 13: run one level per call.
- 2026-11-17 Claude Opus (G3): Classic Yard's dirt still shows faint brightness banding along cell edges in the band look. Not proven; likely URP per-object light lists differing between 4x4-unit chunks. A fix touches the protected render-pipeline asset (same one as D10). Darryn's 26 outside-arena Yard tiles are still drawn at full depth next to the band-deep ground (G5/G8). Prediction failed 3x on cadence only after a Modern Standby on the dev machine (adverse 142.7 -> 132 fps, frame p95 7.4 -> 12.6 ms) with the DLL unchanged; see `evidence/G3/README.md`.
- 2026-11-17 Claude Opus (orchestrator hand-over). Checked by the outgoing orchestrator against the repos.
  - **Running or half-done:** nothing.
    - No `[~]` boxes, no Unity or game processes, and no uncommitted tracked changes in either repo.
    - Untracked on purpose (as every perf task did): perf PNG/JSON, G2b traces and some `evidence/M0` gate records under E1-G, E1-GN6, G2, G2b and G3.
    - Odin keeps four worktrees and branches, all already merged into `alpha-sync`: `claude/g-n1-glue-materials-c88a7a`, `claude/g-n2-glue-validate-cdef50`, `claude/g-n5-client-cost-3d0d28` and `claude/prediction-flap-fix-1abcdd`. They are safe to remove, but not removed; that is the owner's call.
    - Nothing is pushed, in either repo.
  - **Told the owner, only in chat until now:**
    - (a) Classic Yard's 33-42 ms blast frames are one dropped 60 fps frame. Native cost of up to 19 ms scales with its 4150 cells. Recommended: no native profiling until G5/G7 re-author Classic (now in G7).
    - (b) The G3 banding fix needs the owner's OK to edit the protected render-pipeline asset. The owner has not been asked yet.
    - (c) The dev machine ran slower after the 10:34 Modern Standby. If cadence checks keep failing, a restart is the owner's call; never restart it yourself.
    - (d) The owner said CPU-heavy work and a busy machine are fine. Keep the laptop on AC during runs: unplugging happened during the standby.
  - **Old hand-over (`BOM-Release\HANDOFF-opus-main-chat.md`) is stale.** This file supersedes it.
    - Issues 1 and 2 were closed by E1-G and G2b.
    - Issue 3: the edge was fixed by G3; the banding is still open (G3 finding).
    - Issue 5 is already closed here: the PlayerLoop crash by D3D11 (D13), and the 0.75 s input offset by `BomSession.Now` (C2e).
    - Issue 4 was not tracked here. Residual GC is 14-19 MB/min, not from cell presentation (≤ 0.8 KB/frame), likely the HUD (review #12). It is low priority and has no task.
  - **Not verified by the outgoing orchestrator:** whether F2 fix 3 (vSync / frame cap in normal play) was ever done.
  - **Owner checks added today:** E1-G, G2b, E1-GN6 and G3. They are open and not to be ticked by models.
- 2026-11-17 Claude Opus (incoming orchestrator, checked e26dbe37 against both repos; its claims hold).
  - F2 fix 3 was never done: all frame caps sit in scripted paths only, so normal play is uncapped. Now task G8b.
  - G7/G8 gave Classic Yard bedrock, which OD-1 does not cover. Now owner decision OD-5; G7/G8 wait for it.
  - G5's "Done when" will be made checkable (I1–I5 each as an export failure, no Hidden/Indestructible parts, Bridge piles, per-level counts) before anyone claims it.
- 2026-11-18 Claude Opus (G5 pre-G-N1 diagnostic, `evidence/G5/settle-pre-gn1/README.md`): on f3a4e48, before G-N1, the G5 Bridge cracks once in the first 1.8 s (one piece shifts 0.56), then holds. On 3be3283 its lower truss collapses (30 pieces move, max 6.42), so G-N1 causes the collapse. Still, I5 does not pass before G-N1 either: stands on f3a4e48: G5 Bridge no, G1 Bridge no (late cracks at ~18.5 s and ~29.5 s, 731 -> 726), Tower no (identical on both). Every layout changes revision in the first ~2 s; whether to allow a start-up window is the orchestrator's or owner's call. G5 stays [!].
- 2026-11-18 Claude Opus (orchestrator): G5's blocked note says "Lane N fix to G-N1 short-seam capacity". G-N1 never lowers a seam's capacity (min of the two materials' `glue_toughness`; built-ins 1, steel 1.25),
  so it is not a capacity drop. The Bridge also fails OD-6 before G-N1. The task is now G-N7: diagnose first (with the G-N4 per-seam settle report), then the owner picks a fix.
- 2026-11-18 Claude Opus (orchestrator, G-N7 review): no native rule tried fixes the Bridge without hurting G1 or the Tower, and the results are non-monotonic (floor 1 passes, floor 2 fails),
  so a seam-strength rule would be tuning a knife edge. The cause is geometric: G5's partition leaves each diagonal brace touching posts/girders only at a ~0.047 corner (a pin, which carries no torque).
  Design doc 3.2 rule 3 says braces are clipped to the post and girder faces, which should give a full-face seam about brace-width / sin(angle) long (roughly 0.25-0.8), i.e. 25-300x the torque capacity.
  Recommended next step (exporter side, no physics change): G5 checks and fixes the brace-end joinery, measures it with the G-N4 report (`--validate-layout --settle-ticks 2220`), then re-runs OD-6.
- 2026-11-18 Claude Opus (G5 brace joinery, `evidence/G5/brace-joinery/README.md`): the G-N7 premise that the braces hang on 0.047 corners only does not hold. Each brace also has full-face seams (post 0.27–0.33, girder 1.20–1.29 native length), the most Darryn's geometry allows, and those break as well (r up to 45.8). No partition/glue change within design doc 3.2 fixes the Bridge. Measured variants fail or are rejected. The next step is the owner's: drawn gussets or knee braces, or a G-N7 option.
- 2026-11-18 Claude Opus (orchestrator): I checked G5's seam table (`brace-joinery/reports/shipped.brace-seams.txt`), and it supports the finding. My G-N7 review recommendation (exporter joinery) was wrong because it rested on the corner-only cause.
  Most brace seams break in ticks 0–14, so the owner approved G-N8: diagnose and measure a start-up fix (gravity ramp or overlap/contact shock). No production physics change until the owner picks one.
- 2026-11-18 Claude Opus (G-N8, `Documents\BOM\evidence\G-N8\REPORT.md`): the Bridge start-up breaks are not a start-up transient. With no gravity nothing moves; with gravity eased in over 37 s the deck–pile and brace-corner seams still carry 9–23× capacity as torque, because welded pieces never touch (no contact bearing) and the Bridge has no other contacts. A gravity ramp does not fix it and regresses G1/Tower. The fix has to change the standing load path (owner decision).
