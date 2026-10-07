# BOM Architecture Open Questions

**Version:** 0.10  
**Last updated:** 2026-10-07  
**Normative source:** `BOM Architecture.md`

## 1. Interpretation

Nothing in this file is an accepted architectural rule. These questions identify missing decisions without silently filling them in. When a question is resolved, its outcome should be added to `BOM Architecture.md` and its reasoning recorded in `BOM Decision Log.md`.

Priority meanings:

- **P0:** Blocks a faithful implementation of the current architecture.
- **P1:** Needed for a robust networked prototype but not for the earliest local slice.
- **P2:** Can remain deferred until testing or expansion exposes the need.

These priorities describe implementation needs, not the order of the conceptual design interview. Component responsibilities, coarse system ownership, and seven conceptual groupings are accepted under `ECS-005` to `ECS-007`. Fixed limb roots/reach, minimum hold contents, remaining-duration bomb countdowns, and connector reference lifetimes are also settled. Character definitions now supply death-to-environment configuration; `MaterialProperties` applies to living characters and bombs; level/world data supplies fixed walls; world/body-local frame roles are settled. Remaining values, fields/encodings, execution order, and detailed coordination stay open. The immediate goal is a team-facing conceptual handoff for Unity, art, and level design. Networking refinement can wait for its owner. A useful model can retain explicit unresolved policies; the questions below are not an exhaustive serial interview.

**Resolution status:** `OQ-CON-004` remains resolved by `CON-014` / `DEC-046`. This checkpoint settles the death-configuration source (`CHAR-004` / `DEC-047`), shared material-record applicability (`MAT-009` / `DEC-048`), fixed-wall input source (`WORLD-005` / `DEC-049`), and semantic coordinate frames (`WORLD-006` / `DEC-050`). Character damage does not accumulate, and blast power/radius lethality is settled at the semantic level (`CHAR-005` / `DEC-051`). The related questions below are narrowed: actual settings, remaining derivations, units, references, and implementation are still open. Earlier limb inputs and countdown representation remain settled. The 7 October review accepts length-based connector strength and optional percentage failure, makes live bombs ordinary eligible hold targets, excludes automatic limb force breakage from the current build, and accepts shared Boolean hand/foot eligibility (`DEC-052` through `DEC-056`). Numerical settings and implementation contracts remain open as stated below.

## 2. Geometry and destruction

### OQ-GEO-001 — Canonical geometry representation

**Priority:** P0  
**Related rules:** `WORLD-002`, `MAT-007`, `IDENTITY-001`

Authored material sections declare a 2D gameplay shape and aligned visual data under `MAT-007`. What exact data structure represents initial and changed canonical geometry? This includes contour representation, numeric precision or quantization, winding and hole semantics, validation, and the polygon-processing library.

### OQ-GEO-002 — Geometry replication form

**Priority:** P0  
**Related rules:** `NET-001`, `NET-002`, `WORLD-002`

After subtraction, does the host primarily replicate the destruction operation, the resulting contours, or a hybrid with authoritative correction?

### OQ-GEO-003 — Minimum valid material geometry

**Priority:** P1  
**Related rules:** `IDENTITY-001`

What happens to tiny, degenerate, or numerically invalid geometry results? Define minimum area, edge length, vertex count, and cleanup behavior without allowing implementation artifacts to create unstable entities.

### OQ-GEO-004 — Damage reach and occlusion

**Priority:** P1  
**Related rules:** `WORLD-003`, `CHAR-005`

Precisely how does a surface-originating explosion affect overlapping material entities? Define whether material shields other material, whether subtraction applies to every polygon in the blast volume, and how exposed cavities behave. Character lethality uses a blast power/radius condition with no accumulated damage under `CHAR-005`; its exact geometric test and shielding/occlusion remain open.

### OQ-MAT-001 — Canonical material and body properties

**Priority:** P0  
**Related rules:** `MAT-002`, `MAT-005`, `MAT-009`, `STATE-002`, `REBUILD-001`

