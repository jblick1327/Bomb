# BOM Architecture Decision Log

**Version:** 0.14  
**Last updated:** 2026-10-09  
**Normative source:** `BOM Architecture.md`

## 1. Purpose

This log preserves why the current architecture exists. It is historical and explanatory, not the current source of truth. When this file conflicts with `BOM Architecture.md`, the architecture document controls.

## 2. Status meanings

- **Accepted:** Ratified and represented in the current architecture.
- **Provisional:** Historical working status used before ratification or replacement. The five formerly provisional policies were resolved by `DEC-052` through `DEC-056`.
- **Deferred:** Deliberately outside the course implementation.
- **Superseded:** Previously considered or accepted, then replaced.
- **Rejected:** Considered and intentionally not adopted.

## 3. Decisions

### DEC-001 — Host commits canonical state

**Status:** Accepted  
**Affects:** `AUTH-001`, `AUTH-002`

**Decision:** Only the host may commit canonical gameplay state. Clients may predict but cannot establish truth.

**Rationale:** Destructible geometry and shared physics require one authority to resolve conflicting observations and outcomes.

**Consequences:** Client responsiveness and canonical resolution are separate concerns. Reconciliation must follow the host result.

### DEC-002 — Reconstruct from current state

**Status:** Accepted  
**Affects:** `STATE-001`, `STATE-002`, `STATE-003`, `REBUILD-001`

**Decision:** The current world is recoverable from serialized canonical state without replaying its complete history.

**Rationale:** Joining, recovery, debugging, and network correction should depend on the present world rather than an unbounded event log.

**Consequences:** Lasting consequences belong in current geometry, components, relationships, pose, and velocity. Engine solver history remains derived.

### DEC-003 — Two-dimensional authority with derived 3D presentation

**Status:** Accepted  
**Affects:** `WORLD-001`, `WORLD-002`

**Decision:** Gameplay physics and destruction are authoritative in 2D, while the visible 3D scene derives from them.

**Rationale:** BOM's gameplay is 2.5D. A 2D canonical model reduces networking and destruction complexity while retaining a three-dimensional visual style.

### DEC-004 — Stable identity follows connected outcomes

**Status:** Accepted  
**Affects:** `ECS-001`, `IDENTITY-001`

**Decision:** One connected result preserves an entity ID. Multiple disconnected results retire the parent and receive new IDs. No surviving result retires the entity.

**Rationale:** Identity follows the continued existence of one physical piece. Choosing one child to inherit a split parent's identity would be arbitrary.

### DEC-005 — Geometry revision is diagnostic evidence

**Status:** Accepted  
**Affects:** `INTERACT-001`, `INTERACT-002`, `INTERACT-003`

**Decision:** Clients include observed geometry revision with interaction proposals, but a mismatch alone neither accepts nor rejects the request.

**Rationale:** The authoritative geometric validity test matters more than equality of version numbers. Small stale-view discrepancies may still describe a valid nearby interaction.

### DEC-006 — Validate current geometry with bounded correction

**Status:** Accepted  
**Affects:** `INTERACT-002`

**Decision:** The host may project or clamp a proposed contact onto nearby valid current geometry within explicit tolerances, while still enforcing reach and obstruction.

**Rationale:** Minor client-host geometry drift should not make ordinary interactions brittle. Correction must not manufacture validity for fundamentally invalid requests.

### DEC-007 — Persistent physical relationships may be entities

**Status:** Accepted  
**Affects:** `ECS-003`, `ECS-004`, `CON-001`, `LIMB-003`

**Decision:** Limb attachments and structural bonds are persistent relationship entities when they have physical meaning, state, behavior, and lifecycle.

**Rationale:** Many-to-many attachments, break conditions, endpoint remapping, and structural damage are awkward as duplicated endpoint fields.

**Consequences:** Similar relationship entities reuse components through composition rather than inheritance.

### DEC-008 — One grab entity per hand-target attachment

**Status:** Superseded by `DEC-023`  
**Affects:** Former `GRAB-001`, `GRAB-002`; continuing `HAND-001`

**Decision:** Each hand has at most one live grab, and every hand-target attachment is its own grab entity. Hands themselves are not entities.

**Rationale:** One character may make two grabs and several characters may grab the same target. The grab has meaningful independent state, while a hand has no independent lifecycle beyond its slot.

**Consequences:** The grab entity stores the relationship once. Fast hand lookup is derived.

### DEC-009 — Bomb retirement produces no persistent bomb debris

**Status:** Accepted  
**Affects:** `BOMB-001`, `EVENT-001`

**Decision:** A bomb retires when it explodes. The explosion is transient, and the current design does not create persistent bomb-fragment entities.

### DEC-010 — Composite authored objects expand into material and connector entities

**Status:** Accepted  
**Affects:** `MAT-001`, `MAT-002`, `CON-001`

**Decision:** A multi-material authored object instantiates as multiple material entities joined by connector entities.

**Rationale:** Material sections require independent geometry, bodies, damage outcomes, and connection failure.

**Supersedes:** The earlier shorthand that every authored level object always maps to exactly one environment entity.

### DEC-011 — Connected material entities retain separate bodies

**Status:** Accepted  
**Affects:** `MAT-002`, `CON-004`

**Decision:** Connected material entities use separate authoritative physics bodies. A connector derives the joint between them and has no body itself.

**Rationale:** The connection must be able to weaken and fail without changing the identity model of the connected material pieces.

### DEC-012 — Extensible connector composition, rigid course implementation

**Status:** Accepted  
**Affects:** `CON-003`, `ECS-004`

**Decision:** Connector behavior is extensible through components, but the course implementation builds only rigid environmental connectors.

**Rationale:** This avoids a rigid architectural dead end without committing the course project to hinges, springs, sliders, and a universal constraint framework.

**Deferred:** Non-rigid environmental connector implementations.

### DEC-013 — Rigid connectors fail from load or attachment loss

**Status:** Accepted  
**Affects:** `CON-005`, `CON-006`, `CON-007`

**Decision:** Either excessive physical load or insufficient surviving attachment may break a rigid connector. Load failure is immediate rather than fatigue-based and accounts for force and in-plane moment.

**Rationale:** Immediate failure is readable, produces suitable chain reactions, and avoids canonical accumulated-stress state. Moment prevents a long lever from behaving like the same force applied beside the connection.

### DEC-014 — One authored strength derives engine thresholds

**Status:** Accepted  
**Affects:** `CON-008`

**Decision:** Designers author one connector-strength value. The system derives force and torque limits rather than exposing independent engine-specific values as canonical data.

**Rationale:** One semantic value is easier to reason about and keeps Unity joint configuration behind the runtime derivation boundary.

