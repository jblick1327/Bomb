# Phase 1 proposal evidence

8 October 2026. This is **read-only source/provenance inspection and independent analytic arithmetic**, not an implementation, compiler run or new Unity test result. Phase 2 remains unapproved. The [proposal](../../BlastConformance.md) uses the supplied local 1.5.0 checkpoint; the published handbook was not changed.

## Captures and reproducibility

- `inspection.json`: archive identity, all 15 manifest checks, embedded/recomputed sourceHash, six embedded Markdown comparisons, preserved evidence checksum verification, decoded historical test summaries, hashes of experiment source/tests/packages/settings, and independent fixture arithmetic.
- `InspectPhase1.py`: reproduces those read-only checks; takes an optional archive path. It reads ZIP entries in memory and does not run the handbook build, extract sources, invoke Unity, modify any project or implement the proposed cutter.
- `editor-status.json`, `console-status.json`, `scene-status.json`: fresh read-only CLI envelopes against the existing conformance Editor, captured as UTF-8 with LF.
- `handoff.json`: inspected checkout/branch/scene state, frozen versions, source-reading inventory, test scope and pending review decisions.
- `SHA256SUMS.txt`: covers these captures and the reproduction script, excluding this index and the checksum file.

Reproduce the checkpoint/evidence/arithmetic inspection from the report checkout:

```powershell
python Docs/BlastConformanceEvidence/2026-10-08-phase1-proposal/InspectPhase1.py 'C:\Users\jblic\Downloads\BOM-Handbook-1.5.0-Source.zip'
git diff 3f652e9178a78777bd41514441229827f7e611ad -- Assets Packages ProjectSettings
git status --short
git worktree list --porcelain
git ls-remote --heads origin gh-pages feature/handbook-conformance-probe feature/blast-conformance-plan
```

The script follows the signature algorithm in the supplied `handbook/build.py`: UTF-8 SHA-256 of Python's sorted-key, non-ASCII-escaped JSON encoding of `handbook.json`, followed by source texts in that build's specified order. Newlines are normalized as Python text reading does. Each raw source hash and embedded Markdown hash is also checked separately. The supplied archive and all previous evidence remain unchanged. The six complete documents were read in the requested review order, which differs from the build's signature order.

Read-only Editor invocations:

```powershell
unity command editor_status --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance' --format json
unity command console_status --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance' --format json
unity command eval --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance' --format json -- --code 'return UnityEngine.SceneManagement.SceneManager.GetActiveScene().path;'
```

The Editor remains on the earlier conformance checkout and `Assets/Game/Scenes/HandbookConformance.unity`, Play stopped. Current console ground truth is separate from historical Pipeline buffer totals. No tests, recompile, Play transition, scene edit or project switch was requested in Phase 1. Window focus is unnecessary for this read-only inspection.

## Proposed Phase 2 evidence commands — not executed

After James explicitly approves the proposal and the implementation is ready in its own exact-base worktree, use the installed integration and both full assemblies:

```powershell
unity command run_tests --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe' --format json -- --mode editor --filter Bomb.CanonicalDestruction.EditModeTests --filter_type assembly --async_tests true --timeout 300
unity command test_status --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe' --format json
unity command run_tests --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe' --format json -- --mode playmode --filter Bomb.CanonicalDestruction.PlayModeTests --filter_type assembly --async_tests true --timeout 300
unity command test_status --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe' --format json
unity command editor_status --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe' --format json
unity command console_status --caller plugin --skill unity-cli --project-path 'C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe' --format json
```

Wait for completed status after each asynchronous test start; a start envelope with zero tests is not evidence. Decode string-valued `data.result` before recording executed/passed/failed/skipped/inconclusive counts. Preserve final result envelopes and exact start parameters.

Record compiler status from `console_status` ground truth (`compilationFailed`, `compiling`) and Editor readiness after importing edits; discover the frozen integration's available commands before any explicit compile/refresh invocation. Record the actual implementation revision, source/definition hashes, worktree/scene state, independent probe values, radial/boundary/area errors, output connectivity, complete before/after canonical bundles and native colliders/mass/point velocities. Record rejected inputs and their diagnostics. Demonstrate actual physical landing and canonical fuse expiry through the host; direct cutter checks do not substitute for it. Finish with Play stopped and the working tree state reported.

The earlier extreme-force hold stretch is a separate recorded limitation; do not alter solver settings or reclassify it as hard instantaneous reach conformance.

## Review boundary

This report's commit/push is authorized by James's instruction to push the work and report. No implementation approval is inferred. The focused indestructible-barrier question remains pending unless James answers it; all method bounds, authoring/codec and ordering conventions are proposed for review. No historical save migration, package/framework change or handbook amendment is approved.
