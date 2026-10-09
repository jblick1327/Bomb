# BOM — Simulation model source

Handbook **1.6.0**, dated **9 October 2026**. Model baseline: Architecture **v0.14** through **DEC-068**.

Root `index.html` is the page output. It embeds styles, diagrams, navigation, search and the complete six source documents and works offline.

## Edit and rebuild

Edit accepted requirements in `sources/BOM Architecture.md`, append scoped decisions/history in the Decision Log, narrow Open Questions and synchronize the candidate map, team summary and interview handoff. Reconcile `handbook.json` and source-derived reference text in `build.py`.

```sh
python3 handbook/build.py
cp handbook/dist/index.html index.html
```

The build writes identical HTML, readable Markdown and extracted JSON under ignored `dist/`. Commit source and root output together when requested.

## Current checkpoint

- Independent shared blast resistance, ordinary travel plus resistance × thickness, original cover cost, breach continuity and straight paths are accepted (`DEC-062` to `DEC-065`).
- The killing explosion preserves the new corpse shape/ID; later independent blasts use its current environment response (`DEC-066`).
- Indestructible cover fully blocks carving and exposure along its path (`DEC-067`).
- Stable body-ID explosion order and explicit-resistance recovery are accepted for the bounded probe; its schema 3, numerical method/caps and fixture values remain experiment conventions (`DEC-068`).

`BOM-Team-Model-Handoff.md` owns the blast handoff example and reviewed evidence sections reused by the walkthrough/reference pages. The probe at `24e79ff` records 83/83 EditMode and 15/15 PlayMode passes against the supplied 1.5.0 target plus reviewed conventions. The 0.777 mm measured deficit is bounded evidence; layered computation cost, the original opaque-support rejection, unsupported inputs and older hold stretch remain explicit limits. Current 1.6 source changes were not separately run in Unity.

The approved presentation assets, stable routes and ten existing work deliveries/dependencies/order are preserved. The new routes are `#walkthrough/explosion`, `#reference/blast` and `#reference/blast-evidence`. Rules/search omit repeated Accepted labels while source metadata/history remain. Earlier Start work/milestone/staffing and authoring-organization recommendations are still unratified.

## Verification

Rebuild and check rule/source hashes, decision history, internal routes, all affected cards and previous/next navigation together. The evidence page must distinguish normative rules, experiment conventions, successful geometry and expected rejection tests. Preserve valid complete recoverable outcomes without retired-parent dependencies. This documentation checkpoint changes no Unity branch, packages, solver or project settings.