### DEC-015 — Strength means bond strength per attached length

**Status:** Superseded  
**Original status:** Provisional  
**Superseded by:** `DEC-052`  
**Affects:** `CON-009`

**Decision:** Interpret the authored value as bond strength per unit of surviving attachment length.

**Rationale:** Equal values then describe equal bond quality, while larger bonds behave as stronger bonds and erosion naturally weakens them.

**Revisit if:** Level designers cannot tune connector behavior intuitively or the derived torque behavior becomes unnecessarily complicated.

### DEC-016 — Attachment-loss threshold uses a percentage

**Status:** Superseded  
**Original status:** Provisional  
**Superseded by:** `DEC-053`  
**Affects:** `CON-010`

**Decision:** Connector component values may define the minimum surviving attachment as a percentage rather than a universal absolute length.

**Rationale:** A percentage gives the setting a consistent visual meaning across differently sized authored connections.

**Later resolution:** `DEC-046` settled reference lifetimes and pre-replacement failure. `DEC-053` accepts the optional authored percentage condition; actual cutoff values remain tuning work.

### DEC-017 — Bombs cannot create arbitrary interior-origin destruction

**Status:** Accepted  
**Affects:** `WORLD-003`, `CON-012`

**Decision:** Bombs fall from above and cannot begin an explosion inside solid material.

**Rationale:** A previously discussed case in which an internal blast divided a connector range while leaving both endpoint bodies intact was not reachable under the game's actual bomb behavior.

**Consequences:** The course architecture does not need special multi-range connector semantics for that hypothetical.

### DEC-018 — Connector identity mirrors material outcome identity

**Status:** Accepted  
**Affects:** `CON-011`, `COMMIT-001`, `COMMIT-002`

**Decision:** One surviving connector relationship preserves the connector ID. Multiple resulting relationships retire the original and receive new IDs. No surviving relationship retires it.

**Rationale:** The physical bond survives in the one-result case but has become several independently identifiable relationships in the multiple-result case.

**Consequences:** Endpoint remapping and attachment-coordinate transformation must be atomic with material splitting.

### DEC-019 — Structured Markdown is the current documentation source

**Status:** Accepted  
**Affects:** This document set

**Decision:** Use structured Markdown with stable rule IDs and explicit statuses as the current architecture source rather than introducing a machine-first schema during active design discovery.

**Rationale:** ChatGPT can reliably parse disciplined Markdown, humans can audit it directly, and the ECS vocabulary is not stable enough to justify a custom intermediate representation or rigid schema.

**Revisit if:** Deterministic tooling must consume the architecture directly or the record types and terminology have stabilized.

### DEC-020 — Host Unity commits gameplay state; Odin handles networking

**Status:** Accepted  
**Affects:** `AUTH-003`, `AUTH-001`, `STATE-003`, `NET-001`, `NET-002`

**Decision:** The host's Unity simulation computes authoritative gameplay physics and commits canonical gameplay changes, including bomb spawns and structural outcomes. Odin handles connections, transport, protocol delivery, and replication bookkeeping rather than independently deciding gameplay or duplicating the physics simulation.

**Rationale:** BOM's body motion, collisions, attachment behavior, and connector loads influence canonical outcomes. Rechecking these results independently in Odin would require another gameplay-relevant physics simulation. One host simulation can use Unity's physics machinery while keeping its recoverable canonical state and semantic network protocol separate from Unity objects.

**Consequences:** Only the host Unity simulation's committed result establishes gameplay truth. Odin may relay, order, cache, and replicate that result without becoming a second canonical owner. Client Unity physics supports prediction and reconstruction but cannot commit canonical outcomes. The precise runtime bridge and wire encoding remain open.

### DEC-021 — Live bombs use authoritative two-dimensional physics

**Status:** Accepted  
**Affects:** `BOMB-002`, `STATE-002`, `STATE-003`

**Decision:** A live bomb has an authoritative two-dimensional physics body and can respond to collision and moving support. Bomb-specific behavior determines detonation; the bomb retires under `BOMB-001` when it explodes.

**Rationale:** A bomb that lands on material should behave as a physical object as that material moves or gives way. Special bomb behavior does not require a separate movement simulation when the host Unity simulation already calculates gameplay physics.

**Unresolved:** Exact collision response, support behavior, and detonation trigger.

**Later resolution:** `DEC-033` accepts a landing-triggered countdown; precise landing classification, collision/support behaviour, and countdown policies remain open.

### DEC-022 — One authoritative body per character

**Status:** Accepted  
**Affects:** `CHAR-002`, `HAND-001`, `FOOT-001`

**Decision:** A character has one authoritative two-dimensional physics body. Hands and feet are character-local interaction slots; visible limbs do not have separate canonical identities or bodies.

**Rationale:** Limb contact and deliberate attachment can be represented as interactions with the one character body without making every visible limb an independently simulated entity.

### DEC-023 — Hand and foot holds share a relationship entity kind

**Status:** Accepted  
**Affects:** `FOOT-001`, `LIMB-001`, `LIMB-002`, `LIMB-003`, `LIMB-004`

**Decision:** Hand grabs and player-initiated foot holds are persistent instances of the same limb-attachment entity kind. Each hand or foot slot has at most one live attachment, independently of the other slots. Material entities and other player characters are valid target categories for both hands and feet.

**Rationale:** A lasting hold has one physical relationship, lifecycle, and canonical source of truth regardless of which limb initiated it. The kinds of target and behavior may vary through components without creating separate relationship identity systems.

**Supersedes:** The hand-only relationship category in `DEC-008` and former `GRAB-001` through `GRAB-004`. The one-attachment-per-hand and no-duplicate-source principles continue for every limb slot.

**Unresolved:** Attachment constraint behavior, authoritative limb pose, termination and remapping after target changes.

**Later resolution:** `DEC-031` and `DEC-032` settle held-location remapping and existing-hold outcomes on death. Exact constraint, limb pose, numerical/boundary handling, and round-reset behaviour remain open.

### DEC-024 — Bombs are tentatively excluded as limb targets

**Status:** Superseded  
**Original status:** Provisional  
**Superseded by:** `DEC-054`  
**Affects:** `LIMB-005`

**Decision:** Live bombs are not attachable by hands or feet in the current working design.

**Rationale:** The target discussion favored materials and other characters and only tentatively excluded bombs. This exclusion remains isolated so it can be changed without revising limb-attachment identity.

### DEC-025 — Destructible and indestructible pieces share the environment model

**Status:** Accepted  
**Affects:** `MAT-004`, `WORLD-002`, `ECS-001`, the material-entity definition

**Decision:** Indestructible terrain has persistent entity identity in the same environment/material-piece model as destructible geometry. Destructibility is controlled by component data.

