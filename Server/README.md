# Server

`BOM-server.exe` is the Odin game server. When you choose **Online → Host** (in the Unity Editor or in a built game),
the game starts this program and the other players join it. It is built from `Engine/` and must match
`Assets/BOMIntegration/Plugins/x86_64/bomcore.dll`; don't replace one without the other.

| file | sha256 | built from |
|---|---|---|
| `BOM-server.exe` | `8aeb7e3088d65d2f1c3da1342288c30c296a13b450914066085cf83debadcc86` | Engine 9d5fbb2c (b46b00e3 plus: a piece hanging by one glue seam gives way under its own weight), same build as bomcore.dll 70b8b75f |

The level files the server loads come from `integration/fixtures/levels/` (Yard, Bridge, Tower) and
`integration/fixtures/network-yard/yard.json` (Classic Yard). In the Editor the game reads them from there;
`BomFrontDoorBuilder` copies them to `Server/levels/` next to a built game.

To rebuild after an engine change: `integration/tools/Build-OwnerNative.py` builds the DLL and the server from the same
source, then copy both here and into `Assets/BOMIntegration/Plugins/x86_64/` (see `AGENTS.md`).
