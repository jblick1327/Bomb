# Recursive destruction: native benchmark findings

Measured on 2026-10-30. The main finding is to reduce unnecessary refinement before changing the runtime layout. The new same-blast recursion is practical in these native kernels when completely erased outlines are removed directly. Plain records remain a reasonable starting layout.

## Recommended implementation

1. Initialize a piece's current subdivision graph when it is created. This is separate from precomputing possible future generations.
2. Process a blast as one staged transaction. Test subdivisions, generate eligible children, set their seed context at birth and enqueue them for the same blast. Test newly created links as well. Resolve ownership and membership at the end. Apply impulses once to final retained bodies.
3. Before generating from a failed outline, remove it directly when a conservative distance bound proves that every possible descendant will fail this blast.
4. Retain per-piece membership, shared materials and the byte seed. Broadcast piece/material context while processing a batch. Keep major work-buffer capacities between events.
5. Retain an outline's derived width when generation has already calculated it. Reuse shared-boundary information at connection birth; retain local sample offsets for existing connections. Building offsets only for survivors is an optional organization choice, with little consistent timing advantage here.
6. Keep the current simple record layout. Consider columns for a demonstrated full-world streaming loop, independently of generation and geometry storage.

## Main event timings

Values are pooled medians of 18 raw samples from two separate process runs, in microseconds per selected-piece blast transaction. Both columns implement recursive destruction by the same blast. The shortcut is checked only after a subdivision has failed its material test. Retained geometry, connection endpoints, memberships, fading counts and impulse counts agree across equivalent variants.

| Workload | Recursive reference µs | Proven deletion shortcut µs | Ratio | Generated children | Retained subdivisions |
| --- | --- | --- | --- | --- | --- |
| Chunk, partial hit | 274.640 | 29.780 | 9.22× | 316 → 34 | 13 |
| Splinter, partial hit | 61.864 | 44.080 | 1.40× | 50 → 35 | 25 |
| Shatter, partial hit | 2,182.666 | 279.597 | 7.81× | 1594 → 246 | 26 |
| Chunk, finer cutoff | 1,979.809 | 53.329 | 37.12× | 1611 → 62 | 12 |
| Whole piece erased | 1,991.674 | 2.086 | 954.93× | 1714 → 0 | 0 |
| Terminal seed 0 | 3.521 | 3.437 | 1.02× | 0 → 0 | 8 |
| One piece in 512, shuffled | 302.639 | 31.273 | 9.68× | 316 → 34 | 13 |
| One piece in 8,192, shuffled | 292.940 | 29.875 | 9.81× | 316 → 34 | 13 |

The complete-erasure case is a special fast path, not a representative game-frame speedup. Larger scene sizes are scaling stress controls. One selected piece is processed; the other pieces remain unchanged.

The shortcut works because load is `12 * max(0, radius - distance)` and descendants share the material strength. The farthest posed parent vertex bounds the distance of every point inside the parent's convex hull. If even that conservative farthest point exceeds the threshold, all descendant samples must fail. A rounding margin makes the test conservative. The generator must preserve the parent partition. This argument uses the current unoccluded blast field and does not predict new physics contacts.

## Layout comparison after the shortcut

All four event record representations carry the same 64 bytes of data per node: context-first AoS; pose-first AoS; 32-byte hot and 32-byte cold records; and hot columns with cold records. Shared immutable vertices remain in a separate pool. The small seed/depth/state and tree records used during recursion are temporary benchmark work, not proposed persistent subdivision components. Logical child identities are stable hashes of parent identity and ordinal, with 32-bit temporary row references. Skipping an erased branch must not shift other branches' seeds through a shared random stream or allocation-order IDs.

| Workload | Context-first AoS µs | Pose-first AoS µs | Hot/cold µs | Hot columns µs |
| --- | --- | --- | --- | --- |
| Chunk, partial hit | 29.780 | 31.982 | 32.321 | 32.024 |
| Splinter, partial hit | 44.080 | 44.670 | 46.209 | 46.008 |
| Shatter, partial hit | 279.597 | 289.262 | 301.786 | 309.981 |
| Chunk, finer cutoff | 53.329 | 52.289 | 56.225 | 57.554 |
| One piece in 8,192, shuffled | 29.875 | 30.195 | 33.016 | 34.212 |

There is no consistent win for changing the event layout. Identical duplicate controls ranged from 0.92× to 1.08× the reference time, so small single-digit differences should be treated as ties. Allocation state, process/run variation and this virtual CPU limit precision. These measurements do not isolate a hardware cause for small rankings.

## Work selection matters more

These query-only tests begin with a known candidate piece, as if supplied by a broadphase. They do not time spatial-index discovery. The owner scans traverse the whole source node pool once; member queries traverse the selected piece's retained list. The last two columns include the full optimized recursive transaction, demonstrating how an unnecessary scene scan becomes more visible after generation is reduced.

