# BOM shared exchange contract — v0.1 candidate

**Review draft · 12 October 2026 UTC / 11 October Toronto**  
**Saved authority:** Handbook 1.7.0 / Architecture v0.15 / DEC-069, commit `2973f789f825f3395689fbc6e6b7509d938960e4`.

The purpose is to give authoring, Unity and Odin one concrete vocabulary for exchanging data while networking experiments proceed. This document proposes a versioned interface; it does not update the handbook, assign work or approve implementation. The machine-readable schema and examples accompany it in the draft bundle.

The examples cover reconstruction, grabbing, countdowns, splitting and death. A running game must also include any additional lasting state its selected mechanics require; this draft identifies those remaining gaps rather than treating omission as permission.

## 1. What is settled, and what this draft proposes

| Status | Boundary |
|---|---|
| Handbook requirement | Host Unity calculates and commits gameplay, geometry, identity and relationship outcomes. Odin carries requests and committed state. Clients reconstruct from host-produced geometry. |
| Handbook requirement | Current canonical state plus validated dependencies reconstructs the world; engine objects, contacts, solver history and meshes are derived. Each fact has one canonical owner. |
| Accepted in this chat; not yet published | Begin structural replication with full current-world snapshots and an early performance review. Host supplies the initial state and required reusable definitions. Complete snapshots have increasing match-scoped capture numbers; newer snapshots may skip intermediate numbers. |
| Candidate in this draft | All field names, record packaging, numeric types, ID allocation, geometry representation, definition references, API signatures and example profiles below. |
| Still open | Reliable versus best-effort delivery, transport, encoding, cadence, coalescing, smaller ongoing updates, correction, transient effects and recovery mechanics. Throwing is future intent; its controls and records are undesigned. |

**Freeze the decoded interface for an agreed version.** Lossless encoding, compression, packet assembly and delivery can be experimented with behind it. New gameplay state or changed meanings require an explicit schema revision. A partial or incompatible payload never becomes a partial world.

## 2. Proposed common types and frames

| Type | Candidate representation and meaning |
|---|---|
| `MatchId` | UUID identifying a match. Odin supplies the expected match through the established session. |
| `EntityId` | Positive unsigned 64-bit integer, shared by bodies and physical relationships. Host allocates; never reuse within a match. Participant IDs have a separate namespace. |
| Snapshot / geometry / request number | Unsigned 64-bit integer. Separate purposes; a snapshot number is not a geometry revision. Geometry revisions belong to their body ID. |
| `DefinitionRef` | `{id: string, revision: uint32}`. Exact immutable content within a match. Changing content requires a new revision. |
| Numeric values | Finite IEEE-754 binary64 at the decoded boundary. Integers above JavaScript's safe range use decimal strings in the JSON examples. No codec-induced rounding. This deliberately does **not** preserve the earlier illustrative four-byte size assumption. |
| Units | Metres, seconds, kilograms; density is kg/m²; connector strength is N/m. Angles are radians, positive counterclockwise. XY uses +X right, +Y up. |
| `Vec2` / `Pose2D` | `[x,y]` / `{position: Vec2, angle: number}`. Pose locates a local frame in world space; linear velocity is current COM velocity, in m/s; angular velocity is rad/s. |

Shapes and limb roots are body-local; hold points are target-local; connector regions are endpoint-local. Keep the authored local origin unless the host explicitly changes the frame and transforms dependent coordinates. Importers bake scaling into shape and definition inputs. Runtime visual generation uses the same local shape.

Binary64 avoids making an unreviewed geometry quantization rule part of this first exchange. Unity integration must confirm how these values map to its runtime physics. Publishing a result requires geometry, motion and attachments to agree in the exchanged representation.

## 3. Proposed records

The JSON Schema is the exact field reference. This table explains ownership; grouping records together does not prescribe ECS storage.

| Record | Fields / responsibility |
|---|---|
| `WorldSnapshot` | Version, match ID, capture number, host simulation time, next entity ID, world-definition reference; complete arrays of bodies, connectors, holds and participants. Simulation time is host-local metadata, not a shared bomb deadline. |
| `Body` | ID; current shape and geometry revision; local-frame world pose, COM linear velocity and angular velocity; effective body-configuration reference; environment, character or bomb behaviour. The behaviour union packages composition for exchange rather than mandating an engine class hierarchy. |
| `EnvironmentBehaviour` | Indestructible, or independently selected destruction-response reference. Corpses use this ordinary composition. |
| `CharacterState` | Character-definition reference. No duplicate player owner, hold list, independently moving limb root or accumulated health. |
| `BombState` | Bomb-definition reference; countdown is inactive, or active with remaining seconds. Handling does not reset it. |
| `Connector` | ID, endpoint IDs, paired local attachment regions, strength per metre; optional percentage-loss cutoff and lifetime reference length. Intended fit and current length derive from the proposed paired representation below. |
| `Hold` | ID, character ID, one of four limb slots, target ID, target-local held point. Definition roots/reach and body poses provide the other inputs. |
| `Participant` | Participant ID and nullable controlled-body ID. The roster alone owns control. |

