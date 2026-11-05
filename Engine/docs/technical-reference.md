# Odin destruction sandbox



A playable destruction yard built with Odin's bundled Box2D, raylib and raygui libraries. Draw rectangles from four materials, test the layout, and explore its destruction with blasts or falling bombs.



This README and the linked gameplay, implementation and verification documents describe current behavior. The documents in `docs/plans/` are historical references.



## Run



Requires Odin on `PATH`, with compiled `vendor:box2d` and `vendor:raylib` libraries. Previously tested on Windows with Odin `dev-2026-05-nightly:ea5175d`.



From PowerShell:



```powershell

.\scripts\bom.ps1                 # Run the playable sandbox

.\scripts\bom.ps1 Test            # Run the existing test suite

.\scripts\bom.ps1 Build           # Build an optimized executable

```



The helper creates `build/` and `output/`, runs from the project root, and keeps generated files out of the source tree. All Odin source and tests share one package in `src/`.



Equivalent direct commands, run from the project root:



```powershell

New-Item -ItemType Directory -Path build -Force | Out-Null

odin run src -out:build/BOM.exe

odin test src -out:build/BOM-tests.exe

odin build src -o:speed -out:build/BOM.exe

```



The optimized executable is `build/BOM.exe`. For direct launches, keep the project root as your working directory: snapshots and smoke captures are written to `output/` relative to that directory.



For a repeatable headless longevity check, build with `-o:speed` and run:



```powershell

.\build\BOM.exe --soak             # 20 simulated minutes (72,000 fixed 60 Hz ticks)

.\build\BOM.exe --soak 5           # Optional positive whole-minute duration

.\build\BOM.exe --soak-fixture     # Blast-only and 600-tick comparison snapshots

```



The soak uses seed 42, an idle player, the editor yard with one 1.6 x 2 rectangle of Wood, Glass, Rubber and Stone on the floor, and falling bombs at the current default radius 5. Every two simulated minutes it discards any surviving regions through normal regroup/commit, rebuilds those authored rectangles and a fresh pre-split floor into the **same scene and Box2D world**, and respawns the player. The material table, ID counter, buffer capacities and ongoing bomb random stream are retained. Replenishment occurs on the next tick after minutes 2, 4, etc.; its cost is included in that tick. A 20-minute run exercises ten destruction cycles.



Every simulated minute it prints cycle number, tick/blast mean and maximum wall-clock milliseconds, blast count, live/stored region/link/piece counts, ID-map sizes, owned outline vertices, current allocated bytes, Box2D body/joint counts, the next ID, and within-minute live region/link/piece peaks. Allocation output separates tracked Odin heap bytes and Box2D's `GetByteCount`, then sums them; it excludes the tracking allocator's own bookkeeping, unrelated runtime memory and process working-set overhead. The allocator tracker is enabled only for `--soak`, and its overhead is included in timings. Samples describe the ending cycle before replenishment. Blast timing includes the shared blast pass (reach refinement and damage resolution) and physics sync. The headless run is unthrottled and saves `output/soak-final.json`, then prints remaining tracked bytes after destroying the yard to distinguish retained capacity from unreleased allocations.



The fixture uses the same yard and three fixed blasts without physics ticks, plus a separate seeded 600-tick sequence. That ticked replay runs **twice sequentially in one process** and requires byte-identical snapshots, including motion and IDs. An optional output prefix follows `--soak-fixture`. The [original storage report](../evidence/soak/report.md) retains the earlier baseline; [sustained-cycle results](../evidence/soak-cycles/report.md) cover the replenishing soak and out-of-bounds removal.





## Play



The application starts paused in **Edit**, restoring `layouts/autosave.json` when valid. Choose Wood, Glass, Rubber or Stone (keys 1–4), then drag rectangles snapped to a 0.1-unit grid. The preview shows dimensions and any placement problem. Click **Test** or press Enter to simulate. **Layouts** opens the four embedded presets and saved layouts; Ctrl+S saves the next free `layouts/layout-NNN.json`. Drop a layout JSON file in either mode to load it. Authored changes autosave. F3 S/L independently saves and loads v4 World snapshots (v3 still loads) in `output/`. Settings include falling bombs, blast radius and outlines.



| Control | Action |

| --- | --- |

| Left drag in Edit | Preview and place a rectangle using the selected material |

