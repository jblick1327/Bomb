# Task 9: remaining gaps (findings and estimates only, nothing implemented, nothing scheduled)

Effort is development time for one person including re-running the affected gates; build time (about 11-21 minutes per player) is extra.

## 1. First-fracture hitches (cold read 11.9 ms, cold upload 6.7 ms)
**Facts.** `evidence/M9/summary.json` records `max_source_read_ms` 11.92 and cold upload 6.69 ms; warmed reads/uploads peak at 3.60 ms.
Source meshes are read in `BomSourceMeshData` (needs `isReadable`; first touch of a mesh pays the page-in) and uploaded in
4,096-triangle chunks by `BomSourcePresentation` under a 1.5-2 ms scheduling budget. Individual Unity calls are not interruptible, so a
cold single call can exceed the budget; the 11.9 ms hitch is one such call.
**Options.**
- *Warm at load* (recommended first): while the client is in its loading state (before the native baseline is accepted), touch the readable
  index/vertex data of every intact source mesh and run one throw-away upload through the existing job queue, so the first real fracture finds
  warm memory and uploaded buffers. Effort: 0.5-1 day plus a re-run of the M9 performance profile. Risk: slightly longer load; must respect
  the 256 MiB cache cap and stay off during reset/reconnect fences.
- *Pre-build at export*: have `BomMeshPreprocessor` emit the clipped/chunked arrays so runtime does no read at all. Effort: 3-5 days; changes
  the export format and cache keys (protected-content and source-mesh contract updates). Only worth it if warming leaves hitches.
**Expectation.** Warming should remove the read spike; the cold upload may shrink to the warm 3.6 ms level but a driver-side first-use cost can remain.

## 2. Release (non-development) Mono and IL2CPP players
**Facts.** All five player builds in `Assets/BOMIntegration/Editor` pass `BuildOptions.Development`; none of the runtime code branches on
`Debug.isDebugBuild`/`DEVELOPMENT_BUILD`, so nothing depends on development-only behaviour. Test/measurement hooks (`--bom-perf-*`, `--bom-soak-*`,
`--bom-time-scale`, `BomPerformanceProbe`) are compiled into every build, including release; `BOM_TEST_HOST_TOKEN` is also the real host-key
mechanism the launcher uses. `PlayerSettings.enableFrameTimingStats` is on (works in release). No `link.xml` exists and managed stripping is the
project default; `BomNative` P/Invokes and `JsonUtility`-serialised types could be stripped under IL2CPP high stripping.
**Needed.** (1) A build mode without `Development` (and without script debugging/profiler autoconnect) in `BomPerformanceBuilder`/package tools;
(2) decide whether test hooks stay (recommended: gate the `--bom-perf/soak/time-scale` arguments behind a compile symbol or an explicit
`--bom-enable-test-hooks` flag so a shipped player cannot be speed-hacked or scripted by command line; `--bom-time-scale` matters most);
(3) add a `link.xml` preserving `Bom.Native` and the JSON types, and build IL2CPP at the project's default stripping; (4) re-run the identity
guard, prediction profiles (frame timing differs without the development overhead) and the 30-minute soak on release players.
**Effort.** Mono release: 1 day. IL2CPP release plus stripping fix: +1-2 days. Re-measurement is the main cost (about 1.5 hours of unattended runs).
Note the Burst `lib_burst_generated.dll` is shipped in both packages and is still produced in release.

## 3. Fresh-machine dependencies
Checked by reading each binary's PE import table (this machine; not a clean-VM test).
| Component | Runtime dependencies | Packaged? |
| --- | --- | --- |
| `Server/BOM-server.exe` | only Windows system DLLs: kernel32, ntdll, advapi32, ws2_32, bcrypt. No Visual C++ runtime. UDP port (default 47380), firewall rule for LAN. | n/a (system) |
| `bomcore.dll` (in server folder and each player) | kernel32, ws2_32, bcrypt. No VC++ runtime. | yes |
| `Server/BOM.exe` (Odin dev client/observer, packaged for diagnostics) | **vcruntime140.dll**, UCRT, opengl32, gdi32, user32, winmm. | **No:** needs the VC++ 2015-2022 x64 redistributable and OpenGL; not needed to play |
| Mono player | `UnityPlayer.dll` (packaged) -> system d3d11, dxgi, dwmapi, winhttp, crypt32, hid etc.; managed runtime `MonoBleedingEdge` (packaged). | yes |
| IL2CPP player | `GameAssembly.dll` (packaged) + `UnityPlayer.dll`; imports only system DLLs plus the bundled `baselib.dll`. | yes |
| Both players | A GPU with a DirectX 11 (or 12, `D3D12` folder is packaged) driver. 64-bit Windows 10/11 (Unity 6 player requirement). No Unity Editor or Odin compiler. | driver: user |
| Windows Firewall | Inbound UDP allowance for `BOM-server.exe` on LAN hosts (guide in `docs/lan-test.md`). | user |
| PowerShell | The launcher runs in Windows PowerShell 5.1 (built in) and 7 (verified). | built in |
A clean-machine run is still outstanding (`BOM.exe`'s missing VC++ runtime is the only gap found; recommend moving it to the developer-only
symbols folder or documenting it). Effort: 0.5 day for a clean-VM smoke test plus the package tweak.

## 4. Audio hook points (project has no clips; `original_audio_clips` audit counts none)
Unity should only react to native events, never decide them. Existing hooks, all in `BomClientBehaviour` / presentation:
- **Explosion:** the native event loop (`for i < s.event_count`, instantiating `BlastPrefab`/`BomExplosionView` with `e.x, e.y, e.radius`, event id
  de-duplicated by `lastEvent`). Add one `AudioSource.PlayClipAtPoint` per new event id, radius scaling volume/pitch. Fires once per event across
  prediction re-sync because ids are monotonic.
- **Landing/jump/footsteps:** `BomActorView.Apply(pose, correction)` receives the predicted/acquired pose each presentation frame; derive a landing
  from the actor's vertical velocity sign change only for presentation, or ask Odin to expose a grounded/landed flag in the actor pose (an ABI
  addition, would need an owner decision since it changes ABI 1.4).
- **Fracture/debris:** `BomSourcePresentation` job completion (new cut pieces) for a break sound, rate-limited with the existing 2 ms scheduler.
- **Round events:** `BomRoundScenario`/`BomNetworkHud` already observe `round.state`, `winner`, `draw`; hook countdown ticks, round start, elimination,
  win/draw there.
- **Listener:** exactly one `AudioListener` is enabled on the camera by `BomYardBuilder`; original scenes' listeners are disabled in the yard.
**Effort.** Event-driven mixer with explosion, round and UI sounds: 2-3 days plus clip sourcing/licensing. Landing/footsteps via a native flag: +1-2 days
and an ABI decision. Mute/volume setting in the menu: 0.5 day.

## Picking what to schedule
Smallest high-value order: (3) package tweak and clean-VM test, (1) warm at load, (2) Mono release with test-hook gating, then (4) audio. None is scheduled.
