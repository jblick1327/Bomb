Read AGENTS.md first; its rules apply.

BOM — multiplayer step 2a: players, Box2D-free presentation, structure replication (2026-11-04, revised)

Context. Multiplayer will be a dedicated authoritative server (a headless process) streaming to up to 4 clients. In multiplayer the host's own game is just another client of a local server. Clients never simulate physics. They keep a replica of the World's STRUCTURE (materials, cells, connections, pieces), rebuilt from a reliable stream of Baseline + Delta messages, and draw it with poses received separately (step 2b). Solo play keeps drawing its own World directly. Both paths share the same draw code: "draw a Scene with these poses", which never touches Box2D.

This step is entirely offline: no sockets, no processes, no UI changes. Local play must behave exactly as today. The transport is the finished library in src/netcode/ (read src/netcode/report.md). Import it for the byte codec; do not edit it.

STANDING RULE: You may choose or adjust fixture details yourself: coordinates, blast positions and radii, which cells to discard or which bonds to break, seeds, tick counts. Do this whenever a specified fixture does not exercise what its check is meant to test. Record what you chose and why in the report, and continue without stopping. Stop and ask only if a SYSTEM RULE (data model, failure rules, strengths, recipes, physics, snapshot format, byte-identity requirements) conflicts with the code or cannot be implemented as written.