| 1–4 in Edit | Select Wood / Glass / Rubber / Stone |

| Layouts / Ctrl+S in Edit | Presets and saved files / save current layout |

| Drop a layout .json | Load the first JSON file and return to Edit |

| Right click in Edit | Remove the authored object under the cursor |

| Edit / Test button or Enter | Start a fresh test / restore the undamaged edit layout |

| A / D or left / right arrows in Test | Move |

| Space in Test | Jump, with a 0.1 second jump buffer and coyote window |

| Left click in Test | One blast at a valid cursor position |

| Mouse wheel over the world in Test | Adjust blast radius and power |

| R / Reset button in Test | Rebuild the same authored layout and seed |

| Tab / Escape / Settings button | Open settings and pause; close to resume |

| F3 in Test | Show every region outline, IDs, connections and inspection tools |



See [gameplay and defaults](../docs/gameplay.md) for material presets, placement limits, inspection controls.



Gameplay outlines and fill seals follow physical separation. Rigid regions in the same piece hide shared edges even after a bond breaks; flexible regions hide bonded seams using their live incident links. Two anchored pieces also hide their shared edges. Edges against another dynamic piece stay visible; F3 reveals all region boundaries at the same outline width. The width slider uses 0 for ordinary outlines off. Positive widths below 1 draw a continuous 1 px outline with alpha scaled by width; widths of 1 or more retain their thickness. Rubber uses a rest-frame skin with vertices spaced at most 0.1 units apart and fixed, normalised weights from cells within 0.5 units. Its outside has a dark, round-joined film at least 3 px wide, including when ordinary outlines are off. V shows raw cell poses. Stone and Rubber fills are opaque, and the world background has no grid. Fills are followed by 1 px fill-coloured seals on exposed/cracked edges; the film and outline strokes then draw on top. Together seams are not sealed. Real openings wider than about a pixel remain visible. F3 inspection keeps S/L snapshot save/load; the authored rectangle layout is not part of a snapshot.



The editor yard is the only playable scene. The old tower, diagnostic lab, TCP sender/receiver, standalone headless demo and staged material-tuning settings have been removed. `--smoke`, `--smoke-input`, `--soak`, `--soak-fixture` and `--help` remain.



## Physics damage



Blasts and physics share a velocity-change scale: each surviving region contributes an impulse of `region area * L * BLAST_IMPULSE_SCALE` at its centre, and physical damage is `dv * impact_scale / BLAST_IMPULSE_SCALE` (currently 0.2). Material constructors and older snapshots default `impact_scale` to 1; the serialized palette values are Wood 1, Glass 1, Stone 1.6 and Rubber 0. Strengths and blast behavior are unchanged.



In the playable editor yard, objects and the ground are pre-split at creation with their existing material recipe toward a longest bounding dimension of `PRESPLIT_SIZE = 1.0`, retaining grain-limited cells that cannot legally split. They remain ordinary logical regions and connections. Every piece with **flexibility 0** (Wood, Glass, Stone and the floor) has **one rigid Box2D body** containing all its regions' convex shapes. The floor's connected group stays static. Positive-flexibility materials, including Rubber, keep one body per region with soft welds. Rubber keeps its uniform 0.4-unit terminal grid. Future generations still appear only when needed. Creation finishes long thin cells before assigning the existing terminal-batch mark; a genuinely failing cell that cannot split caches seed zero. Blasts still delete it; impacts retain non-dust geometry, while width at or below minimum_width still vanishes. Spatial creation/reach attempts are not damage failures and keep their local no-progress handling. Birth contexts remain deterministic and connections inherit through the existing staging path.



When an impact cracks a cell, its children receive no sibling connections. They retain inherited connections to surviving neighbours, so graph connectivity can still hold some fragments together. Creation and blast-generated children keep their sibling connections. Bonds break from blasts only; weld reaction forces and torques do not contribute damage. The former seam-separation threshold check has been removed. `PRESPLIT_SIZE` still sets the initial cell topology and hence the paths of later breakup.



Strips cut parallel to each polygon's own long axis until its elongation reaches `1 / aspect_ratio`, then cross-cut it. This preserves elongated shapes while allowing a plank to lose an end and creation refinement to finish. Aspect-one recipes and deliberate Glass triangulation are unchanged.



