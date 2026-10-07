# BOM — Team Model Handoff

**Version:** 0.7  
**Date:** 2026-10-07  
**Purpose:** Shared conceptual ECS baseline for Unity, art/assets, and level design  
**Source:** `BOM Architecture.md` v0.11; decisions through `DEC-056`

This summary gives the team a common model to review. The entity, identity, lifecycle, component/system responsibilities, and contracts below are agreed. These include material density/mass derivation, independent destruction response, declared shape/visual alignment, default fragment-property inheritance, reach-constrained holds, course anchoring, and connector reconstruction. Seven conceptual component groupings, fixed limb roots/reach, minimum hold contents, remaining-duration countdowns, and connector reference lifetimes are now accepted. The death-configuration source, shared material applicability, fixed-wall source, and semantic coordinate convention are also accepted. Remaining values, fields/encodings, storage, authoring formats, and system ordering remain open. The Architecture controls if this summary conflicts with it; examples and review suggestions are non-normative. Collaboration is described through roles/responsibilities that may overlap or be shared.

## Simulation boundary

BOM has authoritative 2D gameplay physics and geometry, with 3D presentation derived locally. The lobby host's Unity simulation computes gameplay outcomes and commits canonical state. Odin handles networking and replication. The networking owner can refine its concrete protocol later; this baseline does not select a wire format or transport.

**Canonical state** is the recoverable description of the current world: it must reconstruct the world without replaying its full history. Unity bodies, colliders, joints, solver caches, meshes, interpolation, and lookup indexes are derived machinery. Each lasting fact has one canonical source.

## Entity and state map

Every physical body shares three state responsibilities: **motion** (position, rotation, linear/angular velocity), **reconstructable gameplay shape**, and **physical configuration** sufficient to derive its engine behaviour. Environment pieces, living characters, and live bombs also share `MaterialProperties`; `CharacterState` and `BombState` supply their particular behaviour. Material-piece mass follows the density/area rule below; further physical inputs and derivations remain open.

| Role | Own physics body? | Additional canonical responsibilities |
|---|---|---|
| Environment/material piece | One body per connected piece | Material/destruction behaviour and interaction eligibility. Static/dynamic motion and destructibility are compositional properties. |
| Living Claymate | One body | Character movement and authoritative limb-interaction state. Hands and feet are local slots, with no independent entities or bodies. |
| Live bomb | One body | `BombState`: inactive countdown or active remaining duration, initialized on landing and advanced by the host. |
| Structural connector | No | Endpoint IDs, attachment regions in endpoint material space, recoverable intended rigid relationship, authored strength, and failure policies. Its engine joint is derived. |
| Limb attachment | No | Minimum state: character ID, limb slot, target ID, target-local held location. Roots/reach come from the character definition; it alone owns the hold. |
| Participant record | No | Stable player match identity and optional controlled-body reference, stored in the canonical match roster. This reference alone owns control assignment. |
| Match progression | No | Lasting spawn/round facts required by the chosen mechanics. Exact spawning, scoring, and round rules remain open. |

These are semantic responsibilities, not a mandatory one-component-per-row layout. Destruction, motion, and interaction eligibility remain independently composable.

Accepted conceptual groupings are `BodyMotion2D`, `BodyShape2D`, `MaterialProperties`, `DestructionBehaviour`, `InteractionPolicy`, `CharacterState`, and `BombState`. `BOM-Candidate-Component-Map.md` v0.4 distinguishes these from proposals and remaining fields. A separate `BodyPhysics` is unaccepted: relationship-imposed restrictions derive from attachments, while level/world data supplies fixed wall geometry, fixed behaviour, and stable endpoint identities. Colour is a variable appearance input; a separate `VisualBinding` and its placement remain open. The map shows roster/match data as canonical dependencies for review; that presentation is not an accepted storage partition or a transfer of authority to networking.

