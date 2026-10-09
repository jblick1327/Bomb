# BOM Simulation Architecture

**Version:** 0.14  
**Review state:** Current source of truth; accepted rules govern the current build  
**Last updated:** 2026-10-09  
**Companion files:** `BOM Decision Log.md`, `BOM Open Questions.md`

## 1. Purpose

This document defines the current simulation, ECS, destruction, and networking architecture for BOM. It records the system as it is presently understood. It does not preserve the history of how decisions were reached; that belongs in the decision log.

This document is intended to support implementation, testing, AI-assisted work, technical explanation, and the generation of audience-specific documentation.

## 2. Interpretation rules

1. **Accepted** rules are current architectural requirements, including the current build's gameplay and scope policies.
2. **Deferred** behavior is not required for the course implementation.
3. Open questions are non-normative and live in `BOM Open Questions.md`.
4. Rejected or superseded ideas are non-normative and live in `BOM Decision Log.md`.
5. Unspecified behavior must not be inferred from examples, prior chat messages, the pitch deck, or Unity defaults.
6. A rule changes only through an explicit replacement or supersession entry.
7. Canonical state and derived runtime state must not be treated as interchangeable.

## 3. Terms

### 3.1 Canonical state

The authoritative, recoverable description of the current game world. Canonical state is sufficient to reconstruct the current world without replaying the complete event history that produced it.

### 3.2 Derived runtime state

Unity and physics-engine objects created from canonical state for simulation or presentation. Examples include `Rigidbody2D` instances, colliders, joints, solver caches, contact manifolds, render meshes, interpolation state, and lookup caches.

### 3.3 Persistent canonical entity

A game-world entity whose identity and current state may survive across simulation ticks and may be referenced by other canonical state.

### 3.4 Material entity / environment piece

A persistent canonical entity representing one connected physical environment piece, whether destructible or indestructible. A material entity has its own authoritative physics body. This document uses "material entity" and "environment piece" for the same semantic model; destructibility is controlled by component data under `MAT-004`.

### 3.5 Connector entity

A persistent canonical relationship entity representing a physical bond or constraint between canonical endpoint entities. A connector does not have its own physics body.

### 3.6 Attachment region

The material-space range over which a connector attaches to an endpoint. Structural attachments use regions rather than only point anchors.

### 3.7 Structural commit

An atomic application of entity creation, retirement, geometry replacement, endpoint remapping, and other topology-changing consequences.

### 3.8 Geometry revision

Metadata identifying the geometry state a client believed it was interacting with. A revision is evidence about the client's observation, not authority over whether an interaction is valid.

## 4. Authority and recoverability

### AUTH-001 — Host authority

**Status:** Accepted  
**Kind:** Architectural invariant

Only the host's authoritative simulation may commit canonical gameplay state. Client prediction, local resolution, presentation, and derived physics do not establish canonical truth.

### AUTH-002 — Client prediction

**Status:** Accepted  
**Kind:** Architectural invariant

Clients may predict interactions and consequences locally for responsiveness. The host validates the request and commits or rejects the canonical result.

### AUTH-003 — Unity host simulation and Odin networking

**Status:** Accepted  
**Kind:** Architectural invariant

The authoritative gameplay simulation runs in the host's Unity instance. Its authoritative simulation path computes gameplay-relevant two-dimensional physics, resolves gameplay decisions, and commits canonical state changes, including bomb spawns, physical outcomes, destruction, and entity and relationship lifecycles. The host player's local input and presentation do not gain authority merely by sharing that instance.

Odin handles connections, transport, protocol delivery, and replication bookkeeping. It carries client requests to the host simulation and distributes committed semantic results and recovery state. It may retain a replication mirror or cache, but does not independently commit gameplay facts or run a second authoritative physics simulation. Other Unity instances may predict and reconstruct, but their physics outcomes do not establish canon.

Unity rigidbodies, joints, contacts, and solver history remain derived runtime state under `STATE-003`, even when the host uses them to calculate the outcomes it commits. The placement of these responsibilities does not prescribe an ECS framework, an in-process versus separate-process bridge, or a wire format.

### STATE-001 — Current-state reconstruction

**Status:** Accepted  
**Kind:** Architectural invariant

The current canonical state must be serializable and sufficient to reconstruct the current world without replaying its full event history.

### STATE-002 — Canonical simulation facts

**Status:** Accepted  
**Kind:** Architectural invariant

Canonical state includes all lasting gameplay-relevant facts, including:

- Persistent entity identities and lifecycles.
- Canonical two-dimensional geometry.
- Gameplay components and relationships.
- Position and rotation.
- Linear and angular velocity.
- Lasting structural consequences.

### STATE-003 — Derived engine state

**Status:** Accepted  
**Kind:** Architectural invariant

Unity objects and internal physics-engine state are derived rather than canonical. This includes engine rigidbodies, colliders, joints, solver caches, contacts, render meshes, and interpolation machinery.

### STATE-004 — Store each fact once

**Status:** Accepted  
**Kind:** Data invariant

A canonical relationship or fact must have one canonical source of truth. Reverse lookups and convenience mappings may exist as derived indexes or caches, but they must not duplicate authoritative state.

## 5. ECS semantics

### ECS-001 — Persistent identity

**Status:** Accepted  
**Kind:** Architectural invariant

Every persistent canonical entity receives a stable, match-scoped ID. This includes characters, bombs, destructible and indestructible material/environment entities, limb attachments, and structural connectors.

Transient notifications, commands, collision results, and one-tick events do not automatically receive persistent canonical identities.

### ECS-002 — Components, systems, and events

**Status:** Accepted  
**Kind:** Modeling rule

- Components hold state.
- Systems apply behavior to matching state.
- Transient happenings may be represented as events or messages rather than persistent entities.
- Structural changes are queued and applied through a structural commit rather than mutating topology midway through ordinary system processing.

### ECS-003 — Relationship entities

**Status:** Accepted  
**Kind:** Modeling rule

Relationship entities are reserved for persistent relationships with physical meaning and their own state, lifecycle, or behavior. Purely logical facts should use ordinary component data or transient events unless a concrete need justifies a relationship entity.

### ECS-004 — Composition over inheritance

**Status:** Accepted  
**Kind:** Modeling rule

Different physical relationships may reuse components and systems without sharing a class hierarchy or mandatory generic connector base type. Behavior varies through component composition.

### ECS-005 — First-pass component responsibilities

**Status:** Accepted  
**Kind:** Semantic modeling baseline

