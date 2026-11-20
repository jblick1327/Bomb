Read AGENTS.md first; its rules apply.

BOM — multiplayer step 2b: pose frames, inputs, client clock, end-to-end over the netcode simulator (2026-11-05)

Context. Step 2a is accepted (report.md, evidence/replication-2a/): four players, Box2D-free drawing, canonical structure Baseline/Delta messages and physics-free replicas. This step adds everything else a client needs:
- pose frames with acked delta encoding and a per-client byte budget;
- client inputs that can't be lost;
- an adaptive client clock with interpolation;
- tick-stamped structure application.
It runs end-to-end IN-PROCESS through the real netcode endpoints over its link simulator. Still no sockets, processes or UI (that's step 3). Solo play must stay exactly as it is.

Do not edit src/netcode/. If you find a netcode bug, stop and report it with a reproducing test.

STANDING RULE: You may choose or adjust fixture details yourself: coordinates, blast positions and radii, which cells to discard or which bonds to break, seeds, tick counts. Do this whenever a specified fixture does not exercise what its check is meant to test. Record what you chose and why in the report, and continue without stopping. Stop and ask only if a SYSTEM RULE (data model, failure rules, strengths, recipes, physics, snapshot format, byte-identity requirements) conflicts with the code or cannot be implemented as written.

0. Cleanup: remove the handoff leftovers in evidence/replication-2a/ (full-soak.pid, the empty full-soak-errors.txt and full-soak-exit.txt, tests-debug.txt and partial-before-material-audit.txt). Keep the accepted evidence.

A. Pose resolution (measure first, then choose)
Using 2a's pose measurement, recount "changed entities per tick" for every combination of position step {1/1024, 1/512, 1/256 m} × angle step {65536, 16384, 4096, 1024 per turn}, for the soak-4 and rubble-4 scenarios. For each pair, also compute the worst on-screen error in physical pixels: half a position step, plus half an angle step × the largest piece radius in the scenario, at the view scale of a 2560x1440 physical window.
Rule: choose the coarsest pair (fewest changed entities at rubble-4 p99) whose worst error is ≤ 0.5 px. Report the table and the choice. Implement the choice as POSE_POS_STEP and POSE_ANGLE_STEPS (the netcode quantizers stay as they are; add game-side quantizers).

B. Entities and pose frames
- Replicated entities:
  - dynamic rigid pieces: id and body-origin frame, as rigid_render_frame computes it;
  - rubber cells: id and pose;
  - players: index and pose;
  - bombs: id, pose, landed, and fuse quantized to u8.
  Anchored pieces are never sent (their frame is the identity).
- Bombs need stable ids: World.next_bomb_id. Bomb.id is assigned at spawn and serialized in snapshot v4 (optional; legacy bombs get sequential ids on load).
- Quantized state = (x, y, angle) on the chosen grid. Each side keeps, per received or sent frame, a TABLE: entity -> quantized state.
- Frame message (unreliable, server -> client):
  - header: epoch, tick, base_tick (an acked frame the client has, or none), part index/count, and last_applied_blast_seq for this client's player;
  - entries sorted by (kind, id): id as varint delta from the previous id, flags, then x, y, angle, either as zigzag varint deltas against the entity's value in the base table, or absolute (zigzag varint) when the base has no row;
  - gone: ids that have a row in the base table but no longer exist at this tick.
  Parts are independent, each ≤ 1150 bytes. A part repeats the header and carries its own entries.
  The client's table for frame T = base table − gone + entries. The client may use partial frames for drawing, but acks T only when all of T's parts arrived.
- Server, per client:
  - keep a ring of 64 sent tables (each = base table − gone + sent entries; exactly what the client will hold);
  - encode against the newest frame that client acked (its input message carries the ack); before the first ack, use no base (absolute);
  - candidates = entities whose current quantized state differs from the base table, or that have no row in it.
- Budget and priority:
  - Players and bombs are always included, outside the budget.
  - Everything else fills FRAME_BUDGET = 2 × 1150 bytes by a priority accumulator. Each tick, each candidate's accumulator gains (1 + speed in m/s) × (0.5 + min(area, 1 m²)) × (2 if within 4 m of that client's player else 1). Entities with no row in the base go first. Sent entities reset to 0. Unsent candidates keep accumulating.
  - An entity stays a candidate until its current state equals its acked row, so the final resting pose always arrives.

