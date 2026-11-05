# BOM integration checkpoint

Follow PLAN.md and STATUS.md. Original Unity assets remain frozen; new runtime integration is not implemented yet.

The sources remain separate: this Unity checkout and the extracted Odin archive. Copy local.config.example.json to local.config.json, supply absolute local paths, and keep the latter ignored. Requires the documented Odin May 2026 compiler and bundled native vendors, Unity 6000.2.14f1, .NET, and Windows C++ tools.

```powershell
./integration/tools/Invoke-BomIntegration.ps1 -Task VerifyEnvironment
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content
./integration/tools/Invoke-BomIntegration.ps1 -Task Build
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Fast
```

Content checks compare every recorded original Unity file byte and meta GUID, permit additive new files, and fail if an original file is absent or modified. They do not establish runtime correctness. Odin content manifests record pre-refactor provenance, rather than freezing the source code that this integration must change. NativeInterop runs the proof-only native/C/.NET lifecycle and layout gate. Fast invokes the repository's existing Odin Test and NetTest commands. Environment verification fails on unavailable prerequisites. No unimplemented milestone is reported as passing. Evidence is written under evidence/M0. Runtime/soak, native interop, scene and packaging commands remain to be implemented after their gates.

```powershell
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite NativeInterop
```

The tiny proof exports are deliberately separate from the future bomcore API. No network functionality, gameplay bridge or Unity native host has shipped.
