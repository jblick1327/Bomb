# Implementation



All game source and tests live together in [src/](../src/), in one Odin package. See [gameplay](gameplay.md) for current controls and defaults.



| File | Responsibility |

| --- | --- |

| [main.odin](../src/main.odin) | Playable entry point, smoke and soak modes |

| [model.odin](../src/model.odin) | Stable identity, owned outlines, packed live records, birth contexts, cached widths, memberships and group filtering |

| [render_cache.odin](../src/render_cache.odin) | Per-piece render topology, triangle indices and seam-neighbour caches |

| [rubber_band.odin](../src/rubber_band.odin) | Presentation-owned rest hulls, contact film and straight spans |

| [wood_generation.odin](../src/wood_generation.odin) | Grained creation/damage cuts, jagged seams and nearest-boundary blast sampling |

| [glass_shock.odin](../src/glass_shock.odin) | Transient pre-hit piece lineage, deterministic bond-path transport and one-wave shock failures |

| [blast_query.odin](../src/blast_query.odin) | Spatial blast/terrain candidates and pending child inclusion |

| [soak.odin](../src/soak.odin) | Headless longevity timings and deterministic comparison fixtures |

| [storage_test.odin](../src/storage_test.odin) | Reclamation, membership, query and physics-order regressions |

| [geometry.odin](../src/geometry.odin) | Shared boundaries, displaced cuts, convex hull and collision decomposition |

| [destruction.odin](../src/destruction.odin) | Seeded generation, blast evaluation and the shared structural update |

| [physics.odin](../src/physics.odin) | Box2D bodies, fixtures, weld joints, interaction aggregation and load policy |

| [state.odin](../src/state.odin) | State reader, snapshot validation, serialization and pose interpolation |

| [debug_view.odin](../src/debug_view.odin) | Shared scene rendering, picking and coordinate helpers |

| [player.odin](../src/player.odin) | Capsule controller, contact support, buffered jumps and respawn |

| [yard.odin](../src/yard.odin) | Yard creation/reset, shared settings, aim validation, input routing and the editor yard |

| [editor.odin](../src/editor.odin) | Authored rectangle list, fixed material palette, validation, deterministic construction and Test/Edit transitions |

| [editor_view.odin](../src/editor_view.odin) | Rectangle previews, material colors and editor pointer input |

| [editor_test.odin](../src/editor_test.odin) | Placement, material assignment, layout/reset independence, input consumption and rubber deformation/removal |

| [bombs.odin](../src/bombs.odin) | Falling-bomb mode, independent drop randomness, physics bodies, landing fuses and explosions |

| [sandbox_view.odin](../src/sandbox_view.odin) | Fixed camera, compact HUD, raygui panel and inspection input |

| [sandbox_smoke.odin](../src/sandbox_smoke.odin) | Hidden-window native input and widget playthrough |

| [behavior_test.odin](../src/behavior_test.odin) | Focused behavior and integration checks |

| [recursive_blast_test.odin](../src/recursive_blast_test.odin) | Same-blast termination, child contexts, conservative deletion and recursive agreement |

| [response_test.odin](../src/response_test.odin) | Contact response, rest support and joint immunity regressions |

| [generation_test.odin](../src/generation_test.odin) | Concave partition coverage, material patterns, partition coverage and distinct yard birth contexts |

| [ground_test.odin](../src/ground_test.odin) | Local floor refinement, anchored and detached ground, partition coverage and the sealed bottom |

| [sandbox_test.odin](../src/sandbox_test.odin) | Gravity stability, movement, debris contact, resets, settings and input consumption |

| [bombs_test.odin](../src/bombs_test.odin) | Real landing contacts, one-second fuses, blast integration, pause, mode switches and bomb cleanup |



