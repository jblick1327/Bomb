# BOM integration completed

M0–M9 passed. The Unity project is at `C:\Users\rober\OneDrive\Documents\GitHub\Bomb`.

## Play

Run `outputs/BOM-Windows/Launch-Bom.ps1` with PowerShell 7, or extract BOM-Windows-Game.zip and run Launch-Bom.ps1 there. This opens a local server and two Mono clients. Use `-Backend IL2CPP` for the compiled client. A/D or arrows move, Space jumps, Esc opens the connection menu. The first window hosts the session and can select Elimination or restart a finished round.

## Downloads

- [Windows game and server](BOM-Windows-Game.zip)
- [Matching debug symbols](BOM-Windows-Symbols.zip)
- [Native source overlay](BOM-Windows-Source-Overlay.zip)

The repository includes the Unity source, original-content manifest, native overlay/patch, build tools, configuration example, source identities and raw test evidence under integration/.

## Verified

- Final 30-minute real-process soak: mixed Mono/IL2CPP clients, native server/observer/controller, 183 resets, 511 accepted overlapping-blast ticks; all five exited normally. No incorrect authoritative hash, stale application or tracked resource leak.
- Six ten-minute prediction profiles across three seeds and 30/60/144 Hz; typical and adverse links passed.
- Original 220 game tests, 27 transport tests, 79 shared tests and 20 ABI tests passed. Native C/.NET ABI checks, actual Mono/IL2CPP rounds and source geometry checks passed.
- All 605 protected original Unity files match the baseline. Four pre-existing metadata deletions remain untouched.
- Isolated 1080p reference: 475 cells, 400 independently moving bodies. Native update p95 0.400/0.386 ms; p99 0.670/0.660 ms. Stable pose/render paths recorded zero allocation events. Detailed CPU/GPU frame distributions and raw rows are retained.

## Measured limits

The mesh scheduler uses a 1.5 ms threshold and split uploads. Individual Unity calls remain indivisible: warm upload peaked at 3.602 ms; cold source reading/upload peaked at 11.917/6.686 ms. These are reported rather than treated as a strict interruptible deadline. Reference observer exit 1 followed expected host-left shutdown; both clients, host and server exited 0. The separate mandatory soak exited entirely 0.

No second physical machine was available to verify LAN operation; explicit alternate-loopback binding passed. Reconnect/progression applies within a server session and does not provide account persistence. Fresh-machine dependency coverage is based on imported-library inspection, not a second clean PC.

## Exact native build

Historical record of the M9 build (superseded): native source commit dc22bcb6f925d773b2735278d0165c19c06f35db, ABI 1.4, protocol 6, canonical structure 3, DLL SHA-256 4f8cd3852c9eaa40cb3b2cccbf6cfe097b99c013ae8563954773a5ca294407a7. The current build is protocol 7 (tag 217136225208817073, DLL SHA-256 9a35387de22209b351811129beeb42409942fdff2a4b08bb149ea7f864e1331f); see STATUS.md. Package manifests hash each distributed file. Matching symbols are separate to keep the game download smaller.
