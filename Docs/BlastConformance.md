# Bounded blast conformance experiment

Phase 1 proposal, 8 October 2026. **The required supplied checkpoint is verified. Phase 2 remains unapproved.** This pass changes documentation and inspection evidence only. The method and bounds below are proposed acceptance criteria, not measured results or production policies.

## 1. Baseline, ownership and current path

| Input | Verified identity |
|---|---|
| Normative local checkpoint | James's `C:\Users\jblic\Downloads\BOM-Handbook-1.5.0-Source.zip`; Handbook **1.5.0**, Architecture **v0.13**, decisions through **DEC-066** |
| Embedded and independently recomputed sourceHash | `ef1d9430e490e7b4757e38f57daf12b1dfe19ff3cd2272610aea3147f9e93a0c` |
| Archive SHA-256 | `49deb9ece85b84086ed4b3dcccd76bcc32e518f1c9d91210d5bc3343098491f8` |
| Publication state | The supplied manifest says prepared locally, uncommitted and not pushed. It supplies **no Git revision**. Published `gh-pages` remains `65cd6086626d916f99b9389c589fecf9356bf67d`, Handbook 1.4.0 / v0.12 / DEC-061 at inspection. |
| Exact experiment base | `feature/handbook-conformance-probe` at `3f652e9178a78777bd41514441229827f7e611ad` |
| Report-only checkout | `.worktrees/blast-conformance-plan`, branch `feature/blast-conformance-plan`; based on that exact experiment commit |

The supplied root README was read first, followed by the complete Architecture, Decision Log, Open Questions, candidate map, team summary and interview handoff. All 15 checkpoint file hashes agree with its manifest. The six source files agree with the root HTML's embedded Markdown and hashes; recomputing the build's signature also gives the expected sourceHash. No handbook was rebuilt, edited or published. The earlier failed baseline checks remain in [their dated evidence](BlastConformanceEvidence/2026-10-08-phase1-baseline/README.md) and report history.

No applicable `AGENTS.md` was found in the inspected ancestors or project trees. The installed Unity CLI and legacy 2D physics skill instructions were inspected. The frozen setup is Editor 6000.2.14f1, CLI 1.0.0-beta.10, Pipeline 0.7.0-exp.1, Test Framework 1.6.0 and URP 17.2.0.

| Existing owner / extension point | Finding and bounded responsibility |
|---|---|
| [CanonicalDefinitions.cs](../Assets/Game/Destruction/CanonicalDefinitions.cs) | Shared immutable material definitions and content-hashed selections. Density exists; blast resistance does not. Add resistance here only. |
| [CanonicalSimulationHost.cs](../Assets/Game/Destruction/CanonicalSimulationHost.cs) | Gameplay owns landing, continuous fuse, detonation and death. `TryResolve` uses an exact shape-distance radius test for characters and a separate 24-sided circular cutter for terrain. Neither accounts for intervening material. |
| [DestructionGeometry.cs](../Assets/Game/Destruction/DestructionGeometry.cs), [CanonicalDestructionService.cs](../Assets/Game/Destruction/CanonicalDestructionService.cs) | Convex half-plane subtraction, connected results and inherited result properties. Extend with a bounded batch cutter; retain this backend. |
| [CanonicalOutcomePlanner.cs](../Assets/Game/Destruction/CanonicalOutcomePlanner.cs), [CanonicalMaterialWorld.cs](../Assets/Game/Destruction/CanonicalMaterialWorld.cs) | Complete body/connector/hold/roster remapping, one ID reservation, validation, prepared projection and atomic publication. Reuse these owners. |
| [CanonicalMaterialSnapshot.cs](../Assets/Game/Destruction/CanonicalMaterialSnapshot.cs), [CanonicalWorldRuntime2D.cs](../Assets/Game/Destruction/CanonicalWorldRuntime2D.cs) | Current definition dependency closure and independent recovery; one Rigidbody2D per body and convex cell colliders. No persistent blast state is needed. |

