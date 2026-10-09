# Revised bounded blast evidence — 2026-10-09

Read [the implementation report](../../BlastConformance.md) for rule coverage, conventions, ownership and measured limits. Evidence was captured from the uncommitted review checkout on `feature/blast-conformance-probe` at base `3f652e9178a78777bd41514441229827f7e611ad`. James subsequently authorized committing and pushing the source, tests, report and evidence; the saved checkout receipt preserves the state reviewed before publication.

- `final-edit-verdict.json`: complete 83/83 EditMode pass, 22.38 s.
- `final-play-verdict.json`: complete 15/15 PlayMode pass, 5.36 s.
- `invocations.log`, `Invoke-UnityEvidence.ps1`: exact installed-integration commands and raw envelopes. Zero-count async starts and timed-out starts are not verdicts.
- `states/`: current schema-3 before/after snapshots, outcomes and live landing/mass measurements; `states/handbook/` preserves existing regression measurements.
- `Benchmark.cs`, `benchmark.json`, `accuracy-and-cost.json`: eight cases, one warmup/five measured samples each. All 48 host detonations completed. The first CLI response timed out at 30 s; `restored-editor.json` confirms the completed persisted records.
- `MeasureAccuracy.py`: independent algebra, polygon/ray clipping and symmetric-difference convergence measurements; `published-wide-geometry.png` depicts actual published geometry. No implementation evaluator supplies expected results.
- `exact-continuity-result.json`, `CheckExactContinuity.py`: independent rational diagnosis of one spurious near-tangent double gap. The implementation's adaptive predicates do not waive real retained layers.
- `prior-prototype/`: unchanged failing evaluator, geometry, tests and report from before this continuation. The sibling `../2026-10-09-phase2/` evidence remains checksum-identical.
- `rejected-support-corner/`: original 0.4 m live support attempt, including the successful radius-5 result and byte-identical rejected radius-8 world. The final live proof uses a 0.1 m support whose shadow misses the wide layers. This measured discontinuity remains an explicit negative regression.
- Other dated JSON envelopes preserve intermediate implementation failures, compilation checks, stalled/cancelled starts, import/transport timeouts and the native heap-corruption initialization crash. `prior-measurement/` preserves an independently corrected target-silhouette measurement assumption.
- `generated-scene-backups/`, `generated-scenes-to-preserve.json`, `restored-editor.json`: hash-verified copies of TestRunner/recovery artifacts before removing only those generated assets and restoring the original background setting. No scene/setting/package diff remains.
- `final-editor-state.json`, `final-compiler-state.json`, `final-console-counts.json`, `checkout-state.json`: Play stopped, compiler clear, console 0 errors/0 warnings and protected clean checkouts.
- `AuditEvidence.py`, `audit.json`, `SOURCE-SHA256SUMS.txt`, `SHA256SUMS.txt`: reproducible audit and hashes. Run the audit last when intentional evidence edits are complete.

To reproduce measurements, open this exact isolated project in Unity 6000.2.14f1 and use the installed integration. Run each assembly through the recorded `run_tests` command, then poll `test_status` for a completed verdict. Run `Benchmark.cs` with `unity command eval_file --timeout 120 ... -- --file <absolute script path> --timeout 120000` so both transport seconds and evaluator milliseconds are specified, then `python MeasureAccuracy.py`. Keep Play stopped after completion. Scripts that restore historical generated assets are evidence of this run, not general cleanup instructions.

The caps and 1 mm bound are experimental numerical conventions. Timings do not establish real-time or worst-case performance. Atomic rejection of unsupported geometry is evidence of safety of publication, not successful conformance for that geometry.
