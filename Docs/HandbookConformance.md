# Handbook conformance probe

This is James's approved bounded implementation experiment, not a handbook revision.
Normative baseline: `origin/gh-pages` / `d9ac305f198162e5c20aabebd9c5fe7344f598d4`,
Architecture v0.11, DEC-056, handbook v1.3.2. Experiment base:
`5960ed4e16efc5e3bf21489fb38b6ce429229c04`. Branch:
`feature/handbook-conformance-probe`; worktree:
`C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance`.

The original checkout and assignment prototype remain separate. James separately
authorized committing and pushing the conformance branch after verification.
No merge, package upgrade or handbook edit is included. Unity 6000.2.14f1,
Pipeline 0.7.0-exp.1, Test Framework 1.6.0 and URP 17.2.0 are retained.

## Inspect the fixture

Open `Assets/Game/Scenes/HandbookConformance.unity` in this worktree and enter Play.
The scene component creates one match and one local, manually stepped 2D physics
scene. B falls onto P; landing starts its countdown. The demonstration pauses,
captures current state, destroys the derived objects, reconstructs from JSON,
cuts P with a direct world-space strip, then repeats capture/destruction/recovery.
The final scene is paused for inspection with an active countdown. The component's
**Continue authoritative simulation** context menu resumes it.

| Label | Authored fixture data |
| --- | --- |
| W | Fixed level union: floor `[-5,5] × [-1,0]`, upright `[-4,-3] × [0,4.5]`; indestructible, hold eligible |
| P | Dynamic rectangle `[-3,3] × [-0.5,0.5]`, world position `(0,3)`; density 2, subtraction response, hold eligible |
| C | Rigid W–P bond: W `(-3,2.7)→(-3,3.3)` paired with P `(-3,-0.3)→(-3,0.3)` |
| K | Dynamic Claymate rectangle 0.6 × 0.8 at `(2,1)`; density 1; character definition supplies limb and corpse settings |
| L | Deliberate RightHand K→P at P-local `(2,-0.5)` |
| Participant | Separate persistent match identity; sole controlled-body reference to K |
| B | Dynamic regular 16-gon of radius 0.25 at `(-1.5,6)`; density 3, eligible, inactive countdown |

All seven IDs come from one match allocator. The primary cutter is
`[-0.25,0.25] × [2.4,3.6]` in world coordinates. It is a **direct geometry test**,
not a gameplay bomb explosion. C keeps its ID on the left fresh child, L keeps its
ID on the right fresh child, and P retires. The reachable gameplay check separately
lets a real bomb fall, land, be held, count down and explode at its current 2D pose.

## Ownership and interfaces

| File/area | Owns |
| --- | --- |
| `MaterialEntityId.cs`, allocator in `CanonicalMaterialWorld.cs` | Existing opaque ID value and reservation allocator, used for bodies, relationships and participants; persistent high-water mark |
| `CanonicalDefinitions.cs` | Typed, content-hashed definition references; frozen material, response, appearance and role definitions; fixed character roots/reach and death settings |
| `CanonicalMaterialState.cs` | Immutable current shape, revision, world pose and motion, selected definitions, optional current bomb countdown |
| `CanonicalGeometry.cs`, existing `DestructionGeometry.cs` | Existing convex subtraction, non-overlapping connected cells, transforms, material-point and paired-segment clipping queries |
| `CanonicalRelationships.cs` | Connector endpoints/correspondence/strength/reference; minimal hold record; sole participant control reference; immutable complete graph |
| `CanonicalOutcomePlanner.cs`, `CanonicalDestructionService.cs` | Real evaluation, 0/1/many body identity, complete connector/hold/control remapping before publication |
| `CanonicalMaterialWorld.cs` | Complete mutation validation, internal generation/revision checks, reservation completion, projection preparation, state/index switch, observable notification errors; validated motion/lifecycle batches |
| `CanonicalMaterialSnapshot.cs` | Version-2 full current-state bundle, sorted records, required frozen definitions including death dependencies, allocator; explicit optional-record presence; rejects old schemas/missing/changed dependencies |
| `CanonicalWorldRuntime2D.cs`, contact sensor | Derived local PhysicsScene2D, Rigidbody2D/PolygonCollider2D, paired-pin rigid constraints, maximum-distance holds, measured reactions and contact observations |
| `CanonicalShapeMesh.cs` | Shared extrusion from current canonical cells; the legacy 3D projector and new 2D adapter both use it |
| `CanonicalSimulationHost.cs` | Local authoritative hold validation, command queue, timer activation/advance, blast/death/bomb retirement and immediate measured connector failure |
| `HandbookConformanceFixture.cs`, `HandbookConformanceScene.cs` | Localized approved definitions, geometry, scene demonstration and evidence captures |
| EditMode/PlayMode test files | Focused state and real engine evidence; relevant original tests retained, observer assertion masking corrected |

