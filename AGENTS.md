# Bomb (Unity) agent guide

Odin is the only gameplay authority. Unity presents copied native state and sends input; it never decides
outcomes and never reads or writes wire bytes. This file is read with the Odin repo's `AGENTS.md`
(`C:\Users\jblic\Documents\BOM`), which holds the full rules, commands and open items.

## Locations
- This repo: `C:\Users\jblic\Desktop\Bomb`. Integration branch: `integration/odin-unity-20261105`.
  Default branch (`main`) and the owner's own feature branches are not to be touched.
- `integration/`: `tools/` (scripts), `contracts/` (round-rules.md is the gameplay contract), `fixtures/`, `baselines/`
  (protected-content manifests), `evidence/` (raw run records, kept even for failures), `soak-host/`.
- Native source: `Engine/` (moved in 2026-11-19 from `C:\Users\jblic\Documents\BOM`, now a read-only backup; its own
  rules are `Engine/AGENTS.md`). The matching checkpoint is built with `integration/tools/Build-OwnerNative.py`; ship
  its DLL to `Assets/BOMIntegration/Plugins/x86_64/` and its server to `Server/` together (`Server/README.md`).
- Team-facing overview: `TEAM.md`. Editor tools find the repo through `Editor/BomRepoPaths.cs` (no absolute paths);
  tools that run Unity on a separate validation copy set `BOM_INTEGRATION_ROOT`.
- Release package: `C:\Users\jblic\Documents\BOM-Release`.

## Rules
1. Original Unity assets, GUIDs, scenes and packages stay protected. After any Unity change run
   `integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content` (every file in `integration/baselines/unity-content.json` must verify; 1,559 today).
2. New scripts need `.meta` files with stable GUIDs; never regenerate existing ones.
3. Do not change physics, destruction, material or blast behaviour; those live in Odin. Ask first.
4. Never weaken an assertion; keep failed attempts' evidence next to the passes.
5. One Unity build at a time (memory-tight machine). Never run a build and a soak together.

## Versions
Protocol 9, round format 4, gameplay config 5, ABI 1.6, level 4, canonical 3. Unity 6000.2.14f1.
The shipped `Assets/BOMIntegration/Plugins/x86_64/bomcore.dll` must match `bomcore.build.json` and
`BomExpectedNativeIdentity.cs` (build tag 661202865791242486, DLL sha256 5ef68966...2311c, from Odin alpha-sync 49d1a6e (G-N11), 2026-11-19); the
identity guard (`BomNativeIdentity.Verify`) fails builds and players on a mismatch.

## Commands (PowerShell; pass `-ConfigPath integration/local.config.json` or the owner-validation config explicitly)
- `integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content|NativeInterop|NativeProof|Rounds|Soak|Performance`
- Players: `Build-BomPlayers.ps1 -Backend Mono|IL2CPP|Both`; soak: `Test-UnitySoak.ps1 -SkipBuild -PrimaryPlayer <exe> -GuestPlayer <exe>`
- Play: `Start-BomNetwork.ps1` (local server + two clients). Package: `Package-BomWindows.ps1`.
- Windows PowerShell 5.1 and PowerShell 7 are both targets; PowerShell 7 is not installed on the dev machine.

## Always ask before
Any push or pull request; merging into the default branch; anything that edits protected content; owner-only machine
actions (system settings, closing their apps).

## Current work queue
`integration/ALPHA-SYNC.md`: catch-up with Darryn's AlphaV0.1 (merged 2026-11-10). One task per session; claim and
tick boxes there. Its rules add to the rules above. The protected baseline now covers Darryn's AlphaV0.1 originals, updated for Online v0.2 (1,559 files).

## Open items
Human checks (game feel, two-machine LAN, an artist adding an object). Everything else is tracked in `integration/ALPHA-SYNC.md`.
