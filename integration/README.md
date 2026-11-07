# BOM integration

This branch contains a real native-connected Unity scene at `Assets/BOMIntegration/NativeSlice.unity`. Odin owns gameplay, networking and physics. Unity polls the versioned native API, copies coherent samples, and renders extrusion meshes and actor views. The original scenes, scripts, art and package/settings files remain reference content.

M0–M5 passed. Scheduled input, owner reconciliation and genuine local prediction pass the two required ten-minute link profiles; final Mono prediction on/off and actual rendered response checks pass. M6 level authoring/export is in progress; M7–M9 remain pending. The earlier M4 Mono/IL2CPP evidence remains preserved. See STATUS.md and evidence/M5/summary.json; the full plan is not complete.

The source roots remain separate. `source-lock.json` records archive/toolchain/native commit identities. The ignored `local.config.json` supplies absolute local paths; use `local.config.example.json` for another machine. Unity stays on 6000.2.14f1 and the supplied Odin May 2026 compiler/vendor setup remains pinned.

```powershell
./integration/tools/Invoke-BomIntegration.ps1 -Task VerifyEnvironment
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content
./integration/tools/Invoke-BomIntegration.ps1 -Task Build
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Fast
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite NativeInterop -Seconds 600
./integration/tools/Test-UnitySlice.ps1 -Backend Mono -TimeScale 0
./integration/tools/Test-UnitySlice.ps1 -Backend IL2CPP
./integration/tools/Test-UnitySlice.ps1 -Backend Editor
./integration/tools/Start-BomDemo.ps1 -Play
```

Unity validation uses a separate project copy named in `UnityValidationProject`; it never stops the owner's Editor. Close the dedicated validation Editor before copying a native plugin. `NativeInterop` exercises the real polling client and UDP processes. `NativeProof` retains the small M1 boundary proof separately. `Fast` invokes the existing game and transport regressions. `Content` compares all 605 protected starting files, including metadata GUIDs, packages and settings, while allowing additive integration assets.

The live launch tool waits for usable Unity snapshots before starting the timed scenario. It uses one native host handle, two Unity players and one Odin observer within the original four-client server limit. Hash coverage lists expected/reported revisions per connection; a missing report is never counted as a match. Generated local builds and logs live under ignored build/local directories; milestone evidence and source patches are committed.

For an interactive demo, `Start-BomDemo.ps1 -Play` opens the configured standalone player and a local native server. A/D or arrows move, Space jumps and left-click requests a blast. Close the player to stop the demo. Current diagnostics default to sandbox with native prediction enabled; --bom-prediction-off selects ordinary interpolation. Authored yard export, source-art clipping and elimination remain in progress or pending.

The authored yard is `Assets/BOMIntegration/NetworkYard.unity`. Export creates explicit native gameplay proxies, a validated layout, a preprocessing/classification report, and a runtime registry with direct mesh/material references. Runtime gameplay geometry comes from the native server. The current required source-art clipping stage is still pending.

```powershell
./integration/tools/Test-UnityYard.ps1 -Backend Mono
./integration/tools/Test-UnityYard.ps1 -Backend Mono -SkipBuild -MissingArt
./integration/tools/Test-UnityYard.ps1 -Backend Mono -SkipBuild -RejectManifest
```

These yard gates use the current native source build (protocol 5), not the frozen protocol-4 demo. They keep raw failed attempts and actual rendered captures under evidence/M6. The expected gameplay fingerprint comes from the native export report, and the live test checks that the standalone plugin matches its native build identity.