The first-pass catalogue assigns the following state responsibilities. The conceptual groupings accepted under `ECS-007` refine this catalogue; other record boundaries, exact fields/types, and the implementation split remain candidates. This table does not settle otherwise open policies or implementation details.

| Responsibility | Canonical state it owns | Applies to |
|---|---|---|
| Body motion | Position, rotation, linear velocity, angular velocity | Material pieces, characters, live bombs |
| Body shape | Reconstructable gameplay geometry; any immutable reference must satisfy the chosen recovery contract | Physical bodies |
| Physical configuration | Canonical inputs needed to derive body motion and collision behaviour | Physical bodies |
| Environment behaviour | Material/destruction behaviour and interaction eligibility | Material/environment pieces, including corpses |
| Character behaviour | Living-character movement and authoritative limb-interaction state | Living Claymates |
| Bomb lifecycle | Inactive countdown or active remaining duration under `BOMB-004` | Live bombs |
| Structural connection | Endpoints, attachment regions that recover the intended rigid relationship, authored strength, failure policies, and any percentage reference required by `CON-014` | Structural connectors |
| Limb attachment | Character ID, limb slot, target ID, and target-local held location under `LIMB-012`; roots/reach resolve from the character definition | Hand and foot holds |
| Participant record | Participant identity and optional controlled-body reference | Canonical match roster |
| Match progression | Lasting spawning and round facts required by the chosen mechanics | Match-level canonical state |

Each fact still has one canonical source under `STATE-004`. Destructibility, motion, and interaction eligibility remain independent concerns. Material density and density-times-area mass derivation apply to environment pieces, living characters, and live bombs under `MAT-005` and `MAT-009`. Independently authored blast resistance resolves through the same shared material-property source under `MAT-010`; it is not inferred from density or destruction response. Other physical-property inputs and derivations remain open under `OQ-MAT-001`. Destruction response is independently selectable under `MAT-006`. Authored section shape/visual alignment and resulting-piece property inheritance follow `MAT-007` and `MAT-008`. Rigid-connector reconstruction preserves the intended relationship under `CON-013`. Limb holds constrain reach while permitting body movement and rotation under `LIMB-010`; fixed character-local roots and maximum reach resolve from the character definition under `LIMB-011`, and minimum hold state follows `LIMB-012`. Exact coordinate encoding, further movement inputs, and match mechanics remain open. `ECS-006` assigns coarse system responsibilities; exact implementation partitioning and execution order remain open.

### ECS-006 — Coarse system responsibilities

**Status:** Accepted  
**Kind:** Semantic system baseline

The host simulation assigns the following responsibilities:

| Responsibility | Work it owns |
|---|---|
| Input and interaction | Validate player requests against current state, using the canonical control assignment. |
| Physics integration | Maintain derived Unity bodies and joints; report authoritative motion, contacts, and loads. |
| Gameplay evaluation | Decide when bombs detonate, characters die, or connectors fail. |
| Structural resolution | Compute resulting pieces and relationships, then commit the complete change atomically. |
| Reconstruction and replication | Update derived runtime objects and expose committed semantic results and recovery state to networking. |

For an explosion, gameplay evaluation triggers it; structural resolution computes affected geometry, identities, connectors, and limb attachments together. Existing lifecycle and atomicity rules control those outcomes. Odin retains the networking responsibilities assigned by `AUTH-003`.

This division assigns semantic ownership. It does not require one implementation class or pass per row, select Unity callbacks, or establish tick order, commit frequency, or the timing of physical impulses.

### ECS-007 — Accepted conceptual component groupings

**Status:** Accepted  
**Kind:** Conceptual record-grouping baseline

The following names and groupings are accepted for the conceptual component map:

| Grouping | Responsibility |
|---|---|
| `BodyMotion2D` | World-space local-frame pose, current centre-of-mass linear velocity, and angular velocity under `WORLD-006` |
| `BodyShape2D` | Recoverable current 2D gameplay shape |
| `MaterialProperties` | Shared material properties/definition inputs for environment pieces, living characters, and live bombs under `MAT-009`, including explicit density under `MAT-005` and independently authored blast resistance under `MAT-010` |
| `DestructionBehaviour` | Destructibility and independently selected destruction response |
| `InteractionPolicy` | Effective interaction eligibility used by host validation |
| `CharacterState` | Character-specific definition selection and lasting gameplay state |
| `BombState` | Bomb configuration selection and current lifecycle/countdown state |

Acceptance of a grouping does not settle every field, an ECS framework, storage layout, or definition/reference encoding. Authored Boolean hold eligibility is accepted under `LIMB-007`; live bombs use that policy under `LIMB-005`. `CharacterState` is refined by `LIMB-011`/`LIMB-012`; `BombState` is refined by `BOMB-004`.

The physical-configuration responsibility in `ECS-005` does not require a separate `BodyPhysics` component. Attachment-imposed restrictions derive from the relationships that impose them; an additional canonical anchored/fixed flag must not duplicate that fact. The level/world definition supplies fixed simulation walls with geometry, fixed behaviour, and stable endpoint identities under `WORLD-005`. The exact boundary/configuration encoding remains open. A separate `BodyPhysics` grouping has not been accepted.

Reusable appearance/alignment inputs remain required by `MAT-007`/`MAT-008`. Colour was identified as at least one variable appearance input; its definition/instance placement and a separate `VisualBinding` grouping remain open. Participant/control and match-progression facts remain canonical under their existing rules. Showing them as dependencies outside the body/relationship component catalogue is a review recommendation, not a change of simulation authority or an accepted storage partition.

## 6. World and geometry model

### WORLD-001 — Authoritative 2D simulation

**Status:** Accepted  
**Kind:** Architectural invariant

Gameplay physics and destructible geometry are authoritative in two dimensions. Three-dimensional presentation is reconstructed locally from authoritative two-dimensional state.

### WORLD-002 — Geometry is canonical

**Status:** Accepted  
**Kind:** Architectural invariant

Gameplay-relevant geometry for destructible and indestructible environment pieces belongs to the recoverable canonical description of the world. Render meshes, physics colliders, bounds, and other engine representations derive from it.

The exact polygon representation, quantization rules, and geometry library are not specified by this rule. Whether immutable authored geometry is included directly or resolved through a validated authoring reference remains open; reconstruction must satisfy `STATE-001`.

### WORLD-003 — Reachable bomb destruction

**Status:** Accepted  
**Kind:** Gameplay constraint

Bombs enter the world from above and cannot originate inside solid material. Bomb-driven subtraction begins from a physically reachable bomb position; the course architecture does not require spontaneous enclosed subtraction that starts inside intact solid material.