| Scene subdivisions | AoS owner query µs | Column owner query µs | AoS member query µs | Full event + global owner scan µs | Full event + members µs |
| --- | --- | --- | --- | --- | --- |
| 156 | 0.078 | 0.116 | 0.026 | 29.013 | 29.780 |
| 10236 | 6.846 | 6.566 | 0.025 | 38.731 | 31.273 |
| 163836 | 147.735 | 106.549 | 0.028 | 189.595 | 29.875 |

For full-world reads, the ranking changes. Member traversal visits every node once and broadcasts its piece material; owner traversal also scans the world once. The large inputs deliberately shuffle rows.

| Scene subdivisions | AoS world scan µs | AoS piece/member traversal µs | Hot-column member traversal µs |
| --- | --- | --- | --- |
| 156 | 0.438 | 0.284 | 0.272 |
| 10236 | 32.109 | 28.973 | 22.241 |
| 163836 | 2,765.160 | 2,525.293 | 1,063.959 |

This supports keeping separate choices for streaming access and structural updates. It does not support converting every component to one universal format.

## The shared child-seed check

The tested rule calculates child widths during generation, then makes one common decision: if the maximum child width is at or below the cutoff, assign zero to all children; otherwise derive nonzero child contexts from stable parent identity and ordinal. An individual outline-width guard remains before further refinement. Zero-seed geometry stays live until it actually fails.

The audit found **167 mixed-width sibling batches** and **1009 children below the cutoff that received the shared nonzero context**. None split further because the individual guard stopped them. A shared nonzero seed alone cannot replace exact individual eligibility for irregular geometry. An alternative rule making all siblings terminal when any one is small is possible, but changes fragmentation and was not counted as an equal-output optimization.

In the complete event, the shared-versus-repeated common predicate did not produce a reliable advantage beyond the duplicate-control variation. The seed-only control below writes packed byte outputs for 4,096 batches at a 50% terminal mix; it is not a recommendation for a separate permanent seed column. Values are nanoseconds per sibling batch. Nonzero child hashes are identical in both methods.

| Children per batch | One shared branch ns/batch | Repeated inline common check ns/batch |
| --- | --- | --- |
| 3 | 6.607 | 6.055 |
| 5 | 9.642 | 10.034 |
| 6 | 11.250 | 11.720 |
| 12 | 21.590 | 22.670 |
| 24 | 38.238 | 41.774 |

Keep the shared decision for clarity. The measurements do not justify extra state or dispatch machinery to optimize this comparison.

## Width, anchors and processing order

These values use the deletion shortcut. Width is rotation-independent geometric width. Discovery is FIFO by default; the depth-first variant changes refinement discovery while retaining canonical connection-update waves and one final grouping pass.

| Workload | Cached width µs | Recompute width µs | Offsets only for survivors µs | Depth-first discovery µs |
| --- | --- | --- | --- | --- |
| Chunk, partial hit | 29.780 | 34.189 | 29.658 | 28.591 |
| Splinter, partial hit | 44.080 | 49.305 | 41.412 | 42.177 |
| Shatter, partial hit | 279.597 | 288.353 | 284.280 | 281.231 |
| Chunk, finer cutoff | 53.329 | 62.987 | 52.238 | 52.872 |

Width retention helps some cases, especially once generation has already computed the value for the shared seed decision. In this 64-byte AoS record it uses space otherwise occupied by padding; other actual component layouts may differ. A local anchor pair is 16 bytes. Re-deriving shared boundaries at each query was slower in the separate reference variants, but whole-event gains were much smaller than the earlier anchor-only benchmark because generation and graph work are now included.

No robust discovery-order winner appeared. All generated geometry is retained in temporary event storage until the canonical graph pass, so this does not measure a fully streaming depth-first implementation that recycles dead subtrees. Persistent adjacency, row compaction, long-session tombstone accumulation and stable-ID map maintenance were not timed.

## Eager creation and future-generation caching

Your rule that current geometry exists immediately is the baseline. A separate creation control partitions the reference piece's convex hull using the prototype recipes, finds boundaries, calculates widths and assigns seeds. It excludes engine bodies/joints and the cost of finding that input hull.

| Pattern | Created subdivisions | Current-graph generation µs |
| --- | --- | --- |
| Chunk | 3 | 2.353 |
| Splinter | 5 | 4.336 |
| Shatter | 31 | 23.719 |

The shatter count exceeds its target because the supplied generation approach triangulates and then adds bent-boundary detail. The target count is not a hard output cap.

Precomputing an additional possible generation for every current subdivision is a different cache. It can reduce the measured blast latency, but pays construction and memory costs even for parents that never fail or can be removed directly. A failed parent consumes its cache once in the real program; repeated benchmark samples replay the initial state and must not be mistaken for real cache reuse across that parent's lifetime.

