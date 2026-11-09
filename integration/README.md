# BOM integration

M0â€“M8 passed. M9 hardening, performance, current IL2CPP and the final 30-minute
soak remain in progress. This is a local developer checkpoint, not completion of
the full integration plan.

Odin owns physics, destruction, networking, input scheduling, prediction and
rounds. Unity copies the native C ABI snapshots and supplies input/presentation.
Original Unity assets, GUIDs, prefabs, scenes and packages remain protected.

## Play the network yard

From the Unity repository, using PowerShell 7:

```powershell
./integration/tools/Start-BomNetwork.ps1
```

This starts a local server and two visible Unity windows. The first is the host.
A/D or arrows move, Space jumps, and Esc opens the connection menu. The host can
select Elimination and apply it there. Sandbox blast tools are host-only. The
host can restart a finished round. Closing the host preserves the existing
five-second server shutdown policy. Use `-Clients 1` or `-Port 47381` if needed.

The standalone menu covers endpoint/port, host key, spectator role, loading,
rejection, disconnect, reconnect, game mode, host restart and quit. The server
starts in sandbox. Elimination waits for two validated player baselines, counts
down 180 server ticks, resolves all deaths on a tick together, and awards session
XP once. Rejoining during play spectates until a later round. Results survive a
reconnect; account persistence is outside scope.

The new scene is `Assets/BOMIntegration/NetworkMenu.unity`; the original-art
network yard is `NetworkYard.unity`. `RoundDraw.unity` is a small explicit fixture
for same-tick falling-bomb deaths. Claymate/animations, bomb/fuse materials,
the original blast-ring animation and HUD UXML/USS are reused through read-only
adapters. The source project contains no audio clips to reuse.

## Reproduce checks

```powershell
./integration/tools/Invoke-BomIntegration.ps1 -Task VerifyEnvironment
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Fast
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite NativeInterop
./integration/tools/Test-NetworkRounds.ps1 -SkipBuild
./integration/tools/Test-NetworkRounds.ps1 -Scenario Draw -SkipBuild
```

Builds/tests use the separate project in ignored `local.config.json`. Never copy
a replacement native library into a running Editor: restart the dedicated
validation Editor between builds, and restart an owner-open Editor before using
an updated native plugin. No manual Inspector wiring is required.

The pinned environment is Windows x64, Unity 6000.2.14f1, Odin May 2026 ea5175d,
MSVC/Windows SDK, .NET 10 and Python 3. See `local.config.example.json` for paths,
`source-lock.json` for exact inputs/build identities, and `STATUS.md` for next work.

Current SDK/players use ABI 1.4, game protocol 6 and canonical topology 3.
`build/Network-Mono` and `build/M8-native` form one compatible checkpoint. Frozen
M5, M6 and M7 artifacts retain their original versions; never mix their servers
and DLLs. The older `Start-BomDemo.ps1` remains the frozen M5 demonstration.

Evidence and failed attempts remain under `evidence/M*`. M8 includes real UDP,
two-Unity forfeit and simultaneous-draw runs, an independent Odin observer,
repeated event presentation, native-driven movement/jumps and rendered captures.
See `contracts/round-rules.md` and `contracts/source-mesh-rendering.md` for rules
and ownership. M8 presentation tests disable prediction; static prediction was
validated separately in M5. Dynamic-yard prediction and performance remain M9
work and are not implied by the round correctness gates.
