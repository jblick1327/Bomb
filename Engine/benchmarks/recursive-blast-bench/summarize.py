#!/usr/bin/env python3
"""Rebuild the human-readable findings from recorded native samples."""
import csv
import json
from pathlib import Path
import statistics

ROOT=Path(__file__).resolve().parent
R=ROOT/'results'
def read(name):
    with (R/name).open() as f:
        return list(csv.DictReader(f))
def pool(family, **select):
    rows=read(family+'.csv')
    if (R/f'round1_{family}.csv').exists():
        rows+=read(f'round1_{family}.csv')
    rows=[r for r in rows if all(r[k]==str(v) for k,v in select.items())]
    assert rows, (family,select)
    return statistics.median(float(r[f'sample_{i}_ns']) for r in rows for i in range(9))
def event(case,variant): return pool('events',case=case,variant=variant)
def table(headers,rows):
    return '\n'.join(['| '+' | '.join(headers)+' |','| '+' | '.join(['---']*len(headers))+' |',*['| '+' | '.join(map(str,r))+' |' for r in rows]])
def us(ns): return f'{ns/1000:,.3f}'
def ratio(a,b): return f'{a/b:.2f}×'

def main():
    raw=read('events.csv')
    lookup={(r['case'],r['variant']):r for r in raw}
    cases=list(dict.fromkeys(r['case'] for r in raw))
    pretty={'chunk_boundary':'Chunk, partial hit','splinter_boundary':'Splinter, partial hit','shatter_boundary':'Shatter, partial hit','chunk_deep':'Chunk, finer cutoff','whole_piece_erased':'Whole piece erased','terminal_seed_zero':'Terminal seed 0','sparse_512_shuffled':'One piece in 512, shuffled','sparse_8192_shuffled':'One piece in 8,192, shuffled'}
    result={'events':{},'rows_and_samples':json.loads((ROOT/'validation.json').read_text())}
    mainrows=[]
    for c in cases:
        a=lookup[c,'aos_context'];b=lookup[c,'skip_fully_erased'];normal=event(c,'aos_context');pruned=event(c,'skip_fully_erased')
        result['events'][c]={'reference_us':normal/1000,'pruned_us':pruned/1000,'speedup':normal/pruned,'generated_before':int(a['generated']),'generated_after':int(b['generated']),'final_nodes':int(a['final_nodes']),'final_edges':int(a['final_edges'])}
        mainrows.append([pretty[c],us(normal),us(pruned),ratio(normal,pruned),f"{a['generated']} → {b['generated']}",a['final_nodes']])
    layouts=[]
    for c in ['chunk_boundary','splinter_boundary','shatter_boundary','chunk_deep','sparse_8192_shuffled']:
        layouts.append([pretty[c],*[us(event(c,v)) for v in ['skip_fully_erased','pruned_pose_first','pruned_hot_cold','pruned_hot_columns']]])
    queries=[]
    for c in ['chunk_boundary','sparse_512_shuffled','sparse_8192_shuffled']:
        queries.append([lookup[c,'aos_context']['source_nodes'],us(pool('queries',case=c,whole_world=0,variant='aos_owner')),us(pool('queries',case=c,whole_world=0,variant='hot_columns_owner')),us(pool('queries',case=c,whole_world=0,variant='aos_members')),us(event(c,'pruned_global_scan')),us(event(c,'skip_fully_erased'))])
    whole=[]
    for c in ['chunk_boundary','sparse_512_shuffled','sparse_8192_shuffled']:
        whole.append([lookup[c,'aos_context']['source_nodes'],us(pool('queries',case=c,whole_world=1,variant='aos_owner')),us(pool('queries',case=c,whole_world=1,variant='aos_members')),us(pool('queries',case=c,whole_world=1,variant='hot_columns_members'))])
    cache=[]
    for c in ['chunk_boundary','splinter_boundary','shatter_boundary','chunk_deep']:
        cache.append([pretty[c],us(event(c,'skip_fully_erased')),us(event(c,'pruned_derive_width')),us(event(c,'pruned_survivor_anchors')),us(event(c,'pruned_depth_first'))])
    eager=[]
    for ti,c in enumerate(['chunk_boundary','splinter_boundary','shatter_boundary']):
        r=next(r for r in read('construction.csv') if r['case']==str(ti) and r['variant']=='next_generation_cache')
        build=pool('construction',case=ti,variant='next_generation_cache');cached=event(c,'pruned_prebuilt')
        eager.append([pretty[c],us(build),us(event(c,'skip_fully_erased')),us(cached),us(build+cached),f"{lookup[c,'pruned_prebuilt']['cache_hits']}/{r['cache_entries']}",f"{int(r['cache_bytes'])/1024:.1f}"])
    initial=[]
    for ti,label in enumerate(['Chunk','Splinter','Shatter']):
        r=next(r for r in read('construction.csv') if r['case']==str(ti) and r['variant']=='initial_graph')
        initial.append([label,r['cache_entries'],us(pool('construction',case=ti,variant='initial_graph'))])
    seeds=[]
    for k in [3,5,6,12,24]:
        a=pool('seeds',children_per_batch=k,terminal_percent=50,variant='shared')/4096
        b=pool('seeds',children_per_batch=k,terminal_percent=50,variant='per_child_common')/4096
        seeds.append([k,f'{a:.3f}',f'{b:.3f}'])
    seed_audit=read('seed_policy_audit.csv')
    mixed=sum(int(r['mixed_width_batches']) for r in seed_audit)
    small=sum(int(r['small_children_with_nonzero_seed']) for r in seed_audit)
    maxerror=max(float(r['maximum_impulse_error']) for r in seed_audit)
    controls=[]
    for c in cases:
        controls.extend([event(c,'aos_duplicate_control')/event(c,'aos_context'),event(c,'pruned_duplicate_control')/event(c,'skip_fully_erased')])
    phases=[]
    for c in ['chunk_boundary','shatter_boundary','chunk_deep']:
        phases.append([pretty[c],*[us(pool('stages',case=c,stage=s)) for s in ['prepare_and_old_edges','node_loads_and_generation','connections_groups_filter_impulses']]])
    report=f'''# Recursive destruction: native benchmark findings

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

{table(['Workload','Recursive reference µs','Proven deletion shortcut µs','Ratio','Generated children','Retained subdivisions'],mainrows)}

The complete-erasure case is a special fast path, not a representative game-frame speedup. Larger scene sizes are scaling stress controls. One selected piece is processed; the other pieces remain unchanged.

The shortcut works because load is `12 * max(0, radius - distance)` and descendants share the material strength. The farthest posed parent vertex bounds the distance of every point inside the parent's convex hull. If even that conservative farthest point exceeds the threshold, all descendant samples must fail. A rounding margin makes the test conservative. The generator must preserve the parent partition. This argument uses the current unoccluded blast field and does not predict new physics contacts.

## Layout comparison after the shortcut

All four event record representations carry the same 64 bytes of data per node: context-first AoS; pose-first AoS; 32-byte hot and 32-byte cold records; and hot columns with cold records. Shared immutable vertices remain in a separate pool. The small seed/depth/state and tree records used during recursion are temporary benchmark work, not proposed persistent subdivision components. Logical child identities are stable hashes of parent identity and ordinal, with 32-bit temporary row references. Skipping an erased branch must not shift other branches' seeds through a shared random stream or allocation-order IDs.

{table(['Workload','Context-first AoS µs','Pose-first AoS µs','Hot/cold µs','Hot columns µs'],layouts)}

There is no consistent win for changing the event layout. Identical duplicate controls ranged from {min(controls):.2f}× to {max(controls):.2f}× the reference time, so small single-digit differences should be treated as ties. Allocation state, process/run variation and this virtual CPU limit precision. These measurements do not isolate a hardware cause for small rankings.

## Work selection matters more

These query-only tests begin with a known candidate piece, as if supplied by a broadphase. They do not time spatial-index discovery. The owner scans traverse the whole source node pool once; member queries traverse the selected piece's retained list. The last two columns include the full optimized recursive transaction, demonstrating how an unnecessary scene scan becomes more visible after generation is reduced.

{table(['Scene subdivisions','AoS owner query µs','Column owner query µs','AoS member query µs','Full event + global owner scan µs','Full event + members µs'],queries)}

For full-world reads, the ranking changes. Member traversal visits every node once and broadcasts its piece material; owner traversal also scans the world once. The large inputs deliberately shuffle rows.

{table(['Scene subdivisions','AoS world scan µs','AoS piece/member traversal µs','Hot-column member traversal µs'],whole)}

This supports keeping separate choices for streaming access and structural updates. It does not support converting every component to one universal format.

## The shared child-seed check

The tested rule calculates child widths during generation, then makes one common decision: if the maximum child width is at or below the cutoff, assign zero to all children; otherwise derive nonzero child contexts from stable parent identity and ordinal. An individual outline-width guard remains before further refinement. Zero-seed geometry stays live until it actually fails.

The audit found **{mixed} mixed-width sibling batches** and **{small} children below the cutoff that received the shared nonzero context**. None split further because the individual guard stopped them. A shared nonzero seed alone cannot replace exact individual eligibility for irregular geometry. An alternative rule making all siblings terminal when any one is small is possible, but changes fragmentation and was not counted as an equal-output optimization.

In the complete event, the shared-versus-repeated common predicate did not produce a reliable advantage beyond the duplicate-control variation. The seed-only control below writes packed byte outputs for 4,096 batches at a 50% terminal mix; it is not a recommendation for a separate permanent seed column. Values are nanoseconds per sibling batch. Nonzero child hashes are identical in both methods.

{table(['Children per batch','One shared branch ns/batch','Repeated inline common check ns/batch'],seeds)}

Keep the shared decision for clarity. The measurements do not justify extra state or dispatch machinery to optimize this comparison.

## Width, anchors and processing order

These values use the deletion shortcut. Width is rotation-independent geometric width. Discovery is FIFO by default; the depth-first variant changes refinement discovery while retaining canonical connection-update waves and one final grouping pass.

{table(['Workload','Cached width µs','Recompute width µs','Offsets only for survivors µs','Depth-first discovery µs'],cache)}

Width retention helps some cases, especially once generation has already computed the value for the shared seed decision. In this 64-byte AoS record it uses space otherwise occupied by padding; other actual component layouts may differ. A local anchor pair is 16 bytes. Re-deriving shared boundaries at each query was slower in the separate reference variants, but whole-event gains were much smaller than the earlier anchor-only benchmark because generation and graph work are now included.

No robust discovery-order winner appeared. All generated geometry is retained in temporary event storage until the canonical graph pass, so this does not measure a fully streaming depth-first implementation that recycles dead subtrees. Persistent adjacency, row compaction, long-session tombstone accumulation and stable-ID map maintenance were not timed.

## Eager creation and future-generation caching

Your rule that current geometry exists immediately is the baseline. A separate creation control partitions the reference piece's convex hull using the prototype recipes, finds boundaries, calculates widths and assigns seeds. It excludes engine bodies/joints and the cost of finding that input hull.

{table(['Pattern','Created subdivisions','Current-graph generation µs'],initial)}

The shatter count exceeds its target because the supplied generation approach triangulates and then adds bent-boundary detail. The target count is not a hard output cap.

Precomputing an additional possible generation for every current subdivision is a different cache. It can reduce the measured blast latency, but pays construction and memory costs even for parents that never fail or can be removed directly. A failed parent consumes its cache once in the real program; repeated benchmark samples replay the initial state and must not be mistaken for real cache reuse across that parent's lifetime.

{table(['Workload','Cache construction µs','On-demand blast µs','Cached blast µs','Build + cached blast µs','Cached parents used','Tracked cache KiB'],eager)}

Construction controls include their temporary-buffer allocation and cleanup. Summing build and blast medians is an indicative sequential-work comparison, not a separately measured combined frame. Cache bytes are tracked payload/capacity estimates and exclude unordered-map buckets and allocator overhead. The event storage metric similarly excludes some temporary and per-group allocations. Immutable templates shared across many identical objects could have different amortization; that was not measured. Start with eager current geometry and on-demand future refinement.

## What changed in the native generator

The input includes the original handoff's 12 bent chunk/splinter/shatter geometry snapshots with recorded Box2D poses, plus the uploaded Odin source used as the porting reference. Starting pieces contain 12 or 24 subdivisions. Future-generation recipe targets are 3, 5 and 6, matching the prototype presets; strengths are the fixture's shared values 40/55/30 for subdivisions and 28/35/16 for connections. These are test settings, not added model requirements. Blasts originate outside the structures. The default refinement/group-width cutoff is 0.18; the deeper control uses 0.09.

The C++ port fixes no-progress generation by returning direct removal, completes triangulation or fails validation, and uses double-precision outline coordinates with float motion/load records. During independent validation, the original area/length displacement cap in the port allowed child boundaries to cross. The final generator additionally limits displacement by clearance to the other edges of the two adjacent polygons. The final timings include that work. Independent audits verify child containment, non-crossing/non-overlapping partitions, area conservation and valid polygons, including deeper and complete-erasure scenarios. These findings are not proof of the cause of the screenshot in the newer Odin build.

## Processing breakdown and validation

The reference recursive event includes copied active records, initial connection queries, actual polygon generation and width/seed decisions, inherited and internal connections across canonical refinement waves, connection failure, grouping, retained membership output, size filtering and final impulse records. It uses ordinary C++ containers. These separate instrumented stage timings include clock overhead and should not be added to another row's uninstrumented median.

{table(['Workload','Prepare + old links µs','Node loads + geometry generation µs','Connections + groups + filter + impulses µs'],phases)}

The one-generation control intentionally produces different geometry and is retained only to show workload differences. Equivalent recursive variants match bitwise signatures of retained outlines, endpoint pairs, group memberships, group seeds and final velocities. Fading and impulse counts also match. Width rotation, stable IDs under row shuffling, terminal seed-zero behavior, no-progress removal and a single final blast impulse were checked. The maximum motion/impulse audit error was {maxerror:.3g} in the stored velocity units.

Recorded output contains **{result['rows_and_samples']['timed_rows']} timed rows and {result['rows_and_samples']['raw_samples']:,} raw samples**. Native runs were serialized, pinned to permitted CPU 0 on an AMD EPYC 9V74 virtual CPU, built with GCC 13.3 and `-std=c++20 -O3 -march=native -DNDEBUG -fno-math-errno -ffp-contract=off`. Each row has adaptive repetitions, warmup and nine samples; variants are interleaved in shuffled order. Two process runs are pooled for the report except the dedicated seed control, which has nine samples per row. AddressSanitizer and UndefinedBehaviorSanitizer checks passed; LeakSanitizer was disabled because this host runs under ptrace.

These are native event kernels, not complete game frames. They do not create Box2D bodies/joints, advance physics, implement the player/UI, render, serialize, or simulate an ongoing sequence of changing worlds. The kernel emits connected groups and member lists; applying these to an existing runtime entity store, rewriting ownership references and maintaining ID-to-row maps are outside these timings. Current-graph and cache construction are separate measurements. Single-piece candidate IDs are supplied; spatial-query cost and external engine work remain to be profiled in the actual application.

## Reproduce

Run `python3 run.py --sanitize` on Linux with GCC and Python. It builds and checks the sources, runs two serialized measurement rounds and validates the recorded samples. `python3 validate_results.py` checks packaged result consistency without new timings. `python3 summarize.py` regenerates this report. `manifest.json` lists the hashes of packaged source, inputs, results and documentation. All code uses the C++/Python standard libraries.
'''
    (ROOT/'SUMMARY.md').write_text(report)
    (ROOT/'summary.json').write_text(json.dumps(result,indent=2))
    print(ROOT/'SUMMARY.md')

if __name__=='__main__':
    main()