**Rationale:** Identity can remain consistent across pieces with different destruction, motion, and interaction properties. Permitted physical relationships can use the same entity-reference machinery.

**Supersedes:** The previous definition restricting material entities to destructible pieces, and the unresolved entity-versus-immutable-level-data identity choice in `OQ-WORLD-001`.

**Unresolved:** Exact component records, interaction eligibility policies, and the reconstruction contract for immutable authored geometry. Having entity identity does not require choosing a particular geometry storage format.

### DEC-026 — Grab eligibility is an authored Boolean

**Status:** Superseded  
**Original status:** Provisional  
**Superseded by:** `DEC-056`  
**Affects:** `LIMB-007`, `INTERACT-002`

**Decision:** Level designers or asset creators can control grab eligibility for gameplay geometry through an authored Boolean, proposed as `is_grabbable`, independently of destructibility.

**Rationale:** Eligibility is an interaction property that can vary by authored asset or level choice.

**Original status basis:** The user initially proposed this tentatively. `DEC-056` now accepts the authored Boolean and its shared hand/foot scope.

**Unresolved:** The setting's default, scope for deliberate foot holds, and exact component placement.

### DEC-027 — A dead Claymate becomes an environment piece with the same ID

**Status:** Accepted  
**Affects:** `CHAR-003`, `IDENTITY-001`, `COMMIT-001`, `COMMIT-002`

**Decision:** Character death ends player control and changes the surviving body's behaviour to that of an ordinary environment/material piece. The body retains its existing entity ID through that transition.

**Rationale:** The user wants corpses to participate physically as environment pieces. The same physical piece survives death, so a behaviour switch can preserve its identity and existing references.

**Consequences:** Later applicable geometry changes use ordinary material outcome identity. Keeping the ID does not automatically retain or release limb attachments; those outcomes must still be valid and committed consistently.

**Unresolved:** Corpse material/destruction properties, the character's own holds, other characters' holds on the corpse, and exact transition components.

**Later resolution:** `DEC-032` settles existing holds on death, and `DEC-030` locates control assignment. Corpse properties and exact transition records remain open.

### DEC-028 — Player match identity survives physical-body changes

**Status:** Accepted  
**Affects:** `PLAYER-001`, `STATE-001`, `STATE-002`, `CHAR-003`

**Decision:** Each player has a persistent match identity separate from their current Claymate body's entity ID.

**Rationale:** A corpse can later split and retire its original ID while the participant still needs to be identified. Separate player identity also supports assigning another body if later round rules require it.

**Unresolved:** Participant-state storage, control assignment, connection identity, scoring, and round lifecycle. This decision does not itself require a player ECS entity or a particular scoring system.

**Later resolution:** `DEC-030` chooses canonical match-roster participant records and their control references. Connection identity, scoring, and round lifecycle remain open.

### DEC-029 — Batch checkpoints and assemble the model before further detail

**Status:** Accepted  
**Affects:** Document-set maintenance and `BOM Model Interview Handoff.md`

**Decision:** Discuss and acknowledge decisions in chat, then synchronize the affected original documents together at an explicit checkpoint or handoff. Do not edit and save the set after every conversational turn. The next design activity is a compact candidate entity/component/system map using the current baseline, followed by questions where that map reveals a material gap.

**Rationale:** Per-turn document updates consumed time and attention. Repeated narrow questions risked treating optional gameplay policies as prerequisites and postponing the model they were meant to inform.

**Consequences:** Between checkpoints, the documents describe the last saved baseline and can lag behind settled chat decisions. Checkpoint before switching chats. Ask one question at a time when needed, group closely linked consequences in a clear proposal, and prioritize recoverable state, ownership, identity, references, system responsibilities, and atomic changes. Implementation P0 labels do not dictate interview order.

**Supersedes:** The handoff's previous requirement to save every clear decision in the same turn before asking another question. It also replaces a serial-question-first default with model assembly and targeted gap resolution.

### DEC-030 — Participant records own control assignment

**Status:** Accepted  
**Affects:** `PLAYER-001`, `PLAYER-002`, `CHAR-003`, `STATE-004`, `COMMIT-001`

**Decision:** The canonical match roster holds one participant record per player, with persistent participant identity and an optional controlled-body ID. That reference is the sole canonical source of control assignment. Death clears it in the body-transition commit while preserving the participant record.

**Rationale:** The player outlives any one body. Locating assignment with that stable identity makes ending or reassigning control explicit and avoids duplicate ownership references or a new physical relationship entity.

**Resolves:** Participant-state placement and control-assignment ownership left open in `DEC-028` and part of `OQ-MATCH-001`.

**Unresolved:** Exact record encoding, connection-to-participant mapping, round state, scoring, and respawn/reassignment mechanics.

### DEC-031 — A hold follows its surviving location through destruction

**Status:** Accepted  
**Affects:** `LIMB-008`, `LIMB-001`, `LIMB-002`, `IDENTITY-001`, `COMMIT-002`

**Decision:** If the held location survives on a valid resulting material piece, preserve the limb attachment's ID and remap its target and attachment coordinates as needed. If the location is destroyed or has no valid surviving target, retire the attachment. A hold never branches across split children.

**Rationale:** A continuing physical hold can retain its own identity even when the target's split retires the original material ID. Following the surviving held location preserves continuity and the one-attachment-per-slot invariant.

**Resolves:** The semantic target-remapping and attachment-identity choices in `OQ-LIMB-002`. The earlier GDD's held-point proposal is accepted here through the explicit discussion, rather than inherited from the older document.

**Unresolved:** Exact held-location representation, numerical tolerances, ambiguous boundaries, and round-reset handling. No automatic reattachment to a different location has been accepted.

### DEC-032 — Death releases outgoing holds and preserves incoming holds

**Status:** Accepted  
**Affects:** `LIMB-009`, `CHAR-003`, `PLAYER-002`, `COMMIT-001`, `COMMIT-002`

**Decision:** The dying character's own hand and foot attachments retire in the death commit. Other characters' holds on its surviving body continue with their IDs unchanged. Concurrent destruction of a held location follows `LIMB-008`.

**Rationale:** Death ends the character's active limb behaviour while the corpse continues as a physical target under its existing body ID.

**Resolves:** Existing-hold outcomes left open in `DEC-027` and `OQ-LIMB-002`.

**Unresolved:** Corpse material/destruction properties and exact transition components. Starting a new hold still depends on corpse interaction properties; this decision does not choose those properties.

### DEC-033 — Landing activates a reconstructable bomb countdown

**Status:** Accepted  
**Affects:** `BOMB-002`, `BOMB-003`, `STATE-001`, `ECS-005`