An authored composite object expands into separate material pieces plus connectors. Its authoring container does not automatically become another canonical entity. Persistent physical entities and relationships receive match-scoped IDs; requests and transient events do not automatically enter that namespace.

## Asset and assembly contract

Each authored material section declares a **2D gameplay shape and its alignment with visual data**. An authoring tool may generate the shape. Physics, destruction, mass calculation, and connector placement use that shape; the exact format, units, and alignment encoding remain open.

The shared coordinate contract (`WORLD-006`) is:

| Data | Frame |
|---|---|
| Body position and rotation | World space |
| Body gameplay shape and limb roots | That body's local space |
| Held location | Target body's local space |
| Connector attachment regions | Each endpoint body's local space |
| Visual geometry | Aligned with the body's local gameplay shape |

If splitting changes local frames, structural resolution transforms attachment coordinates to preserve the same surviving material locations. Exact units, origins/pivots, numeric encoding, scaling/alignment data, and tolerances remain open.

For example, a glass platform attached to a wooden support attached to a fixed foundation instantiates as three material entities and two rigid connectors. The authored assembly adds no entity. Asset authoring supplies section data; level composition assembles and places sections and relationships; simulation integration resolves those inputs into canonical state and derived runtime objects. This describes work responsibilities, not a required personnel allocation.

## Material, destruction, and anchoring

Material definitions contain **explicit authored density**. A piece references its definition, so choosing glass resolves a density value. Material-piece mass derives from density multiplied by current gameplay 2D area; geometry loss therefore changes mass. Definition values must resolve consistently when reconstructing the world. Units, exact records, and other physical-property derivations remain open.

**Destruction response is independently selectable from material properties.** Material presets can offer defaults. Shattering is a process; splitting is a possible outcome. Persistent physical material fragments use ordinary material entities and the lifecycle rules below. Decorative particles may be transient. Supporting response selection does not require implementing shattering for the course.

Resulting pieces **inherit material, destruction response, and reusable visual settings by default**; a response may explicitly specify changes. Each result has its own reconstructable state or direct definition references and can reconstruct after its source entity retires. Appearance data applies to the changed shape; inheriting it does not preserve the original unmodified render geometry.

**Fixed foundation pieces plus rigid connectors provide course anchoring.** Structural pieces can attach to foundations through the existing connector model. The level/world definition supplies fixed walls with geometry, fixed behaviour, and stable endpoint identities so connections can reconstruct (`WORLD-005`). Exact reference/configuration encoding remains open. Walls retain the environment model and match-scoped identity; a separate directly-world-anchored destructible-terrain mechanism is not required.

A surviving connector retains its **intended relative position and angle** through reconstruction and endpoint remapping. The whole assembly can move or rotate together. Exact encoding remains open: attachment frames or a rest transform are possible, and existing canonical data should supply the relationship where unambiguous rather than duplicate it in extra fields.

## Agreed lifecycle rules

| Situation | Canonical outcome |
|---|---|
| Material geometry changes | Zero surviving pieces: retire the original. One: preserve its ID and update state. Several: retire the original and assign a new ID to every child. |
| Connector endpoints change | Zero surviving relationships: retire it. One: keep its ID and remap endpoint/attachment data. Several: retire it and create a new connector per valid surviving relationship. |
| A held material piece changes or splits | If the held location survives on a valid result, keep the attachment ID and remap target/coordinates. If the location is lost, retire the attachment. A hold never branches across children. |
| Claymate dies | Keep the body's ID; install environment configuration supplied by the character definition. The corpse reconstructs through ordinary environment records. Clear the participant's controlled-body reference. Release the dead character's own holds; preserve others' holds on surviving locations. |
| Bomb lands | Activate remaining-duration countdown state from selected bomb/fuse configuration. Landing classification, values, units/types, and later-contact policies remain open. |
| Bomb explodes | Retire the bomb; create no persistent bomb fragments. The explosion notification may be transient, while its lasting consequences belong in canonical state. |

