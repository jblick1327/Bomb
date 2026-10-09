# Bounded blast conformance experiment — Phase 2 feasibility review

Date: 2026-10-09. **Uncommitted experiment; not ready to merge.** The approved constant-reach angular fan cannot meet both the required wide-layer fixtures and the reviewed work budget. No numerical bound, dependency, package, solver setting, handbook file or historical expectation was loosened to make it pass.

The unchanged Phase 1 proposal is preserved in [BlastConformancePhase1.md](BlastConformancePhase1.md). New invocations, verdicts, analytic checks and state captures are under [2026-10-09-phase2](BlastConformanceEvidence/2026-10-09-phase2/). Historical evidence remains intact.

## Inputs and authorization

Implementation checkout: `C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe`, branch `feature/blast-conformance-probe`, based directly on **3f652e9178a78777bd41514441229827f7e611ad**. No merge was used. James approved Phase 2, opaque indestructible cover, stable body-ID ordering with a complete commit before the next explosion, and the proposed recovery approach. His latest instruction asks for **uncommitted changes for review**; this implementation has not been committed or pushed.

Normative checkpoint: supplied `BOM-Handbook-1.5.0-Source.zip`, SHA256 `49deb9ece85b84086ed4b3dcccd76bcc32e518f1c9d91210d5bc3343098491f8`, Handbook **1.5.0**, Architecture **v0.13**, decisions through **DEC-066**. The embedded and independently recomputed sourceHash is **ef1d9430e490e7b4757e38f57daf12b1dfe19ff3cd2272610aea3147f9e93a0c**. The supplied prepared checkpoint has no Git revision. Its 15 checkpoint hashes and complete source reading are recorded in Phase 1. Published `gh-pages` was `65cd6086626d916f99b9389c589fecf9356bf67d`, still the older 1.4.0 checkpoint; it was not substituted.

The original checkout (`feature/canonical-destruction-commit`, `5960ed4e16efc5e3bf21489fb38b6ce429229c04`), previous handbook worktree (exact experiment base), and pushed Phase 1 report worktree (`feature/blast-conformance-plan`, `2f77c10df7bc18ff678681ed88918345c99bfd43`) were preserved. No applicable AGENTS.md was found in inspected project/ancestor paths. Unity CLI and legacy 2D physics skill instructions were read. The installed Unity/CLI/package versions were retained.

## Implemented boundaries and ownership

| Files | Responsibility |
|---|---|
| `CanonicalDefinitions.cs` | Explicit presence and finite nonnegative blast resistance in the immutable shared material source; independent of density and response |
| `CanonicalMaterialSnapshot.cs` | New schema 3 bundles; existing dependency closure and allocator validation; reject schema 2 and missing resistance without migration |
| `HandbookConformanceFixture.cs` | Explicit resistance 0 on newly constructed old fixtures; existing density, responses and defaults otherwise retained |
| `BoundedBlastEvaluator.cs` | Ephemeral frozen original-world inputs, material ray intersections, accumulated cost, opacity, whole-sector reach enclosure, character front exposure witnesses, budgets and final radial continuity rejection |
| `BoundedBlastGeometry.cs`, `DestructionGeometry.cs` | Strict double half-plane batch path beside unchanged direct-cutter path; positive-area pieces retained, convex unions merged before canonical conversion; representation failures reject |
| `CanonicalDestructionService.cs` | Resolve the authored response and evaluate the common field only for original candidates; reject stale fields |
| `CanonicalSimulationHost.cs` | One complete structural result per independent explosion, stable due-bomb order, original-input geometry and exposure, same-ID unchanged-shape death, next-explosion ordinary corpse response |
| `BlastConformanceFixture.cs` | Authored cover 4/density 2, core 1/density 3, narrow material 16, selected minimum cell area 0.00001; these are experiment inputs |
| New EditMode/PlayMode test files | Analytic expected outcomes, actual published geometry probes, recovery, rejection atomicity, death, same-tick order and physical landing/fuse evidence |
| `HandbookConformanceTests.cs` | Only the existing schema-specific rejection literal changes from 2 to 3; rejection assertion retained |