**Decision:** A bomb begins its detonation countdown when it lands. Canonical lifecycle state retains countdown activation and enough timing information to reconstruct its remaining lifecycle.

**Rationale:** A current-state snapshot must resume a live bomb correctly without requiring its historical landing event.

**Resolves:** The high-level detonation trigger in `OQ-BOMB-001` and `DEC-021`.

**Unresolved:** Precise landing condition, fuse duration, timer encoding, and policies for later support loss or further landings.

### DEC-034 — Adopt the first-pass component responsibilities

**Status:** Accepted  
**Affects:** `ECS-005` and `OQ-ECS-002`

**Decision:** Adopt the semantic responsibilities for body motion, body shape, physical configuration, environment behaviour, character behaviour, bomb lifecycle, structural connections, limb attachments, participant records, and match progression.

**Rationale:** These responsibilities give the entity and lifecycle rules a coherent state model that the team can review together. Component records can be refined from that common vocabulary.

**Scope:** The user accepted the first-pass catalogue, not exact names, field types, a mandatory one-record-per-row layout, an ECS framework, or a fixed-step sequence. At this decision, provisional and open policies retained their status; `DEC-052` through `DEC-056` now resolve the five tentative gameplay policies. The broad system map shown alongside the earlier entity map remained a proposal at this point.

**Consequences:** Death changes character/environment behaviour on the same body, clears the roster assignment, and retires outgoing holds atomically; destruction resolves material and relationship identities together. Canonical, derived, authoring, and transient data retain their existing distinctions.

**Unresolved:** Physical-property derivation, shape contracts, exact limb pose/constraint/rest data, match mechanics, system partitioning and ordering, and network encoding.

**Later resolution:** `DEC-035` settles material density and mass derivation, `DEC-038` settles preservation of the intended rigid relationship, and `DEC-039` accepts coarse system responsibilities. Other physical properties, relationship encodings, exact implementation partitioning, and execution order remain open.

### DEC-035 — Material definitions author density; mass follows current area

**Status:** Accepted  
**Affects:** `MAT-005`, `ECS-005`, `STATE-001`, `OQ-MAT-001`

**Decision:** Density is an explicit authored value in a material definition. Material pieces reference that definition, and their mass derives from resolved density multiplied by current gameplay 2D area. Reconstruction must resolve consistent definition values.

**Rationale:** Selecting glass can supply its density without making the material name itself a physical rule. Separating authored density from derived mass makes geometry loss affect mass through the same reconstruction contract.

**Resolves:** Density placement and material-piece mass derivation within `OQ-MAT-001`.

**Unresolved:** Values, units, exact material-definition records and reference validation, and other physical-property derivations. Per-instance override policy has not been chosen.

### DEC-036 — Select destruction response independently of material properties

**Status:** Accepted  
**Affects:** `MAT-006`, `ECS-005`, `IDENTITY-001`, `COMMIT-002`

**Decision:** Destruction response is independently selectable from material properties; material authoring presets can supply defaults. Persistent physical material results are ordinary material entities governed by existing identity and relationship rules. Decorative debris may be transient.

**Rationale:** Glass can suggest shattering without forcing every glass piece to behave identically. Shattering names a process, while splitting names an outcome already represented by the model.

**Scope:** This accepts an extension point rather than requiring a shattering implementation or selecting a catalogue of response types.

**Unresolved:** Exact response algorithms, kinds, parameters, and authoring/configuration encoding.

### DEC-037 — Foundations and rigid connectors are sufficient for course anchoring

**Status:** Accepted  
**Affects:** `WORLD-004`, `MAT-003`, `CON-003`

**Decision:** Fixed foundation pieces plus existing rigid connectors provide the course anchoring baseline. A separate directly-world-anchored destructible-terrain mechanism is not required.

**Rationale:** The existing material-piece and connector model can represent fixed supports and the structures attached to them without introducing another anchoring mechanism.

**Scope:** This is a course sufficiency decision. It preserves compositional motion properties and does not ban directly static pieces or create a new foundation entity category.

### DEC-038 — Rebuilding a surviving connector preserves its intended relationship

**Status:** Accepted  
**Affects:** `CON-013`, `CON-011`, `COMMIT-002`, `STATE-004`, `REBUILD-001`, `OQ-CON-002`

**Decision:** Canonical connector data must recover its intended relative position and angle. Reconstruction and endpoint remapping preserve that intended bond, including appropriate transformations into resulting pieces' local spaces.

**Rationale:** Recreating a joint solely from temporarily displaced endpoint poses could adopt a different constraint target, particularly after destruction or world reconstruction. This is a plausible implementation failure whose significance in BOM has not been measured.

**Scope:** The accepted requirement is preserving the intended relationship, not mandatory extra position/angle fields. Existing attachment data can supply it if unambiguous; each canonical fact still has one source. Assembly motion and solver history remain separate concerns.

**Resolves:** The semantic reconstruction requirement in `OQ-CON-002`.

**Unresolved:** Exact encoding, coordinate transformations, and Unity joint-reconstruction method.

### DEC-039 — Adopt coarse system responsibilities

**Status:** Accepted  
**Affects:** `ECS-006`, `ECS-005`, `AUTH-003`, `COMMIT-001`, `COMMIT-002`, `OQ-ECS-002`, `OQ-COMMIT-001`

**Decision:** Adopt the division into input/interaction, physics integration, gameplay evaluation, structural resolution, and reconstruction/replication. Gameplay evaluation decides when an explosion occurs; structural resolution computes the affected geometry, identities, connectors, and holds and commits the complete change.

**Rationale:** Naming who owns evaluation, physical observations, structural outcomes, and publication gives the team a shared system model alongside the accepted component responsibilities.

**Resolves:** The status of the earlier candidate system-responsibility map. This narrows the implementation-partition and coordination questions without settling their scheduling details.

**Scope:** These are semantic responsibilities, not one class or pass per row. Exact component records, Unity callbacks, tick order, commit frequency, and impulse timing remain open. Odin retains networking ownership under `AUTH-003`.

### DEC-040 — Declare each material section's gameplay shape and visual alignment

**Status:** Accepted  
**Affects:** `MAT-007`, `WORLD-002`, `ECS-005`, `OQ-GEO-001`, `OQ-ASSET-001`

**Decision:** Each authored material section supplies a declared 2D gameplay shape and aligned visual data. Tools may generate the shape; physics, destruction, mass, and attachment placement use it as their common shape input.

**Rationale:** A glass platform's visible edge and gameplay silhouette need a defined alignment so collision, destruction, and connector placement use the same authored shape.

