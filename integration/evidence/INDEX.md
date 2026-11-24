# Evidence index

The raw run records for this branch (captures, logs, gate results, soak and perf runs) are not in the repository.
They were removed from the history of this PR branch to keep it small (5.1 GB on disk).

- Archive: `C:\Users\jblic\Documents\BOM-Release\evidence-archive-20261119` on the owner's machine (18,530 files;
  its `engine-evidence` folders belong to `Engine/evidence/INDEX.md`).
- Full history with the evidence still committed: local branch `integration/odin-unity-20261105` at 90ae1e61.
- `NPT` (native pump thread, prediction fixes, seam fix, settled-debris freeze; 2026-11-21 to 11-24) was added later from
  local branch `native-pump-thread` at 401f9ec2, where it is still committed.
- Every file is listed in `INDEX-files.tsv` (path, bytes, sha256, and whether it was committed `git` or only on disk `local`).
  Paths are relative to `integration/evidence/`, which is where `integration/ALPHA-SYNC.md` and the READMEs point.
- Kept in the repository as test inputs: `M6/yard-export/yard.json`, `M7/yard-export/yard.json` and
  `M7/source-export/fixtures.json` (read by the older `Test-UnityYard.ps1` and `Test-SourcePresentation.ps1`).

New runs still write here; `.gitignore` keeps them out of the repository.

| folder | files | size |
|---|---|---|
| `E1-G` | 170 | 117.4 MB |
| `E1-GN10` | 203 | 118.4 MB |
| `E1-GN11` | 18 | 0.0 MB |
| `E1-GN6` | 238 | 153.0 MB |
| `E1-GN9` | 198 | 121.2 MB |
| `F2` | 83 | 7.3 MB |
| `G1` | 136 | 85.1 MB |
| `G2` | 759 | 450.8 MB |
| `G2b` | 305 | 188.5 MB |
| `G3` | 306 | 210.3 MB |
| `G5` | 350 | 84.3 MB |
| `G5b` | 47 | 2.3 MB |
| `G6` | 67 | 40.4 MB |
| `G6b` | 8 | 0.4 MB |
| `G7G8` | 294 | 10.0 MB |
| `G8b` | 27 | 0.0 MB |
| `M0` | 253 | 4.3 MB |
| `M1` | 42 | 0.0 MB |
| `M2` | 126 | 13.0 MB |
| `M3` | 459 | 1.4 MB |
| `M4` | 236 | 6.7 MB |
| `M5` | 85 | 0.7 MB |
| `M6` | 246 | 8.1 MB |
| `M7` | 504 | 12.6 MB |
| `M8` | 12200 | 3090.4 MB |
| `M9` | 858 | 470.4 MB |
| `NPT` | 265 | 66.5 MB |
| `OD13` | 14 | 0.0 MB |
| `OD15` | 29 | 0.4 MB |
| `original-scenes` | 4 | 0.0 MB |
