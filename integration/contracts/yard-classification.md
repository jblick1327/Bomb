# Proposed derived-yard classification

This is an M0 proposal for the separate M6 network yard. The original YardLevel remains unchanged. The static audit records 125 objects, zero missing scripts and four pre-existing missing rock-mesh references. Original terrain startup also reports non-readable Grass_Mesh/Ground_Mesh collision data; the new exporter must use explicit proxies and derived preprocessing data.

| Original group | Proposed network role |
| --- | --- |
| Cube objects carrying DestructibleBlock/gameplay-ground behavior | Explicit gameplay proxies with destructible material and authored anchor segments; preserve the recognizable platform/leg silhouette through compound parts. Detached unpinned fragments become dynamic. |
| Cube (12), which has a collider without the destruction marker | Candidate fixed, indestructible foundation/boundary. Confirm its bounds and trigger status in the derived authoring scene before export. |
| Yard Decore mesh groups without gameplay markers | Decorative rendering by default. Do not infer collision or damage merely from visible grass, ground layers or rocks. |
| Explicitly selected gameplay rocks | New proxy/source markers and derived registry entries; leave original model/import metadata unchanged. Missing source meshes remain visible audit failures rather than invented art. |
| Original player controllers, bomb dropper and local destructible scripts | Reference behavior/art only. New actor views receive native poses and have no gameplay collider or movement controller. |
| Original cameras, HUD document and round session | Reuse visual references/styles through new presenters. Native session/round snapshots become the authority; the legacy session is absent from network scenes. |

M6 will measure transforms, bounds and spawn points, assign durable source/part identities, generate visible proxy approximation reports, and validate the exported geometry against Odin. This proposal does not claim that those policies or the yard exporter have already been implemented.