Topology and relationship outcomes commit **atomically**. A published state must contain complete splits and valid references. Concurrent destruction of a corpse's held location uses the same hold-loss rule. The character definition supplies corpse material, destruction response, interaction eligibility, and reusable appearance selections (`CHAR-004`). Actual values and transition/reference encoding remain open; no inheritance/override default is selected. Starting new holds uses the installed eligibility policy, while accepted incoming holds continue on surviving locations.

Hands and deliberate foot holds share the limb-attachment entity kind. Each slot has at most one live hold. Material pieces, other characters, and live bombs are valid target categories, subject to the same authored Boolean eligibility policy and ordinary host validation. The policy governs both hand and deliberate foot holds independently of destructibility; ordinary foot contact is unaffected. Ordinary foot contact does not create a persistent hold. A character does not duplicate canonical attachment IDs per slot; efficient lookups are derived.

A hold maintains the limb's **held location while the character body can move and rotate within permitted reach**. The attachment constrains motion beyond reach; visible limbs follow the body/attachment relationship without separate physics bodies. The held point follows a moving target. Fixed body-local limb roots and authored maximum reach come from the character definition. Body poses plus the target-local held location derive the constraint and visible held-limb pose. No independently changing authoritative root pose is required. Exact coordinate/numeric encoding, Unity constraint, tuning, and active controls remain open; applied force alone does not release holds in the current build. Deliberate release and applicable destruction, retirement, and death outcomes still apply.

Rigid environmental connectors can fail from excessive load or attachment loss. Load evaluation includes force and in-plane torque; engine limits derive from the authored strength and attachment geometry. Immediate load failure is required, while accumulated fatigue and non-rigid environmental connectors are outside current course requirements.

If attachment-loss percentage is used, the reference follows connector identity: an ongoing ID keeps its reference; each new ID starts with its own initial attached length as 100%, fixed for its lifetime. Check the old connector against its existing reference before creating replacements. A failed old bond produces no child connectors. Connector strength scales with actual surviving attachment length, so 100% of a smaller reference still means a smaller bond. Optional authored percentage failure is accepted; without the setting, that condition does not apply. No universal numerical cutoff is selected. A bomb countdown uses current remaining duration and needs no shared deadline clock solely for reconstruction.

Character damage **does not accumulate**. Gameplay evaluation kills a character when a blast meets its power/radius lethality condition, then applies the transition above (`CHAR-005`). `CharacterState` needs no health or accumulated-damage value. Exact power/radius values, distance/overlap evaluation, and occlusion remain open.

## Agreed system responsibilities

These responsibilities assign semantic ownership under `ECS-006`. They do not require one class or pass per row or select Unity callbacks, a fixed-step sequence, commit frequency, or physical-impulse timing.

| Responsibility | Work it owns |
|---|---|
| Input and interaction | Validate player requests against current state, using canonical control assignment. |
| Physics integration | Maintain derived Unity bodies and joints; report authoritative motion, contacts, and loads. |
| Gameplay evaluation | Decide when bombs detonate, characters die, or connectors fail. |
| Structural resolution | Compute resulting pieces and relationships, then commit the complete change atomically. |
| Reconstruction and replication | Update derived runtime objects and expose committed semantic results and recovery state to networking. |

Interaction validation checks existing endpoints, current geometry, reach, obstruction, and applicable eligibility. Bounded correction can handle small geometric discrepancies; a revision mismatch alone does not decide validity.

For an explosion, gameplay evaluation triggers it; structural resolution computes affected geometry, identities, connectors, and limb attachments together. Networking receives the committed result rather than a partially applied change.

## Worked example: a supported piece splits

Suppose piece P is joined to fixed foundation F by connector C, and a character holds P through limb attachment L. An explosion splits P into two valid pieces. For this example, C's attachment survives only on P1, and the held location survives on P2.

