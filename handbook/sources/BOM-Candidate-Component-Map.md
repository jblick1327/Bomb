# BOM — Candidate Component and Data Map

**Version:** 0.6  
**Date:** 2026-10-08  
**Status:** Review map containing accepted conceptual groupings and explicitly marked candidates  
**Baseline:** `BOM Architecture.md` v0.12; decisions through `DEC-061`

This map assembles the current model. Architecture controls if a summary or example conflicts with it. Seven groupings are accepted under `ECS-007`; that acceptance does not ratify every remaining field, definition placement, numeric type, or implementation boundary. Other groupings below remain candidates. A row describes semantic contents, not a serializer, engine class, memory layout, or requirement for one implementation component per row.

The design focus is the information that must survive and the systems that change it. Use concrete reconstruction and lifecycle cases to expose missing facts. Packaging choices and configurable values can stay open when the underlying responsibility is already represented.

## 1. Reading the map

| Data category | Meaning |
|---|---|
| Stored canonical facts | Current identities, shape, motion, effective configuration selections, persistent relationships, and lasting gameplay state. |
| Validated definition inputs | Reusable values selected by canonical state. Recovery must resolve the same effective values. Embedding, references, and validation encoding remain open. |
| Derived values and machinery | Density-times-area mass for all physical roles, connector capacities, transformed limb roots/held points, constraints, Unity objects, visual meshes, indexes, and caches. |
| Transient work | Requests, contact/load observations, triggers, pending structural plans, and notifications. Lasting consequences enter canonical state. |

A snapshot plus its permitted, validated dependencies must reconstruct the world. A definition reference does not make a required input optional. Store each fact once: avoid a resolved value beside an independently authoritative definition of that same fact.

## 2. Body and property records

Persistent physical entities have match-scoped identity metadata. Identity need not be a gameplay component; its concrete type/allocation remains open.

| Record grouping | Status | Canonical contents or selected inputs | Applies to | Derived values and remaining choices |
|---|---|---|---|---|
| `BodyMotion2D` | Accepted grouping | World-space pose of the local frame; world-space velocity of the current centre of mass; rate of change of body angle (`WORLD-006`). | Environment pieces, living characters, live bombs. | Unity body state/interpolation derive from committed motion. Geometry/frame changes intended to preserve motion preserve surviving material movement, including same-ID results. Numeric types, units, COM/inertia derivation and other motion policies remain open. |
| `BodyShape2D` | Accepted grouping | Recoverable current body-local 2D gameplay shape, or an eligible validated immutable shape reference. Geometry revision is a candidate field here. | Physical bodies. | Colliders, area, bounds, and render geometry derive. Body-local frame meaning is accepted under `WORLD-006`; shape format, local origin/pivot, revision encoding, units, and immutable-reference contract remain open. |
| `MaterialProperties` | Accepted grouping and shared applicability | Selected material definition/effective material-property inputs. | Environment/material pieces, living characters, live bombs; corpses use installed environment selections (`MAT-009`, `CHAR-004`). | Explicit density resolves from material definitions; mass for environment pieces, living characters, and live bombs derives as density × current gameplay area. Further physical inputs/derivations, values, units, and instance overrides remain open. Blast-resistance inputs and their source remain open under `OQ-GEO-004`. |
| `DestructionBehaviour` | Accepted grouping | Destructibility and independently selected effective destruction response/settings, where applicable. | Environment/material pieces. | Response algorithms produce shape/property outcomes. Exact settings and indestructibility representation remain open; shattering is not required. |
| `InteractionPolicy` | Accepted grouping | Effective interaction-eligibility setting or validated policy inputs needed by host validation. | Applicable target bodies. | One authored Boolean governs hand and deliberate foot holds, including live bombs (`LIMB-005`, `LIMB-007`). Host validation still applies. Authoring defaults, record placement, and encoding remain implementation work. |
| `VisualBinding` | Candidate grouping | Reusable appearance inputs and the alignment needed to interpret them with gameplay shape; colour is at least one variable input. | Bodies as needed; material results carry their own recoverable appearance inputs. | Meshes/presentation derive locally. A separate record, colour's definition/instance ownership, alignment encoding, and regeneration remain open. Results must not depend on a retired parent. |

### Physical inputs and fixed supports

`BodyPhysics` has not been accepted as a separate component and is omitted from the assumed compositions below. The physical-configuration responsibility remains: any lasting input needed to reconstruct body behaviour must have a recoverable source. Material inputs belong to their chosen material/property source; attachment-imposed restrictions derive from the connectors/holds imposing them. Do not add an independent anchored flag to duplicate those relationships.

