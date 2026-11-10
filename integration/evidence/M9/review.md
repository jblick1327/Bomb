# M9 hardening review (in progress)

This is a separate audit against the ownership, lifecycle, authority and performance
contracts. Findings are verified with focused regression tests and then the real
process gates; a passing earlier milestone does not close M9.

- Reused connection/epoch pairs could make an old cancellation-ignoring geometry
  task look current and suppress a replacement request. Reproduced before the fix.
  Coordinator generations now stamp queued/completed tickets; old completions and
  old workers cannot revive after reset. The replacement cache and buffer drainage
  test passes, including a previously dequeued completion.
- Native row copying used per-row PtrToStructure, which can box on Mono. A bounded
  unmanaged buffer copy replaces it. A 200-row/high-ID test preserves every field,
  rejects null/count errors and allocates zero bytes in 10,000 warmed copies.
  Mono/IL2CPP integration verification remains required.
- Stable presentation allocated an accept delegate, actor seen/gone collections,
  empty error arrays and a sorted source list every frame. Reuse those buffers and
  rebuild source ordering only for topology changes; measure the complete runtime
  path rather than inferring zero allocation from these edits.
- The optional test-gate worker closure retained its presenter. Capture a separate
  managed gate object instead, including disposal after all jobs drain. Workers
  retain copied geometry/value data and no longer capture Unity-owned presenter
  state through the test hook.
- Endpoint form initialization could precede command-line endpoint setup. Refresh
  the form after OnEnable so the displayed port matches the actual connection.
- Tighten the original blast-animation adapter to the audited assembly as well as
  its class name. The original source remains protected and the adapter owns no
  gameplay decision.

Still to inspect/measure: recursive runtime/inactive/prefab authority checks; native
decoder/ABI edge cases; reset/host-result timing; spectator input churn; reference
loads and expensive source read/uploads; pose/update GC; pooling/eviction and ten
equivalent reset cycles; current Mono/IL2CPP; transport profiles and final soak.

Fixture sizing preflight: the first unmeasured 0.4 m wood boxes produced 1,435
reference cells because normal grain preprocessing subdivides them; that draft is
not the 500-cell reference measurement. A native-validated 0.125 m box preserves
400 separate moving bodies with 400 cells. The full-width fixed floor uses the
unchanged stone recipe (75 cells), giving 475 live cells initially. Stress uses
900 identical independent bodies plus the same floor. Visual and physics outlines
match; no material recipe, physics rule or render-quality setting was changed.
The original 4,615-cell yard remains a separate large case.

Further verified findings:
- Background-reset tests and direct ABI fixtures replaced the whole Odin context,
  which also replaced the test logger. Preserve only the required allocator now.
  The held-worker reset test genuinely failed three assertions before the fix;
  78 shared and 20 ABI tests now pass with their test logger retained.
- Async host reset/mode requests remain pending until the new world is published.
  The terminal result uses the publication tick, handles failure, and checks peer
  incarnation before completing a result. Duplicate and reused-ID tests pass.
- Server timing, frame size/build, per-entity staleness samples and the raw Odin
  client's delay history now have 65,536-sample limits. In particular, staleness
  appended once per entity per frame, so it could dominate a long stress run.
  Totals remain cumulative; diagnostic distributions are bounded recent samples.
- Final native-handle destruction checks both Odin-owned bytes and the DLL's
  process-wide Box2D allocation baseline. A deliberately injected unowned world
  fails teardown; cleanup and a subsequent clean handle pass. Real dedicated
  server metrics also emit a separate Box2D-before/after teardown report.
- The .NET allocation API returns zero on this Unity Mono runtime even for an
  escaped 4 KiB allocation. Early uniform-zero readings are invalid GC evidence.
  A current-thread GC.Alloc event recorder is validated by an escaped allocation;
  Unity's separate GC Allocated In Frame counter records frame allocation bytes.
- Hidden-player screenshots were black and GPU samples absent. Render profiling
  uses actual standalone windows shown without activation. The 1080p frame capture
  is now nonblack and GPU samples are populated; older hidden runs remain raw
  preliminary measurements, not rendered performance acceptance.
- Presentation actor pools retain at most 32 idle views per prefab and reject
  duplicate leases/returns; animation history resets on every reuse. Sparse source
  mesh material slots are being compacted without dropping used slots or geometry.

Preliminary measurements (not final M9 acceptance): reference 475 cells / 400
moving bodies; server p95 4.93 ms, no overruns; native update p95 <= 0.38 ms and
p99 <= 0.60 ms. Warm measured source upload <= 0.104 ms. Stress 975 cells reached
897 moving bodies in source mode and 899 in extrusion. Source mode had 16 server
overruns under combined rendering/geometry load; extrusion had zero. Keep this
failure visible while optimizing and remeasure after material compaction.


Final review follow-ups:
- The first mixed-client preflight exited cleanly but failed its held-work proof:
  jobs started after the supervisor's chosen reset had already completed. The
  supervisor now waits for both blocked-worker markers, observes a later reset,
  and requires stale drops before releasing work. The corrected 120-second mixed
  preflight passes with 15 resets and no forced process stops.
- Captured benchmark frames exposed static authoring previews alongside native
  bodies. Both benchmark scenes now hide those previews, and the build audits
  that condition. Current captures show only native body visuals; original yard
  content is unaffected.
- Empty source submesh slots were compacted with explicit original-slot mappings.
  The editor checks sparse slots 3/24/26, identical vertices, complete triangle
  indices, high UV channels, mirrored tangents, caps and source pivots.
- Explicit numeric IPv4 server binding is implemented; non-loopback binds require
  host authorization. Parser rejection and real 127.0.0.2 UDP/observer tests pass.
  No second physical machine was available for a LAN test.
- Final native DLL, server and observer have matching optimized debug symbols.
  C/.NET layouts/lifecycles pass, as do 79 shared and 20 ABI unit tests. Original
  220 game and 27 transport tests pass. The six 600-second static prediction runs
  pass for seeds 42/137/2026 across 30/60/144 Hz and typical/adverse links. Their
  prediction code is unchanged by the later CLI-only bind addition; identities
  for both builds are retained rather than substituting one for the other.
- Final IL2CPP draw/menu/effect/reconnect gate and Mono original-yard round gate
  pass with all five processes exiting normally and matching authoritative hashes.
  The final 30-minute mixed Mono/IL2CPP soak passed: 183 resets, 511 accepted overlapping-blast ticks, all five exits 0, no forced stops, no stale applications and all tracked resources drained.

Final isolated reference: 475 cells / 400 moving bodies at 1080p. Native p95 0.3999/0.3860 ms and p99 0.6703/0.6597 ms. Both stable pose paths recorded zero allocation events. The 1.5 ms mesh scheduler uses split uploads; an indivisible warm upload reached 3.6018 ms, and cold initialization reached 11.9167 ms source read / 6.6861 ms upload. These measured overruns are retained under section 9.6, which explicitly permits indivisible Unity API costs. The performance observer exited 1 after host-left shutdown; both Unity clients, host and server exited 0. The independent mandatory soak exited entirely 0. Last-ten equivalent live-world cycles show bounded tracked memory; one reconnect transition is excluded with raw rows retained (memory-review.json).