Non-triangulated Chunks/Strips clip shallow-concave parents directly; convex decomposition is reserved for collision shapes. Every accepted cut must produce two simple halves that preserve area and meet the scene's minimum width (0.1 in the yard), including the final triangles for Shards. An uncuttable candidate is skipped while the remaining candidates are tried. Creation and reach refinement use the same guard. Shared seam bends are checked for crossings/touches and width, with up to three amplitude halvings before keeping a straight seam. Triangulation uses relative tolerances, removes consecutive duplicate points internally, and always completes the cleaned polygon's n-2 triangles. These intentional generation changes remove hairline fragments and make some crater rims coarser.



Contacts use Box2D 3.1.1 hit events, evaluated every step even for existing contacts. Their pre-solve approach speed gives `dv = approach_speed * M_other / (M_self + M_other)`. Region masses are their **current connected piece's total polygon area**, cached at regrouping; player and bomb masses come from their bodies. An immovable other body gives the full approach speed, and static regions take no contact damage. The strongest interaction wins; there is no contact torque term or minimum-speed damage gate.



Rubber's zero impact scale keeps its cells immune to physical damage; blasts still remove finite-strength cells. Other materials retain their existing strengths and impact scales. Finished cells (seed zero and width above minimum_width) are skipped when collecting impact failures, so their impacts do not trigger empty structural commits or increment the snapshot revision. Cells that fail generation during the current event still follow the existing staging path.



Measured flat cell-crack onsets for the same seeded 2.4 x 1.2 object (60 Hz / four substeps):



| Material | Impact scale | First cell crack, size 1.0 / 0.5 |

| --- | ---: | ---: |

| Glass | 1 | 0.525 / 0.525 |

| Stone | 1.6 | 0.950 / 0.950 |

| Wood | 1 | 1.625 / 1.625 |

| Rubber | 0 | No impact damage |



Heights are bracketed to 0.05 units. Cell-crack onset agrees at both resolutions. A pre-split Glass pane dropped from 0.8 units cracks into multiple pieces. Individual fragments may retain external attachments or remain packed together by contact; impact fracture does not guarantee every child becomes a separate piece. Analytic single-region thresholds remain `h = (strength * 0.2 / impact_scale)^2 / (2 * 9.8)`: Glass 0.522, Stone 0.977, Wood 1.600. Those isolated tests pass at 30, 60 and 120 Hz. Floors, full-speed player bumps and normal bomb landings remain undamaged; Rubber survives its highest placeable drop.



Rigid regions share the undeformed rest frame: body origin is rest-frame origin, and every shape uses rest coordinates. Each motion read derives region centres and point velocities from that body's transform and angular velocity. Mass, centre of mass and inertia come from the exact logical outlines, even when collision hulls simplify an outline. Regions of the same rigid piece cannot collide with each other or bow at seams. Rubber still stretches through its existing soft joints. Rest-frame skinning applies only to flexible pieces; rigid rendering and interpolation use one common transform.



On fracture, the group with the most surviving regions retains the old body; ties select the lowest region ID. Removed/moved regions lose their old shapes and new regions contribute new shapes. Other groups receive new bodies with the old transform, the old body's point velocity at their new centre of mass, and its angular velocity. Shape/body operations use deterministic ID order at commit/sync. Logical connections still determine pieces and can be broken by blasts. Off-centre blast impulses now give rigid pieces spin; each final region contributes its own area-weighted impulse exactly once. Rubber cells retain their existing centre-impulse behavior.



Flat 0.5-unit Stone drops, measured over four seconds at 60 Hz / four substeps on the current yard floor:



| Object | Pre-split rebound | Single-region control |

| --- | ---: | ---: |

| 2.4 x 1.2 block | 0.002839 | 0.000955 |

| 0.7 x 3.7 post | 0.007737 | 0.000896 |



Heights are centre-of-mass maxima after the first hit, relative to the final second's mean settled height; they include small contact correction/rocking, not just airborne motion. The generation change alters collision tiling and therefore small contact corrections: differences are below the current check's 0.01-unit tolerance (twice Box2D contact slop). The former 0.002-unit comparison fails for the new post geometry; no physics tuning was applied. Shape decomposition and contact distribution can still differ from a single rectangle. Rigid rest-frame error stayed below 0.000001 units in these checks. No joint/contact tuning or material values were changed. See the [rigid-piece verification report](../evidence/rigid-pieces/report.md) for the before/after soaks and checks; the [earlier weld-compliance comparison](../evidence/impact-shatter/report.md) is historical.