| Concern | Result |
|---|---|
| Material identity and mass | Retire P; assign new IDs to P1 and P2. Derive each result's mass from its resolved density and resulting area. |
| Material/response/appearance settings | P1 and P2 inherit P's definitions/settings by default, with changes only where the response explicitly specifies them. Each result reconstructs without consulting retired P. |
| Structural connection | First evaluate any attachment-loss test against C's existing reference. If it passes and one relationship survives, keep C's ID/reference; remap its endpoint to P1 while preserving the intended fit. Otherwise retire it. |
| Character's hold | Keep L's ID; remap its target and held-location coordinates to P2. The held point follows P2; the character body may move/rotate within reach. The hold does not branch. |
| Publication and runtime objects | Commit these outcomes together. Affected bodies/joints/visuals and replicated state reflect that complete outcome. Exact scheduling remains open. |

If a held location is lost, retire that hold instead. If no valid structural attachment survives, retire the connector. If several relationships survive and the old connector passes its attachment-loss test, retire it and create a new connector per relationship, each with its own initial reference. This example illustrates accepted outcomes without choosing a geometry format or fragmentation algorithm.

## Work roles and contracts

| Work role | Agreed design boundary | Useful next review |
|---|---|---|
| Simulation integration | Body/relationship state is reconstructable. Material-piece mass follows current shape and density. Structural resolution owns complete topology outcomes; limb holds constrain reach. | Trace reconstruction, the worked split, held-body motion, and death using the accepted sources and coordinate convention; identify remaining physical derivations and scheduling needs. |
| Asset authoring | Material sections declare gameplay shape and visual alignment. Reusable appearance data supports resulting shapes; visible limbs follow one body's hold relationships. | Check shape/visual alignment in the accepted body-local frame, shared material inputs, death settings, visual regeneration, and limb pose inputs with integration. |
| Level composition | Compose pieces, fixed foundations, and rigid connectors. Select material and response independently. Authors provide one connector-strength value. | Check fixed-wall inputs/endpoint identities and the representative composite's local attachment regions, resolved definitions, and effective eligibility settings. |

These review suggestions do not prescribe an implementation slice or make temporary tooling conventions architectural rules.

## Implementation and authoring boundaries

**Current build policies:** connector strength scales with surviving attachment length; authors may configure independent percentage-loss failure; one Boolean eligibility policy governs hand and deliberate foot holds, including live bombs; applied force alone does not release holds. These are accepted requirements under `CON-009`, `CON-010`, and `LIMB-005` through `LIMB-007`. Actual authoring values, formulas, and encoding still need implementation contracts.

**Important integration/authoring seams:** geometry format and local-coordinate/alignment encoding; definition/reference encoding and units; remaining physical-property derivations; response algorithms and explicit result-property changes; visual regeneration; connector attachment/intended-relationship encoding; limb coordinate encoding, further movement inputs and engine constraint implementation; fixed-support reference/configuration encoding; actual corpse settings and transition encoding; detailed execution and commit scheduling. The ownership and semantic behaviour above are settled; implementation contracts remain explicit review items.

**Next activity:** use `BOM-Team-Handbook.html` for a guided walkthrough, source-linked reference, and proposed starting work by role. Its work cards give deliverables, dependencies, and completion checks; the team chooses assignees and the minimal implementation conventions. The work plan is recommended, not additional architecture. Take candidate map v0.4 and this summary into team review: can a snapshot plus validated definitions reconstruct a running scene with all relationships and behaviour accounted for? Trace the supported/held scene, split, death, and countdown across the work roles. No further semantic decision needs forcing before review; raise one focused question only when a concrete case exposes a material gap. Exact records/ECS framework, geometry tooling, and networking schema, transport, rates, compatibility, and correction strategy remain open. Refine contracts as their roles need them; this handoff does not require resolving every implementation question before review.

For the full rules and rationale, use `BOM Architecture.md`, `BOM Decision Log.md`, and `BOM Open Questions.md`. `BOM Model Interview Handoff.md` carries the ongoing design and checkpoint procedure.
