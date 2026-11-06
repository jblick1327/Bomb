# Verification



Run from the project root. Use `scripts/bom.ps1` to assemble the directory-scoped Odin package from `src/` and `diagnostics/`; Test and NetTest also include `tests/`. Temporary packages are created under `build/` and removed after the command. Direct `odin build src` and `odin test src` commands no longer assemble the full package. Use separate test and playable executables:



```powershell

.\scripts\bom.ps1 Test

.\scripts\bom.ps1 Build

.\scripts\bom.ps1 Smoke

.\scripts\bom.ps1 SmokeInput

.\scripts\bom.ps1 SmokeEditor

.\build\BOM.exe --smoke-msaa

.\build\BOM.exe --soak

.\build\BOM.exe --soak-fixture

```



`--smoke` renders the paused editor yard in a hidden window and exits after two frames, saving `output/sandbox-preview.png`. `--smoke-input` drives actual raylib/raygui input: palette selection, rectangle previews and placement, overlap/degenerate rejection, deletion, paused editing, Test/Edit restoration, reset, outlines, UI consumption, movement/jump, inspection, snapshot save/load, Rubber deformation/cell removal, material breakups and falling bombs. Captures go to `output/`. The old lab/TCP/headless-demo modes no longer exist; Tower is now an embedded editor preset.



Geometry checks include independent area, triangle-intersection, boundary-coverage and edge-intersection predicates. Across 32 seeds, all four palette materials plus the independent Stone floor are checked after pre-splitting, a damaging drop and each of three blasts: every live region meets minimum width, has a simple outline, has collision fixtures, and fills its outline area in f32. A cache regression verifies that unbonded neighbours do not alter topology or bridge a moved gap. Native smoke checks the former dark pixel, every background-coloured pixel analytically inside sampled cached rendered silhouettes, and identical stroke coverage at widths 0.3/0.7 versus 1. Glass impact, Wood pre-split blast and seed-13 frames are captured at widths 0/0.3/0.7/2 without stepping between renders. The seed-13 Wood fill fixture and a pre-split 6x4 block are also rendered at widths 0, 0.5 and 2. Triangulation checks cover translated small corners, duplicate points, scale variation and completion when normal ears stall. Direct clipping replaces the former logical ear-merge regression; collision convex decomposition remains covered.



Destruction checks preserve deterministic birth contexts, no-progress removal, same-blast recursion and connection evaluation, external connection inheritance, broken attachments, the conservative deletion shortcut, one impulse per final survivor, minimum group width and immediate vanishing. Rigid checks cover exact shared rest configuration, shape tags, mass/COM/inertia, largest-body retention, moving split velocities, off-centre blast torque and snapshot reconstruction. Changed collision tiling can alter Box2D contact correction/rocking: the rebound regression permits 0.01 units (twice contact slop), while rest-frame and impulse assertions remain strict. Analytic single-region drop thresholds still pass at 30/60/120 Hz. Pre-split crack thresholds at sizes 1 and 0.5, Glass impact separation, Rubber immunity/deformation, static-floor immunity, player bumps and bomb landings remain checked.



Storage checks cover packed live records, ownership/maps/pairs/incident lists, deterministic storage order, cached outlines, y-only cleanup, same-world replenishment and allocation release. Snapshot encode/decode preserves graph, IDs, geometry and birth seeds. The legacy v2 scene-only encoder remains for compatibility fixtures. V3 World snapshots use local shortest-round-trip f32 JSON (including signed zero) and compare every wire float bitwise, preserve player/bomb motion and rain, and require identical re-encoding. Versions 1 and 2 still load as scenes with fresh actors and rain. Same-process 600-tick replays must be byte-identical, with no tolerance.



`--soak` runs 20 simulated minutes by default at fixed 60 Hz/four substeps, seed 42, four authored materials, idle player and falling bombs. Every two minutes it replenishes layout and floor in the same world while preserving IDs, allocations and the bomb stream. Minute output includes timings, live/stored counts, memory and bodies/joints; teardown must release all tracked bytes. `--soak-fixture [prefix]` writes the fixed blast-only snapshot and two byte-identical sequential 600-tick replays. See the [README](../README.md) for commands and the current two-phase evidence report for measurements. Historical evidence and benchmark inputs are retained unchanged.



`--smoke-msaa` shares the playable window setup and captures the default framebuffer with the native batch flushed before `LoadImageFromScreen` and before `EndDrawing`. On Windows it asserts GL_SAMPLES = 4 and GL_SAMPLE_BUFFERS = 1. It settles the native Wood placement on the pre-split floor, then a pre-split 6x4 Wood block, and captures each at widths 0 and 2 without intervening ticks. The metric accounts for display DPI, includes bonded seams, excludes points within 2 physical pixels of silhouette/crack strokes, and rejects RGB deviations above 8 from the flat composited material colour. It also checks snapshot bytes before and after rendering. Output: `output/msaa-{yard,wood6x4}-{0,2}.png` and matching snapshots. The bit-identity test checks shared rigid vertices at an interpolated rotated pose, in both surface modes; the flexible seam checks remain.



