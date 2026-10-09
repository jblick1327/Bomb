# BOM team handbook

This `gh-pages` branch publishes the team handbook through root `index.html`. The Unity gameplay project is maintained on separate branches.

Handbook **1.6.0**, dated **9 October 2026**, uses Architecture **v0.14** and decisions through **DEC-068**. The standalone HTML also works offline and embeds all six complete model sources.

## Source and build

The editable application and its six model documents are in `handbook/`. Architecture controls current requirements; the Decision Log preserves rationale/scope/supersession; Open Questions records remaining choices. The map, team summary and interview handoff explain the model without overriding it.

Rebuild from the repository root:

```sh
python3 handbook/build.py
cp handbook/dist/index.html index.html
```

Commit source changes and root `index.html` together when requested. Preserve stable routes, the approved layout and prominent walkthrough navigation. No package installation or local server is needed.

## Blast checkpoint

`DEC-062` through `DEC-066` carry forward independently authored shared blast resistance, ordinary distance plus extra resistance × thickness, breach-before-buried-removal, straight outward paths and the uncarved killing-explosion corpse. `DEC-067` adds complete blocking by indestructible cover. `DEC-068` records stable body-ID ordering and explicit-resistance recovery **within the bounded experiment**; it does not choose the whole game's schedule or codec.

The walkthrough now includes an explosion step between countdown and split. Reference routes `#reference/blast` and `#reference/blast-evidence` connect the accepted contract to complete identities/relationships/commit/recovery, reviewed evidence and remaining implementation limits. Values in the numerical example are illustrative, not tuning defaults.

The [bounded blast probe](https://github.com/jblick1327/Bomb/blob/24e79ff0533eabf51627859b097f3503af5f54a1/Docs/BlastConformance.md) records **83/83 EditMode** and **15/15 PlayMode** passes, including all earlier regressions, with a maximum independently measured radial deficit of **0.777 mm** within its 1 mm bound. Its immutable target was supplied Handbook **1.5.0 / v0.13 / DEC-066**, plus reviewed experiment conventions; this 1.6 documentation checkpoint is not a new Unity run.

Layered host medians around **0.64–1.23 s**, and **3.05 s** for a recovered second rotated blast, remain a performance limit. The original **0.4 m-wide opaque-support** corner still rejects the whole explosion; the positive live-layered proof uses **0.1 m-wide support**. The old case remains an expected rejection test, not a repaired/supported detonation. Unsupported geometry and the older extreme-force hold stretch remain visible in the team handoff.

The architecture contains no provisional rules. Reader-facing rules/search omit the repeated Accepted label; source status metadata and all previously published decision history remain. This checkpoint changes no Unity code or prototype branch. Production numerical geometry/performance, authoring values/encoding, exact character boundary lethality and general scheduling retain their open scope. The ten work deliveries, dependencies and order are preserved; no staffing or first milestone is ratified.
