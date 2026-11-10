# BOM fixture policy

The user authorizes choosing or adjusting fixture coordinates, blast positions and radii, cells to discard, bonds to break, seeds and tick counts when a specified fixture does not exercise the intended check. Record the chosen details and reason in the report, then continue without stopping.

Stop and ask only when a system rule (data model, failure rules, strengths, recipes, physics, snapshot format or byte-identity requirements) conflicts with the code or cannot be implemented as written. Fixture adjustments do not authorize changing these system rules.

# BOM agent guide (Unity integration)

Odin is the only gameplay authority. Unity presents copied native state and sends input; it never decides
outcomes and never reads or writes wire bytes.

## Locations
- This repo: `C:\Users\jblic\Documents\BOM` (Odin, native game, server, C ABI, netcode).
- Unity repo: `C:\Users\jblic\Desktop\Bomb`. Integration work is on branch `integration/odin-unity-20261105`;
  its `integration/` folder holds tools, contracts, fixtures and raw evidence.
- Release package: `C:\Users\jblic\Documents\BOM-Release` (see its REPORT.md).
- Pre-integration backup: `C:\Users\jblic\Documents\BOM-before-unity-baseline-20261110T214214370244Z.zip` (keep).

## Rules
1. Do not change existing physics, destruction, material or blast behaviour without asking.
2. Original Unity assets, GUIDs, scenes and packages stay protected; run the protected-content check after
   every Unity change (`Invoke-BomIntegration.ps1 -Task Test -Suite Content`).
3. Gameplay choices the contracts don't cover: pick what is fun and fair, make it data-driven, record it in the
   Unity repo's `integration/contracts/round-rules.md`. Manual blasts are a host-only debug tool.
4. Report failures as failures with raw output. Never weaken an assertion. Keep failed attempts' evidence.
5. Machine is memory-tight: never run two Unity builds, or a build and a soak, together. Stop if C: < 15 GB free.

## Versions
Network protocol 7, round snapshot format 2, gameplay config 2, C ABI 1.4, level format 4, canonical topology 3.
Odin `dev-2026-05-nightly:ea5175d`, .NET 10, MSVC 14.51 / Windows SDK 10.0.26100.0, Unity 6000.2.14f1 (Mono + IL2CPP).
Change a version only when the wire or file layout it names actually changes.

## Commands (PowerShell, from this repo's root)
- Game: `.\scripts\bom.ps1` (Run) / `Build` / `Test` (220 tests) / `NetTest` / `Smoke*` / `Soak` / `ReplicationSoak`.
- Client core: `.\scripts\build-client.ps1 -ConfigPath <local.config.json>`, `.\scripts\test-client-core.ps1 -ConfigPath ...`
  (shared, transport, FFI suites; also regenerates `bindings/`).
- Unity side (Unity repo): `integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content|NativeInterop|Rounds|...`
  (pass `-ConfigPath` explicitly when launching from Git Bash/`-File`), `Build-OwnerNative.py` (matching native
  checkpoint), `Test-UnitySoak.ps1 -SkipBuild -PrimaryPlayer ... -GuestPlayer ...` (30-minute reset-under-load soak),
  `Package-BomWindows.ps1`, `Start-BomNetwork.ps1`.

## Always ask before
Any push or pull request; merging into the Unity default branch; changes to `Documents\BOM` beyond what the task
states; changes to existing physics or destruction behaviour; actions only the owner can do (system settings).

## State and open items
- History: `Baseline: working tree before Unity integration` (tree differs from the M0 import by one file, the old
  root `src.zip`, which the owner deleted on purpose), then `integration/odin-unity` merged. Nothing is pushed.
- Passed on protocol 7: 220 game tests from merged master, transport/shared/FFI suites, native soaks,
  prediction profiles, 30-minute Mono+IL2CPP reset-under-load soak.
- Open: Unity authority audit and scene-play logs, artist guide, LAN guide, release launcher on PowerShell 5.1 and 7,
  human checks (game feel, two-machine LAN, an artist adding an object). Task 9 is findings only.