Density placement and material-piece mass derivation are settled under `MAT-005`: material definitions explicitly author density, pieces reference the definition, and mass derives from density multiplied by current gameplay 2D area. `MaterialProperties` also applies to living characters and live bombs under `MAT-009`; their material input source is settled. Which additional material/body properties are canonical, and how are mass for those roles, center of mass, inertia, collision category, friction, damping, and other engine inputs derived? Define units, definition/reference validation, and any per-instance override policy without duplicating canonical facts.

### OQ-MAT-002 — Destruction-response authoring and implementation

**Priority:** P1  
**Related rules:** `MAT-006`, `MAT-008`, `IDENTITY-001`, `COMMIT-002`

Independent response selection and ordinary material-result semantics are settled. Results inherit material, response, and reusable visual settings by default, with explicit response-specified changes permitted (`MAT-008`). Which response kinds are needed for the course, how are effective settings and explicit result-property changes encoded and reconstructed, and which algorithms implement them? `MAT-006` does not require shattering or every possible response kind; leave additional kinds for demonstrated feature needs.

### OQ-ASSET-001 — Shape/visual alignment and reconstruction encoding

**Priority:** P0  
**Related rules:** `MAT-007`, `MAT-008`, `WORLD-002`, `WORLD-006`, `STATE-001`, `REBUILD-001`

The declared shape/visual contract, default result-property inheritance, and semantic frame roles are settled. `WORLD-006` puts body poses in world space and gameplay shapes, roots, and endpoint attachments in their respective body-local spaces; visual geometry aligns with the local shape. Which exact units, local origins/pivots, scaling/alignment data, numeric encoding, validated definition references, and reusable visual inputs implement those contracts? How do changed pieces reconstruct appropriate visuals without requiring a retired parent's state? Colour is at least one variable appearance input identified in review. Its definition/instance ownership and whether these inputs form a separate `VisualBinding` record remain open. No visual regeneration algorithm or exact authoring format has been chosen.

### OQ-WORLD-001 — Indestructible geometry reconstruction contract

**Priority:** P0  
**Related rules:** `WORLD-002`, `WORLD-005`, `MAT-004`, `STATE-001`, `REBUILD-001`

Identity is resolved: indestructible geometry such as bedrock uses the shared persistent environment/material entity model under `MAT-004`. What canonical geometry data or validated authored reference makes each piece reconstructable? Geometry storage and authoring dependencies remain open; entity identity does not require duplicating immutable asset data in every snapshot. For fixed simulation walls, the level/world definition supplies geometry, fixed behaviour, and stable endpoint identities under `WORLD-005`. How are those inputs and their validated references encoded while preserving match-scoped identities and reconstructable connections? The source is settled; this encoding question does not require a generic `BodyPhysics` record or duplicate attachment-induced anchoring flags.

## 3. ECS and structural processing

### OQ-ECS-001 — ECS implementation

**Priority:** P0  
**Related rules:** Section 5 of `BOM Architecture.md`

Will BOM use Unity Entities, a custom ECS, or another data-oriented implementation? The semantic architecture should remain independent, but the storage and query model must be selected for implementation.

### OQ-ECS-002 — Remaining record boundaries and system interfaces

**Priority:** P0  
**Related rules:** `ECS-005`, `ECS-006`, `ECS-007`, all entity sections

`BodyMotion2D`, `BodyShape2D`, `MaterialProperties`, `DestructionBehaviour`, `InteractionPolicy`, `CharacterState`, and `BombState` are accepted conceptual groupings. Which remaining fields, definition inputs, unaccepted groupings, and system interfaces are needed by demonstrated reconstruction or transition gaps? A separate `BodyPhysics` and `VisualBinding` are not accepted. Showing roster/match data as dependencies outside the body/relationship catalogue is a recommendation, not an accepted storage or authority split. Shared material applicability and the death/fixed-wall input sources are settled under `MAT-009`, `CHAR-004`, and `WORLD-005`; frame roles follow `WORLD-006`. The current map is `BOM-Candidate-Component-Map.md` v0.4; source rules control its status labels.