Intervening material reduces blast reach under `WORLD-007`; a physically reachable origin does not make every target inside the nominal radius exposed.

### WORLD-004 — Course anchoring baseline

**Status:** Accepted  
**Kind:** Course-scope rule

Fixed foundation pieces and existing rigid connectors provide the course anchoring baseline. Movable or destructible structural pieces can be attached to those foundations through connector entities. A separate mechanism for directly world-anchored destructible terrain is not required.

Component-defined motion under `MAT-003` remains compositional; this scope decision does not create a separate foundation identity category.

### WORLD-005 — Fixed walls resolve from level/world data

**Status:** Accepted  
**Kind:** World configuration and reconstruction rule

The level/world definition supplies fixed simulation walls with their geometry, fixed behaviour, and stable endpoint identities so connected pieces and connectors can be reconstructed. These are recoverable world inputs, included in canonical recovery state or resolved through permitted validated dependencies under `STATE-001`.

Walls remain within the existing environment/foundation model, with match-scoped persistent identity under `ECS-001`. This source does not create a new entity category, require a separate `BodyPhysics` grouping, or duplicate the restrictions that connectors impose on attached pieces. Zero velocity alone does not establish fixed behaviour.

Exact world/definition references, geometry and configuration encoding, and ID allocation remain open.

### WORLD-006 — Shared world and body-local coordinates

**Status:** Accepted  
**Kind:** Cross-system coordinate contract

The model uses the following coordinate convention:

| Information | Coordinate meaning |
|---|---|
| Body position and rotation | World-space pose of the body's local coordinate frame |
| Body linear velocity | World-space velocity of its current centre of mass |
| Body angular velocity | Rate of change of the body's angle |
| Body gameplay shape and character limb roots | That body's local space |
| Limb attachment's held location | Target body's local space |
| Structural connector attachment regions | Each endpoint body's local space |
| Visual geometry | Aligned with the body's local gameplay shape |

The local-frame origin may differ from the body's current centre of mass. When a geometry or local-frame change is intended to preserve motion, the resulting motion state must preserve the instantaneous movement of surviving material, including when the body retains its ID. A centre-of-mass change must therefore be reflected in the velocity representation even when the frame is unchanged.

When a split changes a resulting body's local frame, structural resolution transforms attachment coordinates to identify the same surviving material locations. Connector fit and hold continuity still follow `CON-011`, `CON-013`, `LIMB-008`, and `COMMIT-002`; changing a frame does not relocate a hold to different material.

This settles the semantic frames and velocity meanings shared by simulation, authoring, relationships, and presentation. It does not choose a universal motion-inheritance or blast-impulse policy. Precise units, numeric encoding, local origin/pivot choices, centre-of-mass and inertia derivation, scaling/alignment encoding, and numerical tolerances remain open.

### WORLD-007 — Material reduces blast reach

**Status:** Accepted  
**Kind:** Gameplay rule

A bomb's nominal blast radius is its maximum reach through empty space. Intervening material consumes some of that reach according to the material and its thickness. A blast can penetrate a barrier and affect a target beyond it if sufficient reach remains. Character lethality must account for this effective reach under `CHAR-005`.

Material destroyed by a blast still contributes to what that same blast had to overcome. Removing a barrier during structural resolution does not restore the reach spent passing through it.

The shared resistance source is settled by `MAT-010`. `WORLD-008` supplies the linear reach cost, `WORLD-009` requires a breach before material removal behind a layer, `WORLD-010` fixes straight outward paths, and `WORLD-011` makes indestructible cover opaque. Exact authoring values, units/encoding, numerical geometry and character power/radius mapping remain open under `OQ-GEO-004`. No raycasting API or persistent blast entity is selected.

### WORLD-008 — Distance plus resistance-times-thickness consumes reach

**Status:** Accepted  
**Kind:** Blast propagation rule

Ordinary distance travelled consumes blast reach, including distance inside material. Crossing material consumes additional reach equal to its independently authored blast resistance multiplied by the thickness crossed along that path:

`remaining reach = nominal radius − distance travelled − sum(blast resistance × thickness crossed)`

Successive unambiguous material segments add their extra costs. Evaluate a single explosion against its original geometry and material selections; a segment still contributes when the planned result removes it. This is the extra reach cost, not a replacement for ordinary travel distance. The path stops when its reach is exhausted or it encounters opaque cover under `WORLD-011`.

Actual values, units/encoding, numerical intersection method and overlapping-material composition remain open. The metre-based walkthrough is illustrative authoring, not a game default.

### WORLD-009 — Breach intervening material before carving behind it

**Status:** Accepted  
**Kind:** Destruction continuity rule

Along any one blast path, material removal must breach intervening material before continuing into material behind it. A strong outer layer cannot remain unbreached while that same path independently carves a buried hole in a weaker layer. A separate exposed path can affect the target on its own merits.

The complete geometric result must satisfy this rule before publication. Retained fragments must not be silently discarded to create a breach. Original material still consumes reach under `WORLD-007` and `WORLD-008` even where it is removed. Numerical implementation and its supported domain remain implementation work.

### WORLD-010 — Straight outward blast paths

**Status:** Accepted  
**Kind:** Blast propagation and exposure rule

Blast paths travel straight outward from the bomb's current detonation position. They do not turn or spread around corners. Original intervening geometry and material costs determine each path's effective reach and the resulting 2D cut.

Character exposure uses that same original material and effective reach under `CHAR-005`. A target inside the nominal radius can remain protected. A separate unobstructed path can reach a target even when another path is blocked. This rule selects neither a ray count nor a sampling, polygon or numerical algorithm.

### WORLD-011 — Indestructible cover blocks a blast path completely

**Status:** Accepted  
**Kind:** Blast blocking rule

Indestructible cover stops blast propagation at its original first intersection along that path, regardless of reach remaining. Material behind it is not carved and characters behind it are not exposed through that path. A separate exposed path is evaluated independently under `WORLD-010`.

Destruction response remains independent of material resistance: a finite resistance does not make indestructible cover penetrable. This policy applies to the cover's selected non-destructible behaviour; it does not select every living-character response, corpse configuration or numerical shadow-boundary method.

## 7. Environment/material entities and destruction identity

### MAT-001 — Authored composite objects

**Status:** Accepted  
**Kind:** Canonical modeling rule

An authored level object is an authoring container rather than necessarily one canonical entity. A composite object is instantiated as multiple material entities connected by connector entities. A single material section may instantiate as one material entity.

### MAT-002 — Separate physics bodies

**Status:** Accepted  
**Kind:** Physics invariant