`StructuralMutationPlan` carries a complete resolved graph and expected internal
generation. Every new persistent ID must exactly match the active reservation.
Validation and inactive projection preparation precede allocator advancement and
publication. `IPreparedCanonicalProjection.Publish()` is a no-fail main-thread
switch; it may not validate or create additional state. Observers run after both
canonical state and derived lookup/objects switch. Their exceptions are collected
in `NotificationErrors`, which the tests assert explicitly.

Snapshots contain no engine handles, retired-parent records or event replay.
Selections resolve material density, destruction response and appearance independently;
mass derives from density and current area. DefinitionSet freezes
JSON and returns copies; hashes detect dependency content changes. Optional expected
definitions can also validate a bundle against a receiving environment. Schema 1
is deliberately rejected; historical save migration was not approved.

## Approved replaceable conventions

These are fixture choices, not universal gameplay rules or ratified decisions.

* Metres, seconds, kg; density kg/m². Finite float coordinates and canonical radians;
  Unity angular degrees convert only at the adapter boundary. World body poses;
  body-local cells, limb roots and attachments. Convex CCW non-overlapping cells
  form one connected union. Clip tolerance `1e-5`, connectivity `1e-4`.
* The selected subtraction response retains the existing `0.01 m²` minimum **cell**
  cleanup. This is not a universal minimum body area. Unsupported or ambiguous
  geometry/remapping rejects the outcome, including disconnected attachment remnants
  on one unchanged child pair. No fallback relocates a lost held point.
* One survivor keeps its frame. Several children recenter at their own centroids.
  Coordinates preserve the same material points; child COM velocity includes
  `ω × rotated(resultCentroid − sourceCentroid)` for every outcome, including a
  single same-ID survivor whose local centroid changes. Material/response/appearance and
  independently selected motion configuration survive by default.
* Material density × current area supplies engine mass with no floor. The same
  derivation is an approved fixture extension for K/B, beyond MAT-005's material
  scope. Adapter preparation rejects observable engine mass clamping.
* One local 2D physics scene per running fixture, manual fixed step 0.02 s, gravity
  `(0,-9.81)` applied locally, friction 0.4, restitution/damping 0, continuous dynamic
  collision detection. Existing solver settings 8 velocity/3 position iterations
  are retained. No global settings change or extra authoritative 3D simulation.
  Each convex cell has its own PolygonCollider2D on the body's shared Rigidbody2D;
  a single collider with touching paths incorrectly filled the foundation's open
  region in the first engine run. The regression checks empty and solid points.
* C's two corresponding separated attachment endpoints derive its rigid rest fit
  using two pin constraints. Current temporary displacement never becomes rest data.
  Surviving paired-overlap length is capacity input: `Fmax = Sℓ`,
  `Tmax = Sℓ²/2`; S = 5000 N/m in the primary fixture. Sum pin reactions and their
  moments about the bond midpoint. Optional minimum fraction 0.5, lifetime reference
  0.6 m. Test old percentage before replacements; new IDs receive their own initial
  surviving length; ongoing IDs keep their reference. No fatigue/grace period.