The canonical representation already supports connected unions of non-overlapping convex cells, including concavity and enclosed cavities. It supports zero, one and multiple results and complete relationship consequences. The old 3D projection test is separate from the authoritative 2D adapter and remains preserved.

The original assignment checkout remains on `feature/canonical-destruction-commit` at `5960ed4e16efc5e3bf21489fb38b6ce429229c04`; the earlier conformance checkout remains at the exact experiment base. Both were clean and are preserved. Only the separate report checkout is edited here.

The [correction evidence](ConformanceEvidence/Correction-2026-10-08/README.md) contains **50/50 EditMode and 12/12 PlayMode passes**, zero failed/skipped/inconclusive. All 55 original, 15 correction and five earlier Phase 1 checksums still match. This is preserved v0.11 / DEC-056 evidence, not new shielding evidence. No Unity tests ran in Phase 1.

## 2. Proposed full 2D method and bounds

For **one explosion**, freeze the current canonical poses, cells, selected material definitions and resistance before evaluating any target. Work in coordinates relative to the bomb's current position, using double precision internally.

For a straight unit direction `u`, clip the ray against every candidate convex cell. Union touching intervals belonging to the same body so cell seams do not charge twice. Sort unambiguous material segments front to back. For distance `s`:

`C(s) = s + sum(resistance_i × length(segment_i intersect [0,s]))`.

Air costs one per metre; material costs `1 + resistance` per metre. Invert this monotone piecewise-linear cost up to the nominal budget. Retain every original interval even when its body will be cut. This provides layered propagation rather than independent adjusted body radii.

Construct a **conservative adaptive angular fan**, with these coverage obligations:

1. Start sector boundaries at every candidate polygon vertex direction, cell/contact event and the coordinate axes. Include character silhouette events. On each open sector, certify the active intersected edges and their order; subdivide if that certificate fails. A narrow or rotated feature therefore contributes angular events even if no uniform sample would hit it.
2. Each edge intersection has the form `t(theta) = n·(a-origin) / (n·u(theta))`. Bound its numerator/denominator over the entire sector, including trigonometric extrema, with outward rounding. Propagate interval bounds through accumulated costs and the stop interval. Refine uncertain edge order, stop-interval changes and near-parallel denominators. Sampling three rays is not a certificate.
3. Obtain a certified lower reach for the entire sector. Its triangle from the origin to the two boundary directions at that lower reach lies inside every path limit. Subdivide until the reach interval and chord error meet the bounds below. Keep one-sided limits at edge-aligned jumps; never average across a shadow boundary.
4. The union of those triangles is the inner cut. Every removed point has a straight segment to the origin inside the same cut. Subtract it from **all** subtractable intervening bodies. Thus a cut reaching the core also removes the cover along that path. Separate exposed sectors can advance farther; no sector wraps around a corner.

Maintain outer sector bounds for uncertainty checks; they are not cutters. Character exposure uses this **same frozen field**: positive-area intersection with its certified inner region provides an exposed witness; disjointness from the outer enclosure proves protection. Refine ambiguous overlap. If only a tangent or an unresolved boundary within the tolerance remains, reject the explosion with diagnostics rather than guessing alive/dead. The proposed fixture lethality convention retains the current qualifying power threshold of 1 and tests shape overlap, not the centre. Neither is a universal tuning requirement.

