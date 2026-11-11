# Odin authority integration for the Bomb Unity project (draft, not opened)

Branch: `integration/odin-unity-20261105` -> `main`. **Do not open this PR without the owner's yes.** Nothing has been pushed.

## What this adds
- `Assets/BOMIntegration/`: a Unity client that **presents** the Odin game. Odin owns physics, destruction, networking,
  input scheduling, prediction and rounds; Unity copies native snapshots through the C ABI (`bomcore.dll`, ABI 1.4,
  protocol 7) and sends input. No Unity gameplay physics and no managed wire codec.
- Scenes `NetworkMenu`, `NetworkYard`, `RoundDraw` (plus performance/test scenes) built from the original art, with
  prefabs for player, bomb and blast presentation, an authoring layer (`BomLevelAuthoring`, `BomAssetInstance`,
  `BomPhysicsPart`) and a level exporter that the native server validates.
- Native identity guard: Unity refuses to connect if `bomcore.dll` does not match the bindings (ABI, protocol, build tag, SHA-256).
- `integration/`: tools, contracts, fixtures, protected-content manifests, and raw evidence of every run (including failures).
- Elimination mode for 2-4 players: cover-aware blast lethality, actual blast radius, bomb pacing ramp, XP/win accounting
  (`integration/contracts/round-rules.md`).
- Windows package launcher for Windows PowerShell 5.1 and 7, with a LAN host mode (`integration/docs/lan-test.md`) and an
  artist guide (`integration/docs/artist-guide.md`).

## What is not touched
Original scenes, scripts, prefabs, GUIDs and packages under `Assets/Game`, `Assets/Polytope Studio` and the rest of the
original project are unchanged: 605 protected files verified by `Invoke-BomIntegration.ps1 -Task Test -Suite Content`
(last run: `integration/evidence/M0/Test-Content-20261110T232806034Z.json`). The four `PT_Nature_Free_URP_*.unitypackage.meta`
files that were deleted in the working tree before this work are restored. The original `Assets/Game/Scenes` scenes still
load and play on their own (see `integration/review/original-scenes-check.md`). The default branch is untouched.

## How to run
1. Release package: `powershell -ExecutionPolicy Bypass -File .\Launch-Bom.ps1` (two local windows; the first is the host).
   `-Lan` on the host and `-ClientOnly` on a second PC for a LAN game.
2. From source: `integration/tools/Start-BomNetwork.ps1` after building players with `Build-BomPlayers.ps1`.
3. After changing the Odin source: `python integration/tools/Build-OwnerNative.py --config integration/local.config.json`,
   restart the Editor, rebuild players.

## Verification (protocol 7)
220 game tests from merged Odin `master`, 27 transport, 90 shared, 20 FFI; real-UDP four-player round scenarios; six 600-second
prediction profiles; 30-minute Mono+IL2CPP reset-under-load soak (183 resets, 552 same-tick blast pairs, hashes matched);
original-scene smoke logs; protected-content check. See `integration/STATUS.md` and `integration/evidence/`.

## Known limits
- Development Unity players (not release builds); no audio hooks yet; first fracture can hitch (cold mesh upload).
- Mono and IL2CPP players and the native library were built on one machine; the two-machine LAN test and game-feel
  review are still to be done by people (`integration/docs/lan-test.md`).
- Manual blasts are a host-only debug tool. Accounts and XP are server-session-only (no persistence).
- `integration/evidence` is large (raw traces); drop or squash it before merging if repository size matters.
- IL2CPP: the first build attempt on this machine hung (out of memory pressure); the retry passed.
