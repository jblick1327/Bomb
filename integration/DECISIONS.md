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

- M5: bump game protocol to 4/build BOM-scheduled-input-2026-11-06 for scheduled commands, exact owner state, reliable request envelopes/results and u64 event IDs. Keep canonical 2 and transport BOM1 unchanged. Legacy latest-value input remains only in non-application diagnostic fixtures; real authorized sessions use the scheduled path.
- M5: both native and ABI physics fixtures run serially because Box2D world creation and ABI ownership are process-scoped. The fast suite now includes these tests.
- M5: preserve fixed elapsed time in the reference frontend instead of dropping fractional time, and send a disconnect before destroying its client. Full world-report coverage caught both issues; no missing reports are accepted as matching.

- M5 complete: native prediction and conservative fallback live in the shared package. ABI 1.2 adds owner/prediction/result/intent controls without changing existing strides. Visual correction only offsets actor children.
- Profile frame timing uses high-resolution waitable timers and measured cadence, with no fake catchup frames and no relaxed response bounds. Preserve the initial failing profiles.
- A locally queued blast retains its original age; expired/focus/epoch/stall-cleared intent has an ordered local terminal result. Request-result flag 4 means local terminal; status 9 means cleared.
- Freeze a separate demo server path before M6 changes the development wire format.


- M8: protocol 6 and additive ABI 1.4 carry native spectator/resume admission,
  persistent round/results snapshots and acquired-sample roster getters. Existing
  ABI strides and canonical topology 3 are unchanged. Native session credentials
  remain private to the library; reconnect never resurrects a participant.
- M8: reserve the first two eligible connected players while loading; only their
  readiness starts the 180-tick countdown. A regression caught late-player promotion
  while an earlier participant was still loading. Extra connections stay spectators.
- M8: real-network sandbox blasts are host-only diagnostics. Sandbox movement,
  respawn and bomb physics remain unchanged. All same-tick deaths are collected
  before native winner selection; XP/wins are awarded once per round/session.
- M8: scale only the derived Claymate visual to the native capsule height. Copy
  the original bomb/fuse appearance at the native bomb radius. Invoke the preserved
  presentation-only BombBlastVisual through an unscaled-time adapter and preserve
  it for IL2CPP; no BombDropper, legacy movement or collider is enabled. The original
  asset inventory contains zero audio clips, so no replacement sound was invented.
- M8 draw fixture: one fixed indestructible floor; player spawn x=-0.8/+0.8,
  y=0.565; bomb range -0.05..0.05 at height 4. These fixture coordinates guarantee
  that ordinary native falling bombs test both capsules. Native interval, fuse,
  body, damage and lethal settings are unchanged. See fixtures/round-draw.
- M8 capture: hidden Windows backbuffers were black. Capture actual URP camera
  and UI Toolkit targets instead, retain both raw targets and their composite,
  clear the UI target each frame, and reject black/blank captures. Failed attempts
  remain evidence. Round/presentation tests disable prediction; M9 still owns
  dynamic prediction/performance, current IL2CPP and the final soak.