| Proposed bounded domain / acceptance criterion | Limit |
|---|---|
| Nominal radius; authored resistance | Radius 0.25–10 m; resistance 0–16 for these fixtures |
| Coordinates | Absolute positions within ±64 m; relevant transformed vertices within 32 m of the origin |
| Input feature thickness and clearance | At least 0.02 m for tested positive-width layers/gaps; exact shared faces handled separately |
| Work budget | At most 32 candidate bodies, 128 input cells, 1,024 edges, 4,096 sectors, refinement depth 24 and 512 final cells per result |
| Reach variation over an accepted sector | At most 0.0005 m |
| Maximum sector chord deficit | 0.00025 m; at radius 10 this requires at most about 0.8103° sectors even in empty space |
| Conservative inward allowance | 0.0001 m; clipping and float conversion error must be certified within 0.00005 m |
| Overall radial deficit | At most **0.001 m**, on supported one-sided directions; no positive-area removal beyond the certified reach |
| Boundary/topology checks | Every retained cell valid, no positive-area overlaps, expected connectivity and at least the analytically required unbreached cover; no hidden fragment loss |

These are replaceable experimental numerical conventions. None has yet been achieved by an implementation. A cap, predicate uncertainty, unsupported overlap or canonical representation failure **rejects the whole explosion plan** before reservation/publication. It does not increase tolerances or overblock selected targets.

**Backend feasibility gate:** the current cutter drops cells below `minimumRetainedCellArea` during each subtraction (0.01 m² in the old fixture), and its cross-product tolerance is not normalized by edge length. Repeated fan subtraction cannot inherit those behaviours and claim the bounds above. Add a strict batch path using normalized double predicates, retained intermediate positive-area cells, and lossless convex merging/repartitioning before canonical conversion. Require a bound on the complete conversion, not a tolerance per operation. Never discard a positive-area sliver to breach cover. Old direct-cut behaviour and authored thresholds stay intact; new narrow fixtures explicitly select a response with minimum cell area 0.00001 m². If lossless representation under the selected threshold and existing canonical validation fails, stop and report the blocker. A different library, wider representation or solver change needs a separate proposal.

After final float conversion, certify the actual removed/retained intervals over sectors partitioned by result vertices too: removed material must form a prefix through the original intervening material. A retained cover interval followed by removed core is a rejection even if its thickness is within the positional error budget. Numerical uncertainty must not defeat the breach rule.

Check actual resulting geometry with independent ray/segment probes at the centre **and off axis**, retained-cover thickness, area, connectivity and membership on either side of the analytic boundary. For fixtures with analytic boundaries, also measure boundary distance and symmetric-difference area against an enclosure formed from the 1 mm bound. Use analytic formulas or independently written measurement code, never the field evaluator as the oracle.

## 3. Resistance authoring, validation and recovery

Add `hasBlastResistance` and a float `blastResistance` to the shared material definition. In metre-based fixtures resistance expresses extra metres of reach per metre crossed; evaluate that authored float in double precision. The presence bit distinguishes an explicitly authored zero from a missing field that Unity JSON would otherwise initialize to zero. Material validation requires presence and a finite, nonnegative value. The 0–16 numerical domain is an evaluator limit, not the material model's global maximum. Density, connector capacity and response choice remain independent. Bodies resolve resistance from their selected immutable material reference; do not duplicate it in body state or a runtime component.

For **newly constructed** old test fixtures, propose explicitly authoring resistance 0 for terrain, clay, bomb and light, retaining their density and other selections. This is a reviewed fixture convention that preserves their existing purpose, not an inferred game default. New fixtures author cover 4 and core 1 in distinct material definitions and explicitly author living/corpse inputs.

Add schema **3** for newly captured bundles. Schema 2 and missing resistance are rejected with a clear diagnostic; no historical save migration or old-definition reinterpretation is proposed. Content hashes regenerate from the new definitions, including character corpse references. Retain the existing dependency closure: current selections plus corpse selections needed by living characters; after death no former character definition is needed. Tampered, absent, incorrectly typed or changed material definitions must fail recovery. Current legacy body-only direct-cut fixtures can still create and round-trip fresh schema-3 snapshots; such bodies are unsupported inputs to material-dependent blast evaluation.