`nextEntityId` is proposed allocator recovery state: it must exceed every allocated ID, including retired ones. Consumers can check it against live IDs; the host must preserve the full high-water mark. Client reconstruction does not allocate canonical IDs. Absence from a full snapshot means absence from its current world; retirement lists and retired parents are unnecessary for application.

### Geometry and connectors

**Shape candidate:** one connected polygon per body, with a counterclockwise outer ring and clockwise holes. Rings contain at least three distinct points, omit the repeated closing point, and have no self-intersection, touching holes or overlapping holes. Circles or unsupported shapes must be resolved by the host into the agreed canonical representation before capture. This proposes an exchange format; it does not demonstrate a production cutter's support for it.

**Connector candidate:** an array of paired boundary polylines, with corresponding points ordered along the same surviving bond. Each pair has equal arclength; all point correspondences determine the same rigid transform between the endpoint frames. At least one nonzero segment is required. Current attachment length is the sum of A-side polyline lengths, without overlapping ranges. Because correspondence determines the intended position and angle, there is no second rest transform. Current body poses do not redefine the bond.

This is a specific proposal to review, not acceptance of the old probe's minimum-endpoint-length convention. If actual authoring cannot supply such correspondence, revise this record before freezing it. Length-based capacities and percentage-reference lifetimes retain `CON-009` and `CON-014` meanings.

### Host-supplied definitions

`DefinitionBundle` contains the match/version and typed definitions. Snapshots refer to exact revisions; the host supplies the complete transitive dependency closure initially and supplies new dependencies before their state becomes applicable. Repeated identical definitions are harmless; conflicting content for the same match/id/revision is invalid.

| Proposed definition | Explicit inputs |
|---|---|
| Material | Density and independently authored blast resistance. |
| Effective body configuration | Material and appearance references; grab eligibility; friction, restitution, damping and collision layer. These additional physical fields are candidates requiring Unity review. |
| Character | Four fixed local roots and maximum reaches; explicit environment body configuration and destruction selection to install on death. |
| Bomb | Fuse duration and nominal radius. The draft's named blast profile represents a review target, not a settled lethality or power/radius algorithm. |
| World | Gravity, collision-layer pairs, fixed-wall body IDs, geometry tolerance and permitted contact-projection distance. Fixedness comes from this world input; zero motion and connectors do not create an extra anchored flag. |
| Destruction response | Typed response profile, selected independently of material. The example names a carve response without pretending its numerical algorithm is settled. |
| Appearance | Example profile: colour plus extrusion depth, generated from current local geometry. External assets and richer appearance profiles require their own complete delivery contract. |

Mass, COM and inertia are proposed to derive from a uniform-density polygon lamina. Joint capacities, Unity objects and visuals derive; do not transmit independently authoritative copies. The numeric geometry tolerance is an explicit input, not permission to enlarge reach or ignore obstruction.

## 4. Exchange and local interfaces

| Producer → consumer | Contract |
|---|---|
| Authoring → Unity | `ImportScene(SceneInput)`, where `SceneInput = {definitions: DefinitionBundle, initialWorld: WorldSnapshot}`. Supply explicit definitions, body-local shapes, placements and endpoint-local connections. Authored IDs are provisional: host integration establishes the match and consistently remaps bodies, relationships, control and fixed-wall references before committing. |
| Unity → Odin | `CaptureCommittedWorld() → {snapshot, requiredDefinitions}`. Capture one internally consistent committed state, then encode its immutable copy. Never mix bodies from one commit with relationships from another. |
| Client → host Unity through Odin | `GrabRequest` or `ReleaseRequest`, with match and request ID. Odin supplies the authenticated participant separately; a packet cannot claim another participant's authority. |
| Host Unity → requesting adapter | Local `committed` or `rejected` request result. Duplicate logical requests must not commit twice. This is an API outcome, not a decision to add a reliable acknowledgement message or a deduplication algorithm. |
| Odin → client reconstruction | Complete `DefinitionBundle` / `WorldSnapshot` records after decoding and assembly. |
| Client reconstruction → local caller | `Applied(number)`, `IgnoredStale`, `NeedsDefinitions(refs)`, `WrongMatch`, `IncompatibleVersion` or `Invalid(reason)`. These are local results, not required wire messages. |

**Grab:** slot, candidate target ID, target-local candidate point and observed geometry revision. The host finds the living controlled character from the roster and validates current target, eligibility, reach, obstruction and geometry. Revision mismatch alone does not decide the result. Projection is bounded by explicit world policy; it cannot rescue fundamentally invalid interactions.