**Scope:** The user accepted the asset contract, not a particular shape editor, polygon format, visual pipeline, coordinate convention, or exact division of labour. Asset authoring, level composition, and simulation integration are roles/responsibilities that can overlap.

**Unresolved:** Units, local coordinates, scale/alignment encoding, shape validation, and reconstructable visual definitions.

### DEC-041 — Inherit material, response, and appearance settings by default

**Status:** Accepted  
**Affects:** `MAT-008`, `MAT-005`, `MAT-006`, `IDENTITY-001`, `STATE-001`

**Decision:** Resulting pieces inherit the source's material definition, destruction response, and reusable visual definition/settings by default. The selected response may explicitly specify changes. Each result has its own reconstructable state and direct definition references rather than requiring the retired source entity.

**Rationale:** Reusable definitions describe a piece's properties and appearance while canonical geometry describes its current shape. New piece IDs do not require new material or appearance definitions, and reconstruction must work after the parent retires.

**Scope:** This is default inheritance of the named properties, not every component or a requirement to preserve the original render mesh. No response transformation algorithm or result schema is selected.

**Unresolved:** Exact result/property-change encoding and regeneration of visuals from changed geometry.

### DEC-042 — A limb hold permits body motion within reach

**Status:** Accepted  
**Affects:** `LIMB-010`, `LIMB-003`, `CHAR-002`, `HAND-001`, `FOOT-001`, `OQ-LIMB-001`, `OQ-LIMB-003`

**Decision:** A held hand or foot remains attached to its target location while the character's one body can move and rotate within permitted reach. The attachment constrains motion beyond reach; visible limbs follow the resulting relationship without independent authoritative bodies.

**Rationale:** A character hanging from one hand should retain the held location while allowing the body to swing or move, rather than enforcing the fixed arrangement used by rigid structural connectors.

**Resolves:** The semantic physical behaviour within `OQ-LIMB-001`. Existing hold continuity, target eligibility, and death rules remain in effect.

**Unresolved:** Character-side anchors, reach/pose definition, engine constraint implementation, tuning, and active movement controls. Automatic force breakage was Provisional at this decision; `DEC-055` now excludes it from the current build.

### DEC-043 — Accept seven conceptual component groupings

**Date:** 2026-10-06  
**Status:** Accepted  
**Affects:** `ECS-007`, `ECS-005`, `OQ-ECS-002`

**Decision:** Accept `BodyMotion2D`, `BodyShape2D`, `MaterialProperties`, `DestructionBehaviour`, `InteractionPolicy`, `CharacterState`, and `BombState` as conceptual groupings for the component map.

**Rationale:** The user explicitly cosigned the five shared/property groupings and the character/bomb groupings. They give concrete homes to established state responsibilities while their remaining inputs can be refined.

**Scope:** This refines the naming/grouping scope left open by `DEC-034`; it does not replace its responsibility model or accept every field in candidate map v0.1. A separate `BodyPhysics` was challenged as overlapping material inputs and relationship-imposed restrictions and remains unaccepted. Fixed support behaviour still needs a recoverable source. Colour was identified as variable, but a separate `VisualBinding` and its field placement were not explicitly accepted. Moving participant/match entries to a dependency section is an assistant recommendation; their canonical simulation ownership is unchanged.

**Unresolved:** Remaining physical inputs, fixed-boundary encoding, appearance ownership, other record boundaries, types/layout, and system ordering. At this decision, the provisional policies retained their status; `DEC-052` through `DEC-056` now resolve them.

### DEC-044 — Definition roots/reach and the minimum limb-hold record

**Date:** 2026-10-06  
**Status:** Accepted  
**Affects:** `LIMB-011`, `LIMB-012`, `LIMB-010`, `OQ-LIMB-001`, `OQ-LIMB-002`, `OQ-LIMB-003`

**Decision:** A character definition supplies a fixed body-local root and authored maximum reach for each limb slot. A limb attachment's minimum contents, besides its entity ID, are character ID, slot, target ID, and target-local held location. Endpoint poses and those definition inputs derive the reach constraint and visible held-limb pose.

**Rationale:** This provides the missing character-side constraint inputs without inventing independently changing authoritative root poses or copying body/definition state onto every hold.

**Scope:** The user accepted both the fixed-root/reach proposal and the four-field minimum hold. This resolves those parts left open by `DEC-042`. It does not choose force breakage, active pulling/climbing controls, a Unity constraint, or all `CharacterState` fields.

**Unresolved:** Exact coordinates/numeric encoding, remapping tolerances and boundaries, definition validation, implementation/tuning, and any later demonstrated movement inputs. Automatic force breakage was Provisional at this decision; `DEC-055` now excludes it from the current build.

### DEC-045 — Store bomb countdown as inactive or remaining duration

**Date:** 2026-10-06  
**Status:** Accepted  
**Affects:** `BOMB-004`, `BOMB-003`, `ECS-007`, `OQ-BOMB-001`

**Decision:** Canonical countdown state is inactive, or active with remaining duration. Landing activation initializes it from selected bomb/fuse configuration; the host advances the active timer. Recovery uses the current timer state without replaying the landing event.

**Rationale:** This makes the required timing fact explicit and reconstructable without introducing a shared deadline-clock dependency solely for bombs.

**Scope:** This resolves the timer-representation choice left open by the landing-countdown decision. It does not settle landing classification, fuse values, explosion settings, or behaviour on later contacts/support loss.

**Unresolved:** Duration units/types, definition/reference encoding, detailed update/detonation order, and the remaining bomb policies.

### DEC-046 — Connector reference lengths follow relationship identity

**Date:** 2026-10-06  
**Status:** Accepted  
**Affects:** `CON-014`, `CON-010`, `CON-011`, `COMMIT-002`; resolves `OQ-CON-004`

**Decision:** When attachment-loss percentage is used, an ongoing connector keeps its reference length. Each newly created connector uses its own initial attached length as a fixed reference for its lifetime. Before creating replacements, evaluate the old connector's attachment-loss failure against its existing reference; failure retires that bond without replacement connectors.

**Rationale:** A continuing bond measures loss consistently. Newly identified relationships have local baselines instead of being judged against a retired parent's full attachment. Testing the old bond first prevents a split from avoiding failure through reference resets. The user accepted the proposal after the visual walkthrough.

**Scope:** This fills the reference-lifetime question left open by earlier percentage and identity decisions. At this decision, the percentage policy (`CON-010`) and strength-per-length policy (`CON-009`) remained Provisional. `DEC-052` and `DEC-053` now accept them. The example 40% cutoff and lengths are not ratified. Under the length-based strength policy, a child at 100% still has capacity based on its shorter actual attachment.