Only the schema-specific literal in the existing unsupported-schema regression legitimately changes from 2 to 3. Preserve its rejection assertion, the existing spin/allocator/fuse regressions and all historical captured snapshots. Recovery before detonation and after both layered and death results must preserve exactly authored resistance, current geometry/IDs, selections, motion, timers, relationships and allocator high-water mark without retired parents or event replay.

## 4. Host integration and complete structural results

Add an ephemeral blast evaluator/field beside the geometry evaluator. The host passes one original-world view to it and uses its results for both environment subtraction and character exposure. Collect final geometries, newly dead characters' authored corpse selections, bomb retirement and load-failed connectors, then call the existing complete planner and publication path. The field is calculation data, not a new lasting entity, tick system or canonical owner.

For the killing explosion, install the corpse selection on the same body and unchanged shape; do not pass that new corpse through its cutter. The existing planner clears control and outgoing holds and preserves valid incoming holds. For changed environment bodies, run the existing result policy **once from the original source to each final result**. Preserve selection inheritance, density-times-area mass, original frame for a single survivor, fresh IDs/recentring for splits and conditional point-velocity preservation. All body results must be known before connector span pairing, old-connector percentage failure, replacement allocation and held-point remapping.

The current host batches due bombs and skips every newly dead character for the entire batch. That is broader than CHAR-006. Proposed ordering convention for this experiment: use existing stable body-ID comparison to order simultaneously due independent explosions; finish one explosion's full atomic commit before evaluating the next against its new current world. Do not step physics or advance fuses between them. Explicit consecutive `TryDetonate` calls use caller order. No whole-tick immunity or persistent flag is added. A later rejected explosion leaves that explosion uncommitted; it does not undo an earlier completed explosion. This is a proposed local ordering convention, not a handbook-selected global schedule.

## 5. Edge cases, limits and policy question

| Input | Proposed treatment / review boundary |
|---|---|
| Tangency, exact edges, shared cell faces | Merge same-body interval seams; a zero-length crossing adds zero cost. Use one-sided sector certificates. Unresolved pure-tangent character lethality or output topology is rejected, with the location recorded. |
| Cavities and concavity | Use canonical cell unions. Empty cavity intervals cost ordinary distance only. Rays continue straight after a gap; no flood fill through connected empty space. Test an enclosed cavity and an L-shaped covered corner. |
| Origin inside other material | Outside the bounded fixtures; reject without relocating the bomb. Reviewed live fixtures keep its centre in air outside other material. The source shape exclusion does not excuse an embedded environment origin. |
| Overlapping bodies | Positive-area overlap between distinct candidate bodies has no accepted material-combination policy. Reject affected evaluation; exact shared faces are successive intervals. Do not add, maximize or choose a material silently. Physics contact penetration may expose this limitation in live tests and must be reported. |
| Source bomb | Propose excluding only the detonating bomb's own shape from shielding cost and retiring it in the same result. This is an explicit fixture convention requiring review. Other live bombs are not automatically excluded; chain reactions and their transmission are outside this experiment. |
| Non-subtracting cover | A finite resistance alone cannot justify carving behind cover that cannot be breached. **Pending James's answer:** either reject an affected plan as unsupported, or use reviewed opaque-barrier behaviour for both geometry and exposure. Living bodies preserved by CHAR-006 remain original material inputs; removal behind their uncarved shapes is outside the bounded fixtures pending the same breach-policy clarification. |
| Independent explosions | Original inputs are fixed within each explosion. The next independent explosion takes a fresh input snapshot, including installed corpse resistance/response and earlier geometry changes. Use the reviewed ordering above. |

**Focused policy question sent to James:** should indestructible cover with reach remaining stop both carving and character exposure behind it, or should affected plans remain unsupported until transmission policy is decided? No answer is inferred from elapsed time. Exact character boundary lethality, overlap composition, other-bomb interaction, production material values and historical compatibility remain open; fixture conventions do not resolve those policies.

## 6. Bounded change and evidence plan

