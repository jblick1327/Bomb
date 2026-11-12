# BOM developer README (Windows package)

Current versions: ABI 1.6, game protocol 9 (round snapshot format 4, gameplay config 5), level format 4,
canonical topology 3. Unity 6000.2.14f1, Windows x64.

Odin owns physics, destruction, networking, input scheduling, prediction and rounds. Unity copies the native C ABI
snapshots and supplies input and presentation. Original Unity assets, GUIDs, prefabs, scenes and packages remain
protected. No Unity Editor or Odin compiler is needed to play.

## Package contents

- `Launch-Bom.ps1`: starts the local server and game windows. Works in Windows PowerShell 5.1 and PowerShell 7.
- `Mono/` and `IL2CPP/`: complete player directories (`BombPerformance.exe`). Keep each directory's files together.
- `Server/`: `BOM-server.exe`, `BOM.exe`, `bomcore.dll`, `bomcore.build.json`.
- `Symbols/`: debug symbols for the native library and each player backend.
- `yard.json`: the network yard layout.
- `manifest.json`: SHA-256 and size of every file in the package, plus the native identity.
- `README.txt`: short start-up note. This file is the full developer note.

`Logs/` is not shipped. `Launch-Bom.ps1` creates it at run time, one folder per session, and writes the player
logs and `bom-server-<time>.log` there.

## Play

```powershell
powershell -ExecutionPolicy Bypass -File .\Launch-Bom.ps1
```

| Option | Meaning |
| --- | --- |
| `-Backend Mono` (default) or `IL2CPP` | Which player build to start. |
| `-Clients 1` or `2` (default 2) | Number of game windows. The first is the host. |
| `-Port` (default 47380) | UDP port of the local server. |
| `-Lan` | Host for other PCs: the server binds every interface and the host's Esc menu lists the addresses to share. |
| `-ClientOnly` | On a second PC: start only a game window. Type the host's address and port in its connection menu. |

Controls: A/D or arrows move, Space jumps, Esc opens the menu. The host selects Sandbox or Elimination there,
can restart a finished round, and can apply sandbox blast tools. Elimination admits 2-4 ready players and starts
once at least two are ready. Rejoining during play spectates until a later round.

### Main menu (online)

OFFLINE is the local mode. ONLINE opens play over LAN or direct IP:

- **Host game:** pick a level, a UDP port (default 47380) and who may join. *This PC only* binds the server to
  127.0.0.1. *LAN / direct IP* binds 0.0.0.0. START launches `BOM-server.exe` with no window, waits for its
  "listening" line (60 s limit), then connects to 127.0.0.1 with a random host token (24 bytes per hosting),
  passed in memory and never written to disk. The token is visible on the server's command line to programs on
  the same PC only.
- **Busy port:** the host tries the next port (10 in all) and says which port it used. The Esc menu shows it.
- **Join game:** address (dotted IPv4; 127.0.0.1 for the same PC), port (1-65535), and the level the host picked.
  The server refuses a guest whose level differs ("manifest mismatch").
- **Leaving:** RETURN, LEAVE GAME and Main menu in the Esc menu disconnect and load the main menu. A host's server
  ends itself when its host leaves ("SERVER host-left shutdown"), and is killed after 6 s if it has not. Quitting
  kills it at once. Every server is placed in a Windows job object with kill-on-close, so a crash or a Task Manager
  kill of the player takes the server down too.
- **Firewall:** *This PC only* binds loopback, which Windows Firewall does not prompt for. The first *LAN / direct
  IP* host normally gets Windows' "Windows Security Alert ... has blocked some features of BOM-server.exe" dialog.
  Tick **Private networks** and press Allow, or other PCs cannot reach it (play on the host PC still works). Each new
  build folder is a new program path to Windows, so it may ask again.
- **Where the server lives:** the player finds `BOM-server.exe` at `../Server/BOM-server.exe` and the yard at
  `../yard.json`, relative to the player's folder. `--bom-server <exe>` and `--bom-levels <folder>` override both.
  The package currently ships only the yard layout. The menu's other levels (Darryn's YARD, BRIDGE and TOWER) read
  `Server/levels/<level>.json`, which this package does not yet include.

### Server behaviour

The dedicated server defaults to 127.0.0.1. `--bind` accepts a numeric IPv4 address; a non-loopback bind requires a
random `--host-token` of 16-128 bytes. There is no account persistence across server exit. Resume credentials and
the bounded 128-session table are scoped to one server session. Results survive a reconnect within that session.

## Native library identity

Before connecting, the client calls `BomNativeIdentity.Verify()`. It compares the loaded `bomcore.dll`'s ABI,
protocol, canonical version, build tag and SHA-256 with the build's expected identity. On a mismatch the client
refuses to connect. The identity is recorded in `manifest.json` and `Server/bomcore.build.json`. Keep the
complete package together: a client and server from different builds will not match.

## Known limits

- Two physical PCs on one LAN have not yet been verified; loopback and alternate-loopback binding are tested.
- Human checks (game feel, two-machine LAN, adding an object) are still open.

## Performance notes

- The reference fixture has 475 cells (400 independent wood bodies on a 75-cell fixed floor). The stress fixture
  has 975 cells and 900 bodies. These are generated load fixtures, not a copy of the original 4,615-cell yard. Bodies
  are small because the unchanged wood recipe otherwise subdivides them beyond the reference cell budget.
- Authoring previews are hidden in players. All physical body visuals come from native poses.
- Profiling uses 1920x1080 D3D11 standalone windows shown without activation. Hidden windows produce black
  backbuffers and no GPU timings.
- Source mesh uploads use 256-triangle chunks and a 1.5 ms scheduling threshold. Cold source reads and upload costs
  are reported separately. A scheduling threshold is not a guarantee against operating-system preemption.
- Budgets: CPU geometry cache 112 MiB, GPU cache 128 MiB, combined presentation budget 256 MiB, at most 32 idle
  actor objects per prefab, two worker threads with at most 128 queued requests and 64 MiB of staging.
- The Mono .NET thread-allocation counter is not zero-allocation proof. Use Unity's frame counter with its
  instrumentation caveats.
- Matching PDBs are packaged. Native debugger source paths can point at the build's temporary package directory;
  add the extracted native source folder to the debugger's search path if needed.
- The IL2CPP backup directory name is kept in `Symbols/` to preserve debugger paths.