Each material entity has its own authoritative physics body, including when several material entities form one connected authored object.

### MAT-003 — Motion is composition

**Status:** Accepted  
**Kind:** Modeling rule

Static, dynamic, movable, and rule-constrained behavior is determined by components. It is not a different environment-entity identity category.

### MAT-004 — Destructibility is composition

**Status:** Accepted  
**Kind:** Canonical modeling rule

Destructible and indestructible environment pieces use the same persistent entity model. Component data controls destructibility independently of motion and interaction eligibility. Indestructible terrain such as bedrock has persistent entity identity; it is not excluded from the entity model merely because its geometry cannot be destroyed.

This rule establishes the shared identity model, not automatic permission for every grab or structural connection. The exact component records remain open.

### MAT-005 — Explicit material density and derived mass

**Status:** Accepted  
**Kind:** Authoring and physical-configuration rule

Material definitions contain explicit authored density. Environment pieces, living characters, and live bombs resolve density through their selected material inputs under `MAT-009`; choosing a material such as glass resolves that density rather than inferring it from a name. Reconstruction must resolve the same effective definition values.

A body's mass is derived from its resolved density multiplied by its current gameplay two-dimensional area. This applies to environment/material pieces, living characters, and live bombs. Geometry changes therefore update derived mass. At the same density, twice the gameplay area gives twice the mass. This rule does not choose density values, units, definition encoding, or the derivation of other physical properties.

### MAT-006 — Independently selectable destruction response

**Status:** Accepted  
**Kind:** Modeling and authoring rule

A material piece's destruction response is independently selectable from its material properties. Material authoring presets may supply defaults, but selecting a material does not fix its destruction response. The effective response and any lasting configuration must remain recoverable under `STATE-001`.

Responses that produce persistent physical material fragments use ordinary material entities and the existing geometry, identity, and relationship-outcome rules. Purely decorative debris or particles may be transient presentation. Shattering describes a destruction process; splitting describes a possible resulting topology.

This establishes an extension point, not a requirement to implement shattering or every response kind for the course. Exact response kinds, algorithms, parameters, and authoring records remain open.

### MAT-007 — Declared gameplay shape and aligned visual data

**Status:** Accepted  
**Kind:** Asset authoring contract

Each authored material section declares a two-dimensional gameplay shape and its alignment with the visual representation. An authoring tool may generate that shape; manual shape editing is not required by this contract. Physics, destruction, material mass calculation, and structural attachment placement refer to the declared gameplay shape.

This establishes the shape/visual contract between authoring and simulation. The semantic coordinate convention follows `WORLD-006`; exact geometry formats, units, visual definitions, and alignment encoding remain open. Runtime geometry can change under the existing destruction rules.

### MAT-008 — Resulting pieces inherit selected properties by default

**Status:** Accepted  
**Kind:** Destruction result and reconstruction rule

Resulting material pieces inherit the source piece's material definition, destruction response, and reusable visual definition/settings by default. A destruction response may explicitly specify changes to those properties in its results. Mass still derives from each result's resolved density and current area under `MAT-005`; identity still follows `IDENTITY-001`.

Each result carries its own reconstructable state or direct definition references. Reconstructing it must not require consulting a retired parent entity. Appearance data applies to the resulting shape; inheriting it does not preserve the original unmodified render geometry.

This rule settles inheritance for the named properties, not an automatic copy of every component. Exact response-result records, property-change encoding, and visual regeneration remain open.

### MAT-009 — Shared material properties across physical roles

**Status:** Accepted  
**Kind:** Component applicability and input-source rule

Living characters and live bombs use `MaterialProperties` as well as environment/material pieces. Their material inputs resolve through the shared material-property source; `CharacterState` and `BombState` retain their role-specific behaviour. Effective material selections must remain recoverable under `STATE-001` and have one canonical source under `STATE-004`.

Material definitions supply explicit density and all three physical roles use density-times-area mass derivation under `MAT-005`. Remaining physical inputs, centre-of-mass and inertia derivation, values, units, and overrides remain open under `OQ-MAT-001`; shared record applicability does not settle every additional body property.

### MAT-010 — Independently authored blast resistance

**Status:** Accepted  
**Kind:** Shared material input and recovery rule

Material definitions independently author blast resistance through the shared recoverable `MaterialProperties` source used by environment pieces, living characters and live bombs. Reconstruction must resolve the same effective value. Higher resistance consumes more reach for the same thickness under `WORLD-008`.

Blast resistance is independent of density, connector strength and destruction response. Do not infer it from another property or duplicate it as a separately authoritative body or role value. Exact field names, asset organization, authoring values, units/encoding, validation and override policy remain open. The bounded probe's presence flag, numeric type and snapshot version are implementation conventions, not this rule's required representation.

### IDENTITY-001 — Material outcome identity

**Status:** Accepted  
**Kind:** Structural invariant

After a geometry-changing structural operation:

| Connected surviving results | Canonical outcome |
|---:|---|
| 0 | Retire the original material entity |
| 1 | Preserve the original ID and update its state and geometry |
| More than 1 | Retire the original ID and create a new material entity for every result |

No disconnected result inherits the retired parent's ID when a split produces multiple physical pieces.

## 8. Connector entities

### CON-001 — Connector meaning

**Status:** Accepted  
**Kind:** Canonical modeling rule

A connector entity represents a persistent physical relationship between endpoint entities. It stores the semantic state of that relationship. The Unity joint or constraint that realizes it is derived runtime machinery.

### CON-002 — Structural attachment regions

**Status:** Accepted  
**Kind:** Canonical modeling rule

An environmental connector attaches through material-space regions along its endpoints rather than only through a single point.

### CON-003 — Course connector behavior

**Status:** Accepted  
**Kind:** Course-scope rule

The course implementation requires rigid environmental connectors. The architecture may later support hinge, elastic, sliding, or other connector behaviors through additional component compositions, but those behaviors are deferred.

### CON-004 — No connector physics body

**Status:** Accepted  
**Kind:** Physics invariant

A connector entity has no authoritative physics body of its own. It derives a physics constraint between the separate bodies of its endpoints.

### CON-005 — Connector failure inputs

**Status:** Accepted  
**Kind:** Gameplay rule

A rigid environmental connector may fail through either of these independent inputs:

1. Authoritative physical load exceeds its allowed strength.
2. Destruction reduces or invalidates its attachment region according to its component values.

Either input may retire the connector.

### CON-006 — Immediate load failure

**Status:** Accepted  
**Kind:** Gameplay rule

