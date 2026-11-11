# Native elimination rules (owner follow-up)

Current native source: protocol 7 / round snapshot format 2 / gameplay config 4 /
ABI 1.4 / canonical topology 3. Protocol 7 changes the round wire roster from
two to four records. Config 2 adds actual blast radius and the Elimination
interval ramp; config 3 adds player-only gravity scaling; config 4 adds separate
lethal and graze radii. Level format remains 4.
Explicit config-1/2 levels retain authored player/gravity/fuse/Sandbox interval
tuning and gain player gravity scale 1. Config 1 also receives the established
default radius and Elimination pacing. Config 3 retains all authored fields,
including player gravity scale. All three migrate to config 4 with lethal radius
1.2 and graze radius 2.2 under approved D1, preserving authored crater radius.
Current config 4 is validated without silently repairing missing fields.
Historical M8/M9 protocol-6 binaries and M7 protocol-5 binaries must not be mixed
with these builds. E1-N1 completed the Unity config-3 checkpoint; E1-N2 must update
the exporter and native SDK to config 4 and re-export level manifests before N2
is used in Unity.

N1 movement (D2, approved 2026-11-10): new native defaults are speed 7,
acceleration 70 (standing start reaches full speed in six 60 Hz ticks, 0.100 s),
jump speed sqrt(2 * 25 * 2.5), approximately 11.18034, and player gravity scale
25 / 9.8. Jump height is 2.5 units analytically with approximately 0.9 s airtime.
World gravity remains (0, -9.8); bomb and debris gravity are unchanged. Coyote
time and jump buffer remain 0.1 s. The authoritative player body and native
prediction/rewind use the same authored tuning and Box2D per-body gravity scale.
Respawn and rebuild preserve the configured rule. Gravity scale must be finite
and in [0.1, 10], and is included in config and level gameplay manifest hashing.
Omitted configs with recognized native default IDs resolve to current defaults;
explicit v1/v2 configs retain legacy authored movement until re-exported with current tuning.
Only the frozen historical material/seam snapshot fixtures retain the original
player tuning (4 / 32 / 6.3 / scale 1), explicitly approved by the owner on
2026-11-11, preserving their existing snapshots and byte-identity assertions.

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

N2 lethality (D1, approved 2026-11-10): each native detonation tests the player
capsule at its current server pose using min(actual explosion radius,
config lethal_radius), default 1.2 units. Distance is to the capsule surface,
not the player center; tangency alone is not a hit (positive blast reach is
required). A small diagnostic explosion never gains a larger lethal zone.
Destruction and explosion presentation still use the full actual radius,
default bomb_radius 5. Config graze_radius defaults to 2.2; N2 stores and hashes
it, while graze counting and damage remain task N3. Until N3, exposure outside
the lethal zone produces no damage.
Both damage-zone values must be finite: lethal_radius in [0.1, 6], and
graze_radius in [lethal_radius, 6]. They are independent of bomb_radius.
Both are included in config and level gameplay manifests, and catalog JSON
retains their exact float bits. The existing round snapshot lethal_radius
field now reports the effective falling-bomb lethal radius, including the
actual-radius cap. Its layout is unchanged, so round format, protocol and ABI
versions are unchanged.

A capsule dies only when a nonzero part of the lethal blast reaches it without
crossing a solid cell. The read-only blast_capsule_visible query uses
destruction's cover grid and ray/polygon chord intersection code; it also
includes physical solids whose destruction resistance is zero. Destruction's
original attenuation, material recipes and damage queries retain their behavior.
Visibility is evaluated against the pre-damage detonation world: a wall protects
for the blast that destroys it, then a later blast can pass through the opening.
Exposed capsule portions count; the query uses capsule/occluder angular boundaries
rather than a fixed set of sample points. Deaths from every explosion and bounds
check on the tick are accumulated before combining disconnect forfeits and
choosing a winner or draw. Sandbox retains its original respawn and tools.
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
