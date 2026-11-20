# Recursive destruction benchmarks

Read [SUMMARY.md](SUMMARY.md) for findings and the recommended simple implementation. This is a standalone C++ benchmark package for the revised destruction rules, not a replacement game implementation.

The main result is to skip refining a failed outline when the blast is guaranteed to destroy every descendant. Current graphs are initialized eagerly; descendants may be evaluated by the same blast. Child terminal-seed decisions are made at batch creation, with an individual width guard for mixed-size children.

Files:

- `geometry.hpp`: polygon generation, shared boundaries, width, triangulation and safe displaced seams.
- `core.hpp`: four record layouts, recursive refinement, connection inheritance, grouping and impulse output.
- `bench.cpp`: 26 variants, query controls, construction costs and stage timings.
- `seeds.cpp`: shared-versus-repeated common seed-predicate control.
- `audit.cpp`: independent partition, layout, selection, seed, cutoff and motion checks.
- `run.py`: builds, validates, pins and runs native measurements serially.
- `validate_results.py`: checks saved raw samples, summaries, output signatures and manifest hashes.
- `summarize.py`: regenerates the report from the recorded data.
- `inputs/`: supplied bent geometry/native-pose snapshots and the Odin porting references.
- `results/`: two measurement rounds, raw samples, verification records and sanitizer logs.
- `environment.json`, `validation.json`, `summary.json`, `manifest.json`: measurement metadata and checks.

Requirements: Linux, GCC with C++20, and Python 3. No downloaded packages or external libraries are needed.

```bash
python3 validate_results.py
python3 run.py --verify-only
python3 run.py --sanitize
python3 summarize.py
```

`run.py --sanitize` creates new timings and overwrites the result files. The report pools the two rounds' raw samples. Compiler flags, input settings, dimensions and timing exclusions are described in `SUMMARY.md`.

The reference and pruning variants implement the same retained-geometry result. The one-generation control intentionally implements different behavior. Do not compare it as an equal-output optimization, add unrelated microbenchmark speedups together, or treat these event timings as full Box2D frame times.
