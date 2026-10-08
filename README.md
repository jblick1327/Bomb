# BOM team handbook

This `gh-pages` branch publishes the team handbook through its root `index.html`. The Unity gameplay project is on `main`.

Handbook **1.4.0**, dated **8 October 2026**, uses Architecture **v0.12** and decisions through **DEC-061**. It remains a standalone HTML file that also works offline.

## Source and build

The editable application and its six model documents are in `handbook/`. Architecture controls current requirements; the Decision Log preserves rationale and supersession; Open Questions identifies remaining choices. The other documents explain the model without overriding it.

To rebuild from the repository root:

```sh
python3 handbook/build.py
cp handbook/dist/index.html index.html
```

Commit the changed source and root `index.html` together. Keep stable reference routes, the approved layout, and the prominent walkthrough navigation. No package installation or local server is needed.

## Decisions in this update

- Body pose locates its local frame; linear velocity describes its current centre of mass. Geometry/frame changes intended to preserve motion preserve surviving material movement, including same-ID results.
- Environment pieces, living characters and live bombs all derive mass from material density × current 2D gameplay area.
- For connector strength per length `S` and surviving length `L`, capacities are `Fmax = S × L` and `Tmax = ½ × S × L²`.
- The first valid landing starts a continuous fuse. Holding, throwing, support loss and later landings do not pause or reset it; expiry detonates at the current position.
- Material and thickness consume blast reach. Cover destroyed by that blast still contributes to its reach cost.

DEC-057 through DEC-061 record this checkpoint. Earlier accepted policies and their supersession trail remain in force. The current architecture contains no provisional rules. COM/inertia derivation, attachment-length measurement, landing detection, material-resistance inputs/calculation, authoring values and encoding remain explicitly open.

The conformance probe on `feature/handbook-conformance-probe` at `3f652e9` records 62 passing Unity tests against the earlier Architecture v0.11 / DEC-056 baseline. Its radius-only blasts do not demonstrate the new material-dependent reach rule; extreme-load hold reach remains a documented solver limitation. This checkpoint changes no Unity code.

Reader-facing rule pages and search results omit the repeated Accepted status label. The underlying model documents retain their statuses and decision history.

The first shared implementation milestone, work-plan cleanup and fuller destruction walkthrough remain pending. This update does not assign people or select those activities.