Review the assembled map and its reconstruction/transition checks before opening another detailed question. Avoid repeatedly debating names or tuning values when the underlying fact is already represented. Framework, memory/wire layout, and scheduling remain distinct decisions.

### OQ-COMMIT-001 — Simulation and commit pipeline

**Priority:** P0  
**Related rules:** `ECS-002`, `ECS-006`, `COMMIT-001`, `COMMIT-002`

At what point in the fixed update are commands gathered, geometry operations evaluated, physics results read, structural outcomes resolved, and mutations committed?

Coarse ownership is settled under `ECS-006`: gameplay evaluation triggers effects, structural resolution computes and commits complete outcomes, and reconstruction/replication uses committed state. What execution order, callbacks, number of commit boundaries, and physical-impulse timing implement that ownership consistently? No fixed-step sequence has yet been accepted.

### OQ-ID-001 — ID representation and allocation

**Priority:** P1  
**Related rules:** `ECS-001`

What concrete ID type and allocator provide match-scoped uniqueness? Define retirement tracking, stale references, debugging representation, and whether IDs are ever reused during a match.

## 4. Connector model

### OQ-CON-001 — Canonical attachment representation

**Priority:** P0  
**Related rules:** `CON-001`, `CON-002`, `CON-011`, `WORLD-006`

Each attachment region uses its endpoint body's local space under `WORLD-006`. How are regions encoded, intersected, and transformed after destruction while preserving the same surviving material locations? The frame role is settled; representation and numerical details remain open.

### OQ-CON-002 — Intended rigid relationship encoding

**Priority:** P0  
**Related rules:** `CON-003`, `CON-004`, `CON-013`, `STATE-004`, `REBUILD-001`

Preserving the intended relative position and angle is settled under `CON-013`. How do canonical attachment frames, a rest transform, or other unambiguous data encode that relationship, and how does Unity reconstruction retain it after endpoint remapping? Derive it from existing canonical data where possible rather than requiring duplicate fields. Current poses alone must not silently redefine a surviving bond.

### OQ-CON-003 — Strength derivation formula

**Priority:** P0  
**Related rules:** `CON-007`, `CON-008`, `CON-009`, `CON-010`, `CON-014`

How does authored bond strength and current attachment geometry produce force and torque limits? The rule should be intuitive for designers without pretending to provide unnecessary physical fidelity. Define the surviving attachment-length measure and how paired endpoint regions contribute to that measure, including the old-connector failure test under `CON-014`; the reference-lifetime rule is already settled.



### OQ-CON-005 — Joint-load measurement safeguards

**Priority:** P1  
**Related rules:** `CON-006`, `CON-007`

Does immediate force or torque failure need an arming step, hysteresis, or another numerical safeguard against artificial solver spikes when joints are created or reconstructed?

### OQ-CON-006 — Attachment-loss authoring settings

**Priority:** P1  
**Related rules:** `CON-010`

Optional authored percentage failure is accepted. Without the setting, that failure condition does not apply. Which explicit percentages should course-authored fixtures use, what defaults should authoring tools offer, and how is the optional setting encoded? No universal cutoff is selected.

### OQ-CON-007 — Connector component composition

**Priority:** P1  
**Related rules:** `CON-003`, `CON-005`, `ECS-004`

Which concerns become separate components: rigid behavior, force breakage, attachment-loss breakage, authored strength, endpoint regions, and failure presentation?

## 5. Characters and limb attachments

### OQ-LIMB-001 — Reach constraint implementation

**Priority:** P0  
**Related rules:** `LIMB-001`, `LIMB-003`, `LIMB-006`, `LIMB-010`, `LIMB-011`, `LIMB-012`

The hold maintains the target location while the body may move/rotate within permitted reach. Fixed body-local roots and authored maximum reach come from the character definition; minimum attachment contents are settled. Which engine constraint, coordinate/numeric encoding, and tuning implement that behaviour? Hands and deliberate foot holds share the attachment architecture and eligibility policy. Automatic force breakage is excluded from the current build under `LIMB-006`. Active pulling/climbing controls have not been selected by the reach baseline.

