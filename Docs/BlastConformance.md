# Bounded blast conformance experiment

Phase 1 baseline inspection, 8 October 2026. **The required baseline is unavailable; the implementation proposal has not been prepared.** The prompt requires stopping at this gate, so the older handbook has not been substituted and no Unity code, scene or test changes have been made.

## Required and available revisions

| Input | Required | Observed |
|---|---|---|
| Normative handbook | Handbook 1.5.0 / Architecture v0.13 / DEC-066 | Published `gh-pages` commit `65cd6086626d916f99b9389c589fecf9356bf67d`: Handbook 1.4.0 / Architecture v0.12 / DEC-061 |
| Embedded `sourceHash` | `ef1d9430e490e7b4757e38f57daf12b1dfe19ff3cd2272610aea3147f9e93a0c` | `d7be7510fbf6a77b230a12c1ae78a61e781f802bbe9d815da90f1fcb096ce32a` |
| Experiment base | `3f652e9178a78777bd41514441229827f7e611ad` | Present locally and on `origin/feature/handbook-conformance-probe`; exact match |

The published [root README](https://github.com/jblick1327/Bomb/blob/65cd6086626d916f99b9389c589fecf9356bf67d/README.md), `handbook/README.md`, `handbook/handbook.json` and JSON embedded in that revision's root `index.html` agree on the older checkpoint. The embedded hash differs from the expected hash. This is a baseline mismatch, not an inference from the older Unity branch.

The local `origin/gh-pages` reference was initially `d9ac305f198162e5c20aabebd9c5fe7344f598d4`. `git ls-remote` identified the newer published revision, and `git fetch --no-tags origin gh-pages` made it available for immutable inspection without checking it out. No handbook source or generated page was edited, built or published.

## Local checkpoint search

No matching 1.5.0 checkpoint was found among the BOM handbook candidates in Downloads, Desktop and the existing course handoff directory:

| Candidate | Embedded version / baseline |
|---|---|
| Downloads `BOM-Team-Handbook.html` and `BOM-Team-Handbook (1).html` | 1.0 / v0.10 / DEC-051 |
| Downloads `BOM-Team-Handbook (2).html` | 1.3 / v0.10 / DEC-051 |
| Downloads `index (1).html` through `index (5).html` | 1.3.2 / v0.11 / DEC-056 |
| Downloads `BOM-Team-Handbook-Source.zip` | 1.0 / v0.10 / DEC-051 |
| Downloads `BOM-Checkpoint-2026-10-06.zip` | 1.3.1 / v0.10 / DEC-051 |
| Extracted `BOM-Codex-CLI-Checkpoint-2026-10-06` handbook data | 1.3.1 / v0.10 / DEC-051 |

The filename search reported one inaccessible temporary directory inside an unrelated Downloads project. This search does not establish that no other copy exists anywhere on the machine. An exact path to a supplied matching checkpoint would resolve that uncertainty.

James subsequently supplied `C:\Users\jblic\Downloads\index (4).html`. Its embedded JSON contains Handbook **1.3.2**, Architecture **v0.11**, **DEC-056**, with `sourceHash` **`cb8bb50d80e432c6815b5239c367946e3f3fda17c811300f0cc2a0244b2fdbcd`**. Its whole-file SHA-256 is `fcfeddd1153e879d21cdc1d9ffa59292049edf0996fbd71405e7bfc207486f00`. The supplied copy therefore fails the required checkpoint identity check. The adjacent numbered HTML copies also contain that older baseline. A fresh remote-head check still found `gh-pages` at `65cd6086626d916f99b9389c589fecf9356bf67d`. The prerequisite remains unmet; no source review or computational proposal proceeded against these older copies.

The next supplied file, `C:\Users\jblic\Downloads\blast-conformance.md`, is the experiment prompt itself. It repeats the required 1.5.0 / v0.13 / DEC-066 checkpoint and expected hash, but contains neither that checkpoint's embedded JSON nor its complete six source documents. Its whole-file SHA-256 is `8f1918539e123179e7dabc10ead2bcb5e8a43660d9c82da98e2ddc422e1cbc5f`. The newly arrived `index (5).html` is byte-identical to `index (4).html`. Neither resolves the prerequisite, and the published branch remained unchanged on another remote-head check.

## Preserved state and inspection limits

Both existing working trees were clean before the report checkout was created. The original assignment checkout remains on `feature/canonical-destruction-commit` at `5960ed4e16efc5e3bf21489fb38b6ce429229c04`. The existing conformance checkout remains on `feature/handbook-conformance-probe` at the exact experiment base above.

Only this report and its dated inspection evidence are added on `feature/blast-conformance-plan`, in `.worktrees/blast-conformance-plan`, based directly on the requested experiment commit. James's opening instruction to push the work and report authorizes publishing this report branch. The implementation approval gate remains in force; there is no implementation branch, merge or Phase 2 change in this pass.

No applicable `AGENTS.md` was found in the checked repository ancestors or either inspected project tree. The available Unity CLI and 2D physics skill instructions, including the legacy physics reference, were read. The installed Unity CLI is `1.0.0-beta.10`; the existing Editor is `6000.2.14f1`, connected to `.worktrees/handbook-conformance`. Read-only inspection found Play stopped, compilation idle and successful, zero current console errors and one current warning. Historical integration buffer counters are separate from current console counts. The active scene is recorded in the evidence. No Editor was opened for the report checkout, and no packages, project settings or tooling were upgraded.

No Unity tests were rerun. No new blast measurements exist. The earlier 50 EditMode / 12 PlayMode result supplied in the task is historical evidence against v0.11 / DEC-056; it does not prove the requested shielding rules. The previous reports, tests and evidence are preserved.

## Work waiting on the required checkpoint

Publish the prepared Handbook 1.5.0 checkpoint to `gh-pages`, or supply its root `index.html` and complete source package at an accessible local path. Its embedded JSON must match the expected version, Architecture v0.13, DEC-066 and `sourceHash` above before proposal work continues.

After that verification, Phase 1 will read the complete six source documents in the specified order, inspect the actual definitions, host, geometry evaluator, planner, codec, runtime adapter and tests, and propose the bounded propagation method, numerical bounds, recovery treatment, file ownership and independent evidence cases. Computational choices and gameplay ambiguities remain unresolved here. No method, material defaults, historical migration, dependency change or new gameplay policy is approved by this report.

James must explicitly approve that completed proposal before Phase 2 changes Unity code, scenes or tests. Any later implementation must use a separately verified isolated worktree and new branch based on `3f652e9178a78777bd41514441229827f7e611ad`, preserving the existing checkouts and handbook.

Inspection evidence and exact commands: [2026-10-08 Phase 1 baseline evidence](BlastConformanceEvidence/2026-10-08-phase1-baseline/README.md).