The existing full planner owns identity allocation, connector pairing/failure, held-point mapping and control clearing. The host applies the existing motion/result policy once from each original source. No lasting blast entity, physics tick, impulse system or networking owner was introduced. Runtime adapter and solver settings remain unchanged. Unity documents manual fixed-step simulation in [PhysicsScene2D.Simulate](https://docs.unity3d.com/6000.2/Documentation/ScriptReference/PhysicsScene2D.Simulate.html) and angular contributions in [Rigidbody2D.GetPointVelocity](https://docs.unity3d.com/6000.2/Documentation/ScriptReference/Rigidbody2D.GetPointVelocity.html); those primary pages were read while retaining the existing adapter's conventions.

## Method and feasibility failure

Each explosion excludes only its source bomb and captures original body states and immutable selected materials. Convex ray intervals are merged within each body, so internal cell seams are not charged twice. Costs are `distance + sum(resistance × original crossed length)`. Cover removed in the planned result never reduces that cost. Non-subtracting material stops both carving and exposure behind its first original entry. Distinct overlapping candidate bodies and an origin inside other material are rejected rather than assigned a new gameplay policy.

Angular events include all original vertices and character silhouettes. Within each open event interval the active edges provide analytic trigonometric denominator bounds, including extrema. Inversion encloses reach across the whole sector. The inner cut uses constant lower reach with a 0.0001 m inward allowance and chord sagitta at most 0.00025 m. Accepted reach enclosure width is at most 0.0005 m. Shared endpoints are lowered only when the original one-sided path limits agree; true shadow jumps are not averaged. Float conversion has a 0.00005 m gate; total certified radial undercut is limited to 0.001 m.

The batch backend partitions each original convex cell by fan sectors and retains its portion outside the corresponding chord. It merges only adjacent convex unions with matching area, then performs canonical validation and selected response area validation. It rejects retained cells it cannot represent instead of deleting slivers. Result vertices and original/result edge intersections partition a final radial ordering check: retained intervening material followed by removal rejects the whole structural plan. The 16,384-event certificate cap is a bounded implementation work guard; it is not a gameplay rule. This experimental arithmetic uses double guards of 1e-10 m for interval degeneracy and 1e-12 for collinear/merge arithmetic, distinct from positional tolerances. These predicates have not been certified for arbitrary geometry.

**Real blocker:** for radius 5 and the required cover `x=1..2, y=-6..6, resistance=4`, the stopping point remains inside cover throughout `0 <= theta <= acos(0.2)`. Its radial reach is independently:

`s(theta) = (5 + 4/cos(theta))/5 = 1 + 0.8/cos(theta)`.

It increases from 1.8 m to 5 m. Both sides have total variation 6.4 m. A fan whose accepted sector variation is at most 0.0005 m therefore needs **at least 12,800 sectors within these cover angles alone**, before counting any air sectors, inward guard or interval overestimation. The approved cap is **4,096**. This is a conflict in the approved numerical proposal, not a defect that a better uniform ray count or arbitrary cleanup can cure. [CheckFanBudget.py](BlastConformanceEvidence/2026-10-09-phase2/CheckFanBudget.py) produces the independent calculation without calling Unity or the evaluator.

Both radius-5 and radius-8 wide-layer field evaluations reject at the sector budget. Host acceptance tests retain their expected success and actual-geometry assertions. Their before/after snapshots establish rejection without structural publication or allocation. A failed plan does not constitute evidence of 0.8 m cover penetration or 1 m core penetration.

The narrow backend also fails its current decomposition gate: after convex merging, the unrotated narrow case retains a cell with float area **1.24415737e-6 m²** and minimum edge **3.18837916e-6 m**. The rotated case retains a cell with float area **9.970761e-6 m²**. Both fail the selected/canonical 1e-5 m² minimum; the first also fails the existing edge minimum. These positive-area pieces are not dropped. This establishes a limitation of the current sector partition and greedy convex merging; it does **not** prove that no other lossless repartition can represent the same result. Full repartition remains unfinished behind the feasibility gate. Neither representation nor thresholds were widened.

## Exposure and ordering conventions

Exposure uses the same frozen material intervals and cost bounds as carving. A qualifying character has a proved positive angular aperture arriving at its original front surface with cost strictly below the original radius and no earlier opaque material. Its own preserved body does not make its front surface unreachable; it still blocks paths continuing behind it when its selected response is opaque. This front-surface witness is the bounded character overlap convention, rather than a centre-distance test. If only uncertain boundary contact is found without any exposed witness, evaluation rejects. Fixtures retain the power threshold 1; these conventions do not settle universal character tuning.

The killing explosion installs authored corpse selections without changing the body's ID, shape or geometry revision. The existing planner clears control and outgoing holds while retaining valid incoming holds. A subsequent independent explosion takes a new original-world capture and evaluates that corpse's ordinary response. Due bombs are sorted using existing body-ID comparison; each commits before the next field is built, without an intervening physics/fuse step. Explicit calls preserve caller order. A later rejected explosion does not roll back a prior completed explosion.

## Measured results

Installed Unity **6000.2.14f1** and Unity CLI **1.0.0-beta.10** drove the actual project through `run_tests`, assembly filters, async execution and completed `test_status` verdicts. Exact invocations are in `invocations.log`; initial zero-count async responses are never treated as passes.

| Final run | Passed / total | Failed | Skipped / inconclusive |
|---|---:|---:|---:|
| `Bomb.CanonicalDestruction.EditModeTests` | **65 / 78** | **13** | 0 / 0 |
| Existing EditMode cases within that run | 50 / 50 | 0 | 0 / 0 |
| New EditMode cases | 15 / 28 | 13 | 0 / 0 |
| `Bomb.CanonicalDestruction.PlayModeTests` | **13 / 14** | **1** | 0 / 0 |
| Existing PlayMode cases within that run | 11 / 12 | 1 | 0 / 0 |
| New PlayMode cases | 2 / 2 | 0 | 0 / 0 |

The final EditMode verdict is `edit-complete-status.json` (10.10 s); PlayMode is `play-final-status.json` (2.32 s). All leaf verdicts and stacks are preserved. Thirteen new EditMode acceptance cases fail: **11 sector-budget rejections** (five translated/rotated wide-layer cases, wide opaque cover, behind-layer character, original-cost/order test, full planner test, cavity and covered corner) and **two narrow retained-cell representation rejections**. Their expected success assertions remain intact. Assertions after the initial failure, including wide post-carve geometry, order invariance and layered structural remapping/recovery, were not reached.

The one old PlayMode regression is `PhysicallyFallingHeldBomb_CountsDownAndExplodesFromReachableOrigin_WithAtomicDeathAndHoldCleanup`: final geometry fails the prefix certificate at angle **3.6433830942227932 rad**. This prototype does not successfully reproduce that preserved gameplay explosion. The rejection is not excused by positional tolerance or hidden cleanup; its cause/repair remains an outstanding geometry task. The old test's expectations were not changed. The other old physics/recovery/hold tests pass. The previous 12/12 PlayMode evidence still belongs to the original radius-only implementation, not this experiment.

| Demonstrated case | Actual observations and limits |
|---|---|
| Empty space, radii 0.25, 0.75, 5 and 10 | 10,001 independent angular probes per field plus successful host bomb retirement. At radius 10: 512 sectors, maximum measured undercut **0.00028824529 m**, enclosure width **0.00010000000 m**, reported conservative deficit bound **0.00033824717 m**. No measured overreach. |
| Thin unbreached layer, radius 1.05 | Actual published cover starts at **x=1.009899973869 m**, leaving **0.010100007057 m** centrally; core geometry, ID and revision are identical. 526 sectors, 280 result cells. Whole-field reported deficit bound **0.00093816973 m** and maximum conversion drift **5.99387033e-8 m**. |
| Independent full-geometry thin-layer measurement | 10,001 directions across the analytic opening: maximum radial deficit **0.000495933171 m**, minimum 0. Actual removed area **0.003995189818 m²** versus independent analytic **0.004222630558 m²**. Symmetric difference for this conservative cut is **0.000227440740 m²**, below the **0.000650673743 m²** enclosure derived from the 1 mm radial bound. This measurement calls no implementation evaluator. |
| Bounded opaque cover, radius 0.75 | Source retires; original cover and weak core shapes remain identical; character within nominal reach behind them remains alive with unchanged shape. The separate required wide opaque fixture still fails the fan cap. |
| Exposed qualifying character | Same body ID and shape on death; authored corpse role/configuration installed; control and outgoing hold cleared; valid incoming hold preserved. Recovery succeeds. A subsequent independent blast fully removes the corpse through its ordinary response. |
| Simultaneous expiry | Two due bombs presented in reverse order produce two separate complete commits in stable ID order during one host Tick. First snapshot contains the unchanged-shape corpse and second live bomb; second snapshot contains neither. No whole-tick immunity. Play frames advance. |
| Real falling bomb, opaque foundation | Bomb falls from y=2 and activates the original 8 s fuse after **30 real host physics ticks**, landing at **y=0.4101417**. It retires after exactly **400 active ticks**. Original opaque floor is unchanged; notification errors are empty. Field uses 2,544 sectors with enclosure **0.000499593850 m** and conservative deficit **0.000948514291 m**. Capture/rebuild preserves authored floor resistance 4. This proves an actual landing/fuse explosion, **not successful layered terrain carving**. |
| Recovery/validation/rejection | Explicit resistance stays independent and frozen, density changes do not derive it, expected definition hashes reject changed dependencies, missing resistance and schema 2 reject. Unsupported overlap, embedded origin and unresolved pure-tangent character exposure reject without publication. Existing single-survivor spin, allocator and fuse regressions pass. |

The initial new thin-layer test incorrectly placed the permitted conservative error on the opposite side of the analytic boundary. It was corrected to `expected - 0.001 <= retained-front <= expected`, with a separate check that unbreached thickness is at least the analytic 0.01 m. This changes a new test assertion to match the approved inward method; no old geometric expectation or error bound changes.

Compilation ends completed with `compilationFailed=false`, no compiler errors, and no compiling work. Current console ground truth reports **0 errors / 0 warnings**. Pipeline history contains three URP default-camera warnings and no errors; these were preserved without changing a scene. Initial development included a corrected long/ulong compile mismatch. A clean script-cache rebuild during discovery exhausted Windows allocation and stalled; only the verified isolated Editor/helper tree was restarted. Preliminary runs that omitted the new class remain as preliminary evidence. The final test runs include all new cases and are independent of those incomplete discovery runs.

Final Editor PID **11640**, exact isolated project, Play **stopped**, pause false. One clean unsaved default scene is open (empty scene name/path, two roots), with no scene asset changes. There are no package, project setting or scene diffs. Branch remains at the exact base commit, with source/tests/reports/evidence **uncommitted and unstaged**. Original and previous checkouts remain clean and unchanged. The evidence audit verifies 47 current schema-3 snapshots and byte-identical before/after worlds for all 13 rejected captured acceptance cases.

The preserved extreme-force hold limitation remains documented separately in [HandbookConformance.md](HandbookConformance.md): a 6.15577 m transient distance for 1.5 m authored reach, settling to 1.50000 m after 40 steps in the old diagnostic. Its gameplay relevance still depends on future control/contact load bounds; no solver, reach rule, artificial release or force clamp was changed in this blast pass. That issue does not explain the new final-geometry regression.

## Review needed to continue

The current approved constant-lower-reach method must change before the required wide-layer cases can succeed under the reviewed cap. A possible next proposal is a varying-endpoint cut with a whole-sector bound on interpolation error and conservative breach certification, retaining the 1 mm geometric bound and existing backend. It requires a new numerical proof and representation feasibility check; endpoint sampling alone would be insufficient. Increasing the sector cap is another review option, with explicit performance and output-cell evidence. Neither change was made here.

Layered carving, original-cost exposure/order invariance, full layered connector/hold/motion outcomes and post-layered recovery remain acceptance obligations until their actual geometry passes. Arbitrary geometry, overlap composition, embedded origins, exact tangent lethality, historical save migration, chain reactions, blast impulses, shattering and production networking remain untested/outside scope. The preserved extreme-force hold reach limitation remains separate. Passing bounded cases is not certification of arbitrary geometry or the entire game.