| Rule coverage proposed | Evidence obligation |
|---|---|
| MAT-010 | Explicit independent material authoring, validation, definition hashes and pre/post recovery equality |
| WORLD-007 / WORLD-008 | Shared original-world distance plus resistance-times-thickness budget; layered analytic geometry and exposure, no refund |
| WORLD-009 | Certified continuous inner cut, retained-cover probes and no buried core removal |
| WORLD-010 | Complete angular coverage, rotated/narrow/corner checks and one calculation shared with character exposure |
| CHAR-005 / CHAR-006 | Qualifying exposure, unchanged shape/ID on death, authored corpse selections and subsequent independent carving |
| Existing identity, relationship, motion, fuse and publication rules | Complete planner and live projection/recovery regressions remain in force |

After explicit Phase 1 approval, create a separate `.worktrees/blast-conformance-probe` and `feature/blast-conformance-probe` directly at `3f652e9178a78777bd41514441229827f7e611ad`. Verify absolute paths and all checkout dirty states first. Carry the reviewed report as documentation without merging branches.

| Planned files | Scope |
|---|---|
| `Assets/Game/Destruction/CanonicalDefinitions.cs`, `CanonicalMaterialSnapshot.cs` | Explicit resistance validation and current schema/dependency handling |
| New `Assets/Game/Destruction/BoundedBlastEvaluator.cs` | Original-world interval costs, certified angular coverage and shared exposure field |
| `DestructionGeometry.cs`, `CanonicalDestructionService.cs` | Strict batch subtraction and lossless representability checks within the existing backend |
| `CanonicalSimulationHost.cs` | Shared blast evaluation, per-explosion death exception and reviewed independent-explosion ordering |
| `HandbookConformanceFixture.cs`; new `BlastConformanceFixture.cs` | Explicit reviewed resistance values; layered, narrow and live landing fixtures |
| Existing `Assets/Tests/EditMode/HandbookConformanceTests.cs`; new EditMode and PlayMode blast test files | Necessary schema literal update and focused regressions through the actual evaluator/host/planner/runtime |
| `Docs/BlastConformance.md` and a new dated implementation evidence directory | Coverage, exact commands/results, measured bounds, unsupported inputs and limitations |

Planner, publication, canonical body representation, runtime adapter, old scenes, old reports/evidence, package/project settings and assignment prototype need no planned edits. Scene authoring is not needed for the evidence: isolated PlayMode fixtures use the live runtime host. If a later demonstration scene is useful, propose it separately. A change beyond these files or replacement of the backend returns for review.

Independent expectations use a bomb at the origin, wide cover `x=[1,2]`, core `x=[2,4]`, both spanning `y=[-6,6]`. Illustrative values are air 1 m, cover resistance 4, core resistance 1. Cost to core is **6 m**, through core **10 m**. Off-axis directions that cross both wide layers have cost to core `6/cos(theta)`; the radius-5 cover boundary is `x=0.8+cos(theta)`, and radius-8 core boundary `x=4cos(theta)-1`. These expectations come from algebra, not the proposed implementation.

Additional independent fixtures: a 0.02 m square cover centred at `(3.01,0)`, resistance 16, leaves central reach **4.68 m** at radius 5; rotating that square alone by 37° gives `5 - 0.32/cos(37°)`, while directions outside its silhouette retain nominal reach. A wide 0.02 m-thick layer starting at 1 m with resistance 4 and radius 1.05 retains **0.01 m** of cover and does not carve the core behind it. For a single cell-union shell whose central material intervals are `[1,2]` and `[3,4]`, resistance 1 and radius 5 reach **3.5 m**: the cavity is air.

The corner fixture is an L formed by rectangles `x=[1,2], y=[-1,3]` and `x=[2,4], y=[2,3]`, resistance 4. At radius 7, a character at `x=[3.4,3.6], y=[1.4,1.6]` has minimum direct cost above 8 m and must survive. An air route via `(0.9,-1.1)` and `(2.1,-1.1)` is shorter than 7 m; its existence must not expose the character. Include an uncovered character control to detect blanket blocking. Proposed cover/core densities are explicitly authored 2 and 3 respectively, independent of resistance.

