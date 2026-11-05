# M0 source dependency map (static inspection)

All game source files currently declare package main. An importable shared package does not exist. scripts/bom.ps1 stages src plus diagnostics for each directory-scoped Odin build, and adds tests for Test/NetTest. Preserve this staging behavior when establishing the original baseline.

| Layer | Current files and extraction constraints |
| --- | --- |
| Entry/frontends | main.odin dispatches --server/--bot-client/--hidden-client before GUI initialization; sandbox_view, editor_view, menu_view, net_game_ui own UI. net_real currently imports raylib, so a headless entry path is not yet a headless dependency graph. |
| Transport | src/netcode/{socket,packet,codec,connection,endpoint,link_sim}.odin supplies UDP, reliability and impairment. Reuse its codec exclusively. |
| Domain/topology | model, geometry, shape_geometry, material_library/wire, exact_json; inspect model's Box2D fields before moving domain definitions. |
| Simulation | physics, destruction, shape_build, wood_generation, glass_shock, glue, mortar, rubber_band, player, bombs, yard. Box2D remains server-owned except the bounded prediction world added after M4. |
| Replica | replication encodes canonical Scene, baselines/deltas and hashes. Repl_Cell currently has id/owner/material/frame/outline/rest_center, no source provenance. net_frame carries pose entities. |
| Client | net_client mixes transport/replica/clock/input with Bot, Sandbox_Settings, Render_Cache_State and Bomb_Burst. Extract settings and event records; caller owns bots, rendering caches and burst aging. |
| Lifecycle | net_client_init initializes endpoint/replica/maps; clear_state clears pending data/rings/input/visual collections; destroy frees endpoint/replica/maps/caches; reset clears on baseline epoch. Acquire/release sample ownership is not implemented. |
| Timing | net_client_step receives, adjusts clock, applies queue, ages bursts by NET_STEP_DT, computes drawn poses and generates one input on every connected call; then client_update. Mechanical extraction preserves this; elapsed-time adaptation is a separate gate. world_step must be traced to confirm exact end-of-tick convention. |
| Persistence/identity | layout_state/layout_files/exact_json; state/world_state/world_compat; all model/shape_build/refinement constructors and replication encode/decode must gain provenance together in M6. Static inventory is not proof of complete coverage. |

Baseline compatibility: GAME_PROTOCOL_VERSION=3 and GAME_BUILD_ID=BOM-menus-2026-11-05 in net_session. Initial transport and canonical limits must be independently locked from code before changing them.

Bounds inventory: player_after_step hard-codes x<-8.5, x>9.5, y<-3, y>12; PLAYER_SPAWN is (-4.5, capsule half-height+0.005). Audit bombs.odin spawn/cleanup/acceptance, yard.odin world_remove_out_of_bounds, blast_aim/query and editor camera limits before M6 migration. Keep legacy behavior during M0–M2.

Proposed yard classification: original ground/destruction scripts identify candidate gameplay terrain; original wall/platform colliders identify candidate fixed proxies; unmarked art remains decoration. Object-by-object inventory and screenshot evidence are pending Unity inspection; no asset is classified automatically by its visual silhouette.