A force-breakable connector fails on the first authoritative physics step where its valid measured load exceeds its allowed limit. The course implementation does not require accumulated stress or fatigue state.

### CON-007 — Force and moment

**Status:** Accepted  
**Kind:** Gameplay rule

Connector load evaluation accounts for both translational reaction force and in-plane reaction torque. The torque represents the bending moment produced when forces act at a distance from the connector.

### CON-008 — Authored strength value

**Status:** Accepted  
**Kind:** Authoring rule

Level authors set one connector strength value. Runtime force and torque limits are derived from that value and the connector's attachment geometry. Raw engine `breakForce` and `breakTorque` values are derived and are not independent canonical facts.

### CON-009 — Strength per attached length

**Status:** Accepted  
**Kind:** Gameplay policy

Connector strength is authored per unit of surviving attachment length. Destruction that shortens the attachment reduces its effective load capacity.

For authored strength per unit length `S` and current surviving attachment length `L`, the capacity formulas are:

| Capacity | Formula |
|---|---|
| Maximum translational force | `Fmax = S × L` |
| Maximum in-plane torque | `Tmax = ½ × S × L²` |

Halving the surviving attachment length halves its force capacity and quarters its torque capacity. Both limits derive from the single authored strength under `CON-008`; the `½` factor is part of this gameplay model.

The precise surviving attachment-length measure and paired-endpoint representation, load measurement, units, numeric encoding, and authored strength values remain implementation and tuning work. These formulas do not assert physical fidelity or establish balanced gameplay values.

### CON-010 — Minimum surviving percentage

**Status:** Accepted  
**Kind:** Optional authored failure condition

Connectors may have an authored minimum surviving attachment percentage. When configured, a connector fails when its remaining attachment falls below that percentage of its reference length, independently of its instantaneous load. Without that setting, this percentage-based failure condition does not apply.

The reference lifetime and pre-replacement failure check follow `CON-014`. The actual percentage is an authored tuning value; no universal cutoff is selected. Authoring-tool defaults, the precise attachment-length measure, and encoding remain implementation work.

### CON-011 — Connector outcome identity

**Status:** Accepted  
**Kind:** Structural invariant

When structural change affects a connector endpoint:

| Surviving physical relationships | Canonical outcome |
|---:|---|
| 0 | Retire the original connector |
| 1 | Preserve the connector ID, remap the affected endpoint, and transform its attachment data into the surviving child's local space |
| More than 1 | Retire the original connector and create a new connector for each surviving relationship |

If both endpoints split, new connectors are created only for child pairs that share a surviving physical attachment. Connector retirement, creation, endpoint remapping, and derived-joint reconstruction occur in the same structural commit.

### CON-012 — No required disconnected-range case

**Status:** Accepted  
**Kind:** Course-scope rule

The course implementation does not need special semantics for the hypothesized case in which an interior-origin blast divides one attachment range into disconnected remnants while both endpoint entities remain unchanged. Bombs cannot originate inside intact solid material. If a reachable gameplay case later produces equivalent topology, it must be handled by the ordinary geometry and relationship outcome rules or promoted as a new requirement.

### CON-013 — Preserve the intended rigid relationship

**Status:** Accepted  
**Kind:** Relationship reconstruction invariant

Canonical connector data must be sufficient to recover the intended relative position and angle between its endpoints. Rebuilding a surviving rigid connector preserves that intended relationship. Endpoint remapping and transformation into resulting pieces' local spaces preserve the same physical bond meaning under `CON-011` and `COMMIT-002`.

Current body poses describe the current arrangement; reconstruction must not silently adopt temporary displacement as a new intended relationship. The whole assembly may still move or rotate together.

The encoding remains open. Local attachment frames or a relative rest transform are candidates. If existing canonical attachment data already determines the intended relationship unambiguously, derive it from that data rather than duplicate it in additional fields. Internal solver history remains derived under `STATE-003`.

### CON-014 — Percentage reference follows connector identity

**Status:** Accepted  
**Kind:** Conditional relationship lifecycle and recoverability rule

When attachment-loss percentage is used, each connector has a reference attachment length representing 100%. That reference is fixed for that connector's lifetime:

| Identity outcome | Reference rule |
|---|---|
| An ongoing connector keeps its ID | Keep its existing reference length, including after shortening or remapping |
| A new connector is created | Its own initial attached length becomes its reference length |
| A connector is replaced by several surviving relationships | Each new connector starts with its own initial surviving attachment length as 100% |

Before creating replacement connectors, evaluate the old connector's attachment-loss failure against its existing reference. An old connector that fails that test retires without replacements from that bond. A structural split must not evade failure by first resetting child references. Identity and relationship changes still commit atomically under `CON-011` and `COMMIT-002`.

The reference must remain recoverable from the current connector's state or permitted validated dependencies. Later current geometry alone cannot recover a reference that has already lost attachment; reconstruction must not require the retired parent.

Starting at 100% does not restore the old bond's absolute load capacity. Under `CON-009`, capacity uses actual surviving attachment length. Optional authored percentage failure is accepted under `CON-010`; actual cutoff values, authoring defaults, measurement formula, and exact canonical encoding remain open. The illustrated 40% cutoff is not an accepted value.

## 9. Players, characters, limb slots, and attachments

### PLAYER-001 — Player identity is separate from body identity

**Status:** Accepted  
**Kind:** Canonical modeling rule

A player has a persistent match-participant identity separate from the entity ID of their current Claymate body. The player's identity is not replaced merely because that body dies, becomes an environment piece, splits, or retires, or because a later body is assigned to the player.

The player's participation identity is a lasting recoverable gameplay fact. `PLAYER-002` locates participation and control assignment in canonical match-roster records. Exact record encoding, connection identity, and any scoring or round rules remain open.

### PLAYER-002 — Match roster owns control assignment

**Status:** Accepted  
**Kind:** Canonical modeling and data invariant

The canonical match roster contains one participant record per player, holding their persistent match identity and an optional controlled-body entity ID. That reference is the sole canonical source of control assignment. Bodies do not duplicate the assignment as another authoritative owner reference; reverse lookups may be derived.

The participant record survives body death, splitting, retirement, and later reassignment. On character death, its controlled-body reference is cleared in the same commit as the body behaviour transition. This does not specify connection identity, respawning, scoring, or round mechanics, nor require a separate physical relationship entity for control.

### CHAR-001 — Character entity

**Status:** Accepted  
**Kind:** Canonical modeling rule

A player character is one persistent canonical entity.

### CHAR-002 — Character physics body

**Status:** Accepted  
**Kind:** Physics invariant