* Engine automatic break force/torque is infinite for both connector and hold
  machinery. Host checks measured connector force/torque immediately after each
  step. Holds have no force failure policy. Hands root `(±0.2,+0.3)`, reach 1.5 m;
  feet root `(±0.15,-0.35)`, reach 1.0 m. Maximum-distance constraints permit movement
  and rotation. Ordinary foot collision creates no hold.
  The normal reach/load test applies `(1000,500)` N. A separate extreme-force
  diagnostic applies `(10000,5000)` N, verifies no hold retirement and reports
  transient solver stretch; it does not assert instantaneous hard reach at that
  load. This limitation is an explicit remaining engine issue, not a changed rule.
* New hold requests require current roster control, living actor, valid endpoint,
  authored target Boolean eligibility, free slot, current surface, reach and clear
  path. Maximum surface correction `1e-4 m`. Observed revision mismatch is diagnostic
  only; internal mutation stale checks remain separate. Existing incoming holds can
  survive death even though the installed corpse rejects new holds.
* Bomb landing is an environment support contact with upward normal ≥ 0.5 and
  approaching relative motion. Activation installs 8 seconds. Active countdowns
  continue on support loss, later contacts and holding. Bomb retirement cleans up
  targeting holds atomically. One canonical double duration is held internally in
  milliseconds and advanced by the integral 20 ms step; fractional milliseconds are
  preserved. Schema 2 still encodes `countdown.remaining` as numeric seconds, now
  read/written at double precision. No expiry epsilon or history-based clock reset.
  No bomb fragments.
* Blast power 1, radius 0.75 m, 24-gon subtraction. Lethal when power ≥ 1 and distance
  to current character shape ≤ radius; no damage accumulator, occlusion/shielding,
  attenuation or blast impulse. Bodies that become corpses in this blast are not
  carved again by that blast. Death keeps ID/shape/motion, installs selected clay,
  subtraction response, ineligible environment role and clay appearance, clears
  control/outgoing holds and keeps incoming surviving holds.
* Existing material tints supply appearance; current shape extrudes 0.2 m with
  identity XY alignment. Meshes have no 3D collider/body. Camera is for inspection.
* Host order: validate queued commands → step 2D physics → batch capture motion /
  measure loads / observe contacts → advance existing timers and activate new ones →
  evaluate gameplay → resolve the complete outcome → prepare projection → commit →
  notify. Commands/notifications have no automatically allocated persistent IDs.

## Executed verification

The correction pass on 2026-10-08 executed **50/50 EditMode and 12/12 PlayMode
tests successfully** in Unity 6000.2.14f1, with no skipped or inconclusive tests.
The [correction evidence](ConformanceEvidence/Correction-2026-10-08/README.md)
records eight reproduced failures before the fixes and all subsequent passes.
The earlier `35b4693` implementation executed 39/39 EditMode and 11/11 PlayMode
tests successfully; its preserved reports below remain unchanged. Both runs include all
eight original EditMode tests and the original PlayMode test. Unity reported
`compilationFailed: false`, `compiling: false` and zero current console errors.
Historical failed runs are retained, rather than counted as current failures or
silently discarded.

Evidence was produced in `Temp/ConformanceEvidence/` and copied to the persistent
[evidence directory](ConformanceEvidence/README.md). Final reports:
[EditMode run 4](ConformanceEvidence/editmode-result-4.json), duration 1.16 s;
[PlayMode run 5](ConformanceEvidence/playmode-result-5.json), duration 1.49 s.
Their start envelopes record the exact selections. Exact invocation pattern,
using the isolated project path on every call:
Exact invocation pattern, using the isolated project path on every call:

```powershell
unity command eval --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance' --format json -- --code 'UnityEditor.AssetDatabase.Refresh(); return UnityEditor.EditorApplication.isCompiling;' --timeout 15000
unity command console_status --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance' --format json
unity command set_autotick --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance' --format json -- --enable true --interval_ms 16 --persist true
unity command run_tests --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance' --format json -- --mode editor --filter Bomb.CanonicalDestruction.EditModeTests --filter_type assembly --async_tests true --timeout 300
unity command run_tests --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance' --format json -- --mode playmode --filter Bomb.CanonicalDestruction.PlayModeTests --filter_type assembly --async_tests true --timeout 300
unity command test_status --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance' --format json
```

