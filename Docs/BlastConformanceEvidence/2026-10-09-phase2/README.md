# Phase 2 evidence — 2026-10-09

This is an **incomplete, failing conformance experiment**, preserved uncommitted for review. See [the report](../../BlastConformance.md) for the failed feasibility gate and regression. No handbook, package, project setting or scene change is included.

Base: `3f652e9178a78777bd41514441229827f7e611ad`; worktree `C:\Users\jblic\Desktop\Bomb\.worktrees\blast-conformance-probe`; branch `feature/blast-conformance-probe`. Handbook supplied checkpoint: 1.5.0/v0.13/DEC-066, sourceHash `ef1d9430e490e7b4757e38f57daf12b1dfe19ff3cd2272610aea3147f9e93a0c`; no checkpoint Git revision supplied. Unity 6000.2.14f1, installed Unity CLI 1.0.0-beta.10, existing integration/packages/settings retained.

| Artifact | Meaning |
|---|---|
| `edit-complete-start.json`, `edit-complete-status.json` | Final full EditMode assembly invocation/verdict: 65 passed, 13 failed, 0 skipped/inconclusive, total 78 |
| `play-final-start.json`, `play-final-status.json` | Full PlayMode assembly invocation/verdict: 13 passed, 1 failed, 0 skipped/inconclusive, total 14 |
| `compiler-final.json` | Final compilation completed, no compiler errors |
| `console-counts.json`, `console-current.json` | Current ground truth 0 errors/warnings; Pipeline history 3 default-camera warnings, 0 errors |
| `final-editor-state.json`, `final-scene-state.json` | Correct project, PID 11640, Play stopped, no compilation, clean unnamed default scene |
| `fan-final-measurement.json`, `MeasureFan.cs` | Live Unity rejection at 4,097 sectors for each required radius; measured 411/383 ms on this run; no publication |
| `analytic-budget.json`, `CheckFanBudget.py` | Independent minimum 12,800 sectors in cover angles alone at the reviewed 0.5 mm variation bound |
| `published-geometry-measurements.json`, `MeasurePublishedGeometry.py` | Independent thin-layer actual polygon probes and analytic area comparison; no evaluator calls |
| `states/` | Before/after schema-3 captures, accepted diagnostics, rejected unchanged worlds, empty-space probes, actual landing/fuse and same-tick commits |
| `audit.json`, `AuditEvidence.py` | Verdict collection counts, current schema/presence checks, rejected before/after byte equality, stopped/clean Editor checks |
| `SOURCE-SHA256SUMS.txt`, `SHA256SUMS.txt` | Exact source/test and evidence signatures |
| `invocations.log`, `Invoke-UnityEvidence.ps1` | Exact timestamped installed-integration commands and reproduction wrapper |
| Earlier `edit-*` and `compiler-*` files, `infrastructure.txt` | Preserved intermediate discovery/correction and memory recovery; not substitutes for final verdicts |

Run from the verified experiment worktree with its Editor ready:

```powershell
& 'Docs/BlastConformanceEvidence/2026-10-09-phase2/Invoke-UnityEvidence.ps1' -Operation edit -Label review-edit-start
& 'Docs/BlastConformanceEvidence/2026-10-09-phase2/Invoke-UnityEvidence.ps1' -Operation status -Label review-edit-status
& 'Docs/BlastConformanceEvidence/2026-10-09-phase2/Invoke-UnityEvidence.ps1' -Operation play -Label review-play-start
& 'Docs/BlastConformanceEvidence/2026-10-09-phase2/Invoke-UnityEvidence.ps1' -Operation status -Label review-play-status
python 'Docs/BlastConformanceEvidence/2026-10-09-phase2/CheckFanBudget.py'
python 'Docs/BlastConformanceEvidence/2026-10-09-phase2/MeasurePublishedGeometry.py'
python 'Docs/BlastConformanceEvidence/2026-10-09-phase2/AuditEvidence.py'
```

Poll each async run until its returned `status` is `completed` before starting the next. The wrapper checks the absolute project path and targets that exact Editor on every command. Preserve recorded files by using fresh labels. Test-generated files live in ignored `Temp/BlastConformanceEvidence`; the preserved `states/` copies remain after Unity clears Temp on restart. The recorded final Play verdict uses identical core/runtime source to the last EditMode run; only two focused EditMode tests were subsequently added. No Play rerun was needed after that test-only addition.

Thirteen new EditMode expected-success cases remain failing; assertions downstream of the initial rejection were not executed. The old held-bomb gameplay case is a **new PlayMode regression**, failing the final continuity certificate. Smaller accepted opaque/death/landing cases do not establish successful required wide-layer carving or arbitrary-geometry conformance.