A character uses one authoritative two-dimensional physics body. Visible limbs and their interaction positions derive from character state rather than having separate canonical bodies or entity identities.

### CHAR-003 — Death switches the body to environment behaviour

**Status:** Accepted  
**Kind:** Canonical lifecycle rule

On character death, the surviving body becomes an ordinary environment/material piece through a change in component-defined behaviour. Player control ends, and the body's existing entity ID is preserved through this transition. Death alone does not create a replacement body identity.

Subsequent applicable geometry changes follow `IDENTITY-001`. The character definition supplies the environment configuration installed on death under `CHAR-004`; the actual corpse property values remain open. The participant control reference is cleared under `PLAYER-002`; existing limb attachments follow `LIMB-009`. These changes are resolved consistently with the behaviour transition under `COMMIT-001` and `COMMIT-002`.

### CHAR-004 — Character definition supplies the death configuration

**Status:** Accepted  
**Kind:** Lifecycle configuration and reconstruction rule

The character definition supplies the environment configuration to apply on death: material, destruction response, interaction eligibility, and reusable appearance selections. The transition installs those selections into the surviving body's environment records while preserving its ID under `CHAR-003`.

Thereafter, the corpse reconstructs through the ordinary environment model from its current records and permitted validated definitions. Reconstruction does not require retaining the former living `CharacterState` or replaying the death event. Definition defaults and installed selections must not become independently authoritative copies of the same current fact.

This settles the configuration source and resulting ownership. It does not choose actual corpse values, an inheritance/override default, exact transition records, or an additional entity or record called a profile. Control and hold changes still commit with the transition under `PLAYER-002`, `LIMB-009`, and `COMMIT-002`.

### CHAR-005 — Blast lethality without accumulated damage

**Status:** Accepted  
**Kind:** Character damage and death rule

Character damage does not accumulate. A character dies immediately when a blast satisfies its power/radius lethality condition for that character. The accepted baseline therefore needs no health or accumulated-damage value in `CharacterState`.

The host's gameplay evaluation applies the lethality test and triggers the existing death transition under `CHAR-003` and `CHAR-004`. Lasting body, control, and relationship consequences commit under the existing structural rules.

The lethality test uses effective blast reach after accounting for intervening material and thickness under `WORLD-007`. Being inside the nominal radius alone does not establish exposure. A barrier destroyed by this blast still contributes to its reach cost.

Material resistance, distance-plus-thickness cost, straight propagation, breach continuity and indestructible blocking follow `MAT-010` and `WORLD-007` through `WORLD-011`. The killing explosion preserves the new corpse under `CHAR-006`. Exact power/radius mapping and the geometric character boundary/lethality test remain open; no additional death cause is selected.

### CHAR-006 — The killing explosion leaves the new corpse uncarved

**Status:** Accepted  
**Kind:** Current-build death and destruction policy

An explosion that kills a living character does not carve the resulting corpse. That death transition retains the body's existing shape, geometry revision and ID while installing its authored environment configuration under `CHAR-003` and `CHAR-004`. Ordinary control and hold consequences still commit with the transition.

A subsequent independent explosion evaluates the corpse using its current ordinary environment destruction response. This exception belongs to the killing explosion alone; it is not whole-tick immunity and requires no new immunity timer or persistent blast state. General scheduling of independent explosions remains open. The bounded experiment's stable body-ID order is recorded in `DEC-068`, within that experiment's scope.

### HAND-001 — Hands as slots

**Status:** Accepted  
**Kind:** Canonical modeling rule

Left and right hands are character-local slots rather than entities. Their visible positions derive from authoritative character pose and presentation state.

### FOOT-001 — Feet as attachment slots

**Status:** Accepted  
**Kind:** Canonical modeling rule

Left and right feet are character-local slots rather than entities or separate authoritative physics bodies. Ordinary contact does not create a foot attachment; a player chooses when to request one.

### LIMB-001 — Limb attachment identity

**Status:** Accepted  
**Kind:** Canonical modeling rule

Hand grabs and foot holds use the same persistent limb-attachment relationship entity kind. Each attachment belongs to one character limb slot and one target entity. A character may have at most one live attachment per hand or foot, while its slots are independent: both feet may attach to different targets, and multiple characters may attach to the same target.

### LIMB-002 — Attachment source of truth

**Status:** Accepted  
**Kind:** Data invariant

The limb-attachment entity is the canonical source of the relationship. The character does not also store canonical attachment IDs per slot. A derived index from `(character ID, limb slot)` to attachment ID may exist for efficient lookup.

### LIMB-003 — Physical relationship

**Status:** Accepted  
**Kind:** Canonical modeling rule

A limb attachment creates a physical relationship between canonical entities. Its engine constraint is derived runtime state. Hand and foot behaviors may differ through component composition without becoming different relationship entity kinds.

### LIMB-004 — Target categories

**Status:** Accepted  
**Kind:** Canonical modeling rule

Material entities, other player characters, and live bombs are valid target categories for hand and deliberate foot attachments. Authored eligibility under `LIMB-007`, specific surface, reach, obstruction, and gameplay validity still require authoritative validation under `INTERACT-002`.

### LIMB-005 — Bomb target eligibility

**Status:** Accepted  
**Kind:** Gameplay policy

Live bombs are valid hand and deliberate foot attachment targets, subject to their effective authored interaction eligibility and ordinary authoritative validation under `LIMB-007` and `INTERACT-002`. Bombs have no categorical hold exclusion.

Holding a bomb leaves its countdown lifecycle intact under `BOMB-001` and `BOMB-004`. When a bomb explodes and retires, holds targeting it also retire as part of the complete structural outcome; no relationship may retain a retired target.

### LIMB-006 — No automatic force breakage in the current build

**Status:** Accepted  
**Kind:** Course-scope policy

Applied force alone does not release a hand or deliberate foot hold in the current build. Automatic grip-strength failure is outside the current course scope, and no force-break threshold is required on the hold.

The reach constraint remains in effect. Deliberate release and applicable held-location destruction, endpoint retirement, and character-death outcomes still end holds under `LIMB-008`, `LIMB-009`, and `COMMIT-002`.

### LIMB-007 — Authored grab eligibility

**Status:** Accepted  
**Kind:** Authoring and gameplay policy

Level designers or asset creators control deliberate hold eligibility through an authored Boolean setting. One shared policy governs hand and deliberate foot attachments, including holds on indestructible terrain and live bombs. Eligibility is independent of destructibility.

