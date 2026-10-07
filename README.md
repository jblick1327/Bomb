# BOM team handbook

This `gh-pages` branch publishes the team handbook through its root `index.html`. The Unity gameplay project is on `main`.

Handbook **1.3.2**, dated **7 October 2026**, uses Architecture **v0.11** and decisions through **DEC-056**. It remains a standalone HTML file that also works offline.

## Source and build

The editable application and its six model documents are in `handbook/`. Architecture controls current requirements; the Decision Log preserves rationale and supersession; Open Questions identifies remaining choices. The other documents explain the model without overriding it.

To rebuild from the repository root:

```sh
python3 handbook/build.py
cp handbook/dist/index.html index.html
```

Commit the changed source and root `index.html` together. Keep stable reference routes, the approved layout, and the prominent walkthrough navigation. No package installation or local server is needed.

## Decisions in this update

- Connector strength scales with surviving attachment length.
- Authors may configure minimum-surviving-percentage failure independently of load. No universal cutoff is selected.
- Live bombs use ordinary hold eligibility and authoritative validation.
- Applied force alone does not release limb holds in the current build.
- One authored Boolean eligibility policy governs hand and deliberate foot holds. Ordinary foot contact is unaffected.

DEC-052 through DEC-056 record these decisions. Earlier tentative decisions have explicit supersession links. The current architecture contains no provisional rules; numerical values, formulas, field layout, and other implementation contracts retain their stated scope.

Reader-facing rule pages and search results omit the repeated Accepted status label. The underlying model documents retain their statuses and decision history.

The first shared implementation milestone and the destruction-content expansion remain separate pending decisions. This update does not assign people or change the Unity game.
