# BOM — Simulation model source

Handbook 1.3.2, dated 7 October 2026. Model baseline: Architecture v0.11 through DEC-056.

The published page is the repository's root `index.html`. It contains all styles, diagrams, navigation, search, and six complete source documents. It can also be opened locally without a server or internet connection.

## Edit and rebuild

Edit model decisions in `sources/BOM Architecture.md`, preserve rationale and supersession in the Decision Log, and narrow the Open Questions. Reconcile the candidate map, team summary, interview handoff, `handbook.json`, and generated reference text in `build.py`.

From the repository root:

```sh
python3 handbook/build.py
cp handbook/dist/index.html index.html
```

The build also writes an identical standalone HTML copy, readable Markdown, and extracted JSON under `handbook/dist/`. Only root `index.html` is the published output. Build artifacts in `dist/` are ignored.

## Current policy review

- Connector strength is authored per surviving attachment length.
- Authors may configure independent minimum-surviving-percentage failure; no universal cutoff is selected.
- Live bombs use ordinary authored hold eligibility and host validation.
- Applied force alone does not release limb holds in the current build.
- One authored Boolean governs hand and deliberate foot holds. Ordinary foot contact is unaffected.

DEC-052 through DEC-056 record these choices. Historical tentative decisions retain their supersession trail; the current architecture contains no provisional rules. Remaining numerical values, geometry contracts, encoding, controls, and tuning retain their actual scope.

The approved layout, walkthrough navigation, stable reference routes, and ten work deliveries are preserved. Earlier recommendations about the first shared milestone, candidate authoring organization, networking-start wording, and destruction expansion were not accepted by this policy review.

Reader-facing accepted rules omit the repeated status label, including in search results. The embedded source documents and decision history retain their original metadata.

## Verification

Before committing, rebuild and check the changed rules, embedded sources, reference pages, and work cards together. Check internal routes and unchanged presentation assets. Model edits must leave the complete structural outcomes reconstructable without dangling references or retired-parent dependencies.