IDs are monotonic and mapped to packed storage rows. After structural staging, inheritance and regrouping finish, one commit swap-removes dead regions, connections and pieces and deletes their map keys. Outlines are individually owned slices in a common undeformed reference frame, freed on removal. Rigid body handles live on pieces, flexible body handles on regions, and joint handles on connections and are excluded from JSON. `add_subdivision` copies its input; the caller retains ownership of that input allocation. Borrowed record/polygon views must not cross structural commits. `make_polygon` creates an owned polygon. See [live storage and the soak command](../README.md#live-storage).



Current subdivisions and connections exist when a piece is created. Non-grained objects and ground pre-split to the 1-unit maximum bounding dimension; Rubber retains its grid. Grained recipes instead thin to 0.3 and slant-cut strips longer than 2.0. Physics bodies are created after this construction resolves. Future geometry is generated on failure or by spatial reach refinement described below. `apply_failures` stages one generation for physics reactions and manual failures. `blast_pass` reuses that staging operation in a simple loop: evaluate the current geometry, replace failures, and evaluate new children and connections against the same blast until nothing else fails. Only then regroup affected pieces, filter connected groups and synchronize physics. A failed connection cannot be healed by proximity; only surviving old attachments are inherited. Failure IDs and groups use stable ordering, including when storage rows are shuffled. `discard_subdivisions` provides direct removal independently of a generative seed.



Each child receives its future seed context at birth, derived from its parent's context and child ordinal. Allocation IDs and later ownership changes do not affect that context. Non-grained recipes keep the sibling width/seed-zero guard. Grained cells retain their contexts while a long thin strip may still legally cross-cut; an actual failed cell with no valid children caches seed zero. Seed-zero geometry remains live until it fails. Connected-group width filtering remains a separate final step.



Before generating a failed outline, the blast can remove it directly when its farthest posed vertex proves every descendant will fail. This assumes partition-preserving generation, shared material strength, an unoccluded radial load and unchanged transforms during the event. The bound rounds distance outward with `nextafter`, uses a strict `1e-4` load margin and declines nonfinite inputs. Skipping a branch leaves other branches' seeds unchanged. `blast_pass(..., false)` disables the shortcut for correctness comparisons; normal play enables it.



Non-grained, non-triangulated generation clips shallow-concave parents directly, without logical convex decomposition. For each largest candidate it tries the recipe axis, then the other axis at the same seeded fraction. Both halves must be simple, preserve parent area, and meet the scene minimum width. An uncuttable candidate is left alone while other candidates are tried. Triangulated recipes retain deliberate triangles and check the final triangle widths too. The cutoff also applies during creation and reach refinement; a failed unpartitionable region still follows direct removal, while creation/reach retain it for their ordinary next decision. Strips preserve their long-axis rule. Collision decomposition remains separate from logical generation.



Chunks and cross-grain seams retain the midpoint tent. Along-grain seams insert alternating seeded displacements about every 0.25, capped at 0.03 and by clearance. Each seam path is installed identically on both sides after checking complete outlines for crossing/touching and minimum width; invalid bends get three amplitude halvings, then remain straight. Shards have no jitter. Triangulation uses size-relative tolerances, internally removes consecutive duplicate vertices and clips the largest convex turn if normal ear selection stalls, so it completes the cleaned polygon's n-2 triangles. Rendering no longer has its own duplicate cleanup.



For grained damage, thickness at least twice minimum width requests thinning along the current polygon's long axis, with no cross-grain fallback. Thinner cells may slant-cut only at length at least eight times thickness. A general half-plane clip places the cross-cut at the seeded 0.4-0.6 fraction, offset by opposite signed 0.75-thickness displacements on the long sides. All old area, simple-polygon and minimum-width guards remain. Connections own derived rest shared-boundary segments, freed on removal and recomputed on decode. Only grained connections use the closest posed point on these segments for blast load; other materials retain the midpoint sample. Strengths, blast falloff, impulses and contact damage are unchanged.



Physical damage now uses velocity change on the blast scale, multiplied by each material's `impact_scale`: Wood/Glass 1, Stone 1.6, Rubber 0, other constructed materials 1. The strongest contact interaction wins. Box2D 3.1.1 hit events are evaluated every step, including existing contacts, and supply pre-solve approach speed only for points with a confirmed impulse. Connected-piece polygon-area masses determine region collision ratios, while external actors use body mass and static partners count as infinite; static regions take no contact damage. No contact impulse/dt, torque lever arm or one-unit/s qualification remains. Weld reactions cause no damage; bonds break only from blasts. Impact-generated children keep inherited outside attachments but receive no sibling connections. Thresholds use `load > 0 && load >= strength`; strength records are never reduced by prior events. `physics_tick` accepts a replacement `Load_Calculator` function. See the [README load rule and drop table](../README.md#physics-damage).



Blast radius controls both reach and power: direct load is `10 * max(0, radius - distance)`, with zero load for nonpositive radii. The fixed global `BLAST_LOAD_MULTIPLIER` is 10; increasing radius increases load at a fixed distance, without a fixed maximum. For example, a sample 0.5 units away receives load 5 at radius 1 and load 25 at radius 3, enough to fail strength 20. At the default radius 5.0 and strengths 35 / 20, subdivision samples can fail within 1.5 units and connection samples within 3.0. Impulses are `direction * load * mass * 0.2`, applied through each final survivor's center once at its own sample. A surviving default-material region contributes an impulse corresponding to less than roughly 7 units/second of added speed; a rigid piece distributes those impulses into translation and rotation. Generated motion includes the parent's linear and angular motion; removed ancestors receive no blast impulse. New contact and joint reactions wait for the next solver step. Both tuning constants and the falloff live in `destruction.odin`. Global soft-joint damping is 0.7. Flexibility zero selects one rigid body per logical piece, with region-tagged shapes in its shared rest frame. Positive flexibility keeps one body per region and spring welds. Region-area-weighted blast impulses act at region centres on rigid bodies and can produce spin; flexible cells keep centre impulses.



Every `blast_pass` calls `refine_blast_reach`: every cell reached by the destructive core is refined down to the minimum width on all objects, then centre sampling and same-blast recursion resolve damage. Game and tests share this entry point; no separate yard refinement call remains. This is the selected A behavior; the temporary candidate switch and center-only alternative have been removed. An unsuccessful spatial split retains its original outline for the actual damage decision. An unpartitionable failed subdivision caches seed zero. Blasts delete it; impacts retain it unless it is at or below minimum width. Spatial-only refinement is not a failure, so its unrefinable set remains necessary. Refinement and damage share one structural event before final bodies and impulses. The optional physics support plane anchors connected pieces with a reference edge at the base, so subdivision alone does not introduce gravity loads into intact terrain. When a piece loses its last anchored connection, its existing bodies become dynamic with their logical mass and inertia. Logical links between anchored regions remain available to blast evaluation without creating unnecessary static-to-static solver constraints.



The bundled library is Box2D 3.1.1. Contact damage uses `World_GetContactEvents`, with hit events enabled on region fixtures and the event speed threshold zero. This avoids polling every body's contacts and avoids the installed binding's stale impulse-field names entirely; the old total-normal-impulse accessor is removed. The [3.1.1 hit-event pass](https://github.com/erincatto/box2d/blob/v3.1.1/src/solver.c) examines active contacts every step, independently of begin-contact events. Rigid bodies use exact outline mass and centre-of-mass inertia; Box2D 3.1.1's mass setter consumes COM inertia directly despite the installed binding's local-origin comment. After shape changes the collision extents are refreshed before overriding the mass. Shape user data maps contacts/queries to logical regions. On regroup the largest group keeps its body (ties by lowest region ID); other groups inherit its transform, point velocity at their COM, and angular velocity. The player still starts supported to avoid an artificial startup landing when entering Test.



Collision decomposition merges adjacent convex regions. Box2D can collapse microscopic ears during hull welding; those ears are omitted from fixtures, and a subdivision with no resolvable fixture receives a small bounding box proxy. The destruction outline, logical identity, polygon mass and inertia remain retained. Collision fixtures never become additional destruction entities.



Group width is the minimum projection width of its reference geometry's convex hull. Small subdivisions remain live when their connected group is wide enough. Narrow resulting groups vanish immediately. New groups are filtered before any new bodies are created. Rendering interpolates poses and optionally blends shared presentation vertices across flexible joints; it does not modify collision or failure geometry. Wood fill is opaque; Glass retains its transparency. For flexible pieces with the cosmetic surface enabled, live seams whose posed vertices differ by at most 0.001 world units share rendered points, including T junctions. Broken seams remain separate, and larger deformation retains the existing cosmetic blending.



The implementation uses ordinary packed arrays, affected-piece membership rebuilds, an endpoint-pair map, Box2D AABB blast queries and explicit snapshots. Pending children join spatial candidates before bodies exist. Render topology and seam-neighbour caches use each region's incident links and are invalidated by piece changes; frames transform cached vertices. Body/joint creation uses ascending IDs, and structure synchronization is gated by its internal revision. Full motion/load updates, picking and snapshot encoding still visit live state; they do not visit deleted history. Buffer capacity can retain a peak allocation for reuse.



## World and commands



`World` owns Scene, player, bombs, rain, settings, tick and derived base handle. `Layout` owns authored rectangles and their identity counter. `Sandbox` owns presentation and editor interaction, with explicit `world: World` and separate Layout fields (no `using` promotion). Input queues ordered blasts, settings and debug edits; only the first fixed step consumes them. Later steps receive move only. `world_tick` applies settings, debug edits and validated blasts, then the unchanged actor/physics/cleanup sequence. Its events drive bursts, notices and interpolation invalidation.



## Snapshots



V3 World snapshots add player and bomb motion and gameplay timers, the independent rain stream, settings and tick. `world_state.odin` rebuilds the engine bodies on load; `exact_json.odin` writes each f32 with `g`, precision -1, bit size 32, preserving signed zero. The legacy scene wire remains nested v2, and v1/v2 files still load as scene-only. Box2D solver/contact caches are derived and are not snapshotted; continuation drift is measured in `report.md`.



Scene snapshots carry current geometry, materials, stable IDs, piece memberships, future generation seeds, structural revision, and body motion. Version 2 retains each subdivision's birth seed context; version 1 snapshots still load using their original piece contexts. Widths, anchors and runtime piece mass are derived from the transmitted outlines. Materials are constructed through `make_material`, with impact_scale defaulting to 1. Infinite strengths have explicit flags so snapshots remain valid JSON. Material `impact_scale` is serialized as a number; its wire presence distinguishes Rubber's explicit zero from old snapshots without the field, which load with 1. Seeds never reconstruct existing damaged geometry.



Outlines use the cached endpoint-split render boundary in both surface modes. A per-edge flag hides exactly the portions covered by live bonded neighbours. Broken bonds remain visible even when another path keeps their regions in one piece. F3 bypasses the flags to inspect every region edge. Cache rebuilding follows piece topology changes and never modifies the simulation.



Rendering paints static fills before moving objects, so floor seals cannot cover darker resting glass. Glass is opaque RGB (86,153,174). Rendering draws all region fills and then 1 px fill-coloured seals along cached draw-flag edges, followed by a separate pass of all outline strokes. Together seams (same rigid piece, bonded flexible neighbours, or two static pieces) get no seal. Fractional positive outline widths use 1 px geometry and scaled alpha, avoiding dashed raster coverage; width zero omits only outlines. The equal-transform Box2D render-cache query is removed. No simulation geometry or snapshots change.



Editor follow-up: `editor_snap` applies integer rounding followed by f32 division by 10 only on mouse input. `layout_state.odin` validates authored bounds, identities, palette names, seed and next free identity into a temporary Layout. `layout_files.odin` provides the interactive-only save/autosave boundary; constructors and unit tests perform no runtime file I/O. `layout_view.odin` implements the modal panel and first-JSON drop selection. The four layout files in `src/presets/` are embedded by `presets.odin`.



Render caches belong to `Sandbox.render_caches`, outside World. `Render_Caches` maps cell IDs to owned `Render_Cache` values; its presentation state also owns static signature/revision and the last observed structure revision. At the start of drawing or measuring, `render_cache_prepass` recomputes the same static signature and prunes dead keys only when structure changes, then ensures every live cache. Later rendering only reads map entries, with no cache pointer retained across an insertion. World tick/build/load/explosion paths do no cache construction; structural commit and Scene destruction free simulation records only. Presentation cleanup independently releases the map and its allocations. Notice lifetime advances before the Edit/paused early return.



Glass has `shock_loss = 4`; the other palette materials and floor use zero. Optional snapshot fields preserve this value exactly; missing values default to zero, and disabled values are omitted so non-glass snapshots retain their bytes. The exact JSON writer understands optional union fields with `omitempty`.



Before a blast, shock captures each enabled piece's nearest rest point and initial radial load. An ephemeral lineage map follows its cells through spatial refinement, direct failures and provisional regrouping. After the normal direct recursion, surviving rim cells seed Dijkstra with their straight centroid distance from the source. Sorted IDs, incident bonds and a cost/ID heap make transport deterministic. Each cell receives the greatest load from its sources, losing `shock_loss` per metre of centroid-path travel. Shock failures take one generation, suppress sibling bonds, pass their load to children and then break qualifying live bonds. There is no shock recursion or additional impulse. Impact aggregation retains the strongest hit's actual Box2D point and load per failed cell; the same transport runs within that pre-impact piece. Both paths reuse the existing final regroup/commit. The hit sources and shock maps are released within the damage batch.



Rubber skin weights seed every live rest cell containing the point, then search live bonds within `SKIN_RADIUS`. Frontiers and the final weight list use cell-ID order; the weight formula and normalization are unchanged. Each rubber piece has a presentation band cached by its render revision. A monotone-chain rest hull retains contact segments on its edges and adds one straight segment per uncovered span. Drawing maps these endpoints through the already skinned cell outlines, retaining the old film colour, thickness and round joins. Interior holes and bite edges keep their ordinary fill seals but have no film. F3 region strokes remain independent; the V raw-body view retains the original per-cell film.



The render-only material tile, GLSL shader and rest-coordinate batching live in `src/material_texture.odin`; pixel checks are in `src/texture_checks.odin`. `src/ui_text.odin` owns the four font atlases, measuring/truncation, overflow counter, buttons and keycaps. Textures and fonts are released by `presentation_shutdown` before closing each graphics window. Layout decoding owns only authored objects and custom materials. Saving always writes canonical v3; v1/v2 input upgrades on save.

Authored_Shape stores an unrotated box, a degree angle, and Rect/Wedge. Polygon SAT and clipped intersection area handle overlap, while closest boundary points drive contact snapping. New rotated builds refine in the object frame before transforming their shared vertices to global rest space once; zero-angle rectangles retain the legacy path. Subsequent splits invert the float rotation matrix in double precision, preserve parent vertices exactly and transform each new shared cut vertex once. Subdivision.frame is serialized only when nonzero. Rubber grids retain uniform fitted cells; clipped slivers merge across their longest shared edge.

Glue links normalize authored identities and require polygon contact. The two directed sampled seams choose the smaller total length. Near-contact q is projected onto the other boundary, as clarified by the revised rule; otherwise the outward normal ray finds the fillet boundary. Samples are grouped by cell pair, inherited deterministically on split and owned by Connection. Glue uses the mortar seam geometry accessor, strength, blast threshold, weld lifecycle and force failure logic. Snapshot validation checks sample finiteness, positive weights, width and both boundary distances. The legacy scene writer uses a presence union at its optional frame field to preserve fixed-decimal snapshot bytes; World snapshots retain their existing exact encoder.

Flush glue rendering classifies samples in rest space; posed endpoint separation from small solver drift does not change the seam type. Consecutive flush midpoints are connected at mortar width, and half-weight tangent extensions close the ends of each cell-pair run. Singleton flush samples use a line segment. Fillet quad winding is evaluated once and emits two triangles once each. The diagnostic observer in seam_diagnostics.odin is inactive during normal simulation; it reports the existing force decisions without changing them. The original radius-4 demo blast creates legitimate transmitted overloads despite welded-pair collision already being disabled; the follow-up capture uses the separately documented radius-3 fixture under the fixture policy.
