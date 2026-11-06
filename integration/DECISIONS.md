# Integration decisions

- Use the November 5 live Bomb checkout, not the older BOM/BOM-main Unity projects.
- Retain two source roots. Extract the supplied BOM.zip into the task workspace; do not replace either older Unity repository with Odin files. The local ignored configuration identifies the extracted Odin root.
- Preserve archive working-tree changes. Its Git HEAD alone does not describe the supplied source.
- Original Unity deletions predate integration and remain untouched. Baseline manifests describe actual starting bytes.
- The official Unity Hub CLI discovered and reached the existing Pipeline 0.7.0-exp.1 service. No connector package upgrade was needed. Batch Editor and standalone verification complement this connection.
- Installed the matching 6000.2.14f1 Windows IL2CPP module and the registered Windows SDK through the existing installers. Both Mono and IL2CPP real players pass; no Editor/package version upgrade.

- Content acceptance freezes the original Unity assets/packages/settings. The Odin manifest is provenance for semantic comparisons: native code must change during extraction, so a byte freeze on all native sources would contradict M2.
- The official May compiler reports exactly dev-2026-05-nightly:ea5175d. A portable Microsoft SDK x64 package supplies missing libraries, with MSVC and -ignore-vs-search configured locally; no global toolchain upgrade.

- M2: keep one initially broad headless shared package and explicit frontend migration aliases. This avoids duplicate codec/simulation implementations while allowing the original tools/tests to retain their names. Graphics caches, bots and visual aging live outside the core.
- M2: preserve the legacy empty Edit -> loaded Edit -> Test server-construction sequence, including epochs. Pure layout/world builders serve both frontends. Instrumentation globals move with the simulation rather than dropping existing tests/profiling hooks.
- M3: the elapsed-time/presentation change follows the mechanical M2 checkpoint. Keep validated received topology in a separate data replica; expose only due topology for rendering. Bound the presentation clock between applied topology and received pose data, and preserve monotonic progress during delay changes. The existing clock fixture retains both +/-5% rate checks; its injected beyond-newest state now checks clamping rather than extrapolating past all received poses.
- M3: complete full-state topology transactions retain their native transaction ID until acknowledgement. Full state can coalesce due revisions while reporting the accepted from/to revision and effective tick. Catalog, prediction and round fields explicitly report unavailable/disabled until their later milestones.
- M3: decoder validation rejects nonfinite geometry, invalid IDs/references, oversized structures and incomplete baselines before unsafe graph access. A new truncation fixture found and fixed the old empty-baseline acceptance bug. These are boundary-validation changes, not changes to strengths, recipes or physics.

- M4: additive ABI 1.1 exposes authoritative actor dimensions through a read-only query. It corrects fallback capsule/bomb meshes without changing shared simulation, client timing, protocol 3 or canonical format 2. Generated layouts, native focused tests and both Unity scripting backends passed.
- M5: pin timestamp estimation, acknowledged schedule resets, integer command slots, terminal requests and owner replay before changing the wire; see contracts/scheduled-input-v4.md. That note is a contract, not evidence that prediction is implemented.
