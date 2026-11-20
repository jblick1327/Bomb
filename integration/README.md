# BOM integration

M0-M9 passed. Current Mono/IL2CPP builds, Windows package, reproducible tools and
executed evidence are available. Paths in this file are relative to the Unity repository's `integration/`
folder (in a package this file is `DEVELOPER-README.md`; those files are in the repository, not the package).
See `STATUS.md` and `evidence/M9/summary.json` there.

Odin owns physics, destruction, networking, input scheduling, prediction and
rounds. Unity copies the native C ABI snapshots and supplies input/presentation.
Original Unity assets, GUIDs, prefabs, scenes and packages remain protected.

## Play from the main menu (C5)

The game player `Bomb.exe` (built by `Test-FrontDoor.ps1`, `BomFrontDoorBuilder.BuildMono`) starts at Darryn's
`MainMenuScene`. OFFLINE is his local mode, unchanged (D4). ONLINE opens Odin play over LAN or direct IP (D3):

- **Host game:** pick a level (CLASSIC YARD, or Darryn's YARD, BRIDGE and TOWER from C6), a UDP port (default 47380) and who may join:
  *This PC only* binds the server to 127.0.0.1; *LAN / direct IP* binds 0.0.0.0 and the host's Esc menu lists the
  addresses other PCs type in. START launches `BOM-server.exe --bind <ip> --port <port> --layout <level json>
  --host-token <random>` with no window, waits for its "listening" line (60 s limit), loads the level and connects to
  127.0.0.1 with the same token, passed in memory to `ConnectTo` (no `BOM_TEST_HOST_TOKEN`). The token is 24 random
  bytes per hosting; it is visible on the server's command line to programs on the same PC, nowhere else.
- **Busy port:** the host probes the port with an exclusive bind and also watches the server for
  `Could not bind UDP port`; it then tries the next port (10 in all) and says which port it used. The Esc menu shows it.
- **Join game:** address (dotted IPv4; 127.0.0.1 for the same PC), port (1-65535) and the level the host picked
  (the guest loads that level's scene; the server refuses a guest whose level differs, "manifest mismatch").
- **Leaving:** RETURN, LEAVE GAME and *Main menu* in the Esc menu disconnect and load the main menu. A host's server
  ends itself when its host leaves ("SERVER host-left shutdown"); it is killed after 6 s if it has not. Quitting kills it
  at once. Every server is also placed in a Windows job object with kill-on-close, so a crash or a Task Manager kill of
  the player takes the server down too.
- **Where the server lives:** `Server/BOM-server.exe` and `Server/levels/<level>.json` next to the game exe (the
  build copies them there). Fallback for today's BOM-Windows package layout: `../Server/BOM-server.exe` and
  `../yard.json`. `--bom-server <exe>` and `--bom-levels <folder>` override both. F4 packages this.
- **Firewall:** *This PC only* binds loopback, which Windows Firewall does not prompt for (the gate runs this way). The first *LAN / direct IP* host is expected to get Windows' "Windows Security Alert ... has blocked some
  features of BOM-server.exe" dialog (not triggered by the gate, which never binds 0.0.0.0 on the owner's machine);
  tick **Private networks** and press Allow, or other PCs cannot reach it (play on the host PC still works). The host
  screen warns about this before START. Each new build folder is a new program path to Windows, so it may ask again.
- Server output goes to `bom-server-<time>.log` next to the player log.

Gate: `./integration/tools/Test-FrontDoor.ps1 -ConfigPath integration/local.config.owner-validation.json [-Level Yard|Bridge|Tower]`
(evidence in `evidence/M8/frontdoor-*`, `frontdoor-<level>-*` with `-Level`). The build also exports Darryn's three tile levels
(`Editor/BomTileLevelBuilder.cs` v2, G5: the design doc section 3 mapping in `Editor/BomTileMapping.cs`) to
`integration/fixtures/levels/<Scene>.json` (+ `.tiles.json`, the per-tile mapping and parts; `.tiles-input.json`, the mapping
input) and copies them to `Server/levels/`. Invariants I1-I4 fail the export; their negative tests run without Unity:
`dotnet run --project integration/tools/g5/TileMappingTests -- test`. It mirrors nothing outside `Assets/BOMIntegration`: copy `Assets/Game/Scripts/MatchMenuUI.cs`
to the validation project first if it changed (the tool checks).

## Play the network yard

From the Unity repository, using Windows PowerShell 5.1 or PowerShell 7:

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
starts in sandbox. Elimination admits 2-4 natively validated ready players (it
starts once at least two are ready), counts down 180 server ticks, resolves all deaths on a tick together, and awards session
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

Current SDK/players use ABI 1.6, game protocol 9 (round snapshot format 4, gameplay config 5),
level format 4 and canonical topology 3.
`build/Network-Mono` and `build/M8-native` form one compatible checkpoint. Frozen
M5, M6 and M7 artifacts retain their original versions; never mix their servers
and DLLs. The older `Start-BomDemo.ps1` remains the frozen M5 demonstration.

Evidence and failed attempts remain under `evidence/M*`. M8 includes real UDP,
two-Unity forfeit and simultaneous-draw runs, an independent Odin observer,
repeated event presentation, native-driven movement/jumps and rendered captures.
See `contracts/round-rules.md` and `contracts/source-mesh-rendering.md` for rules
and ownership. M8 presentation tests disable prediction; static prediction was
validated separately in M5. Dynamic-yard prediction and performance were validated
in M9 (six 600-second prediction profiles and the 30-minute reset-under-load soak)
and rerun after each native checkpoint (latest: E1-N4, protocol 9); see `evidence/M9/`.


## Unified build, test and package commands

Use Windows PowerShell 5.1 or PowerShell 7 and the pinned local.config.json paths. When a tool is
started with `-File` from another shell, pass `-ConfigPath` explicitly. Keep UnityValidationProject
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

`Package-BomWindows.ps1` accepts -MonoPlayer, -Il2CppPlayer and -OutputDirectory (a new folder; existing packages are kept).
Since F4 it packages the front-door game `Bomb.exe` (MainMenuScene first; built by `Build-BomGame.ps1 -Backend Both`
into `build/validation/Game-Mono` and `Game-IL2CPP`), not the old network-menu player. It verifies both embedded DLL
hashes and the server hash. The package has complete `Mono/` and `IL2CPP/` game folders (each with its own
`Server/BOM-server.exe` and `Server/levels/{yard,YardLevel,BridgeLevel,TowerLevel}.json`), Symbols, a SHA-256 manifest,
developer instructions, README.txt and Launch-Bom.ps1. The convenience launcher runs under Windows PowerShell 5.1 or
PowerShell 7; the game executables do not require the Unity Editor or Odin compiler.

```powershell
./Launch-Bom.ps1                    # two Mono windows at the main menu
./Launch-Bom.ps1 -Backend IL2CPP     # two IL2CPP windows
./Launch-Bom.ps1 -Clients 1 -Lan     # one window; prints this PC's addresses for a LAN game
```

The launcher only opens windows; the game starts and stops its own server (ONLINE > HOST GAME > START, then JOIN GAME in
the other window). `Test-FrontDoor.ps1 -Backend Mono|IL2CPP -SkipBuild -PlayerPath <package>/<Backend>/Bomb.exe` plays a
scripted round against a package. The dedicated server defaults to 127.0.0.1; a non-loopback bind requires a
random --host-token of 16-128 bytes, which the game generates. A second physical
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

## Rebuilding the native library

Run this whenever the Odin source (`C:\Users\jblic\Documents\BOM`) changes in `src/shared`, `src/netcode`, `src/ffi`
or `bindings`, or before any player build that must match the current server:

```powershell
python integration/tools/Build-OwnerNative.py --config integration/local.config.json
```

It builds the server, dev client and `bomcore.dll` from a fresh copy of the Odin source (the source repo is never
written), writes `bomcore.build.json`, copies the DLL, `BomNative.cs`, the build record and the generated
`BomExpectedNativeIdentity.cs` into `Assets/BOMIntegration`, verifies the copied DLL's SHA-256, and writes
`local.config.owner-validation.json` for the test tools. **Close every Unity Editor that has this project open before
running it, and restart the Editor afterwards**: a loaded native plugin cannot be replaced by a domain reload.
Rebuild the Mono/IL2CPP players after it (`Build-BomPlayers.ps1`).

Identity guard: before connecting, `BomNativeIdentity.Verify()` compares the loaded library's ABI, protocol, canonical
version, build tag and the file's SHA-256 with `BomExpectedNativeIdentity`. On a mismatch Unity refuses to connect and
reports: "Cannot connect: bomcore.dll does not match this client. Run the native rebuild command, rebuild the player if
needed, and restart the Unity Editor after changing the DLL."