The initial EditMode run executed 37 tests: 33 passed, four recovery tests failed
because JsonUtility expanded absent optional objects. Explicit presence fields
correct that codec issue. Interim compiler errors (an unassigned error variable,
projection identity property name and callback discard shadowing) were corrected.
The second EditMode run passed 37/37, the third passed 38/38, and the final run
passed 39/39 after adding a recovery safety regression: a reservation belonging
to another allocator cannot commit or cancel this allocator's reservation, even
when their internal token numbers coincide.

The first PlayMode run executed 10 tests: four passed and six failed. Diagnostics
identified inverse point-transform measurements and the multi-path collision hull.
After correcting these, the second run passed seven of ten. Remaining failures
identified activation resetting staged native-body velocities (restored after
activation before notification), an extreme-force transient reach overshoot, and
a torque-test input that exceeded both force and torque capacities. The isolated
torque input is now 2000 N·m: the measured first-step moment exceeds capacity while
net force stays below it. Failed run envelopes and focused diagnostics remain in
the evidence directory. The third PlayMode run passed 10/11; its last failure was
exact colour equality after floating-point conversion, corrected to a `1e-5`
numeric tolerance. The fourth and final fifth runs both passed 11/11. One subsequent test-start request met a compilation domain
reload and returned a network error; no pass was inferred from it.

The saved scene was also executed independently of the test runner. The initial
additive scene-creation attempt was refused by Unity because an untitled scene
was open. Inspection showed the untouched, clean default camera/light scene;
the fixture replaced it only after verifying there were no dirty scenes.
No unsaved scene was discarded. The independent demonstration then completed
both destroy/recover cycles and the real evaluator split. Its graph inspection
recorded five Rigidbody2D projections, zero 3D rigidbodies, fixed W at `(0,0)`,
C `match-...0005` on left child `match-...0009` at x = -1.6246,
L `match-...0006` on right child `match-...0008` at x = 1.6254,
P `match-...0002` absent, participant control still on K, and active B with 8 s
remaining. Frame counts advanced from 33440 to 83500 while the host was deliberately
paused for inspection, confirming background Editor ticking. IDs allocated to
left/right children depend on evaluator result order; their spatial identity,
not a particular suffix, is the assertion.

The [scene preview](ConformanceEvidence/handbook-conformance.png),
[scene inspection](ConformanceEvidence/scene-verification-2.json), and actual
[before](ConformanceEvidence/scene-before.json) /
[after](ConformanceEvidence/scene-after.json) bundles are retained.
The scene has only a bootstrap and camera in Edit mode; its runtime objects derive
from canonical state on entering Play. **Continue authoritative simulation** resumes
the paused host. The primary demonstration's pause freezes the whole host, rather
than changing the bomb lifecycle. The separate reachable-bomb test exercises expiry.