Every `blast_pass` first refines every cell reached by the blast's destructive core, on every object, down to the minimum width, then resolves center-sampled damage and same-blast recursion. This shared entry point is used by the game and tests; the yard has no separate refinement pass. This is **A**, selected after the visual comparison; the temporary A/B switch and center-only alternative have been removed. The radial blast-load law, inherited connections, same-blast child evaluation, deletion shortcut and single final impulse per survivor remain unchanged. The [shared-pass verification report](../evidence/shared-blast/report.md) records historical gameplay equivalence, the superseded seam-check failure and that soak. The [historical comparison report](../evidence/presplit/report.md) and [video](../evidence/presplit/video/blast-rules-A-vs-B.mp4) retain both candidates' results for reference.



## Live storage



Groups below the minimum width vanish immediately. After each yard simulation tick, regions whose position is below y = -5 (`YARD_FLOOR_BOTTOM - 2`) are also discarded, regrouped and committed immediately, for every material. This uses the region position, so touching the boundary does not remove it. There is no x cutoff; debris can move visibly beyond either end of the base before falling below it. There is no fade or retained visual remnant. Storage cleanup does not alter damage thresholds or recipes.



Regions, links and pieces remain plain records with monotonic, never-reused IDs. A single commit after inheritance and regrouping swap-removes dead records and deletes their map keys. Each region owns its outline and collision-shape handles. A rigid piece owns its body (region handles alias it); a flexible region owns its own body and its links own soft joints. Physics handles and render caches are excluded from snapshots. Piece memberships and endpoint-pair lookup stay current during staging. Array capacity can retain a peak allocation for reuse, but loops visit current records, not session history.



Regrouping uses affected-piece memberships. Blast and terrain candidates come from Box2D's padded AABB query, supplemented by pending children until final bodies exist. Rendering caches outline topology, triangle indices and flexible skin weights per piece change; frames transform those cached vertices. Neighbours are structural, with no Box2D query: the cell's own piece, live non-mortar links, and for an anchored cell the anchored cells of other pieces whose rest bounds overlap its own expanded by 0.05. Anchoring is `piece_anchored`, shared with physics. Physics structure sync runs only after the internal structure revision changes. New shapes/bodies/joints use ascending IDs; rendering uses ascending IDs within static and moving fill passes, independent of packed storage order. Shape user data carries the region ID for hit events and blast queries. V4 wraps the compatible scene format with every active player (index, body, timers, blast radius), bomb, rain, settings and tick state, writing all f32 values exactly. V3 (one player) loads into player 0 with the settings blast radius. For the scene, decoding reconstructs piece mass and rigid bodies from member outlines and region poses, including angular motion. Box2D free-slot/solver ordering can cause small numerical differences in ticked replays.



## Verify



```powershell

.\scripts\bom.ps1 Test

.\scripts\bom.ps1 Smoke           # Hidden-window sandbox capture

.\scripts\bom.ps1 SmokeInput      # Native input/widget playthrough and material captures

```



The test executable is `build/BOM-tests.exe`; smoke PNGs and snapshots are written to `output/`. The existing behavior suite runs without a display; smoke checks require graphics support. See [verification details](../docs/verification.md) for coverage and output names.



## Folder layout



| Path | Contents |

| --- | --- |

| [src/](../src/) | Game code and tests, kept in one Odin package |

| [scripts/bom.ps1](../scripts/bom.ps1) | Run, build, test and diagnostic commands |

| [docs/](../docs/) | Gameplay, implementation, verification and historical plans |

| [benchmarks/recursive-blast-bench/](../benchmarks/recursive-blast-bench/) | Standalone C++ benchmark, recorded inputs, results and hash manifest |

| [evidence/](../evidence/README.md) | Preserved screenshots, dated playtest reports, captures and unique archives |

| `build/` | Generated executables and debug symbols; ignored by Git |

| `output/` | Generated runtime snapshots, smoke captures and local verification logs; ignored by Git |



Historical evidence remains eligible for version control. The benchmark's copied Odin files are recorded inputs, so they are retained separately from the live source. See the [implementation guide](../docs/implementation.md) for the source map and solver details.



