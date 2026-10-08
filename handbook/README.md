# BOM — Simulation model source

Handbook 1.4.0, dated 8 October 2026. Model baseline: Architecture v0.12 through DEC-061.

The published page is the repository's root `index.html`. It contains all styles, diagrams, navigation, search, and six complete source documents. It can also be opened locally without a server or internet connection.

## Edit and rebuild

Edit model decisions in `sources/BOM Architecture.md`, preserve rationale and supersession in the Decision Log, and narrow the Open Questions. Reconcile the candidate map, team summary, interview handoff, `handbook.json`, and generated reference text in `build.py`.

From the repository root:

```sh
python3 handbook/build.py
cp handbook/dist/index.html index.html
```

The build also writes an identical standalone HTML copy, readable Markdown, and extracted JSON under `handbook/dist/`. Only root `index.html` is the published output. Build artifacts in `dist/` are ignored.

## Current checkpoint

- Local-frame poses and current centre-of-mass velocity have explicit meanings. Motion-preserving geometry/frame changes preserve surviving material movement, including same-ID results.
- Density × current gameplay area supplies mass for environment pieces, living characters and live bombs.
- Connector capacities are `Fmax = S × L` and `Tmax = ½ × S × L²`, from one authored strength per length and current surviving attachment length.
- The first valid landing starts a continuous fuse. Handling, support loss and later landings preserve progress; expiry detonates at the current position.
- Material and thickness consume effective blast reach, including cover destroyed by that same blast.

DEC-057 through DEC-061 record these choices. Historical decisions and their supersession trail remain intact; the current architecture contains no provisional rules. Remaining numerical values, geometry contracts, COM/inertia derivation, attachment-length/load measurement, landing detection, blast-resistance inputs/calculation, encoding, controls and tuning retain their actual scope.

The reviewed conformance probe at `3f652e9` records 50 EditMode and 12 PlayMode tests passing against the earlier Architecture v0.11 / DEC-056 baseline. It informed the first four decisions. Its radius-only blast model does not exercise the new shielding rule; extreme-load hold reach remains a documented limit. The Unity code and evidence are unchanged by this handbook checkpoint.

The approved layout, walkthrough navigation, stable reference routes, and ten work deliveries are preserved. Earlier recommendations about the first shared milestone, candidate authoring organization, networking-start wording, and destruction expansion were not accepted by this policy review.

Reader-facing accepted rules omit the repeated status label, including in search results. The embedded source documents and decision history retain their original metadata.

## Verification

Before committing, rebuild and check the changed rules, embedded sources, reference pages, and work cards together. Check internal routes and unchanged presentation assets. Model edits must leave the complete structural outcomes reconstructable without dangling references or retired-parent dependencies.