C. Client inputs (unreliable, client -> server, every tick)
- Contents: epoch, ack (newest complete frame tick), move (i8), radius (quantized), jump_counter (u16, +1 per press), and the last ≤ 8 blasts not yet confirmed by last_applied_blast_seq, each with blast_seq (u16), quantized position and radius.
- Server, per player:
  - move = the latest input;
  - one jump when jump_counter advanced since the last applied value;
  - apply each new blast_seq exactly once, in order;
  - reject positions outside the yard, and rate-limit to 4 blasts per second per player (a rejection emits that player's blast_rejected event).

D. Client clock and interpolation
- Render tick R (fractional) advances in real time, adjusted by at most ±5% toward the target R* = newest complete frame tick − delay. If |R* − R| > 0.5 s, snap.
- delay (in ticks) adapts: delay = clamp(1 + ceil(p95 frame-arrival jitter over the last 2 s, in ticks) + (2 if any frame was lost in the last 2 s else 0), 2, 12). A lossless, jitter-free link settles at 2.
- Draw poses: interpolate between the tables of the complete frames bracketing R. Positions lerp; angles take the shortest arc. An entity new at T1 shows at its T1 pose from T1. An entity gone at T1 draws until R ≥ T1. Rows that aren't in the replica's structure aren't drawn.
- Convert to draw inputs the existing way: piece frames map to rigid cell poses, plus rubber cell poses and player/bomb poses. Then call the existing draw path on the replica.

E. Tick-stamped structure and events (reliable channel)
- Baseline/Delta messages and explosion events {tick, position, radius} carry their tick. The client queues them and applies or plays each once R ≥ its tick, in order. If one arrives after R has passed its tick, apply it on arrival. There is NO global freeze.
- A new epoch's Baseline resets the client: replica, tables and clock.

F. In-process server and client objects
- Net_Server: owns the World, the shared structure index, one netcode server connection plus one per-client state (endpoint, sent-table ring, priorities, acked tick, input state).
  Per tick: receive -> apply inputs -> world_tick -> emit the structure Delta and events to all clients (reliable) -> build each client's frame (unreliable) -> write packets.
- Net_Client: an endpoint, replica, tables, clock and render poses.
- Messages use the netcode codec. Bots now act only through Net_Client input messages.

G. Checks
a) The resolution table and choice from A.
b) Frame codec: round-trips (delta and absolute, gone, multi-part); fuzz 10,000 random buffers through frame and input decode with no panic.
c) Table agreement: in (d), every time a client acks a frame, its table for that frame equals the server's record bit for bit. Mismatches = 0.
d) End-to-end soak, 10 minutes, falling bombs, 4 bots through Net_Clients over link_sim:
   - client 0 is "local": 0 latency, no loss;
   - clients 1–3 are remote: 40 ± 10 ms each way, 2% loss, 1% duplicates, 2% reordering.
   Report per client:
   - structure: the replica equals the server's canonical structure at every revision once applied (and after a final 2 s flush with bots idle);
   - render error: compare each drawn entity's interpolated pose with the server's true pose at the same fractional tick (keep a server pose history). p50/p99/max position error (m) and angle error, for all entities and separately for players and bombs;
   - the chosen delay over time (local must settle at 2) and the clock adjustments;
   - late structure: how many messages arrived after R passed their tick, and the maximum lateness;
   - frame bytes per tick p50/p99/max, average and peak 1-second upload (kbit/s);
   - budget saturation (fraction of ticks where candidates didn't fit) and the maximum staleness of any changed entity (ticks from change to inclusion);
   - inputs: jumps applied == presses issued; blasts applied + rejected == issued; 0 duplicates.
e) Solo: the 48 accepted captures and 10 legacy captures pass 2a's v4 criteria; the existing PNG captures are unchanged.
f) Performance: per-client frame build cost per tick (p50/max) with 4 clients, and server tick time p50/max, during (d).
g) Teardown: Odin 0, Box2D 0.

Deliver: report.md at the repo root (choices, check numbers, byte manifest) and evidence under evidence/replication-2b/. Remove interim/handoff files from evidence/replication-2b/ before finishing. No zip. Do not commit to git.