**Consequences:** Any reference needed later must survive as current canonical state or a valid dependency; a child never reconstructs by consulting its retired parent. Connector replacement/remapping remains an atomic structural outcome. Paired attachment data may already encode the intended fit under `CON-013`; no redundant rest fields are mandated.

**Unresolved:** Precise attached-length measurement, threshold defaults, force/torque formula, reference encoding, and execution details.

### DEC-047 — Character definition supplies environment settings on death

**Date:** 2026-10-06  
**Status:** Accepted  
**Affects:** `CHAR-004`, `CHAR-003`, `STATE-001`, `STATE-004`, `OQ-CHAR-001`

**Decision:** The character definition supplies the environment configuration applied on death. The transition installs its material, destruction-response, interaction-eligibility, and reusable appearance selections into the same body's environment records, preserving its ID. The corpse thereafter reconstructs through the ordinary environment model.

**Rationale:** Death needs a clear source for its resulting configuration. Installing the effective environment selections makes current-state recovery independent of the former living state and the event that changed it.

**Scope:** This fills the source gap left by `DEC-032` and the component-map review. It does not choose actual corpse values, a default inheritance/override policy, an extra profile entity/record, or a precise record encoding. Existing control, hold, geometry-identity, and atomicity rules still apply.

**Unresolved:** Actual settings, validated definition/reference encoding, and implementation of the composition transition.

### DEC-048 — Characters and bombs also use MaterialProperties

**Date:** 2026-10-06  
**Status:** Accepted  
**Affects:** `MAT-009`, `MAT-005`, `ECS-007`, `OQ-MAT-001`, `OQ-ECS-002`

**Decision:** Living characters and live bombs use `MaterialProperties` alongside their role-specific `CharacterState` and `BombState`. Material inputs resolve through the shared material-property source, just as for environment bodies.

**Rationale:** These roles also have physical bodies. Shared material input ownership closes the missing source in their conceptual compositions without inventing a separate record merely because a body is a character or bomb.

**Scope:** The user accepted record applicability and the material input source. This does not ratify a full physical-property catalogue, select engine defaults, or extend the material-piece mass formula to unmentioned roles. The density authorship and material-piece derivation in `MAT-005` remain in force.

**Unresolved:** Additional body inputs and derivations, units, effective selections/overrides, and definition encoding. A separate `BodyPhysics` remains unaccepted.

### DEC-049 — Level/world data supplies fixed walls

**Date:** 2026-10-06  
**Status:** Accepted  
**Affects:** `WORLD-005`, `WORLD-004`, `ECS-001`, `STATE-001`, `OQ-WORLD-001`

**Decision:** The level/world definition supplies fixed simulation walls with geometry, fixed behaviour, and stable endpoint identities so attachments and connectors can reconstruct.

**Rationale:** The existing fixed-foundation/rigid-connector anchoring model needs recoverable support inputs. Zero velocity is insufficient to establish fixedness; the wall's world data supplies that fact while relationships supply the restrictions they impose on attached bodies.

**Scope:** This settles the source left open by the component-map review. Walls stay in the existing environment model with match-scoped identity. It does not create a new entity category, globally fixed IDs across matches, a duplicate anchored flag, or an accepted `BodyPhysics` grouping.

**Unresolved:** Exact configuration/geometry encoding, permitted validated references, and identity allocation.

### DEC-050 — Share world poses and body-local attachment coordinates

**Date:** 2026-10-06  
**Status:** Accepted  
**Affects:** `WORLD-006`, `MAT-007`, `CON-011`, `CON-013`, `LIMB-008`, `LIMB-011`, `LIMB-012`, `OQ-ASSET-001`

**Decision:** Body position/rotation use world space. Gameplay shape and limb roots use the body's local space. Held locations use the target body's local space; connector regions use each endpoint's local space. Visual geometry aligns with the body's local gameplay shape. When splits change local frames, structural resolution transforms attachment coordinates to identify the same surviving material locations.

**Rationale:** Simulation, asset authoring, presentation, connectors, and holds need a shared interpretation of their geometry. A local-frame change must preserve the existing bond or held material location rather than invent a different attachment.

**Scope:** This closes the semantic frame-role gap, refining the encoding choices left open by earlier shape, hold, and connector decisions. It does not choose precise units, numeric types, local origins/pivots, angle representation, geometry formats, or transformation tolerances.

**Unresolved:** Exact units, encoding, validated definition references, and numerical transformation/boundary details.

### DEC-051 — Character damage does not accumulate

**Date:** 2026-10-06  
**Status:** Accepted  
**Affects:** `CHAR-005`, `CHAR-003`, `CHAR-004`, `ECS-007`, `OQ-GEO-004`, `OQ-BOMB-001`

**Decision:** Character damage does not accumulate. A blast causes immediate death when the character meets its power/radius lethality condition; the conceptual baseline needs no health or accumulated-damage value in `CharacterState`.

**Rationale:** The user explicitly described survival as meeting or not meeting a blast's radius/power condition, rather than retaining damage between hits. This closes the lasting-damage-state question raised during handoff preparation.

**Scope:** Gameplay evaluation performs the host's test, then the accepted death transition establishes environment behaviour on the same surviving body ID. Existing geometry, roster-control, hold, and atomicity rules continue to govern the complete outcome. This does not choose a particular radius formula, body-centre versus shape test, occlusion policy, or additional death cause.

**Unresolved:** Exact power/radius values and mapping, geometric evaluation, and shielding/occlusion.

## 4. Rejected or superseded approaches

### HIST-001 — Every authored level object is always one entity

**Status:** Superseded by `DEC-010`

A single-material object may map to one material entity, but a composite object expands into multiple material entities and connectors.

### HIST-002 — Every ECS object receives persistent network identity

**Status:** Rejected

Only persistent canonical entities require stable match-scoped identity. Transient events and implementation machinery do not automatically enter that namespace.

### HIST-003 — A generic connector class hierarchy

**Status:** Rejected

Shared relationship behavior uses component composition and systems. No inheritance hierarchy is required.

### HIST-004 — Duplicate grab references on the character

**Status:** Rejected

The grab entity is canonical. Character-hand lookup is derived rather than duplicated as authoritative state.

### HIST-005 — Immediate machine-first architecture schema

**Status:** Rejected for the current phase

YAML, JSON Schema, a custom DSL, or a knowledge graph may become useful later. Introducing one before the architecture vocabulary stabilizes would add ceremony and risk encoding premature abstractions.

### HIST-006 — Interior-blast disconnected attachment ranges

**Status:** Rejected as a required course case

The discussed geometry assumed a blast could originate inside intact material. That assumption contradicts the game's falling-bomb behavior.
### DEC-052 — Accept connector strength per surviving attachment length