| Required case | Independent observation through approved Phase 2 path |
|---|---|
| Empty space | Geometry reach within 1 mm below nominal radius, no certified overreach; verify multiple angles and area. |
| Radius 5 | Central cover penetration 0.8 m and retained thickness 0.2 m within 1 mm; no core subtraction. Check actual shapes at 0°, 10°, 20° and 30°. |
| Radius 8 | Cover breached; central core penetration 1 m within 1 mm. Verify continuous removal across the cover/core interface and the off-axis formula. Cover-back opening half-height is about 1.763834 m. |
| Cover removed in planned output | Core still penetrated 1 m; reverse target enumeration and cell order, compare equivalent geometry and exposure. No same-blast refund. |
| Character behind wide layers | Shape `x=[4.1,4.3], y=[-0.1,0.1]`: all direct paths cost at least 10.1 m, so it survives radius 8 despite lying inside nominal reach. |
| Exposed qualifying character | Same ID and identical shape on death, installed corpse inputs, cleared control/outgoing holds, valid incoming hold retained. No carving by its killing explosion. |
| Later independent blast | Authored corpse response carves it normally; check consecutive calls without a physics step and the reviewed simultaneous-expiry order. No immunity timer. |
| Full structural result | Wide cover splits into two fresh-ID bodies; core remains connected with its ID. Verify inherited selections/resistance, analytic mass and point velocity; surviving/failed/split connectors, surviving/destroyed held locations, one complete publication per explosion and observable observer errors. |
| Recovery | Capture/rebuild before detonation, after layered cutting and after death/subsequent blast. Compare resistance and the complete current graph; reject invalid definitions, unsupported schemas and roster-only allocator collisions. |
| Robustness | Translate within bounds and rotate by 17°, 37° and 90°; include a 0.02 m-wide feature at 3 m whose silhouette is only about 0.382°. Analytic oriented-rectangle intersections must bound removal inside/outside its shadow; test narrow layers, a cavity and a covered L corner with no corner wrapping. |
| Actual gameplay explosion | A falling bomb must contact valid support, activate its authored fuse once and expire via `CanonicalSimulationHost.Tick` at its current reachable position. Use one layered fixture as well as the retained existing landing regression. Capture canonical and collider geometry, cover/core probes, exposure and structural outcomes. Direct cutter tests remain geometry evidence only. |

Run both complete existing assemblies plus new cases through the installed integration on the exact implementation project. Preserve existing expectations unless a reviewed semantic change requires a documented adjustment; zero fixture resistance retains the old radius-only scenarios' purpose, and new bounds legitimately replace the host's 24-sided cutter representation. Report every failed/skipped/rejected case rather than weakening assertions. Record start/status envelopes, compiler and current console status, passed/failed/skipped/inconclusive counts, measurements, snapshots and checksums. The [evidence index](BlastConformanceEvidence/2026-10-08-phase1-proposal/README.md) records the proposed exact invocations and current read-only handoff state.

The backend's lossless final representation is the implementation feasibility gate; indestructible transmission is the pending gameplay choice. The old extreme-load hold result remains separate: peak **6.15577 m** for authored reach **1.5 m**, settling to about 1.5 m after 40 steps. This proposal changes neither solver settings nor that limitation. Production networking, controls/matches, impulses, shattering, art, arbitrary geometry and historical migration remain untested or outside scope.

**Stop for review:** James's opening instruction authorizes committing/pushing this report branch. It does not approve Phase 2. Approval should cover the bounded method, numerical limits, explicit fixture/encoding/ordering conventions and the barrier decision above before Unity source, scenes or tests change. Passing the future cases would be bounded evidence, not certification of the entire game.
