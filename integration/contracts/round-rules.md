# Native elimination rules (owner follow-up)

Current native source: protocol 9 / round snapshot format 4 / gameplay config 5 /
ABI 1.6 / canonical topology 3 (N4; see the N4 section at the end). Protocol 7 changed the round wire roster from
two to four records. Config 2 adds actual blast radius and the Elimination
interval ramp; config 3 adds player-only gravity scaling; config 4 adds separate
lethal and graze radii. Config 5 adds `grazes_to_die` (default 3, valid integer
range 1..255). Protocol 8 and round format 3 add each player's `graze_count` as
a little-endian u32 to the native round wire roster. ABI 1.5 exposes that count
in the former reserved u32 of `BomRoundPlayer`, retaining its 64-byte stride.
Level format remains 4.
Explicit config-1/2 levels retain authored player/gravity/fuse/Sandbox interval
tuning and gain player gravity scale 1. Config 1 also receives the established
default radius and Elimination pacing. Config 3 retains all authored fields,
including player gravity scale. Configs 1..3 gain lethal radius
1.2 and graze radius 2.2 under approved D1, preserving authored crater radius.
All configs 1..4 migrate to config 5 with `grazes_to_die` 3. Explicit config 4
retains every authored field, including both damage radii, movement, gravity,
destruction radius, fuse and pacing. Current config 5 is validated without
silently repairing missing fields. Omitted native default IDs v1..v5 resolve
to current defaults. Unknown versions remain invalid.
Historical M8/M9 protocol-6 binaries and M7 protocol-5 binaries must not be mixed
with these builds. E1-N1, E1-N2 and E1-N3 completed the Unity config-3, config-4
and config-5 checkpoints: the exporter is on config 5, level manifests
are re-exported, and limb-loss presentation is in place. E1-N4 moved the native SDK to ABI 1.6 / protocol 9.

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
default bomb_radius 5.

N3 grazes (D1): an exposed capsule outside the effective lethal radius and
inside or tangent to min(actual explosion radius, config `graze_radius`),
default 2.2, receives exactly one graze per detonation. Distance is measured
to the capsule surface. The annulus is strictly outside the lethal zone;
N2's harmless lethal tangency remains harmless. Outer graze tangency is
included using an inclusive distance gate and one-ULP expansion of the
read-only visibility query radius; shared blast loads are unchanged.
Full pre-damage cover, including zero-resistance physical solids, protects;
partial exposure in the annulus counts. The graze that reaches `grazes_to_die`
kills with death reason Blast, retaining the final count. Pending or committed
deaths cannot accumulate further grazes. Same-tick third-graze deaths use the
existing simultaneous winner/draw rules. Every rebuilt round clears the body
and roster counts; disconnects retain the last copied count in the result.
Sandbox has no grazes. The world still destroys and presents the full actual
explosion radius, and material, physics and bomb scheduling are unchanged.
Both damage-zone values must be finite: lethal_radius in [0.1, 6], and
graze_radius in [lethal_radius, 6]. They are independent of bomb_radius.
Both are included in config and level gameplay manifests, and catalog JSON
retains their exact float bits. The existing round snapshot lethal_radius
field reports the effective falling-bomb lethal radius, including the
actual-radius cap. The damage threshold also participates in config and level
gameplay manifests and exact catalog JSON round trips.

An immediate lethal-zone death occurs only when part of the lethal blast reaches the capsule without
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
graze counts, result XP, winner/draw/reason, session totals, wins, level progress and restart
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
once per second. Graze changes also dirty the round snapshot for reliable
publication on that tick, including nonlethal hits. `BomRoundPlayer.graze_count`
is persistent authoritative state: Unity can compare it within the same round
and session/generation to present one lost limb per increment, including
multiple grazes on one server tick. Late observers can reconstruct the current
look without a transient event; round-ID changes reset it. Duplicate or older
snapshots do not award XP in the frontend.

The ABI preserves existing struct strides.
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

## N4 items and D12 graze next to cover (native, 2026-11-11)

