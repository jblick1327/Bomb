# Native elimination rules (owner follow-up)

Current source: protocol 7 / round snapshot format 2 / gameplay config 2 /
ABI 1.4 / canonical topology 3. Protocol 7 changes the round wire roster from
two to four records. Config 2 adds actual blast radius and the Elimination
interval ramp; v4 level format remains 4. Old config-1 levels migrate to the
current defaults while preserving their authored player/gravity/fuse/Sandbox
interval tuning. M8/M9 protocol-6 binaries and M7 protocol-5 binaries are frozen
historical checkpoints and must not be mixed with these builds.

Odin owns a 2–4-participant elimination controller, separate from Sandbox.
At least two matching, natively validated ready baselines start a
180-server-tick countdown. The controller selects every eligible ready player,
up to the four connection slots, when that countdown starts. An unready slot
does not block two ready players. Existing connected players may finish baseline
validation and join during that countdown, without extending its start time or
replacing selected participants. Connection generations are captured at countdown
selection: later joins or reconnects spectate. The roster freezes at Playing.
An interrupted countdown returns to Waiting. Gameplay runs only in Playing;
Waiting, Countdown and Finished retain network/server ticks while freezing the
physics world. A host restart publishes a fully rebuilt world before advancing
the round ID. The existing five-second host-left shutdown stays in place.

Each native detonation tests the player capsule at its current server pose,
using that explosion's actual authoritative blast radius (config default 5).
There is no independent lethal-radius setting. A capsule dies only when a
nonzero part of the actual blast reaches it without crossing a solid cell.
The read-only query uses destruction's cover grid and ray/polygon chord
intersection code; it also includes physical solids whose destruction
resistance is zero. Destruction's original attenuation, material recipes and
damage queries retain their behavior. Visibility is evaluated against the
pre-damage detonation world: a wall protects for the blast that destroys it,
then a later blast can pass through the opening. Exposed capsule portions count;
the query uses capsule/occluder angular boundaries rather than a fixed set of
sample points. Deaths from every explosion and
bounds check on the tick are accumulated before combining disconnect forfeits
and choosing a winner or draw. Sandbox retains its original respawn and tools.
Manual blast and layout-upload requests are rejected in elimination.

The last living participant wins. If all remaining participants die on the
same server tick, the round is a draw. Dynamic cell/piece out-of-bounds cleanup
also applies to indestructible material. Fixed and anchored sources are exempt;
indestructibility still rejects ordinary damage and prevents minimum-width
pruning. These cleanup rules do not add a damage path through indestructibles.

Elimination bomb intervals interpolate linearly on 60 Hz server simulation
ticks from config `elimination_start_interval` (default 1.0–2.5 seconds) to
`elimination_end_interval` (0.4–1.0 seconds) over
`elimination_ramp_seconds` (90 seconds), then hold the end range. Each scheduled
drop draws from that tick's range with the existing seeded RNG. Resetting the
round resets the ramp and RNG stream. Sandbox retains its fixed configured
`bomb_drop_min`/`bomb_drop_max` range. Native gameplay validation and manifest
hashing include all config-2 fields. Unity authoring exports those values;
Unity does not implement the timing rule.

Round state, participant session IDs/generations, survival ticks, bombs faced,
result XP, winner/draw/reason, session totals, wins, level progress and restart
permission are persistent snapshot data. XP is `10 * bombs_faced + alive_ticks/60`
using integer division and saturating counters. A round/session award is applied
once. The first level requires 100 XP; each subsequent level adds 50 to the cost.

Session identities are server-local. A 128-bit random secret, scoped to a random
server instance, permits a native handle to resume its in-memory totals. It does
not preserve its connection generation or resurrect a participant. Midround
joins/resumes spectate until a later round. One session cannot use two active
connections. The bounded 128-session table rejects further new admissions when
full; a local server restart starts a new session. Credentials are not logged or
passed to Unity. There is no account persistence or authentication service.

Only Odin implements the application codec. Welcome/Hello exchange native resume
credentials and explicit spectator intent. Native Ready confirms a validated
canonical baseline. The reliable round snapshot is sent on state changes and
once per second. Duplicate or older snapshots do not award XP in the frontend.

ABI additions are separate structs/getters, preserving existing struct strides.
`bom_client_get_round` requires an acquired sample and matching sample sequence;
its actual 0–4 participant rows and four connection rows are borrowed until release.
`BomSession` copies them before releasing and clears all pointers. Join flags
are set before connecting. C ABI host operation 5 selects game mode; operation 4
continues to upload layouts. The native wire host operation for game mode is 4.

Historical M8 executed evidence: 215 original game tests plus five integration regression tests, 74 shared tests, 19 ABI tests, C/.NET
23-layout lifecycle checks, and a real UDP diagnostic with four native handles,
two rounds, interrupted countdown, late spectator, forfeit, rejected commands,
and reconnecting to results. See M8 evidence for exact build identities. A first
failed diagnostic sent an action before input-schedule readiness; the corrected
driver waits for a fresh native owner/schedule and verifies the server's durable
rejection result.

The standalone menu derives a scene from the network yard and uses the original
HUD UXML/USS and a derived Claymate/animation prefab. Original assets are not
edited. Historical two-Unity yard and simultaneous-draw runs, Odin observer
agreement, repeated event presentation, native movement/jump animation and
rendered menu/game/disconnect captures passed. See evidence/M8/summary.json and
the completed original M9 evidence. Those results do not certify the changed
owner-follow-up binaries; their new validation is recorded separately.

Real-network Sandbox manual blasts are host diagnostics; offline Sandbox
physics/input fixtures retain their original behavior. Native async reset keeps
the old world/network alive while a worker builds the next epoch; publication
precedes round-ID advancement. Host mutations remain gated while pending. The
historical reset-under-load soak and current follow-up status are linked in
`integration/review/decisions-needed.md`.