**Date:** 2026-10-07  
**Status:** Accepted  
**Affects:** `CON-009`, `CON-008`, `CON-014`  
**Supersedes:** `DEC-015`

**Decision:** Connector strength is authored per unit of surviving attachment length. Destruction that shortens the attachment reduces effective load capacity.

**Rationale:** James accepted this explicitly. The authored value describes bond quality consistently, while larger attachments support more load and erosion weakens them.

**Unresolved:** Precise length measurement, force/torque conversion, units, and tuning. These implementation contracts do not make the accepted behaviour provisional.

### DEC-053 — Accept optional authored attachment-loss percentage failure

**Date:** 2026-10-07  
**Status:** Accepted  
**Affects:** `CON-010`, `CON-014`  
**Supersedes:** `DEC-016`

**Decision:** Connectors may have an authored minimum surviving attachment percentage. When configured, falling below it causes failure independently of current load. Without the setting, this percentage condition does not apply.

**Rationale:** James explicitly asked to commit the optional failure condition. It gives authors control over when a nearly severed bond gives way, including while unloaded.

**Scope:** This accepts the supported mechanism, not a universal percentage. Existing identity-based references and the old-connector pre-replacement check remain in force. Cutoff values and authoring defaults remain tuning work.

### DEC-054 — Replace live-bomb exclusion with ordinary hold eligibility

**Date:** 2026-10-07  
**Status:** Accepted  
**Affects:** `LIMB-004`, `LIMB-005`, `LIMB-007`, `BOMB-002`, `COMMIT-002`  
**Supersedes:** `DEC-024`

**Decision:** Live bombs are valid hand and deliberate foot hold targets when their effective authored eligibility permits the hold and ordinary host validation succeeds.

**Rationale:** James pointed out that the grabbable trait already expresses eligibility and saw no reason for a categorical bomb exception.

**Consequences:** Holding preserves the bomb's countdown lifecycle. Bomb retirement also retires holds targeting it in the complete structural outcome. This does not bypass geometry, reach, obstruction, or other validation.

### DEC-055 — Exclude automatic limb force breakage from the current build

**Date:** 2026-10-07  
**Status:** Accepted  
**Affects:** `LIMB-006`, `LIMB-010`, `LIMB-012`

**Decision:** Applied force alone does not release hand or deliberate foot holds in the current build. Automatic grip-strength failure is outside the current course scope.

**Rationale:** James asked to remove the mechanic for now. Holds retain the accepted reach behaviour without adding a load-based release condition or required grip-strength threshold.

**Scope:** Deliberate release, held-location destruction, endpoint retirement, and character-death rules remain in effect. This excludes limb force breakage; structural-connector force/torque failure is still required.

### DEC-056 — Accept one authored grabbability policy for hands and feet

**Date:** 2026-10-07  
**Status:** Accepted  
**Affects:** `LIMB-007`, `LIMB-004`, `LIMB-005`, `INTERACT-002`, `ECS-007`  
**Supersedes:** `DEC-026`

**Decision:** An authored Boolean controls deliberate hold eligibility independently of destructibility. Hand and deliberate foot holds use the same policy in the shared limb-attachment architecture. Live bombs use ordinary eligibility.

**Rationale:** James supported the existing grabbable trait and clarified that hands and feet are architecturally the same.

**Scope:** Eligibility permits an attempt and never bypasses host validation. Ordinary foot contact is unaffected. Existing hold continuity retains its accepted rules. The example field name, authoring default, exact record placement, and reference encoding are not prescribed.

### DEC-057 — Define centre-of-mass velocity and motion-preserving geometry changes

**Date:** 2026-10-08  
**Status:** Accepted  
**Affects:** `WORLD-006`, `STATE-002`, `ECS-007`  
**Refines:** `DEC-050`

**Decision:** Body position/rotation describe the world-space pose of its local frame. Linear velocity is the world-space velocity of its current centre of mass; angular velocity is the rate of change of body angle. The local-frame origin may differ from the centre of mass. When a geometry or frame change is intended to preserve motion, it preserves the instantaneous movement of surviving material, including a same-ID result.

**Rationale:** The conformance review exposed an asymmetric one-survivor cut that moved the centre of mass without changing the body ID or frame. Retaining the old COM velocity changed surviving material's motion. James accepted the clarified meaning and conditional preservation requirement.

**Scope:** This does not impose universal motion inheritance, prohibit blast impulses, or select a frame-recentring policy. COM/inertia derivation, units, numeric encoding, and other motion policies remain open. The experiment's corrected motion-preservation implementation is evidence for that policy's cases, not a universal gameplay choice.

### DEC-058 — Apply density-times-area mass to all physical roles

**Date:** 2026-10-08  
**Status:** Accepted  
**Affects:** `MAT-005`, `MAT-009`, `ECS-005`, `ECS-007`  
**Extends:** `DEC-035`, `DEC-048`

**Decision:** Environment/material pieces, living characters, and live bombs all derive mass as resolved material density multiplied by current two-dimensional gameplay area. At equal density, twice the area gives twice the mass.

**Rationale:** James accepted the same mass derivation for roles already sharing material inputs. Geometry and selected material consistently determine body mass across the physical world.

**Unresolved:** Actual density values, units, definition/reference encoding, COM/inertia and other physical-property derivation, collision settings, and override policy. This does not adopt the experiment's fixture values or other engine defaults.

### DEC-059 — Adopt connector force and torque capacity formulas

**Date:** 2026-10-08  
**Status:** Accepted  
**Affects:** `CON-008`, `CON-009`, `CON-014`  
**Refines:** `DEC-014`, `DEC-052`

**Decision:** For authored strength per unit length `S` and surviving attachment length `L`, connector capacities are `Fmax = S × L` and `Tmax = ½ × S × L²`. The `½` factor is accepted as part of the gameplay model; authors still provide one strength value.

**Rationale:** James accepted the experiment's simple geometric capacity model. Halving the attachment halves direct-force capacity and quarters bending capacity, making partial destruction meaningful before a bond disappears.

**Scope:** This is a chosen gameplay model, not a claim of physical fidelity or established balance. The attachment-length measure, paired-endpoint representation, load measurement, units, numerical encoding, and strength values remain open. Optional percentage failure and its identity-based references are unchanged.

### DEC-060 — Keep an activated bomb fuse running through handling and later contacts

**Date:** 2026-10-08  
**Status:** Accepted  
**Affects:** `BOMB-001`, `BOMB-003`, `BOMB-004`, `LIMB-005`  
**Refines:** `DEC-033`, `DEC-045`, `DEC-054`

**Decision:** The first valid landing activates the configured remaining-duration countdown. Holding, throwing, movement, support loss, and further landings do not pause, restart, or extend it. Expiry detonates the bomb at its current position.

