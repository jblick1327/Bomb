# Engine evidence index

The engine's raw run records (captures, logs, test and perf runs) are not in this repository. They were left out of
every commit when the engine moved in from its own repo (`C:\Users\jblic\Documents\BOM`, branch `alpha-sync`, 49d1a6e)
on 2026-11-19, the same rule as `integration/evidence`.

- Archive on the owner's machine: `C:\Users\jblic\Documents\BOM-Release\evidence-archive-20261119\engine-evidence`
  (5,373 files, 609 MB). Seven older zips that the engine repo had already deleted are in `engine-evidence-deleted-earlier`.
- The old engine repo still has the full history with evidence committed.
- `INDEX-files.tsv` lists every archived file (path relative to `Engine/evidence/`, bytes, sha256). Paths in
  `Engine/AGENTS.md` and the engine READMEs that start with `evidence/` refer to these files.

New runs still write here; `Engine/.gitignore` keeps them out of the repository.
