# Bounded blast verification

**Reviewed implementation:** `feature/blast-conformance-probe` at `24e79ff0533eabf51627859b097f3503af5f54a1`, based directly on `3f652e9178a78777bd41514441229827f7e611ad`. [Implementation report](https://github.com/jblick1327/Bomb/blob/24e79ff0533eabf51627859b097f3503af5f54a1/Docs/BlastConformance.md); [dated evidence](https://github.com/jblick1327/Bomb/tree/24e79ff0533eabf51627859b097f3503af5f54a1/Docs/BlastConformanceEvidence/2026-10-09-revision-1).

**Tested handbook:** the supplied Handbook **1.5.0**, Architecture **v0.13**, through **DEC-066**, with sourceHash `ef1d9430e490e7b4757e38f57daf12b1dfe19ff3cd2272610aea3147f9e93a0c` and source ZIP SHA-256 `49deb9ece85b84086ed4b3dcccd76bcc32e518f1c9d91210d5bc3343098491f8`. Opaque cover, ordering and recovery conventions were explicitly accepted during its review. Handbook 1.6.0 first recorded those decisions and evidence; 1.7.0 reconciled their presentation and geometry replication. The current 1.8.0 checkpoint adds authoring/snapshot requirements and separate local evidence. These documentation updates are not fresh Unity runs or certification of their whole models.

### Recorded and independently checked results

The completed Unity verdicts contain **83/83 EditMode** and **15/15 PlayMode** passes, with zero failed, skipped or inconclusive tests. All original 50 EditMode and 12 PlayMode regressions pass, including the physically falling held-bomb case. Newly added tests include successful geometry and intentionally rejected inputs; a passing rejection test does not mean that input detonates successfully.

| Obligation | Bounded evidence |
|---|---|
| Strong cover over weak core | Radius 5 penetrates 0.799600005 m of cover, leaves 0.200399995 m unbreached and leaves core geometry identical. Radius 8 breaches cover and penetrates 0.999599934 m of core. |
| Identity and full structural handoff | Radius-8 cover becomes two fresh-ID bodies; connected core keeps its ID. Real planner checks connector failure before replacement, held-point survival/loss, inherited selections, density × measured area and point velocity. |
| Shielding and original cost | A character behind the layers survives inside nominal radius 8. Removed cover retains original cost; target/cell order, narrow layers, translated/rotated cases, cavities and a covered corner have independent expectations. |
| Death and later blasts | The killing explosion keeps shape/ID and applies control/holds. A subsequent independent explosion carves the corpse; simultaneous expiry commits separately in stable body-ID order. |
| Recovery and live gameplay path | Current resistance/definitions and complete outcomes recover without retired parents/replay. Real falling bombs activate an 8 s fixture fuse, rebuild, then expire after 400 active host ticks. These numbers are fixture conventions. |
| Measured accuracy | Largest independently measured radial deficit is **0.777 mm**, within the experiment's 1 mm bound. Measurements inspect actual serialized polygons with independent algebra/clipping; this is not a proof for arbitrary geometry. |

The handbook review checked all 98 recorded leaf verdicts, 28 source hashes, 283 revised evidence checksums and 112 preserved earlier evidence checksums, and reproduced the independent saved-geometry measurements. Unity suites ran in James's Codex worktree; they were not rerun in this documentation environment. The immutable commit's relevant Assets, Packages, ProjectSettings and scene diff confirms only the bounded source/test additions and no package, solver, setting or scene change.

### Remaining limits

| Limit | Current evidence and consequence |
|---|---|
| Layered computation cost | Five measured host samples per case give medians about 0.64–1.23 s for first layered blasts and **3.05 s** for a recovered second rotated layered blast. Narrow cases are about 29–32 ms. This is not demonstrated real-time gameplay performance; operation-count caps are not latency guarantees. |
| Opaque-support shadow | The original **0.4 m-wide support**, radius-8 reachable landing case still **rejects the whole explosion** because its rounded shadow edge would leave intervening material before removed material. The final successful live layered test uses **0.1 m-wide support** whose shadow misses the layers. The original case is retained as an expected atomic rejection; it is not repaired or a successful detonation. |
| Unsupported geometry | Cross-body positive-area overlap, embedded/on-material origin, unresolved tangent-only character contact, arbitrary enclosed-hole output, smaller features and cases exceeding work/representation bounds remain unsupported or unproven. |
| Structural rejection scope | Saved explicit rejected detonations preserve byte-identical canonical/allocator snapshots and produce no structural notification. Earlier independent explosions stay committed. Physics/fuse advancement before a rejected Tick is a separate effect, not a whole-tick rollback guarantee. |
| Earlier hold solver limit | A 1.5 m hold stretched transiently to 6.15577459 m under extreme force, then settled near 1.5 m. Load/error criteria and solver strategy remain open; this probe changes neither the solver nor the hold rule. |

The recorded 65/78 EditMode and 13/14 PlayMode failing prototype, the revised method/budgets and their corrected results remain in the branch's dated evidence. The direct cutter and historical tests retain their authored thresholds. No test result adopts a production geometry algorithm, framework, wire format, corpse values, general schedule, blast impulse, shattering process or historical-save migration.

James accepted stable body-ID ordering and explicit-resistance recovery for this experiment (`DEC-068`), and delegated numerical/encoding/fixture details to Codex within the agreed scope. Future implementation work should address the measured shadow and performance limits under the accepted rules. Decisions changing gameplay, canonical state/ownership/representation or scope return to James. The assignment prototype remains separate; no merge is implied by this evidence checkpoint.

## Earlier probe

`feature/handbook-conformance-probe` at `3f652e9178a78777bd41514441229827f7e611ad` records 50 EditMode and 12 PlayMode tests passing against Architecture v0.11 / `DEC-056`. Its corrected COM motion, shared mass, connector formulas and continuous fuse cases informed accepted rules. Its radius-only explosions did not demonstrate `WORLD-007`. The bounded blast successor and its exact tested checkpoint are recorded in the evidence section above; extreme-load hold reach remains a solver limitation. This handbook update changes no Unity code and does not approve every fixture convention.