Current outline/generation verification, crater comparisons and three-run timings: [two-phase report](../evidence/piece-outlines-generation/report.md). The later rendering follow-up replaces the equal-transform T-junction query with fill-coloured edge seals; snapshots and real open gaps are preserved. See [render checks](../evidence/render-seals/report.md).



MSAA window rendering uses rlgl's white shapes texture after raygui initialisation, avoiding font-atlas UV dropout. Rigid fills and strokes transform rest vertices through one interpolated piece frame, so bonded cells share bit-identical rendered vertices. `build/BOM.exe --smoke-msaa` checks actual 4x-MSAA default-framebuffer captures (not render textures) at outline widths 0 and 2. See [MSAA seam verification](../evidence/msaa-seams/report.md).



Grained recipes (`aspect_ratio < 1`, including Wood) clamp their seeded cut within 0.4..0.6 to leave minimum_width on both sides of the chosen cut axis. If that cannot fit or fails geometry validation, the part is left alone; there is no cross-grain axis fallback. Ungrained recipes retain both axis attempts. See [borders and grain evidence](../evidence/borders-grain/report.md) for measured fragment shapes and limitations. Static pieces share a render revision updated at physics structure sync; dynamic pieces retain their own revision. Together neighbours use live bonds for flexible cells and the region world AABB for rigid/static cells, with shared rest boundaries feeding both endpoint insertion and border flags.





### Mortar and glue force failure

A mortar or glue seam is every live connection between one body pair. Each tick its weld reactions are summed into one force F and torque T about the seam midpoint, and the seam's ratio is `r = |F| / (280 * L) + |T| / (0.5 * 280 * L^2)`, where L is the total seam length and 280 is `MORTAR_STRENGTH`.