An eligible value permits a hold attempt; the host must still validate current geometry, reach, obstruction, slot occupancy, and other applicable rules under `INTERACT-002`. An ineligible value rejects new deliberate holds. Ordinary foot contact does not create a persistent attachment and is unaffected by this setting.

The effective value must be recoverable from current state or permitted validated definitions. `is_grabbable` is an illustrative field name, not a required API. Authoring defaults, exact record placement, and definition/reference encoding remain implementation work. Existing hold continuity follows `LIMB-008` and `LIMB-009`.

### LIMB-008 — Hold continuity through destruction

**Status:** Accepted  
**Kind:** Canonical lifecycle and structural invariant

When destruction changes an attached material piece, a limb attachment follows the valid resulting piece on which its held location survives. The attachment retains its own ID, remaps its target where necessary, and transforms its attachment coordinates into the resulting target's local space. A one-result geometry update follows the same held-location validity rule while retaining the material ID under `IDENTITY-001`.

If the held location is destroyed or has no valid surviving target, retire the attachment and release the hold. One limb attachment never branches or duplicates across multiple children. Resolution occurs in the same structural commit as the geometry and target-identity changes.

Exact coordinate representation, numerical tolerances, and ambiguous boundary cases remain open. This rule does not authorize moving a hold from a destroyed location to a different surviving location merely to preserve it.

### LIMB-009 — Existing holds on character death

**Status:** Accepted  
**Kind:** Canonical lifecycle rule

In the character's death commit, retire its own hand and foot attachments. Other characters' existing holds targeting the surviving body continue with their attachment IDs unchanged. The target body keeps its ID under `CHAR-003`; no retargeting is needed solely because it becomes an environment piece.

If concurrent destruction removes a held location, resolve that attachment under `LIMB-008`. Eligibility for starting new holds on the corpse still comes from its interaction properties; those properties are not selected by this continuation rule.

### LIMB-010 — Holds constrain reach while permitting body movement

**Status:** Accepted  
**Kind:** Physical interaction baseline

During a hand or deliberate foot hold, the limb stays attached to its held location on the target. The character's one authoritative body can move and rotate as permitted by that limb's reach and the other physical constraints. The attachment constrains movement beyond the permitted reach rather than imposing a rigid body arrangement.

Visible limbs follow the resulting body/attachment relationship and have no separate authoritative physics bodies. The held location follows a moving target; destruction and death still resolve attachments under `LIMB-008` and `LIMB-009`.

This chooses the physical behaviour at the semantic level. Character-side roots/reach and minimum attachment contents are refined by `LIMB-011` and `LIMB-012`. Exact coordinate/numeric encoding, engine constraint type, stiffness/damping, and active movement controls remain open. Applied force alone does not release holds in the current build under `LIMB-006`.

### LIMB-011 — Fixed local roots and authored maximum reach

**Status:** Accepted  
**Kind:** Character definition and reconstruction baseline

Each character limb slot has a fixed body-local root, such as a shoulder or hip, and an authored maximum reach supplied by the selected character definition. The character's current body pose transforms the root into world space. The target's current pose and the attachment's target-local held location determine the held point.

Those inputs are sufficient for the accepted reach constraint and for deriving held-limb presentation; the baseline does not require a separately changing authoritative root pose or separate limb body. Character motion and constraints can still change the visible pose. This does not select active pulling/climbing controls, further lasting character inputs, exact numeric values/types, or the engine constraint implementation.

### LIMB-012 — Minimum canonical hold contents

**Status:** Accepted  
**Kind:** Minimum relationship-record baseline

Besides its persistent relationship identity, a limb attachment's accepted minimum canonical contents are character ID, limb slot, target ID, and held location in target-local space. Fixed roots and maximum reach resolve from the selected character definition under `LIMB-011`; endpoint poses resolve from their body-motion state.

Do not duplicate those definition or body-motion facts on the attachment, or duplicate attachment ownership on the character. The derived constraint, visible held-limb pose, and `(character, slot)` lookup use those sources. Held-location remapping follows `LIMB-008`. Exact local-coordinate/numeric encoding remains open. No force-break threshold is required under `LIMB-006`. Any demonstrated additional attachment-specific lasting inputs require their own nonduplicated source; they are not silently added to this accepted minimum.

## 10. Bombs and events

### BOMB-001 — Bomb lifecycle

**Status:** Accepted  
**Kind:** Canonical lifecycle rule

A bomb is a persistent canonical entity while it exists. On explosion, the bomb entity retires. The bomb does not produce persistent bomb-fragment entities in the current design.

### BOMB-002 — Live bomb physics

**Status:** Accepted  
**Kind:** Physics invariant

A live bomb has an authoritative two-dimensional physics body. Its movement responds to the physical world, including collision and support by moving material. Bomb-specific behavior governs its detonation, with the landing-triggered countdown under `BOMB-003`. The precise collision response and classification of a landing remain open.

### BOMB-003 — Landing starts a recoverable countdown

**Status:** Accepted  
**Kind:** Gameplay lifecycle and recoverability rule

A live bomb begins its detonation countdown on its first valid landing. Its canonical bomb-lifecycle state records countdown activation and enough timing information to reconstruct its remaining path to detonation without replaying the original landing event.

Once activated, the countdown continues while the bomb is held, thrown, moving, or unsupported. Losing support or landing again does not pause, restart, or extend it. When the countdown expires, the bomb detonates at its current position and retires under `BOMB-001`.

The remaining-duration representation is accepted under `BOMB-004`. The landing classification, authored countdown value, and detailed update/detonation ordering remain open.

### BOMB-004 — Countdown stores remaining duration

**Status:** Accepted  
**Kind:** Canonical lifecycle-state baseline

`BombState` represents a countdown as inactive, or active with a remaining duration. On the first valid landing, the host initializes that duration from the selected bomb/fuse configuration and advances the active countdown through the authoritative simulation. Holding, throwing, support loss, and later landings preserve its progress under `BOMB-003`. Reconstruction reads the current activation state and remaining duration without replaying the landing event.

A deadline against a shared match clock is not required for this countdown representation. Duration values, units/numeric encoding and precision, landing classification, and detailed update/detonation ordering remain open. No fixture timestep or numeric timer implementation is selected by this rule.

### EVENT-001 — Explosion event

**Status:** Accepted  
**Kind:** Modeling rule

The explosion itself may be represented as a transient event or consequence. Lasting results of the explosion must appear in current canonical state.

## 11. Interaction requests and validation

### INTERACT-001 — Client proposal

**Status:** Accepted  
**Kind:** Network contract

A client may resolve or predict an interaction locally and send the host:

- The intended interaction.
- The proposed target entity ID.
- The proposed contact or attachment point.
- The geometry revision the client observed.