Owner decisions D6 (items) and D12 (graze next to cover), approved 2026-11-11.
Native protocol 9, round snapshot format 4, gameplay config 5 (unchanged), C ABI 1.6,
level format 4, canonical topology 3. Unity picks this up in E1-N4.

**D12.** If a capsule reaches inside the lethal radius but cover hides every part of it
within that radius, an exposed part in the lethal-to-graze band (1.2 to 2.2) counts as a
graze. Before N4 such a player took nothing. Full cover still protects. A capsule that
exactly touches the lethal boundary (tangent at 1.2) stays harmless, as N3 decided.

**Items (D6).** Only the server spawns and simulates items, and only while an Elimination
round is Playing. Defaults follow Darryn's AlphaV0.1 `BombDropper`,
`FallingCollectibleItem` and `ArenaPlayerController`:
- Timing: the first item comes 3 to 8 s after the round starts, then one every 12 to 20 s
  (uniform), counted in server ticks. The draw uses a seeded stream (world seed +
  "item") kept apart from bomb drops, so the bomb schedule is unchanged.
- Kinds: silver coin 25 %, gold coin 15 %; invincibility, slow and speed boost share
  the remaining 60 % equally (20 % each).
- Placement: x is uniform over the level's bomb spawn range, at the bomb spawn height.
  The item falls at Darryn's constant 18 units/s² with x fixed. It stops on the first
  surface below (structure or floor; players and bombs are ignored) and stays there
  until the next detonation, which makes it fall again. It disappears after 15 s
  (900 ticks) or when it leaves the bomb cleanup bounds.
- Pickup: the item is a circle of radius 0.35. It is collected when it overlaps an
  alive player's capsule (boundary included). Each tick runs after the physics step and
  before detonations. Items are checked in ascending id; on a tie, the lowest player
  slot gets the item. A player who already died this tick collects nothing.
- Coins: silver +10, gold +50. Coins collected during the round are added to that
  player's round award: `xp_gained = 10 × bombs faced + seconds alive + coins`. They
  count even if the player later dies.
- Effects last 10 s (600 ticks). Picking up the same effect again restarts its timer.
  Speed boost (×1.5) and slow (×0.5) share one slot, so a new one replaces the old one.
  Invincibility runs alongside either speed effect.
- Speed effects scale only the horizontal movement target (7 → 10.5 or 3.5).
  Acceleration, jump and gravity are unchanged. The shared movement kernel counts the
  timer down, and the owner state carries the effect and its remaining ticks, so client
  prediction replays an active effect and its expiry exactly. A pickup itself is not
  predicted; the next owner state corrects it.
- **Invincibility** protects against all blast damage: no lethal hit and no graze.
  It does not protect against leaving the kill bounds.
- New rounds, resets and rebuilds clear all items, coins and effects.

**What clients receive.**
- Items are actors in the pose frames: kind 4 (`Item`). In `BomPose`, `flags` bit 0
  means landed and bits 8–15 hold the item kind: 1 silver coin, 2 gold coin,
  3 invincibility, 4 slow, 5 speed boost (Darryn's `CollectibleItemType` + 1).
  `BomActorShapeInfo.item_radius` is 0.35.
- Each `BomRoundPlayer` (stride 64 → 88) adds `coins`, `effects` (bit 0 invincible,
  bit 1 speed boost, bit 2 slow), `invincible_end_tick` and `speed_end_tick`. The end
  ticks are the last server tick the effect applies (inclusive), and 0 when inactive.
  Effects are reported only for living players while the round is Playing, so Unity can
  drive `PlayerItemGlow` from them. The snapshot is re-sent on pickup and on expiry,
  not every tick.
- `BomRoundInfo` adds `graze_radius` (the effective graze zone, capped by the actual bomb
  radius like `lethal_radius`) and `grazes_to_die`, appended after `connections`, so
  Unity can draw a fainter second ring.

**Not covered here.** Unity presentation (Darryn's item prefabs, pickup sound, glow,
graze ring) is E1-N4. Item tuning is native constants (`ITEM_TUNING`), not
gameplay-config fields. Moving them into the config would mean config 6 plus a
migration.
