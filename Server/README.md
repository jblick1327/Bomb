# Server

`BOM-server.exe` is the Odin game server. When you choose **Online → Host** (in the Unity Editor or in a built game),
the game starts this program and the other players join it. It is built from `Engine/` and must match
`Assets/BOMIntegration/Plugins/x86_64/bomcore.dll`; don't replace one without the other.

| file | sha256 | built from |
|---|---|---|
| `BOM-server.exe` | `5fb88e2a9d5090bc3e89fa296736aa3a0f8e0cc02bf2a4ccd3a2684352ceaaee` | Engine 829b3808 (NPT, ABI 1.7; NPT changed no server source), same build as bomcore.dll 3265d9f7 |

The level files the server loads come from `integration/fixtures/levels/` (Yard, Bridge, Tower) and
`integration/fixtures/network-yard/yard.json` (Classic Yard). In the Editor the game reads them from there;
`BomFrontDoorBuilder` copies them to `Server/levels/` next to a built game.

To rebuild after an engine change: `integration/tools/Build-OwnerNative.py` builds the DLL and the server from the same
source, then copy both here and into `Assets/BOMIntegration/Plugins/x86_64/` (see `AGENTS.md`).
