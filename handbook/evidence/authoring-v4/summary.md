# Authoring v4 verification

The reviewed from-scratch packet is `BOM-Spec-Review-2026-10-12-v4.zip`, SHA-256 `e810fedab0ca36abab5cc443cc28db49fbd3e5c98f2766f0b63b5e8021e0ff83`. Its test target is Handbook 1.7.0 / Architecture v0.15 plus the Unity authoring v1 specification. This 1.8.0 documentation checkpoint is not a fresh Unity run. The packet is separate from the earlier Bomb branch probes and does not claim a Unity/Odin wire implementation.

- Supplied Unity 6000.6.5f1 results: **56/56 EditMode and 12/12 PlayMode pass**, no failed/skipped/inconclusive cases. Eight focused interaction/lifecycle regressions also pass, with preserved fail-first evidence.
- Independent documentation review checked current source, assertions, result counts and all **281 payload hashes**. Unity was not rerun in this documentation environment.
- The saved reference remains **6 bodies, 30 boundary vertices and 2 bonds**. A real connected blast captures **3 bodies, 136 vertices and 2 replacement bonds**; fresh reconstruction rebuilds four pins and resolves displaced anchors toward the unchanged intended fit.
- The final correction keeps all **47 runtime files** and the saved reference scene unchanged. Earlier bond-creation/overlap/allocator fixes and the canvas/numeric and failed-projection retention fixes remain covered.

The [dated evidence exports](https://github.com/jblick1327/Bomb/tree/gh-pages/handbook/evidence/authoring-v4) retain the reported verdicts and source-record hashes. The supplied current native console is clean; older pipeline errors are retained as history. File-picker paths are injected in automated tests; no manual-dialog or beginner-study claim is made. Timing samples are single warmed-Editor observations, not arena-scale budgets or bandwidth results.

Local conventions include an integer geometry grid of 100000 units/metre, float Unity/JSON vectors, local schema 1 with match/kind/sequence string IDs, content-hash definitions, affine appearance mapping and embedded PNG dependencies. The exchange candidate proposes different numeric/ID/definition records; compatibility is unproved. The sampled blast domain, exterior-only origins, reset scope, paired-length/load measurement, gameplay tuning and remaining game mechanics retain explicit limits.

**Authority correction:** Earlier authoring draft/review notes called the capacity formulas and percentage policy provisional. `CON-009`, `CON-010` and their ratification history already accept them: `Fmax = S × L`, `Tmax = ½ × S × L²`, with optional authored percentage failure. Only measurement, realization, encoding, defaults and actual values remain open. `DEC-077` records this status correction without changing the original decisions.