The level/world definition supplies fixed simulation walls with geometry, fixed behaviour, and stable endpoint identities (`WORLD-005`). Recovery includes those inputs or their permitted validated dependencies. Exact reference/configuration encoding remains open. Walls stay in the environment/foundation model with match-scoped identities; no generic per-body motion-policy record is selected.

Living characters and live bombs also use `MaterialProperties` (`MAT-009`), alongside their role-specific state. Their material input source is settled. Additional physical inputs and derivations, including collision settings, remain open under `OQ-MAT-001`; shared applicability does not automatically place every engine input in material properties or select engine defaults.

## 3. Character and bomb records

| Record grouping | Status | Canonical contents or selected inputs | Definition inputs and derived boundary |
|---|---|---|---|
| `CharacterState` | Accepted grouping; remaining contents partly open | Selected character definition and any independently lasting inputs required by the movement/interaction mechanics actually selected. No duplicate participant-owner or attachment-ID fields. | Each limb slot has a fixed body-local root and authored maximum reach in the definition (`LIMB-011`). Body motion and attachment state derive the reach constraint and held-limb pose. The character definition also supplies environment configuration applied on death (`CHAR-004`). Character damage does not accumulate, so no health/damage value is required (`CHAR-005`). Actual corpse settings, active controls, further gameplay inputs, and encoding remain open. |
| `BombState` | Accepted grouping and countdown baseline | Selected bomb configuration; countdown is inactive, or active with remaining duration (`BOMB-004`). Landing activation initializes duration from selected bomb/fuse configuration; the host advances it. | Recovery uses current countdown state without replaying landing or requiring a shared deadline clock. The first valid landing starts the fuse. Holding, throwing, support loss, and later landings preserve its progress; expiry detonates at the current position (`BOMB-003`). Landing classification, fuse/explosion settings, units/types/precision, and detailed update/detonation order remain open. |

Fixed roots/reach are definition inputs, not changing copies on every hold. There is no separately changing authoritative limb-root pose in the accepted baseline. The definition may still have other authoring/presentation inputs, and a later selected movement mechanic may expose additional canonical character state.

Death keeps the body's identity and changes it to environment behaviour under `CHAR-003`. A `CharacterState` → environment composition change is a candidate realization. A separate `is_dead` flag is unnecessary merely to duplicate that composition; any independently meaningful match/result fact must be represented if its mechanic is selected. The character definition supplies the environment selections installed on death (`CHAR-004`): material, destruction response, interaction eligibility, and reusable appearance. Thereafter, the corpse reconstructs from ordinary environment records and validated definitions without former living state or replaying death. Actual values and transition/reference encoding remain open; no inheritance/override default is selected.

## 4. Persistent physical relationships

| Record grouping | Status | Canonical contents or selected inputs | Derived values and remaining choices |
|---|---|---|---|
| `StructuralConnection` | Candidate grouping around accepted relationship rules | Endpoint IDs; paired endpoint-local attachment regions sufficient to recover the intended rigid fit; authored strength and applicable failure-policy inputs. Any percentage reference follows `CON-014` and must be recoverable. | Attachment data may already determine relative position/angle. Add rest data only if the selected encoding leaves that fit ambiguous. Unity joint and capacities derive: `Fmax = S × L`, `Tmax = ½ × S × L²` (`CON-009`). One authored strength and optional percentage failure are accepted. Attachment encoding, paired length measurement, load conversion, authoring values, and implementation remain open. |
| `LimbAttachment` | Accepted minimum record contents | Character ID, limb slot, target ID, target-local held location; persistent relationship identity is entity metadata (`LIMB-012`). | Fixed root/reach resolve from the character definition; endpoint poses from body motion. Constraint, visible held-limb pose, and `(character, slot)` lookup derive. Exact coordinates/types and remapping tolerances remain open. Applied force alone does not release holds in the current build; no grip-strength threshold is required. Additional attachment-specific state is not silently included in the minimum. |

Both are persistent relationships with IDs and no physics body. Each limb slot has at most one live hold. The attachment alone owns that relationship; the character does not store a second authoritative attachment reference.

### Connector reference lifetime

The reference-lifetime rule is accepted (`CON-014`). Optional authored percentage failure is also accepted (`CON-010`); these reference rules apply when that setting is configured.

| Outcome | Reference length and failure evaluation |
|---|---|
| One connector keeps its ID after shortening/remapping | Keep its existing reference length, fixed for that ID's lifetime. |
| A connector is newly created | Its own initial attached length becomes its fixed reference. |
| Several relationships replace an old connector | Test the old connector against its existing reference before creating replacements. If it passes, retire it and create each child connector with its own initial surviving attachment as 100%. |
| The old connector fails its attachment-loss test | Retire the bond; create no replacements from it. |

