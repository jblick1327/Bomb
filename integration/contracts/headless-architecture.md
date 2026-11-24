# Current extraction boundary

The M0 dependency map describes the supplied baseline. The implemented boundary is now:

| Layer | Source and responsibility |
| --- | --- |
| Native transport | Odin src/netcode; UDP, reliability, bounded fragments, packet codecs. No managed wire codec. |
| Shared domain/simulation | Odin src/shared; material/geometry/state, world and player kernel, server, replication and headless client. No raylib import in its dependency graph. |
| Headless server | Odin src/server/main.odin imports the shared package and starts the dedicated server without a window. |
| Reference frontend | Existing src/main.odin and migration aliases use the same shared implementation. Net_Client_View owns graphics caches/effect aging; bot input remains outside the shared client. |
| Native polling boundary | src/ffi and generated bindings; per-handle context/allocator, owner-thread enforcement, bounded elapsed pump, acquired samples, full-state transactions/events, host controls and diagnostics. |
| Unity runtime | Bom.Unity.Runtime assembly; session/input host, copied sample acceptance, extrusion builder, coordinates, actor prefab views and effects. No Unity collision/movement/damage authority. |
| Unity tooling | Bom.Unity.Editor assembly; isolated build/geometry/lifecycle checks and new scenes/prefab variants. The original assets and gameplay scripts remain available. |

Received topology is validated in a separate pure-data replica. Presented topology advances only when its effective tick is due. Native sampling adds a fractional presentation time without generating extra fixed commands. World/server ticks refer to completed fixed steps; M5 will add explicit future command slots and owner reconciliation on top of this tested boundary.
