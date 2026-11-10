# BOM integration

M0-M9 passed. Current Mono/IL2CPP builds, Windows package, reproducible tools and
executed evidence are available. See STATUS.md and evidence/M9/summary.json.

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


## Unified build, test and package commands

Use PowerShell 7 and the pinned local.config.json paths. Keep UnityValidationProject
as a separate copy; build tools do not change the source project's build settings.
Native source is maintained on integration/odin-unity-20261105 in the extracted
BOM repository. The native patch and raw-byte source overlay are retained under
patches/ so the archive's uncommitted starting contents can be reproduced.

```powershell
./integration/tools/Invoke-BomIntegration.ps1 -Task VerifyEnvironment
./integration/tools/Invoke-BomIntegration.ps1 -Task Build -Backend Both
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Fast
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite FullNative
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite NativeInterop
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite UnitySlice -Backend Both
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Prediction
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Soak -Seconds 1800
./integration/tools/Invoke-BomIntegration.ps1 -Task Launch -LaunchMode IL2CPP
./integration/tools/Invoke-BomIntegration.ps1 -Task Package
```

Build includes the dedicated server, Odin observer, shared native DLL, both Unity
backends, and matching native/managed/IL2CPP debug symbols. Unity builds are written
to integration/build/validation rather than overwriting frozen milestones. If the
validation copy is new, Build-BomPlayers.ps1 copies Assets, Packages and
ProjectSettings there. It then refreshes only the derived SDK and native plugin.
Close that validation Editor before rebuilding. The normal source Editor may stay
open. Original scenes remain single-player reference content.

Fast runs the focused shared-client/API suite and transport tests. FullNative also
runs the original game tests. NativeInterop compiles the C caller and .NET caller
against the actual DLL. UnitySlice exercises the real player/Editor bridge;
Rounds and Performance are additional Suite values. Prediction runs all pinned
impairment seeds (42, 137, 2026) through actual sockets, with positive one-way
jitter, at the documented 100/200 ms RTT profiles. The recorded expanded matrix
also covers 30/60/144 Hz. No Unity wire decoder is involved.

For existing player builds, Test-UnitySoak.ps1 accepts -SkipBuild, -PrimaryPlayer
and -GuestPlayer. Test-Performance.ps1 accepts -Load Reference or Stress and -Tier1
for extrusion. Run build and test tasks serially when they share an output folder.
The soak's native host controller is built from integration/soak-host using the
same generated bindings as the clients. It is a native API caller, not a codec.

## Windows package

Package-BomWindows.ps1 accepts -MonoPlayer, -Il2CppPlayer and -OutputDirectory.
It requires a new destination and verifies both embedded DLL hashes. The package
contains complete Mono and IL2CPP player directories, Server, Symbols, a SHA-256
manifest, a yard layout, developer instructions, and Launch-Bom.ps1. Players start
in the original-art network menu; benchmark drivers activate only with explicit
test arguments. PowerShell 7 is needed for the convenience launcher; the game
executables do not require the Unity Editor or Odin compiler.

```powershell
./Launch-Bom.ps1                    # two Mono windows and a local server
./Launch-Bom.ps1 -Backend IL2CPP     # two IL2CPP windows
./Launch-Bom.ps1 -Clients 1
```

The first window is host. A/D or arrows move, Space jumps, Esc opens the menu.
The host selects Sandbox or Elimination there. The dedicated server defaults to
127.0.0.1; --bind accepts a numeric IPv4 address. A non-loopback bind requires a
random --host-token of 16-128 bytes. Launch-Bom.ps1 -Bind 0.0.0.0 explicitly enables
other interfaces while retaining the generated host key. A second physical
machine was unavailable: alternate-loopback binding is tested, physical LAN
coverage is a reported limit. There is no account persistence across server exit;
resume credentials and the bounded 128-session table are server-session scoped.

## Profiling and ownership notes

The 475-cell reference fixture has 400 independent wood bodies and a 75-cell fixed
floor; stress has 975 cells and 900 independent bodies. They are generated playable
load fixtures, not a reduced copy of the preserved 4,615-cell yard. Bodies are small
because the unchanged wood recipe otherwise subdivides them beyond the reference
cell budget. Authoring previews are hidden in players; all physical body visuals
come from native poses. The original yard is also exercised by the round gate.

Profiling uses 1920x1080 D3D11 standalone windows shown without activation. Hidden
windows produced black backbuffers and no GPU timings and are not rendered-frame
acceptance evidence. CPU/GPU timings include their recorded workload; raw rows,
spikes, reset intervals, counters, backend and hardware are retained. Source mesh
uploads use 256-triangle chunks and a 1.5 ms scheduling threshold to leave margin
for the 2 ms target. Cold source reads and upload costs are reported separately;
a scheduling threshold is not a guarantee against operating-system preemption.

The Mono .NET thread-allocation counter returned zero even for an escaped 4 KiB
allocation. It is not used as zero-allocation proof. A positive-control-validated
current-thread GC.Alloc recorder counts allocation events in native copy,
presentation and geometry scopes. Unity's separate frame counter records total
allocation bytes, including instrumentation, engine, UI and effects. Stable pose
frames exclude topology/actor changes and active/pending geometry work.

Per-source jobs use two workers, at most 128 queued requests and 64 MiB of staging
reservations. The CPU geometry cache is 112 MiB, GPU cache 128 MiB and combined
presentation budget 256 MiB including fallback reservations. Idle actor pools hold
at most 32 objects per prefab. Teardown checks native handles/Odin bytes, Box2D
allocation baselines, actor views, generated meshes, cache bytes and worker buffers.
Native server and raw observer diagnostic histories use bounded recent samples;
full-run totals remain cumulative. Server timing distributions are rolling when
the 65,536-sample capacity is reached; whole-loop overrun logs are also retained.

The native fingerprint covers raw source bytes, so restore the exact source overlay
before reproducing its tag. The manifest records its sorting culture (en-CA),
compiler, optimization and -debug option; set the recorded culture when rebuilding
elsewhere. Matching PDBs are packaged. Native debugger source paths can refer to
the build script's temporary package directory: add the extracted native src folder
to the debugger's source search path if requested.


To restore source into a dedicated copy of the supplied BOM archive:

```powershell
./integration/tools/Restore-NativeOverlay.ps1 -NativeRoot C:/path/to/extracted/BOM -AllowOverwrite
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo('en-CA')
```

The helper verifies the overlay hash, confines every output to the chosen project
root, and verifies every restored file. It does not delete archive files or edit
Git history. Use a dedicated source copy because the overlay deliberately replaces
integration source paths. The raw overlay preserves line endings for the native
source tag; the Git patch is also included for review.