The MSAA smoke also isolates rigid internal broken bonds and two separate anchored floor pieces, then captures a 6x4 Wood blast at widths 0 and 2. Border tests distinguish same-body rigid boundaries, flexible bonds and static/static neighbours. Finished-cell tests cover repeated impact retention, blast removal, dust removal and an actual Wood throw/drop. Grain-limited pre-split exceptions must prove they cannot generate a legal partition.



World-state follow-up: `--measure-world` records both 600-tick restore continuations and a five-minute seed-42 falling-bombs run without refills. `--smoke-aim` writes `evidence/world-v3/aim-glass.png`. The MSAA suite additionally settles Glass 6x4 for 120 ticks at the Wood fixture camera, blasts at (-0.1,2), asserts at least ten live cross-piece crack boundaries, and counts every glass silhouette pixel above RGB (86,153,174)+3 at width zero. See [the report](../report.md) for before/after results and measurements.



`--smoke-editor` checks queued-radius HUD/aim pixels, adaptive ring segments, World byte identity while presentation caches are built, numeric palette shortcuts, snapped drag previews and reasons, Layouts modal input consumption, native save/load/Ctrl+S, eight newest files, Last session, autosave/restart, and all four preset buttons. It writes the five Step 2 PNGs under `evidence/editor-step2/` and uses unique test folders under `output/`, leaving interactive `layouts/` alone. Teardown asserts zero tracked Odin bytes and zero additional Box2D bytes. Pure tests cover exact layout JSON round trips, atomic rejection, first-JSON selection, decimal grid bits, shared edges and four 600-tick settling runs. See [the Step 2 report](../report.md). The earlier World measurements remain in [the Step 0/1 report](../evidence/world-v3/report.md).



Presentation-cache follow-up: presentation_cache_test.odin counts cache ensures only in test builds. The headless 600-tick/three-blast fixture plus snapshot load must make zero calls. It also checks Edit/paused notice expiry, exact live-cell cache keys after every blast, unchanged World bytes during cache preparation, signature rescans only on structure changes, and independent cache cleanup after Scene destruction. --bench-presentation times five headless 600-tick/three-blast replays; --soak 1 records the existing one-minute falling-bombs workload. See the current report for timings.



Rubber-band follow-up: `rubber_band_test.odin` covers the editor-built 6×4 bite/hole fixture, a narrower gap that exposes the old weight search, piece-revision invalidation, split bands and independent cleanup. `--capture-rubber-band [directory]` asserts an actual 4× MSAA default framebuffer and captures the bite, deliberate bend, Materials preset and radius-6 Materials blast after 30 ticks, each at widths 0 and 2. Captures assert unchanged snapshot bytes and zero tracked Odin/Box2D allocations after teardown. The undamaged bend and Materials captures must match the baseline pixel-for-pixel. See [the rubber-band report](../report.md); the previous cache report is preserved at [evidence/presentation-caches/report.md](../evidence/presentation-caches/report.md).



Wood splinters: `wood_splinter_test.odin` checks the editor-built plank's dimensions and multi-vertex seams, thinning before cross-cuts, genuinely finished strips, long-bond peeling and exact reconstruction of derived boundary segments. `--wood-study [directory]` repeats the sixteen-seed 6×4 study and writes a combined non-Wood v3 fixture. `--capture-wood [directory]` writes actual-MSAA width-2 plank, Wood blast and Tower blast images; the plank uses F3 region outlines so its construction is visible. The normal 32-seed geometry, four-preset settling, snapshot, MSAA, native input and leak checks remain enabled. The mixed v3 fixtures intentionally change and must still replay identically. See [the current report](../report.md) for baseline and final measurements.



Glass shock: `--glass-study [directory]` measures the settled 5×2.5 pane at radii 3/4 immediately after the blast, the 2×1 flat drop at its first damaging impact batch, and a control with no Glass objects or unused Glass material entries. It records physical-piece and logical-cell median areas by distance band. `--capture-glass [directory]` captures the two panes 30 ticks after damage and Glass house 60 ticks after the specified blast, at width 2 through actual 4× MSAA. Tests cover the recorded regressions, exact Dijkstra costs, disconnected bonds, inherited loads, one generation without sibling glue or extra impulse, optional field compatibility and one structural commit per blast/impact batch. The radius-3 prototype range is a reported prediction, not a reason to tune the prescribed loss. See [the current report](../report.md); the Wood report is preserved at [evidence/wood-splinters/report.md](../evidence/wood-splinters/report.md).



Menu simplification: `scripts/bom.ps1 SmokeMenus` (or `build/BOM.exe --smoke-menus`) drives the native material picker and menus, verifies all pages at 1280x800 and 900x700, asserts zero text overflow and unchanged World bytes during captures, then hosts a real local session, returns to Edit, places a shape, uploads it through Test, changes radius and leaves. Captures and the report live under `evidence/menu-simplification/`. The updated SmokeMaterials and SmokeInput fixtures use the new picker and menu pages. Neither verification mode changes interactive layouts.