A child at 100% has not regained the old bond's absolute strength. Under the accepted length-based strength policy, capacity follows actual surviving attached length. No numerical cutoff is accepted: 40% and the lengths used in the walkthrough were examples. Store or resolve the reference so later reconstruction does not need a retired parent or lost geometry.

## 5. Canonical match dependencies

This section is a recommended presentation boundary for the review map. These facts remain in the same authoritative simulation. The user questioned their relevance as body components; their separate placement here is not an accepted storage partition or a transfer to networking.

| Canonical match dependency | Status | Canonical contents | Relevance to this slice |
|---|---|---|---|
| `ParticipantRecord` | Canonical responsibility accepted; record grouping/placement still a candidate | Stable participant identity and optional controlled-body ID in the canonical match roster. | Supplies the sole control assignment used by interaction validation. Death clears it atomically; reverse lookup is derived. Connection mapping, scoring, and respawn rules remain open. |
| `MatchState` | Canonical responsibility accepted; broad placeholder outside the body/relationship catalogue | Lasting spawn/round facts required by mechanics actually selected. Exact fields remain open. | Refer to it only where a selected mechanic needs lasting match facts. The accepted bomb countdown does not require a shared deadline clock. No scoring, winner, scheduling, or random-state scheme is selected. |

## 6. Definitions and entity composition

Definitions are reusable inputs, not additional physical entities. The following is a candidate authoring organization. Its required facts and accepted placements are marked explicitly.

| Definition/configuration source | Inputs it supplies or may supply |
|---|---|
| Material definition | Explicit density and shared material input ownership for environment pieces, living characters, and live bombs are accepted; all three derive mass from density × current area. Additional physical and blast-resistance inputs/derivations remain open. |
| Destruction-response definition | Independently selected response and parameters. Presets can offer defaults; effective selection remains recoverable. |
| Appearance inputs | Reusable visual settings and shape alignment; colour may vary. Definition/instance division and a separate `VisualBinding` remain open. |
| Character definition | Fixed body-local limb roots and authored maximum reach are accepted. It supplies the environment configuration installed on death: material, destruction response, interaction eligibility, and reusable appearance. Actual values, other movement inputs, and encoding remain open. |
| Bomb definition/configuration | Selected fuse/explosion inputs; exact values/encoding and physical defaults remain open. |
| Level/world definition | Supplies fixed wall geometry, fixed behaviour, and stable endpoint identities (`WORLD-005`). Exact validated references/configuration encoding remain open; no separate `BodyPhysics` is assumed. |

Instantiation resolves effective selections. An authoring default is not a second canonical selection. Definition validation must prevent reconstruction from silently substituting different values.

| Role | Current conceptual composition |
|---|---|
| Environment piece | Identity + `BodyMotion2D` + `BodyShape2D` + `MaterialProperties` + `DestructionBehaviour` + applicable `InteractionPolicy`; recoverable appearance and any further justified physical inputs. |
| Living Claymate | Identity + `BodyMotion2D` + `BodyShape2D` + `MaterialProperties` + `CharacterState` + applicable `InteractionPolicy`; recoverable appearance and further justified physical inputs. Definition roots/reach and live holds supply the accepted limb baseline. |
| Live bomb | Identity + `BodyMotion2D` + `BodyShape2D` + `MaterialProperties` + `BombState` + applicable `InteractionPolicy`; recoverable appearance and further justified physical inputs. Bombs are valid hold targets subject to ordinary authored eligibility and host validation. |
| Structural connector | Identity + candidate `StructuralConnection`; no body. |
| Hand/foot hold | Identity + minimum `LimbAttachment`; no body. |
| Participant/match dependencies | Canonical roster and applicable match-level facts; no additional physical control-assignment relationship. |

An authored composite expands into pieces and connectors; this map adds no assembly entity. Fixed supports stay within the accepted environment/foundation model. Role names describe compositions, not a class hierarchy or mandatory redundant role enum. These compositions show semantic coverage and remaining inputs, not complete executable schemas.

### Shared coordinate contract

The semantic convention is accepted under `WORLD-006`:

| Information | Frame |
|---|---|
| Body position and rotation | World-space pose of the local frame |
| Body linear velocity | World-space velocity of the current centre of mass |
| Body angular velocity | Rate of change of body angle |
| Body gameplay shape and character limb roots | That body's local space |
| Held location | Target body's local space |
| Structural connector attachment regions | Each endpoint body's local space |
| Visual geometry | Aligned with the body's local gameplay shape |