| Runtime check | Observed result | Evidence |
| --- | --- | --- |
| Supported/held recovery, then real split and another recovery | Old objects removed across a frame; 65 physics steps including post-recovery simulation; fixed W; connector fit error 0.00007248 m; hold distance 0.39942 m; active countdown 7.40000 s | `primary-before.json`, `primary-after.json`, `primary-measurements.json` |
| Rest fit recovered from temporary displacement | 0.53757 m initial mismatch reduced to 0.00040245 m after 100 steps; displaced pose was not adopted as rest data | `connector-rest-fit.json` |
| Immediate connector force failure | 180.380 N against 60 N capacity, zero measured moment; retired on the first loaded step | `connector-force.json` |
| Immediate connector moment failure | About 443.49 N below 600 N force capacity; absolute moment 339.512 N m above 180 N m capacity; retired on the first loaded step | `connector-torque.json` |
| Moving/rotating hold under `(1000,500)` N | Reaction 358.704 N, body rotation 17.267 degrees, final distance 1.44418 m; each loaded step checked within the test's 0.05 m solver tolerance around 1.5 m | `hold-reach.json` |
| Extreme force, no automatic hold release | Reaction peak 8369.49 N; hold/joint preserved; transient distance 6.15577 m for 1.5 m reach, final distance 1.50000 m after 40 steps | `hold-extreme-solver-limit.json` |
| Mass below the legacy floor; independent presentation depth | Engine accepted 0.0200000014 kg; changing depth from 0.2 to 0.8 m left the 2D trajectory unchanged | `mass-and-presentation.json` |
| Physically reachable gameplay explosion | B fell and landed, an ordinary validated hold preserved its timer, expiry retired B and targeting hold, K died without changing ID and lost control/outgoing hold; origin `(-1.34883,3.76241)` outside P, surviving P area 5.50453 square metres | `reachable-bomb.json` |

Each measurement file uses the same diagnostic DTO. Unused fields contain defaults;
they are not assertions about that case. The corresponding test and table identify
the meaningful fields. The reachable-bomb origin is a measured pose, not an authored
interior shortcut; small run-to-run solver variations are expected.

### Accepted rules exercised in this bounded slice

This is case evidence, not a certification of every possible world or input.

| Rule IDs | Evidence and boundary |
| --- | --- |
| AUTH-001; Unity simulation part of AUTH-003 | Local host owns validation, physics observations, gameplay and publication. No clients or Odin networking. |
| STATE-001 through STATE-004; REBUILD-001 | Complete current-state bundles resolve definitions and rebuild after old objects are destroyed; no handles, retired parents or event replay. |
| ECS-001 through ECS-004 | Match-scoped persistent IDs across body/connector/hold/participant records, composed selections, ephemeral requests, complete structural commits. |
| ECS-005 through ECS-007, implemented responsibilities only | Motion/shape/material/response/eligibility/character/bomb/relationship/participant data and local system ownership; no full movement or match-progression catalogue. |
| WORLD-001 through WORLD-006 | One authoritative 2D scene; canonical geometry with derived extrusion; fixed definition-authored W and C anchoring; world poses/local geometry; WORLD-003 evidence comes from the reachable-bomb PlayMode case, not the direct strip. |
| MAT-001 through MAT-009, fixture scope | Authored W/P sections and C composition; separate bodies; independently selected motion, response, appearance and material; density/area mass without floor; aligned geometry; inheritance and shared material inputs. No general composite authoring tool. K/B density derivation is the approved extension beyond MAT-005's material-piece scope. |
| IDENTITY-001 | Real evaluator removal, connected survivor and split; respectively retire, same ID, or fresh children with retired source. |
| CON-001 through CON-011; CON-013; CON-014 | Paired body-local attachment remapping, no connector body, rigid fit, measured translational force and bending moment, immediate load failure, length-based capacity, optional old-bond percentage check and identity-based lifetime references; both-endpoint split avoids false Cartesian pairs. |
| CON-012, scope handling only | Unsupported disconnected remnants on one unchanged endpoint pair reject the plan. No such reachable gameplay case is claimed or special semantics invented. |
| PLAYER-001; PLAYER-002 | Separate participant identity and sole roster control reference; current-control validation and death clearing. |
| CHAR-001 through CHAR-005 | One living K body with definition-authored roots/death settings; same-ID environment transition, control/outgoing/incoming hold consequences, corpse-only recovery, two sublethal blasts without accumulated damage. Full locomotion is omitted. |
| HAND-001; FOOT-001; LIMB-001 through LIMB-009; LIMB-011; LIMB-012 | Minimal canonical hold contents, shared hands/feet target eligibility including eligible/ineligible bombs, current validation, target-local point continuity/loss, no force-only release, moving-target and death behavior, and ordinary foot contact creating no hold. |
| LIMB-010, bounded loads only | Real movement/rotation and reach constraint under the reported normal load. Instantaneous reach under extreme forces remains an explicit engine gap. Visible limb art is omitted. |
| BOMB-001 through BOMB-004; EVENT-001 | Real dynamic landing activates a current-state timer; recovery/holding/support loss preserve it; expiry retires the live bomb and leaves canonical destruction/death results. Explosion has no persistent event identity. |
| INTERACT-002; INTERACT-003, local proposals only | Current host geometry, eligibility, control, reach, obstruction and free slot decide validity; observed revision mismatch alone is diagnostic. Internal stale-plan protection is separate. No client transport. |
| COMMIT-001; COMMIT-002 | Complete geometry/identity/relationship/control outcomes; invalid graph/preparation/stale plan/throwing evaluator policy preserve state and allocator; canonical and projection visibility before observers; observer exceptions explicitly checked. |