| Workload | Cache construction µs | On-demand blast µs | Cached blast µs | Build + cached blast µs | Cached parents used | Tracked cache KiB |
| --- | --- | --- | --- | --- | --- | --- |
| Chunk, partial hit | 34.933 | 29.780 | 24.664 | 59.598 | 2/12 | 9.2 |
| Splinter, partial hit | 85.483 | 44.080 | 33.846 | 119.329 | 2/24 | 21.2 |
| Shatter, partial hit | 558.996 | 279.597 | 187.689 | 746.685 | 4/24 | 80.5 |

Construction controls include their temporary-buffer allocation and cleanup. Summing build and blast medians is an indicative sequential-work comparison, not a separately measured combined frame. Cache bytes are tracked payload/capacity estimates and exclude unordered-map buckets and allocator overhead. The event storage metric similarly excludes some temporary and per-group allocations. Immutable templates shared across many identical objects could have different amortization; that was not measured. Start with eager current geometry and on-demand future refinement.

## What changed in the native generator

The input includes the original handoff's 12 bent chunk/splinter/shatter geometry snapshots with recorded Box2D poses, plus the uploaded Odin source used as the porting reference. Starting pieces contain 12 or 24 subdivisions. Future-generation recipe targets are 3, 5 and 6, matching the prototype presets; strengths are the fixture's shared values 40/55/30 for subdivisions and 28/35/16 for connections. These are test settings, not added model requirements. Blasts originate outside the structures. The default refinement/group-width cutoff is 0.18; the deeper control uses 0.09.

The C++ port fixes no-progress generation by returning direct removal, completes triangulation or fails validation, and uses double-precision outline coordinates with float motion/load records. During independent validation, the original area/length displacement cap in the port allowed child boundaries to cross. The final generator additionally limits displacement by clearance to the other edges of the two adjacent polygons. The final timings include that work. Independent audits verify child containment, non-crossing/non-overlapping partitions, area conservation and valid polygons, including deeper and complete-erasure scenarios. These findings are not proof of the cause of the screenshot in the newer Odin build.

## Processing breakdown and validation

The reference recursive event includes copied active records, initial connection queries, actual polygon generation and width/seed decisions, inherited and internal connections across canonical refinement waves, connection failure, grouping, retained membership output, size filtering and final impulse records. It uses ordinary C++ containers. These separate instrumented stage timings include clock overhead and should not be added to another row's uninstrumented median.

| Workload | Prepare + old links µs | Node loads + geometry generation µs | Connections + groups + filter + impulses µs |
| --- | --- | --- | --- |
| Chunk, partial hit | 3.158 | 258.342 | 39.094 |
| Shatter, partial hit | 17.462 | 1,717.412 | 253.077 |
| Chunk, finer cutoff | 10.696 | 1,573.406 | 244.064 |

The one-generation control intentionally produces different geometry and is retained only to show workload differences. Equivalent recursive variants match bitwise signatures of retained outlines, endpoint pairs, group memberships, group seeds and final velocities. Fading and impulse counts also match. Width rotation, stable IDs under row shuffling, terminal seed-zero behavior, no-progress removal and a single final blast impulse were checked. The maximum motion/impulse audit error was 2.26e-07 in the stored velocity units.

Recorded output contains **590 timed rows and 5,310 raw samples**. Native runs were serialized, pinned to permitted CPU 0 on an AMD EPYC 9V74 virtual CPU, built with GCC 13.3 and `-std=c++20 -O3 -march=native -DNDEBUG -fno-math-errno -ffp-contract=off`. Each row has adaptive repetitions, warmup and nine samples; variants are interleaved in shuffled order. Two process runs are pooled for the report except the dedicated seed control, which has nine samples per row. AddressSanitizer and UndefinedBehaviorSanitizer checks passed; LeakSanitizer was disabled because this host runs under ptrace.

These are native event kernels, not complete game frames. They do not create Box2D bodies/joints, advance physics, implement the player/UI, render, serialize, or simulate an ongoing sequence of changing worlds. The kernel emits connected groups and member lists; applying these to an existing runtime entity store, rewriting ownership references and maintaining ID-to-row maps are outside these timings. Current-graph and cache construction are separate measurements. Single-piece candidate IDs are supplied; spatial-query cost and external engine work remain to be profiled in the actual application.

## Reproduce

Run `python3 run.py --sanitize` on Linux with GCC and Python. It builds and checks the sources, runs two serialized measurement rounds and validates the recorded samples. `python3 validate_results.py` checks packaged result consistency without new timings. `python3 summarize.py` regenerates this report. `manifest.json` lists the hashes of packaged source, inputs, results and documentation. All code uses the C++/Python standard libraries.