The local-frame origin may differ from the current centre of mass. Changes intended to preserve motion preserve surviving material movement, including same-ID results. When a split changes local frames, structural resolution transforms attachment coordinates to identify the same surviving material locations. Exact units, numeric encoding, origins/pivots, scaling/alignment data, and tolerances remain open. This contract does not require a separate coordinate component.

## 7. System ownership

These are the accepted coarse responsibilities (`ECS-006`). Record accesses below explain the model and do not establish passes or a fixed-step sequence.

| Responsibility | Inputs it uses | State or work it produces |
|---|---|---|
| Input and interaction | Roster control assignment, character definition/state, target shape/policy, existing holds. | Validated movement/interaction requests. Relationship changes enter the structural path. Raw requests are transient unless they establish lasting state. |
| Physics integration | Motion/shape, resolved physical inputs, structural connections, holds, definition roots/reach. | Derived bodies/constraints, host motion, transient contacts/loads. Authoritative motion enters `BodyMotion2D` through the host simulation. |
| Gameplay evaluation | Character/bomb/match state, current geometry and validated blast inputs, relevant physics observations, and connector policies. | Death, detonation, connector failure, progression triggers, and canonical countdown updates. Blast reach accounts for intervening material/thickness; topology consequences go to structural resolution. |
| Structural resolution | Trigger/request plus shapes, properties, identities, relationships, and control assignment. | Complete geometry, identity, behaviour, and relationship outcomes; connector pre-replacement checks; atomic changes with valid references. |
| Reconstruction and replication | Committed canonical records and validated definitions/configuration. | Updated derived objects/indexes and semantic committed state/recovery data exposed to Odin. |

Engine joint handles, measured loads, solver history, reverse indexes, and pending split plans are not additional canonical facts. Tick order, callbacks, commit frequency, and physical-impulse timing remain open.

## 8. Reconstruction and transition checks

### Rebuild a held, supported scene

Suppose a character holds platform P, connector C joins P to fixed support W, and a live bomb has an active countdown.

| What must be recovered | Current source | Remaining contract |
|---|---|---|
| Body arrangement and motion | Entity identities plus `BodyMotion2D`; local-frame poses and current COM velocity use world space | Numeric units/types and exact pose encoding. |
| Shapes and material inputs | Body-local `BodyShape2D` plus shared `MaterialProperties`; all physical roles derive mass from density/area | Shape/reference validation, consistent units, and further physical derivations. |
| W stays fixed | Level/world definition supplies geometry, fixed behaviour, and stable endpoint identities | Exact validated-reference and configuration encoding remain open; do not infer fixedness from zero velocity. |
| C preserves its intended fit | Endpoint IDs and paired local attachment data; extra rest data only if necessary | Canonical region encoding within the accepted endpoint-local frames. Current displaced poses do not redefine the bond. |
| C's percentage test remains meaningful | C's lifetime reference and current attached measure | Reference encoding and length measure; no retired-parent dependency. |
| Character remains held within reach | Minimum hold record, fixed definition root/reach, endpoint poses | Coordinate/definition validation and engine realization. |
| Bomb remains on its path to detonation | Selected bomb configuration and active remaining duration | Units/types and update ordering; no landing-event replay or shared deadline clock is required. |
| Appearance matches current shape | Recoverable visual settings/alignment, including applicable colour | Appearance ownership and regeneration. |

The accepted hold, timer, and connector-lifetime semantics have concrete sources. Shared material inputs, fixed-wall sources, and frame roles also have accepted homes. The whole-scene audit still exposes exact configuration/reference encoding, further physical derivations, and validation contracts. The map does not claim those unspecified parts are already a complete executable schema.

### Grab

1. Resolve the participant's controlled body, selected character definition, slot root/reach, target shape, and applicable eligibility.
2. Validate current geometry, reach, obstruction, endpoint existence, and slot occupancy. Geometry revision is evidence, not a validity shortcut.
3. Create one hold with character ID, slot, target ID, and target-local held location.
4. Derive the constraint, visible held-limb pose, and slot lookup without duplicate character-side references.

### Supported piece splits

Use P attached to W by C and held through L. P splits into P1 and P2. C has one valid surviving relationship on P1; L's held location survives on P2.

