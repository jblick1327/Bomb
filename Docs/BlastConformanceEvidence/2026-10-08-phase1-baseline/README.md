# Phase 1 baseline inspection evidence

8 October 2026. This directory records a failed prerequisite check, not a blast implementation or test run. The required Handbook 1.5.0 / Architecture v0.13 / DEC-066 checkpoint was unavailable in the published branch and inspected local handbook candidates.

`baseline-inspection.json` records the initial expected and observed versions, embedded hashes, exact Git revisions, local candidate results and inspection scope. `supplied-checkpoint-inspection.json` records the subsequent supplied `Downloads/index (4).html` identity check, the nearby numbered copies and the supplied `blast-conformance.md` instruction file. `editor-status.json` and `console-status.json` preserve the initial successful read-only Unity command envelopes. `scene-status.json` records that inspection's read-only evaluation of the active scene path. All JSON is UTF-8 with LF newlines. `SHA256SUMS.txt` covers those five JSON files. The initial four captures are unchanged.

Reproduce the published baseline check from the repository:

```powershell
git ls-remote --heads origin gh-pages feature/handbook-conformance-probe
git fetch --no-tags origin gh-pages
git show 65cd6086626d916f99b9389c589fecf9356bf67d:README.md
git show 65cd6086626d916f99b9389c589fecf9356bf67d:handbook/README.md
git show 65cd6086626d916f99b9389c589fecf9356bf67d:handbook/handbook.json
$page = (git show 65cd6086626d916f99b9389c589fecf9356bf67d:index.html) -join "`n"
$json = [regex]::Match($page, '<script[^>]*type="application/json"[^>]*>([\s\S]*?)</script>').Groups[1].Value
$data = $json | ConvertFrom-Json
$data | Select-Object version, baseline, sourceHash
```

Read-only Editor commands used the installed CLI and exact existing project path:

```powershell
$cli = 'C:\Users\jblic\AppData\Local\Unity\bin\unity.exe'
$project = 'C:\Users\jblic\Desktop\Bomb\.worktrees\handbook-conformance'
& $cli --version
& $cli status --project-path $project --format json
& $cli command --caller plugin --skill unity-cli --project-path $project --format json
& $cli command editor_status --caller plugin --skill unity-cli --project-path $project --format json
& $cli command console_status --caller plugin --skill unity-cli --project-path $project --format json
& $cli command eval --caller plugin --skill unity-cli --project-path $project --format json -- --code 'return UnityEngine.SceneManagement.SceneManager.GetActiveScene().path;'
```

The directory/filename search used `rg --files` over Downloads, Desktop and Documents, excluding generated Unity state, Git metadata, package caches, worktrees and node_modules. Candidate HTML JSON was parsed in memory. ZIP archives were opened read-only with `System.IO.Compression.ZipFile.OpenRead`; no archive was extracted or changed. One unrelated temporary directory was inaccessible. Search results therefore have a stated scope rather than proving global absence.

The supplied checkpoint was read directly from `C:\Users\jblic\Downloads\index (4).html` using `Get-Content -Raw -Encoding UTF8`. Its JSON was extracted with the same script-tag expression above and parsed with `ConvertFrom-Json`; its file identity was measured with `Get-FileHash -Algorithm SHA256`. Embedded Markdown SHA-256 values were checked against their UTF-8 content. Nearby filenames were discovered with `rg --files 'C:\Users\jblic\Downloads' --maxdepth 1 -g 'index*.html'`. A fresh `git ls-remote --heads origin gh-pages feature/handbook-conformance-probe feature/blast-conformance-plan` confirmed the published handbook had not advanced. No Unity command or test was rerun for this additional file check.

`C:\Users\jblic\Downloads\blast-conformance.md` was then read completely with `Get-Content -Raw -Encoding UTF8` and hashed with `Get-FileHash -Algorithm SHA256`. It is the bounded experiment prompt, with the same required baseline and stop condition, rather than the normative handbook package. The newly arrived `index (5).html` was parsed and hashed by the same method; it matches the older supplied HTML byte for byte. Another `git ls-remote --heads origin gh-pages` still returned `65cd6086626d916f99b9389c589fecf9356bf67d`.

No applicable repository/ancestor `AGENTS.md` was found. Integration instructions read:

- `C:\Users\jblic\.codex\plugins\cache\unity-agent-plugin\unity\0.1.8-beta\skills\unity-cli\SKILL.md`
- `C:\Users\jblic\.codex\plugins\cache\unity-agent-plugin\unity\0.1.8-beta\skills\create-2d-physics\SKILL.md`
- `C:\Users\jblic\.codex\plugins\cache\unity-agent-plugin\unity\0.1.8-beta\skills\create-2d-physics\references\legacy-2d-physics.md`

No tests were run, no prior result was reclassified as current shielding evidence, and no Unity source, scene, test, dependency, project setting or handbook content changed. The report is published separately on `feature/blast-conformance-plan`; Phase 2 remains unapproved.