### OQ-LIMB-002 — Remaining attachment resolution details

**Priority:** P0  
**Related rules:** `LIMB-001`, `LIMB-002`, `LIMB-008`, `LIMB-009`, `LIMB-012`, `COMMIT-002`, `IDENTITY-001`

Semantic remapping is settled: a surviving held location follows its valid resulting target while retaining the attachment ID; a destroyed or invalid held location releases the hold, with no branching (`LIMB-008`). Death releases the dying character's own holds and preserves others' holds on surviving locations (`LIMB-009`). The accepted minimum record uses a target-local held location (`LIMB-012`). `WORLD-006` settles frame roles and requires transforms to preserve surviving material locations. What exact numeric encoding, transformation implementation, numerical tolerance, and boundary-disambiguation policy implements those rules? Define round-reset termination. Endpoint retirement must leave no dangling references; any surviving-target remapping still follows the accepted identity and validity rules. Do not introduce relocation from a destroyed location merely to keep a hold alive.

### OQ-LIMB-003 — Remaining character movement and pose inputs

**Priority:** P1  
**Related rules:** `HAND-001`, `FOOT-001`, `LIMB-010`, `LIMB-011`, `LIMB-012`, `ECS-007`

Fixed definition roots/reach, endpoint body poses, and the target-local held location cover the accepted hold baseline. Does any selected active movement mechanic require additional lasting character inputs beyond that baseline? If so, give each fact one recoverable source. Exact visible-limb construction remains a presentation/authoring contract; do not add independently changing authoritative roots, duplicate attachment ownership, or limb bodies without a demonstrated need.

### OQ-LIMB-004 — Bomb target eligibility

**Status:** Resolved  
**Related rules:** `LIMB-004`, `LIMB-005`, `LIMB-007`

Resolved by `DEC-054`: live bombs are valid hold targets subject to their effective authored eligibility and ordinary host validation. Their category imposes no blanket exclusion. Bomb retirement ends targeting holds in the complete structural outcome.

### OQ-LIMB-005 — Grab-eligibility authoring and encoding

**Priority:** P1  
**Related rules:** `LIMB-007`, `LIMB-004`, `INTERACT-002`, `STATE-001`

The authored Boolean and shared hand/deliberate-foot scope are accepted by `DEC-056`. What authoring defaults, exact record placement, and definition/reference encoding make the effective value available for host validation and reconstruction? `is_grabbable` is an illustrative name, not a required component field. Existing hold continuity remains governed by `LIMB-008` and `LIMB-009`.

### OQ-CHAR-001 — Canonical death-to-environment transition

**Priority:** P0  
**Related rules:** `CHAR-002`, `CHAR-003`, `CHAR-004`, `PLAYER-002`, `LIMB-009`, `ECS-005`, `MAT-004`, `COMMIT-001`, `STATE-001`

The accepted semantic transition ends character behaviour, establishes environment behaviour on the same body ID, clears the participant's control reference, retires outgoing holds, and preserves incoming holds on surviving locations. The character definition supplies the environment configuration applied on death under `CHAR-004`; the transition installs those selections into environment records, and the corpse then reconstructs without its former living state. What actual material, destruction, interaction, and appearance settings are selected, and how are the transition records and validated references encoded? No corpse inheritance/override default is selected. Concurrent geometry outcomes still follow ordinary identity and hold rules. This does not require independently simulated limbs.

## 6. Bombs and match state

### OQ-BOMB-001 — Landing semantics and remaining bomb configuration

**Priority:** P0  
**Related rules:** `BOMB-001`, `BOMB-002`, `BOMB-003`, `BOMB-004`, `ECS-007`, `EVENT-001`, `STATE-001`