**Rationale:** James explicitly agreed with the experiment's continuous-fuse behavior. Handling an active bomb changes the danger's position while retaining predictable progress to detonation; destruction beneath it does not reset that progress.

**Unresolved:** Landing classification, authored fuse values, duration units/precision and numeric encoding, and detailed update/detonation order. The corrected experiment's 20 ms step and double-millisecond timer remain implementation conventions.

### DEC-061 — Reduce blast reach through material, including cover destroyed by that blast

**Date:** 2026-10-08  
**Status:** Accepted  
**Affects:** `WORLD-003`, `WORLD-007`, `CHAR-005`

**Decision:** Nominal blast radius sets maximum reach through empty space. Intervening material consumes reach according to the material and its thickness. A blast may penetrate a barrier and reach targets beyond it if sufficient reach remains. Material destroyed by that same blast still contributes to what it had to overcome; deletion does not remove its reach cost. Character lethality accounts for effective reach.

**Rationale:** James required blast radius to account for material in between and explicitly accepted this penetration behavior. Terrain provides protection without every thin barrier becoming an unconditional shield.

**Unresolved:** Material-resistance inputs, their definition/instance source and relation to other properties, values and units, propagation/thickness calculation, and exact power/radius mapping. No formula, raycasting algorithm, new ECS record, or persistent blast entity was selected.

**Experiment boundary:** The reviewed conformance branch tested radius-only explosions against Architecture v0.11 / `DEC-056`. Its reported successes do not demonstrate this newly accepted shielding rule. Updating the probe's blast model and evidence is later implementation work, not part of this handbook checkpoint.

### DEC-062 — Author blast resistance independently in shared material properties

**Status:** Accepted  
**Date:** 2026-10-08  
**Affects:** `MAT-010`, `ECS-005`, `ECS-007`, `WORLD-007`

**Decision:** Blast resistance is independently authored through the shared recoverable material-property source. It is independent of density, connector strength and destruction response, and greater resistance costs more reach for the same thickness.

**Rationale:** James preferred the clearer name "blast resistance" and accepted its independent source. This resolves the source/property part left open in `DEC-061` without selecting a field name, asset layout, actual values or encoding.

### DEC-063 — Require a breach before removing material behind a layer

**Status:** Accepted  
**Date:** 2026-10-08  
**Affects:** `WORLD-009`, `WORLD-007`, `CHAR-005`

**Decision:** Removal along one blast path must breach intervening material before carving material behind it. A separate exposed path may reach that material independently. Destroyed cover keeps its original reach cost.

**Rationale:** James required a strong outer layer to protect a weak core while it remains unbreached. His mention of Darryn described informal observations from playing with his own experiments, not a formal test or a reproduced bug. The requirement was accepted on its own merits; no specific Darryn result is claimed fixed.

### DEC-064 — Add linear material cost to ordinary travel distance

**Status:** Accepted  
**Date:** 2026-10-08  
**Affects:** `WORLD-008`, `WORLD-007`, `MAT-010`

**Decision:** Additional reach consumed equals blast resistance × thickness crossed. Ordinary travel distance also consumes reach, including distance inside material. Successive unambiguous layers add costs; original material remains chargeable even when removed.

**Rationale:** James accepted this simple, inspectable propagation calculation. The worked 1 m air / 1 m cover at resistance 4 / 2 m core at resistance 1 example illustrates costs of 6 m to the core and 10 m through it; these are not adopted game defaults. Numerical geometry, overlaps and actual authoring values remain open.

### DEC-065 — Propagate straight outward without corner wrapping

**Status:** Accepted  
**Date:** 2026-10-08  
**Affects:** `WORLD-010`, `WORLD-008`, `WORLD-009`, `CHAR-005`

**Decision:** Evaluate straight outward paths from the current bomb position using original material and effective reach. Paths do not turn or spread around corners. Geometry removal and character exposure use this same propagation basis.

**Rationale:** James accepted direct propagation. No raycasting API, sample count or polygon algorithm was selected.

### DEC-066 — Preserve the new corpse through its killing explosion

**Status:** Accepted  
**Date:** 2026-10-08  
**Affects:** `CHAR-006`, `CHAR-003`, `CHAR-004`, `LIMB-009`, `COMMIT-002`

**Decision:** The killing explosion preserves the new corpse's shape, geometry revision and body ID. Install the ordinary authored death configuration and control/hold consequences. A later independent explosion uses the corpse's selected environment response; there is no whole-tick immunity or new timer.

**Rationale:** James explicitly preferred leaving the newly dead character uncarved because it adds humour. This is an accepted current-build policy. Independent-explosion ordering was still open at this checkpoint.

### DEC-067 — Make indestructible cover completely opaque

**Status:** Accepted  
**Date:** 2026-10-09  
**Affects:** `WORLD-011`, `WORLD-009`, `WORLD-010`, `CHAR-005`

**Decision:** Indestructible cover blocks both carving and character exposure behind its original first intersection along a blast path, even when reach remains. Separate exposed paths can still reach a target.

**Rationale:** In reviewing the bounded blast proposal, James accepted complete blocking as the consistent solution even if the case rarely appears in the game. This closes indestructible-cover transmission, not numerical shadow handling or every living-character/corpse response choice.

### DEC-068 — Scope ordering and recovery choices to the bounded blast experiment

**Status:** Accepted  
**Date:** 2026-10-09  
**Affects:** `CHAR-006`, `MAT-010`, `STATE-001`, `COMMIT-002`

**Scope:** `feature/blast-conformance-probe`; experimental implementation conventions, not global game scheduling or a production save/wire-format requirement.

**Decision:** Simultaneously due independent explosions commit individually in stable body-ID order; each reads the previous complete result without another physics/fuse step. Explicit consecutive calls use caller order. Recovery preserves explicitly authored resistance, including zero; the reviewed probe uses schema 3 and rejects older/missing inputs without historical migration. Codex owns numerical methods, computational limits, encoding and fixture details within the agreed experiment and reports measured results and limitations.

**Rationale:** James separately accepted the proposed explosion order and recovery approach, then clarified that test specifics are Codex's concern. The continuation permitted numerical method/budget revisions while preserving accepted rules and independent expected outcomes. A choice changing gameplay, the canonical representation or agreed architecture still returns for review.

**Evidence boundary:** The implementation at `24e79ff0533eabf51627859b097f3503af5f54a1` records 83/83 EditMode and 15/15 PlayMode passes. These are bounded fixture results; they do not ratify production performance, arbitrary geometry, a new framework, historical migration, staffing or a merge into the assignment prototype. The team handoff records the measured limits.