AUTH-002, the networking part of AUTH-003, INTERACT-001 transport and NET-001/002
are not demonstrated. Nor are complete player controls, full matches, all arbitrary
geometry/relationship topologies, universal solver bounds or historical save migration.

## Scope and specification feedback

The legacy Arena remains a prototype: constrained 3D bodies, bounds-based rock
authoring, legacy mass floor, transient bombs and prototype death behavior are
outside the conformance scene. Its synthetic interior bomb call is relabelled in
`Docs/Checks.md` and `VerifyCanonicalDestruction`. The new probe reuses its canonical
evaluator/world/codec/mesh generation, not those gameplay/physics assumptions.

No production networking, client prediction, complete controls, full match rules,
new ECS or geometry dependency, shattering/art/UI/performance work, historical
schema migration or arbitrary reachable geometry guarantee is demonstrated.

Remaining engine limit: the approved single 0.02 s step and 8/3 solver settings
allow transient stretch under extreme inputs. A diagnostic measured 6.156 m for a
1.5 m reach immediately after `(10000,5000)` N, with the hold identity/joint intact;
distance returned to approximately 1.5 m after about 0.6 s. Increasing solver work,
substepping or restricting controls would need a separate decision. No force cap,
extra substeps, relocation or hold-break threshold was introduced to hide this.

Resolved clock defect: `35b4693` repeatedly subtracted float 0.02 s, leaving about
0.000007063 s after 400 steps and expiring on step 401. The correction uses one
double duration in milliseconds and subtracts an exact integral 20 ms. Eight seconds
now expires at step 400, including recovery every step and periodic recovery.
Positive fractional steps are retained and expire on the next step; the physically
reachable bomb case also asserts exactly 400 active steps. This is an implementation
precision correction, not a new gameplay duration or handbook rule.

Reach assessment: K has mass 0.48 kg, so gravity supplies about 4.709 N. The two
diagnostic force vectors have magnitudes about 1118 N and 11180 N, approximately
237 and 2374 times its weight. Their unconstrained one-step velocity changes would
be about 46.6 and 466 m/s. These are deliberate load probes, not established movement
control settings. The scene has gravity/collisions/holds and no authored locomotion
controls or blast impulse; its primary and reachable-bomb checks did not reproduce
the extreme stretch. That does not establish a bound for future controls or contact
loads. Gameplay relevance remains conditional on intended acceleration, jump/pull
impulses, falls and moving supports, plus an accepted reach-error/settling criterion.
No force cap, movement redesign, solver setting change or extra physics step was added.

Proposed handbook clarifications for James's review (not edits): distinguish
definition dependency integrity from engine object identity; make explicit that
canonical velocities describe COM motion when any shape change moves its centroid,
including a same-ID survivor whose frame is retained; require recovery
evidence with temporary body displacement when testing connector rest fit; specify
whether disconnected attachment remnants on one child pair need a later geometry
contract; consider documenting publication's no-fail projection-switch contract and
the difference between whole-host pause and holding/support loss for countdowns.
The tested numeric formulas, landing classification, corpse values and cleanup
remain implementation conventions unless James explicitly adopts them.