| Affected state | Complete outcome |
|---|---|
| P, P1, P2 | Retire P; create both children with new IDs and their own shape, motion, and required inputs. Motion-preserving changes must preserve surviving material movement; other child-motion and impulse policies remain open. |
| Material/response/appearance | Inherit the named settings by default unless the response explicitly changes them. Derive each child's mass from density and area; neither child needs retired P. Other component inheritance is not automatically settled. |
| C | Evaluate any old attachment-loss test using C's existing reference. If it passes, keep C's ID/reference, remap to P1, and preserve intended fit. If it fails, retire C. |
| L | Keep L's ID; remap target and transform held coordinates into P2's local frame, identifying the same surviving material location (`WORLD-006`). Do not branch the hold or relocate it to another point. |
| Runtime/publication | Commit the complete geometry/identity/relationship outcome atomically, then derive valid runtime state and expose committed semantic results. |

If several relationships survive and C passes its old test, retire C and create each new connector with its own initial reference. If the old bond fails, create none. If L's held location is destroyed, retire L.

### Character death

A blast satisfying its power/radius lethality condition causes immediate death; character damage does not accumulate (`CHAR-005`). Effective reach accounts for material and thickness under `WORLD-007`, including cover destroyed by that blast. Exact values, geometric evaluation, resistance inputs and propagation calculation remain open.

1. Keep the surviving body's ID and resolve the character-to-environment behaviour change. Concurrent geometry changes use ordinary identity rules.
2. Resolve the environment configuration from the selected character definition and install its material, destruction-response, interaction-eligibility, and reusable appearance selections into the body's environment records. Actual values and encoding remain open.
3. Clear the participant control reference and retire the dying character's outgoing holds.
4. Preserve incoming holds on surviving locations. Starting a new hold uses corpse eligibility; it does not silently cancel accepted continuing holds.
5. Commit the complete transition together, then update derived machinery and expose the committed result. The corpse reconstructs through ordinary environment records and validated definitions without the former living state or death-event replay.

### Bomb countdown and detonation

1. The first valid landing activates the canonical countdown and initializes remaining duration from selected bomb/fuse configuration.
2. The host advances active remaining duration; a current snapshot retains activation and progress. Holding, throwing, support loss and later landings do not pause, restart or extend it.
3. Expiry detonates at the current position, retires the bomb and produces no persistent bomb fragments. Material-dependent blast reach follows `WORLD-007`; lasting destruction/relationship outcomes commit through structural resolution.
4. Landing classification, numeric fuse values/precision, blast-resistance inputs/calculation and detailed update ordering remain open.

## 9. Gaps exposed by the map

| Gap | Why it matters | Current boundary |
|---|---|---|
| Coordinate and alignment encoding | The accepted world/body-local convention must be implemented consistently, including material-location-preserving transforms after splitting. | Semantic frame roles are settled (`WORLD-006`); exact units, origins/pivots, shape format, scaling/alignment encoding, transformations, and tolerances remain open. |
| Definition/reference recovery | Reconstruction must recover the same effective values without a retired parent. | Dependency validation and encoding remain open; no hash/version scheme is selected. |
| World configuration encoding and further physical inputs | W must recover level/world-supplied fixed behaviour and endpoints; all physical roles share material inputs and may need further nonduplicated inputs. | The wall and material input sources are settled (`WORLD-005`, `MAT-009`); encoding and further derivations remain open. No duplicate attachment-imposed restrictions or separate `BodyPhysics` are assumed. |
| Blast reach calculation | Intervening material and thickness consume reach, including cover destroyed by the same blast; penetration can continue while reach remains. | Material-resistance inputs/source, propagation and thickness calculation, values/units and power/radius mapping remain open (`WORLD-007`, `OQ-GEO-004`). |
| Appearance ownership | Variable colour and reusable appearance inputs need a recoverable source and must suit changed shapes. | Definition/instance placement, a separate `VisualBinding`, alignment, and regeneration remain open. |
| Corpse values and other result settings | Death installs environment configuration supplied by the character definition; destruction does not automatically copy every component. | The corpse source and resulting environment-record ownership are settled (`CHAR-004`). Actual values, transition/reference encoding, and result inputs beyond accepted material/response/appearance inheritance remain open. |
| Additional movement and implementation contracts | The accepted hold baseline is represented; selected active controls may expose additional lasting inputs. | Active controls, constraints/tuning, physics interfaces, and detailed scheduling remain open. |

Use `BOM-Team-Handbook.html` for the walkthrough, source-linked reference, and proposed starting work. Next take this map and the team summary into cross-role review for reconstruction completeness and duplicate ownership. Trace the supported/held scene, split, death, and countdown. No further semantic decision needs forcing before that review; raise a focused question only when a concrete case exposes a material gap. This checkpoint selects no networking schema, ECS framework, geometry library, numerical cutoff, new movement mechanic, or additional destruction-response algorithm.