Failure is an impulse rule, not a tick count. Each seam carries `damage`, in seconds of excess capacity. Every tick, with dt the fixed physics step (1/60 s): if `r >= 1` then `damage += (r - 1) * dt`, otherwise `damage = 0` (a tick within capacity heals the seam completely). The seam breaks, all members at once, when `damage >= SEAM_TOUGHNESS`, which is **0.4 s**. A violent impact (one tick at r = 77 absorbs about 1.3 s) breaks a seam at once, while a brief moderate transient (a blast's velocity change resolved across a rigid weld chain in one solver step) does not. There is neither an immediate `r >= 2` path nor a tick count, and the rule does not depend on the tick rate. Damage is shared by every member connection of the seam and saved on each; merged groups keep the largest member damage.

`SEAM_TOUGHNESS` was chosen by sweeping 0.025 to 1.6 s over five checks (original demo blast, 3x tip block, mortar calibration, 600-tick glued cantilever, 1x1 Stone block dropped from 3 m); 0.2, 0.4 and 0.8 s pass all five and 0.4 is the geometric-mean midpoint. `scripts/seam-toughness-sweep.py` repeats the sweep through `-define:SEAM_TOUGHNESS=<seconds>`; the table is `evidence/seam-toughness/sweep.md`.

Snapshots store the optional connection field `damage` (f32, omitted when 0). The former `overload_ticks` is still accepted on load and ignored (treated as 0); it is never written. A negative or non-finite `damage` is rejected.

The blast rule is unchanged: a mortar/glue connection takes the minimum connection strength at the seam midpoint. Strengths, joint and contact settings are unchanged. Reproduce with `--diagnose-demo` (per-tick `FORCE` lines with r and damage before/after, `LIVE` lines at ticks 20 and 120), `--calibrate-mortar` and `--mortar-seeds`; the tests `demo_original_blast_remote_seams`, `force_rule_tip_block_breaks`, `force_rule_drop_block` and `mortar_seam_*` exercise the rule.

### Blast cover



Materials add effective metres per metre crossed: Stone (including floor) 3, Rubber 3, Wood 1.5, Glass 0.5. `blast_resistance` is optional in snapshots and defaults to zero for legacy files. Each blast captures posed cell polygons and original piece ownership before damage. Rays integrate polygon intersection lengths in cell-ID order, excluding the target's original piece; descendants inherit that exclusion. Cell, connection/mortar, impulse and initial Glass shock loads use the resulting effective distance. Impacts and mortar reaction checks keep their existing rules. Tangent boundary-only contact adds no length. The cover snapshot remains valid through the final structural/physics commit.





Blast-cover acceleration caches a per-cell positive-area shadow-overlap test, inherited by descendants. Remaining segments traverse a one-metre snapshot grid grouped by original owner; candidate cells are sorted by ID before the unchanged chord arithmetic. Packed snapshot/edge/grid storage and transaction scratch avoid per-ray allocations. Exact query memoization, geometric failure upper bounds and zero-load early termination preserve decisions. Newly uncovered cells may use farthest-point erasure proofs; the legacy extent-only reach heuristic is retained only where the previous cover implementation already admitted it, because expanding it changes survivor refinement. See the current report for both byte identity and ID-free fixture equivalence.



Generation within a blast also reuses failed partition results, uses stack storage for small width hulls, and uses a resettable arena for temporary partitions. Completed outlines are copied to their normal owner before reset. These operations retain the original sort, float arithmetic and primitive ordering; differential tests compare the resulting vertex bits. Larger polygon-query cache entries retain the full ordered float input to resolve hash collisions exactly.





## Layout-owned custom materials



`Layout.materials` owns up to four named custom recipes. The original ground Stone and four built-in Scene material records retain indices 0?4. Used custom entries append in palette order; unused customs stay in the layout file but do not add Scene records. Scene custom names have independent ownership, so a layout rename cannot invalidate the active World.



Layout JSON version 2 adds `materials`, with `name`, `base`, `toughness`, `blast_resistance`, RGB `color`, and the applicable `strip_thickness`, `shock_loss` or `flexibility`. Omitted knobs get base defaults. Bounds, names, base and object references are validated before replacing the layout. Rejected loads leave both layout and World intact. Material snapshot fields `strip_thickness` and `color` follow the optional `shock_loss` pattern: absence means the legacy thickness 0.3 and existing name-based colour. The final built-in Wood explicitly carries 0.2, which is serialized. Neither strengths nor failure rules changed.



Material follow-up: `Recipe` names the four families; authored palette references are `Slot` values. Each in-memory `Material` carries RGB explicitly and has a positive strip target only when `aspect_ratio < 1`; other materials use zero for the unused strip. Only snapshot encoding/decoding has the legacy name-colour mapping and missing grained-strip default 0.3. A strip field on a non-grained snapshot material is invalid. Custom Wood targets must be in [STRIP_MIN, 0.6], where STRIP_MIN = 2 * WOOD_MINIMUM_WIDTH = 0.2. Layout decoding rejects smaller targets without clamping. Generation rules are unchanged.


## Players and structure replication (multiplayer step 2a)

Everything here is offline: no sockets and no UI changes. Local play behaves as before.

**Players.** `World.players` holds up to `MAX_PLAYERS` (4) players, each with `active`, `blast_radius` and a runtime pose mirror. `world_add_player` and `world_remove_player` manage them; every player spawns at `PLAYER_SPAWN`. Players share a negative collision group, so they pass through each other and collide with everything else. `Tick_Commands.players[i]` carries move, jump, blasts and an optional radius for each active player; `bomb_radius` and `mode` are world-level. Blasts apply in player-index order, each player's blasts in order, using that player's radius. The local Sandbox sends the same radius to `players[0].radius` and `bomb_radius`. Poses of players and bombs are mirrored from their bodies after every physics step and after snapshot load; drawing reads the mirrors.

**Presentation reads only replicable state.** The draw paths (render cache, debug view, sandbox view, rubber band, glue view, mortar drawing, textures, editor view) make no Box2D calls. `Scene.anchor_y` is structural and `piece_anchored(scene, piece, anchor_y)` is the one anchoring rule used by physics and rendering.

**Replication.** Canonical structure is epoch, structure revision, anchor_y, full materials, cells (id, owner, material, frame, outline, rest_center), connections (id, a, b, mortar, glue samples) and pieces (id, material, cell ids in host order), sorted by id and encoded with the netcode codec (`canonical_encode`). The server (`Repl_Server`) keeps one structure index and, on any tick where `structure_revision` changed, emits one Delta against it; a rebuild (reset, layout load, snapshot load) bumps `Scene.epoch` and emits a Baseline. Messages over 200 KB are split into numbered parts that a replica applies atomically. A `Replica` is a physics-free Scene built only by `replica_apply_message`; it keeps its own per-piece render revisions and callers drop their render caches when `rebuilt` is set. Run the full checks with `scripts/bom.ps1 ReplicationSoak` (`--replication-soak [minutes]`); a two-minute variant runs in `scripts/bom.ps1 Test`.