### INTERACT-002 — Authoritative validation

**Status:** Accepted  
**Kind:** Network contract

The host validates the proposal against current authoritative state, including current geometry, proximity or reach, obstruction, endpoint existence, and other applicable gameplay rules.

Small geometric discrepancies may be projected or clamped onto nearby valid authoritative geometry only within explicit permitted tolerances. Projection cannot convert a fundamentally obstructed, unreachable, retired, or otherwise invalid interaction into a valid one.

### INTERACT-003 — Revision semantics

**Status:** Accepted  
**Kind:** Network contract

A geometry-revision mismatch does not by itself accept or reject an interaction. The revision records what geometry the client believed it was acting on and supports diagnostics and synchronization. Authoritative validity decides the outcome.

## 12. Structural commit and reconstruction

### COMMIT-001 — Atomic topology changes

**Status:** Accepted  
**Kind:** Architectural invariant

Topology-changing consequences are resolved and committed atomically. A committed state must not contain references to retired entities, partially applied splits, duplicated canonical relationships, or runtime joints whose canonical connector no longer exists.

### COMMIT-002 — Relationship remapping

**Status:** Accepted  
**Kind:** Structural invariant

Persistent physical relationships must be resolved against geometry outcomes during the same structural commit that changes their endpoints. A relationship remaps to valid surviving results, becomes multiple new relationships where required by `CON-011`, or terminates when no valid result exists.

### REBUILD-001 — Runtime reconstruction

**Status:** Accepted  
**Kind:** Architectural invariant

Material rigidbodies, colliders, connector joints, render meshes, presentation objects, and lookup indexes are reconstructed from current canonical state. Internal solver history is not required to establish canonical truth.

## 13. Networking boundary

### NET-001 — Semantic protocol

**Status:** Accepted  
**Kind:** Architectural invariant

The network protocol communicates semantic simulation state and operations rather than serializing Unity objects, engine joints, or arbitrary ECS memory layout.

### NET-002 — Canonical consequences

**Status:** Accepted  
**Kind:** Architectural invariant

Once the host commits an interaction or structural consequence, the canonical result is replicated. Clients may derive noncanonical presentation and runtime consequences locally where appropriate.

## 14. Course implementation boundary

The course implementation currently requires:

- Host Unity-authoritative two-dimensional gameplay state, with Odin handling networking and replication.
- Reconstructable canonical state.
- Persistent identities for characters, bombs, destructible and indestructible material/environment entities, limb attachments, and structural connectors.
- Persistent player match identity separate from the current Claymate body's entity ID.
- Canonical participant-roster records owning optional controlled-body references.
- Character death switches the surviving body to environment behaviour while preserving its ID, installing environment selections supplied by the character definition; the corpse then reconstructs from ordinary environment records.
- Character damage does not accumulate; a qualifying blast causes immediate death under its power/radius lethality condition, with intervening material reducing effective reach under `WORLD-007`.
- Death clears player control and the dying character's own holds while preserving other characters' holds on surviving locations.
- One authoritative physics body per character and live bomb, with hands and feet as character-local interaction slots.
- Destructible material geometry with the accepted identity rules.
- Separate physics bodies for material entities.
- Shared `MaterialProperties` for environment pieces, living characters, and live bombs; explicit density in material definitions, with mass for all three roles derived from density and current 2D gameplay area.
- Independently selectable material destruction response, with physical results using ordinary material entities.
- A declared 2D gameplay shape and aligned visual data for each authored material section.
- Default inheritance of material, response, and reusable visual settings by resulting pieces, with explicit response-specified changes permitted.
- Course anchoring through fixed foundation pieces and rigid connectors; fixed wall geometry, fixed behaviour, and stable endpoint identities supplied by recoverable level/world data.
- Rigid environmental connectors with derived Unity joints.
- Recoverable intended connector relationships preserved through reconstruction and remapping.
- Force, torque, and attachment-loss failure paths for rigid connectors.
- Atomic structural commits and relationship remapping, using world-space local-frame poses, centre-of-mass linear velocity, and body-local shapes, limb roots, held locations, and endpoint attachment regions under `WORLD-006`. Visual geometry aligns with the local gameplay shape; remapping preserves surviving material locations. Changes intended to preserve motion preserve surviving material's instantaneous movement, including same-ID results.
- Limb holds retain their IDs and follow surviving held locations through destruction; destroyed locations release their holds.
- Limb holds maintain their held locations and constrain reach while permitting character-body movement and rotation; fixed local roots and authored maximum reach resolve from the character definition, with minimum hold state under `LIMB-012`.
- The first valid landing starts a bomb countdown represented canonically as inactive or active with remaining duration. It continues through holding, throwing, support loss, and later landings, then detonates at the current position.
- The first-pass component responsibilities under `ECS-005` and the accepted conceptual groupings under `ECS-007`, with remaining fields/encodings open.
- Connector capacity is `Fmax = S × L` and `Tmax = ½ × S × L²` under `CON-009`; optional authored percentage failure uses identity-based references under `CON-010` and `CON-014`.
- Nominal blast radius gives maximum reach through empty space. Straight paths consume ordinary distance plus independently authored resistance × thickness from original material, including cover removed by that explosion (`WORLD-007` to `WORLD-010`, `MAT-010`).
- A path must breach intervening material before carving behind it; indestructible cover fully blocks carving and character exposure through that path (`WORLD-009`, `WORLD-011`).
- The killing explosion leaves the resulting corpse uncarved; a subsequent independent explosion uses its ordinary current environment response (`CHAR-006`).
- One authored Boolean eligibility policy governs deliberate hand and foot holds, including live-bomb targets, under `LIMB-005` and `LIMB-007`.
- Applied force alone does not release limb holds in the current build under `LIMB-006`.
- The coarse system responsibilities under `ECS-006`, with execution order still open.
- Client interaction proposals validated against authoritative current state.

The following are not implied by this document and remain open or deferred:

- Exact ECS framework, unaccepted record boundaries and remaining fields/encodings, and system/commit ordering.
- Exact geometry representation, units, numeric encoding, local origins/pivots, quantization, and polygon library.
- Additional physical-property inputs/derivations, actual corpse settings, and fixed-wall/definition reference encoding.
- Blast-resistance inputs and their source, propagation and thickness calculation, and exact power/radius mapping.
- Exact fixed-timestep rate, snapshot rate, transport, rollback, or correction strategy.
- Geometry-operation versus result-contour replication.
- Non-rigid environmental connector implementations.
- Final multiplayer capacity.