Two further clarifications are proposed: define acceptable numerical reach error
and any settling window, or require a solver strategy that provides a hard bound;
and define countdown precision/expiry at fixed-step boundaries. No existing rule
was edited to adopt either limitation.

Remaining implementation work outside the approved slice: choose a solver strategy
if hard instantaneous reach is required; establish gameplay load/error bounds;
extend the geometry
contract when a real reachable unsupported case exists; then implement production
controls/matches/networking or schema migration as separately scoped work. The
prototype adapters still require their own migration if the team adopts this model.

## Correction pass after review of 35b4693

The real subtraction policy applies `omega cross COM-offset` before its identity/
frame choice. One survivor retains pose/local coordinates/ID and gets the corrected
COM velocity; several children still recenter and receive the correction once.
Two consecutive asymmetric cuts test both unrotated and rotated spinning sources,
including the second cut's nonzero original centroid, analytic surviving-point
velocities, relationship continuity and unchanged allocator sequence. A PlayMode
test verifies native `Rigidbody2D.GetPointVelocity` before/after the same-ID commit
and after old objects are destroyed and recovered.

Recovery high-water validation now runs for defined matches with any participant,
connector or hold, independent of whether bodies remain. Body-only legacy snapshots
keep their previous non-allocated-ID compatibility. Roster-only regressions reject
counters below/equal to the participant ID and a mismatched namespace, then prove
valid round-trip recovery and allocation of the next noncolliding participant ID.

The timer implementation changes `BombCountdown`, the lifecycle step and the codec's
numeric duration precision. Snapshot schema and field names are unchanged; prior
numeric remaining durations are read as given, without changing an already saved
duration. The native simulation step remains 0.02 s. Double milliseconds permit
fractional durations while removing the repeated subtraction error in this fixture.

The full EditMode assembly ran before the fixes: 42/50 passed, eight failed. Those
failures exactly reproduce two single-survivor velocity cases, three roster-only
validation cases and three eight-second expiry/recovery cases. Afterward, 50/50
passed in 2.40 s; the full PlayMode assembly passed 12/12 in 1.80 s. Compiler and
final console checks reported no failure and zero errors/warnings. The original
eight EditMode and one PlayMode tests remain included. The original checkout, scene,
packages/settings and handbook revisions remain separate and unchanged.

Current reports, commands and measurement bundles are preserved in the correction
evidence subdirectory with separate checksums. The original evidence stays intact.
The background setting is restored and Play mode stopped. The correction work stays
on `feature/handbook-conformance-probe`; the original experiment branch and handbook
remain untouched.

## Verification checkpoint before commit and push

Unity is left open in the isolated project with `HandbookConformance.unity` active
and Play mode stopped. The temporary `runInBackground` setting was restored to its
original false value. Package and ProjectSettings diffs are empty. The original
checkout remains clean on `feature/canonical-destruction-commit` at the base commit;
At the recorded verification checkpoint, the new branch was at that same commit
with all implementation, scene, tests, documentation, generated Unity metadata and
persistent evidence **uncommitted**. The preserved `handoff-final.json` records that
checkpoint, before James's separate authorization to commit and push this branch.
Handbook sources are unchanged; no merge or handbook publication is authorized.

The earlier missing-Blender import warning for the inherited `Rock.blend` asset
did not prevent these Unity tests or the dedicated scene. No dependency was installed.
The final console retains one recorded orphan-metadata warning from the temporary
preview cleanup. Unity removed the image's orphan metadata on refresh; the remaining
empty capture folders and their metadata were then removed and the database refreshed
again. No temporary screenshot assets remain. The [warning](ConformanceEvidence/console-scene-warnings.json)
and [final console status](ConformanceEvidence/console-final.json) are retained;
there are zero console errors and no compilation failure.
Source/documentation whitespace checks passed. The staged Unity-generated scene
and metadata retain the Editor's standard spaces after empty YAML fields.
[Evidence index](ConformanceEvidence/README.md) includes
SHA-256 hashes so the current reports and bundles can be distinguished from later runs.