**Release:** slot and expected hold ID. It may retire only that participant's current matching hold. This prevents a delayed release from ending a replacement hold. Movement, pulling, climbing and throwing inputs are deliberately absent pending selected mechanics.

Proposed request IDs are unique per authenticated participant within a match. Snapshot numbers must not wrap within a match. Delivery ordering and the mechanism for deduplicating requests remain open; a repeated logical request cannot become a second action.

This candidate supports only the listed message kinds. Version compatibility is initially proposed to require an exact version match. Future input types, round progression, spawning schedules or lasting character state must get typed fields; an untyped extension bag must not hide them.

## 5. Validation and atomic application

1. Check expected match, version, complete assembly, finite values and ID ranges. Resolve exact definition references and their expected types; missing dependencies produce `NeedsDefinitions`.
2. Validate geometry and unique entity IDs across bodies and relationships. References must point to live records of the right kind. Connector regions must survive on their endpoints and recover one intended fit. Holds must have living owners, valid target locations and unique `(character, slot)` pairs. Eligibility governs starting holds; it does not retroactively end accepted surviving holds.
3. Control references must name living characters with unambiguous control. Fixed IDs must resolve to the world-defined walls. Percentage failure data requires its lifetime reference. No hidden defaults may replace missing required inputs.
4. If the snapshot is newer than the last applied capture number, stage the reconstructed state and expose it atomically. Otherwise ignore it. Failed validation or reconstruction leaves the previous canonical state intact. A newer snapshot waiting on definitions need not stop application of an older complete snapshot that is still newer than the current world.

After 40, a ready complete 42 can apply directly. A delayed 41 cannot overwrite it. Applying 42 does not require observing 41's split or playing its effects. Skipped explosion audio/animation is a separate transient-delivery decision.

These checks cannot prove that a client received every intermediate event, nor establish the correctness of the host's blast calculation. They protect the reconstruction boundary.

## 6. Examples and proposed completion checks

The bundle contains definitions; initial scene 10; held scene 11 with an active fuse; split scene 13; and death scene 14. Every scene is a full snapshot. The numbers intentionally skip 12.

| Case | Expected current state |
|---|---|
| Split | Retire P and bomb B; both pieces have new IDs and complete host geometry/configuration. Keep C on the left piece and L on the right, transforming local regions/point to preserve the original bond and material location. |
| Death | Keep K's body/shape/revision, install explicit corpse selections, clear control and outgoing L, retain the other character's incoming hold. |
| Recovery | Reconstruct scene 13 or 14 directly from that snapshot plus definitions, without P, B, prior snapshots or replay. |
| Reordering | Deliver 13, 11, 13, 10, 14: apply 13 then 14; older/duplicate captures do not overwrite. |
| Motion | Separate same-ID geometry example changes COM and COM velocity while preserving the velocity of a surviving material point. |

All dimensions, densities, fuse durations, tolerances and strengths in these examples are fixture choices. They are not gameplay tuning or bandwidth evidence.

**Proposed integration check:** Unity captures a complete state, Odin encodes/decodes it, and a fresh Unity instance reconstructs the same canonical records and resolved configuration. Check the split, death, control and relationships, not only visual similarity. Record actual encoded bytes, capture/application time and delivery delay on representative arenas afterward. This is a suggested completion criterion, not an approved team milestone.

## 7. Review before freezing

Start with **the common numeric and shape representation**: it is the dependency shared by import, destruction, reconstruction and serialization. Next review the paired connector representation against real authoring cases.

The candidate cannot yet be called the complete game's frozen contract. Unity integration must confirm the additional physics inputs and contact/damping/collision mapping; gameplay must supply selected movement/lasting character inputs, blast lethality/configuration and any actual round/spawn facts. Rich appearance may need an asset profile. Those are concrete missing semantics, not reasons to keep debating transport first.

No current Unity/Odin code compatibility is claimed. The checkpoint contains bounded earlier implementation evidence; its linked immutable report was unavailable for inspection during this draft. The named response and physics profiles remain review targets until connected to actual compatible implementations.

Once the record choices are reviewed, collect accepted changes at an explicit handbook checkpoint. Keep the authoritative requirements in the handbook and link the schema/examples from it; avoid competing descriptions of gameplay rules.

**Requirement anchors:** `AUTH-001–003`, `STATE-001–004`, `WORLD-005–011`, `MAT-005–010`, `IDENTITY-001`, `CON-001–014`, `PLAYER-001–002`, `CHAR-003–006`, `LIMB-001–012`, `BOMB-001–004`, `INTERACT-001–003`, `COMMIT-001–002`, `REBUILD-001`, `NET-001–002`. Complete sources remain in the supplied checkpoint. [Immutable handbook source](https://github.com/jblick1327/Bomb/tree/2973f789f825f3395689fbc6e6b7509d938960e4/handbook).