Landing starts the countdown; canonical timer state is inactive or active with remaining duration, initialized from selected bomb/fuse configuration and advanced by the host. That representation is settled and does not require a shared deadline clock. How is a valid landing identified, what fuse/explosion settings are selected, and how are their values/references and duration units encoded? If needed, define responses to later support loss or further landings and detailed update/detonation ordering. Character blast lethality does not accumulate damage (`CHAR-005`); exact power/radius values and mapping remain open. These values and policies need not all be resolved for the conceptual map.

### OQ-MATCH-001 — Match-level canonical state

**Priority:** P0  
**Related rules:** `STATE-001`, `STATE-002`, `AUTH-003`, `PLAYER-001`, `PLAYER-002`, `ECS-005`, `CHAR-003`

Participant placement and control ownership are settled: canonical match-roster records contain player identity and the sole optional controlled-body reference (`PLAYER-002`). Which additional round phase, bomb-scheduling, player-result, scoring, and winner facts are required by the chosen mechanics, and how do connection identities map to participants? The first-pass catalogue locates lasting spawning/round facts in match progression; exact mechanics and records remain open. Earlier game documents do not automatically ratify those mechanics.

## 7. Networking

### OQ-NET-001 — Transport and delivery channels

**Priority:** P1  
**Related rules:** `NET-001`

Select the networking library and determine reliable versus unreliable delivery for lifecycle changes, geometry, snapshots, inputs, and transient events.

### OQ-NET-002 — Tick and replication rates

**Priority:** P1  
**Related rules:** `AUTH-001`, `NET-002`

Choose the authoritative simulation rate, input-send rate, snapshot or correction rate, and interpolation buffer. Previously suggested numerical values are not accepted decisions.

### OQ-NET-003 — Client correction strategy

**Priority:** P1  
**Related rules:** `AUTH-002`, `NET-002`, `REBUILD-001`

Define how clients reconcile predicted pose, limb attachments, geometry, and connector state after authoritative results arrive.

### OQ-NET-004 — Join and recovery snapshot

**Priority:** P1  
**Related rules:** `STATE-001`, `REBUILD-001`

Define snapshot boundaries, ordering, and validation for joining or rebuilding a client from current canonical state.

### OQ-NET-005 — Host departure

**Priority:** P2  
**Related rules:** `AUTH-001`

Confirm whether the match terminates when the host leaves or whether any authority-transfer behavior is required. The GDD mentions termination, but this has not been ratified in the architecture discussion.

### OQ-NET-006 — Transient-event delivery and deduplication

**Priority:** P1  
**Related rules:** `EVENT-001`, `NET-001`, `NET-002`

Which transient events are sent over the network, how are late or duplicate deliveries handled, and which effects should instead be derived from replicated canonical consequences?

### OQ-NET-007 — Protocol evolution and compatibility

**Priority:** P1  
**Related rules:** `NET-001`, `NET-002`, `STATE-001`

How are Unity and Odin schemas coordinated as gameplay state and message types evolve? Choose the compatibility/version policy, message/field evolution rules, and any supported historical versions. The discussion recommended a provisional semantic contract and matching compatible builds, but no serializer or compatibility policy has been accepted. New lasting state must remain recoverable under `STATE-001`. This is networking-owner work and can wait while the team-facing baseline is prepared.

## 8. Scope and production constraints

### OQ-SCOPE-001 — Multiplayer capacity

**Priority:** P1  
**Related rules:** Course scope

Resolve the conflict between the older ten-player GDD target and the newer four-player direction.

### OQ-SCOPE-002 — First implementation slice

**Priority:** P0  
**Related rules:** Section 14 of `BOM Architecture.md`

Select the smallest ordered implementation slice that proves the canonical model. Its contents and precise order have not yet been accepted.

## 9. Deferred extensions

The following are intentionally outside current course requirements unless promoted through a new decision:

- Hinge, elastic, and sliding environmental connectors.
- Accumulated connector fatigue or stress damage.
- Detached character limbs or independently simulated hands and feet.
- Persistent bomb fragments.
- A fully formal machine-readable architecture DSL.
