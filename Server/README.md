# Server

`BOM-server.exe` is the Odin game server. When you choose **Online → Host** (in the Unity Editor or in a built game),
the game starts this program and the other players join it. It is built from `Engine/` and must match
`Assets/BOMIntegration/Plugins/x86_64/bomcore.dll`; don't replace one without the other.

| file | sha256 | built from |
|---|---|---|
| `BOM-server.exe` | `61219686c98fff0873403003cb6032bd108d8bfa53943e0ea93c65eaa158728f` | Engine b46b00e3 (59b51704 plus a precise, above-normal server loop that catches up short stalls, and prediction that bridges missing commands and keeps going near bombs), same build as bomcore.dll 2e702c32 |

The level files the server loads come from `integration/fixtures/levels/` (Yard, Bridge, Tower) and
`integration/fixtures/network-yard/yard.json` (Classic Yard). In the Editor the game reads them from there;
`BomFrontDoorBuilder` copies them to `Server/levels/` next to a built game.

To rebuild after an engine change: `integration/tools/Build-OwnerNative.py` builds the DLL and the server from the same
source, then copy both here and into `Assets/BOMIntegration/Plugins/x86_64/` (see `AGENTS.md`).
