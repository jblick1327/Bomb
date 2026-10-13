# BOM — Simulation model source

Handbook **1.8.0**, dated **13 October 2026**. Model baseline: Architecture **v0.16** through **DEC-077**.

Root `index.html` is the page output. It embeds styles, diagrams, navigation, search and the complete six source documents and works offline.

## Edit and rebuild

Edit accepted requirements in `sources/BOM Architecture.md`, append scoped decisions/history in the Decision Log, narrow Open Questions and synchronize the candidate map, team summary and interview handoff. Reconcile `handbook.json` and source-derived reference text in `build.py`.

```sh
python3 handbook/build.py
cp handbook/dist/index.html index.html
```

The build writes identical HTML, readable Markdown and extracted JSON under ignored `dist/`. Commit source and root output together when requested.

## Previous checkpoint

- Host-produced gameplay geometry and resulting entity/relationship state are the replication baseline (`NET-002`, `DEC-069`). Encoding, compression, delivery, correction and recovery remain implementation choices under narrowed `OQ-GEO-002`.
- The seven decision-audit findings are reconciled: blast scope, canonical committed shapes, work proposals, candidate asset organization, networking timing and Decision Log section hierarchy now agree. All 68 prior decision bodies are unchanged.
- Independent shared blast resistance, ordinary travel plus resistance × thickness, original cover cost, breach continuity and straight paths are accepted (`DEC-062` to `DEC-065`).
- The killing explosion preserves the new corpse shape/ID; later independent blasts use its current environment response (`DEC-066`).
- Indestructible cover fully blocks carving and exposure along its path (`DEC-067`).
- Stable body-ID explosion order and explicit-resistance recovery are accepted for the bounded probe; its schema 3, numerical method/caps and fixture values remain experiment conventions (`DEC-068`).

`BOM-Team-Model-Handoff.md` owns the blast handoff example and reviewed evidence sections reused by the walkthrough/reference pages. The candidate map owns the definition-organization qualifier reused by the definitions reference. The probe at `24e79ff` records 83/83 EditMode and 15/15 PlayMode passes against the supplied 1.5.0 target plus reviewed conventions. The 0.777 mm measured deficit is bounded evidence; layered computation cost, the original opaque-support rejection, unsupported inputs and older hold stretch remain explicit limits. The 1.6 and 1.7 documentation changes were not separately run in Unity.

The approved layout/diagrams, stable routes and ten existing work deliveries/dependencies/order are preserved. Work navigation and pages now identify proposals explicitly; no shared milestone or staffing is ratified. Routes `#walkthrough/explosion`, `#reference/blast` and `#reference/blast-evidence` remain. Rules/search omit repeated Accepted labels while source metadata/history remain. Required authoring inputs stay authoritative; the exact asset organization remains a candidate.

## Verification

Rebuild and check rule/source hashes, decision history, internal routes, all affected cards and previous/next navigation together. The evidence page must distinguish normative rules, experiment conventions, successful geometry and expected rejection tests. Preserve valid complete recoverable outcomes without retired-parent dependencies. This documentation checkpoint changes no Unity branch, packages, solver or project settings.

## Authoring and snapshot checkpoint — 1.8.0

Architecture is the requirements authority. ASSET-001–009 and CON-015 now record the accepted Unity authoring v1 workflow; NET-003–005 record initial full snapshots, host-supplied dependencies and newer complete match-scoped captures. All earlier decision bodies are preserved; DEC-070–077 publish the new checkpoint and correct the earlier authoring notes' provisional label for already-accepted connector formulas/percentage policy.

The six sources and reader pages are synchronized. Reference pages now cover Unity authoring, snapshot application and scoped v4 evidence. The first-use guide is under `handbook/guides/`, archived candidate schema/examples under `handbook/drafts/exchange-v0.1/`, and dated result exports under `handbook/evidence/authoring-v4/`. The exchange proposal remains a candidate; the local schema is not claimed compatible.

V4 records 56 EditMode / 12 PlayMode passes supplied from Unity 6000.6.5f1, with all 281 payload hashes checked independently. No Unity rerun or complete-game/network conformance is claimed. Local runtime files/reference scene are unchanged by the final authoring fixes. The older bounded blast probe and its limits remain separate evidence. This documentation change edits no Unity branch, package, solver or gameplay scene.

Build with `python3 handbook/build.py`, copy the generated `handbook/dist/index.html` to root, and commit the sources and root page together. Preserve stable routes/layout and the ten proposed role deliveries; this checkpoint selects no new shared game milestone or staff assignment.