A. Up to four players
- MAX_PLAYERS :: 4. World.player becomes World.players: [MAX_PLAYERS]Player, each with active: bool. Player gains blast_radius: f32.
- world_add_player(&world, index) and world_remove_player(&world, index). Every player spawns at PLAYER_SPAWN.
- Players don't collide with each other (collision filter); they collide with everything else. This is a gameplay choice the user can reverse later.
- Tick_Commands:
  - per player: players: [MAX_PLAYERS]Player_Commands{move, jump, blasts: [dynamic]Vec2, radius: union{f32}}, applied only to active players. A player's blasts use that player's blast_radius;
  - world-level: mode, bomb_radius: union{f32} (today's `radius`; it sets settings.blast_radius, the falling-bomb radius), remove_region, break_connection.
  - Blasts apply in player-index order, each player's blasts in order.
- Local Sandbox: the wheel and slider send players[0].radius AND bomb_radius with the same value, so solo behaviour and every capture stay identical. sandbox_radius reads players[0].
- A new player's blast_radius starts at settings.blast_radius.
- Tick_Events: respawn and blast_rejected become per player.
- world_tick stays the only path that mutates the World.
- Player and Bomb gain a runtime-only mirrored pose (`json:"-"`), refreshed from the body after every physics step and after snapshot load, exactly as cells mirror sub.pose. Drawing reads these mirrors.
- World snapshot v4: a "players" array listing active players with their index, existing Player fields and blast_radius. v3 snapshots load into players[0] with blast_radius = settings.blast_radius. v4 round-trips exactly.
- Byte identity (single player, which is all existing fixtures):
  - for all 48 accepted captures, the Scene section is byte-identical;
  - decoding the new v4 capture gives players[0] bit-equal to the accepted v3 player, and the same bombs, rain, settings and tick.
  Physics is unchanged because only player 0 has a body.

B. Presentation reads only replicable state
Rule: the draw paths never call Box2D. That covers render_cache, debug_view's draw code, sandbox_view, rubber_band, glue_view, mortar drawing, material_texture and editor_view. A client has no bodies. F3 picking/editing tools may keep using Box2D.
- Static pieces: extract the anchoring rule from physics_sync_structure into one pure function, piece_anchored(s, piece_id, anchor_y) -> bool: some live cell of the piece has a non-degenerate edge on anchor_y, within the existing 1e-5 tolerances. Physics and rendering both call it. render_static and the static signature in render_cache_prepass use it instead of Body_GetType. Scene carries anchor_y as structure (it is replicated).
- render_together_neighbours: replace World_OverlapAABB with structural candidates:
  - the cells of the same piece;
  - cells joined to it by a live non-mortar connection (incident_links);
  - when the cell is anchored, cells of other anchored pieces whose rest bounds overlap its rest bounds expanded by 0.05.
  This is equivalent today: anchored cells never move, so their posed and rest bounds coincide, and the existing filter (same rigid owner / both static / bonded, plus a shared rest boundary) is unchanged. The final neighbour lists must be identical.
- Players and bombs are drawn from their mirrored poses; bombs also need landed and fuse.
Checks:
- grep: no b2. calls in the draw paths listed above. List any that remain and why.
- Every existing PNG capture is pixel-identical: UI captures, texture checks, MSAA checks, rotation/glue demo captures and frame-bench frames.
- A test that builds render caches for the soak world before and after the change and compares every cell's draw_edge and neighbour list: identical.

C. Structure replication (offline)
- Every structural mutation must bump Scene.structure_revision: cells, pieces or connections created, killed or compacted, piece membership changes, and glue/mortar connection deaths from force or blasts. Audit this; connection deaths in apply_failures and the glass-shock path are suspects. The lockstep check below runs on EVERY tick, so a missed bump fails it.
- Canonical structure = what a client needs to draw. No seeds, overload counters, velocities or Box2D handles.
  - world epoch, structure_revision, anchor_y;
  - materials: full Material records, including custom names, colour and strip;
  - cells: id, owner, material, frame, outline, rest_center;
  - connections: id, a, b, mortar, glue samples (clients rebuild rest_segments from outlines, as snapshot decode does);
  - pieces: id, material, cell ids in the HOST's order. The first cell anchors rigid_render_frame, so reordering would perturb float poses.
  Top-level lists are sorted by id.
- canonical_encode(scene) -> []u8: binary via the netcode codec, ids as varint, every f32 bit-exact. Used for messages and equality checks.
- Messages:
  - Baseline{epoch, tick, canonical structure};
  - Delta{epoch, tick, from_revision, to_revision, materials appended, cells added (full records) and removed (ids), connections added (full) and removed, pieces added (full) and removed, pieces whose cell list changed (new list)}.
  A message over 200 KB is split into numbered parts applied atomically (the netcode reliable limit is 255 KB). Report the largest.
- The server keeps ONE shared structure index: live ids, each piece's cell list, the revision. On any tick where structure_revision changed, it emits one Delta diffed against that index. Every client receives the same stream.
- A rebuild (reset, layout load, snapshot load) starts a new epoch with a Baseline. A joining client gets a Baseline at the current revision, then the following deltas. Deltas from another epoch, or whose from_revision doesn't match, are errors.
- Replica: a Scene with no physics (no bodies, joints or Box2D world), built only by apply_baseline and apply_delta. It maintains its own per-piece render_revision so the existing render caches rebuild correctly. The existing render caches and draw code must work on it, given poses.
- Bots for testing, one seeded scripted input per active player: walk to a random x across the yard and back, jump at random intervals, and (when enabled) blast a random valid point within 6 m every 4–8 s.
Checks (put the full runs behind a CLI mode, e.g. --replication-soak, plus a 2-minute variant in the unit tests):
a) Lockstep soak: the 20-minute soak (falling bombs, two-minute refills) with 4 bots blasting. After EVERY tick, apply any delta to a replica and require canonical_encode(replica) == canonical_encode(host). Report the number of deltas, delta size p50/p99/max (including refills), and baseline size at start and end.
b) Late join: at minute 10 start a second replica from a Baseline, follow the deltas, and require the same equality every tick.
c) Render equivalence: at 10 sampled ticks of (a), give the replica the host's exact cell poses and render both. PNGs pixel-identical.
d) Pose-bandwidth measurement (sizes step 2b). Per tick, count:
   - awake bodies (rigid pieces, rubber cells, bombs, players);
   - CHANGED entities: rigid piece frames, rubber cells, bombs and players whose quantized pose (netcode quantize_pos/quantize_angle) differs from the previous tick.
   Report p50/p95/p99/max of both, plus the tick and situation of each max, for three scenarios:
     (1) the soak of (a): 4 bots blasting, falling bombs;
     (2) a rubble field (the Materials preset after 6 spread radius-5 blasts, settled), then 4 bots walking through it for 5 minutes with no blasts or bombs;
     (3) scenario (1) with 1 bot.
e) Performance: soak worst-blast_pass median before/after (3 runs each, sequential), and delta-generation cost per structural tick (p50/max).

Deliver: write report.md at the repo root (fixture choices, check numbers, the grep list from B, the revision-bump audit, byte manifest), with evidence under evidence/replication-2a/. No zip needed; the reviewer reads the repo directly. Do not commit to git. Do not edit src/netcode/.
