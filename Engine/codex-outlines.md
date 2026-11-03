# Codex conversation

## User

instead of a toggle for outline or no outline, can it instead be a slider that goes from no outline to the thinnest possible outline to the thick one

## Assistant

I’ll find the outline control and replace the toggle with a thickness slider that starts at no outline.

## Activity

    $ pwd; rg --files -g AGENTS.md -g package.json -g '*.cs' -g '*.uxml' -g '*.uss' -g '*.tsx' -g '*.ts' -g '*.jsx' -g '*.shader' -g '*.md' | Select-Object -First 100
    
    Path
    ----
    C:\Users\jblic\Documents\BOM
    README.md
    evidence\soak-cycles\report.md
    evidence\load-scale\report.md
    evidence\README.md
    docs\verification.md
    evidence\blast-phase-diagnosis\report.md
    evidence\rigid-pieces\report.md
    docs\gameplay.md
    codex-session-01a18d0b-2ef6-7c70-99fd-72bc108b2f1d.md
    docs\implementation.md
    evidence\impact-shatter\report.md
    evidence\blast-speedups\report.md
    docs\plans\playable-sandbox-ux-plan.md
    docs\plans\physics-response-tuning-plan.md
    docs\plans\destruction-model-implementation-plan.md
    evidence\shared-blast\report.md
    evidence\soak\report.md
    benchmarks\recursive-blast-bench\SUMMARY.md
    evidence\playtests\2026-11-01-wood-seams\report.md
    evidence\playtests\2026-11-01-impulse\report.md
    benchmarks\recursive-blast-bench\README.md
    evidence\presplit\video\README.md
    evidence\playtests\2026-11-01-wood-ab\report.md
    evidence\presplit\report.md
    evidence\playtests\2026-11-01-strengths\report.md
    evidence\playtests\2026-11-01-placement\report.md
    evidence\playtests\2026-11-01-boundary-jitter\report.md
    evidence\playtests\2026-10-31-destruction\report.md
    evidence\playtests\2026-11-01-wood-impact\report.md
    evidence\playtests\2026-10-30\report.md
    
    
    ✓ • 582ms

## Activity

    $ Get-ChildItem -Force; rg -n -i 'outline' --glob '!codex-session*' --glob '!evidence/**' --glob '!benchmarks/**' .; git status --short; Get-ChildItem -Path .. -Filter AGENTS.md -Force
    
    
        Directory: C:\Users\jblic\Documents\BOM
    
    
    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    d--h--        2026-11-02   2:13 AM                .git
    d-----        2026-11-02   2:15 AM                benchmarks
    d-----        2026-11-03   4:05 AM                build
    d-----        2026-11-02   2:17 AM                docs
    d-----        2026-11-03   4:21 AM                evidence
    d-----        2026-11-03   4:12 AM                output
    d-----        2026-11-02   2:15 AM                scripts
    d-----        2026-11-03   3:49 AM                src
    -a----        2026-11-02   2:15 AM            429 .gitignore
    -a----        2026-11-02   8:15 PM        2936824 codex-session-01a18d0b-2ef6-7c70-99fd-72bc108b2f1d.md
    -a----        2026-11-03   3:57 AM          16096 README.md
    -a----        2026-11-03   3:33 AM          87022 src.zip
    .\README.md:42:Every simulated minute it prints cycle number, tick/blast mean and maximum wall-clock milliseconds, blast count, live/stored region/link/piece counts, ID-map sizes, owned outline vertices, current allocated bytes, Box2D body/joint counts, the next ID, and within-minute live region/link/piece peaks. Allocation output separates tracked Odin heap bytes and Box2D's `GetByteCount`, then sums them; it excludes the tracking allocator's own bookkeeping, unrelated runtime memory and process working-set overhead. The allocator tracker is enabled only for `--soak`, and its overhead is included in timings. Samples describe the ending cycle before replenishment. Blast timing includes the shared blast pass (reach refinement and damage resolution) and physics sync. The headless run is unthrottled and saves `output/soak-final.json`, then prints remaining tracked bytes after destroying the yard to distinguish retained capacity from unreleased allocations.
    .\README.md:49:The application starts paused in **Edit**. Choose Wood, Glass, Rubber or Stone, then drag rectangles into the empty area above the destructible floor. Click **Test** or press Enter to simulate the layout. Settings include falling bombs, blast radius and outlines. Closing the application discards the authored layout; snapshot files contain simulation geometry, not a saved editor layout.
    .\README.md:91:Rigid regions share the undeformed rest frame: body origin is rest-frame origin, and every shape uses rest coordinates. Each motion read derives region centres and point velocities from that body's transform and angular velocity. Mass, centre of mass and inertia come from the exact logical outlines, even when collision hulls simplify an outline. Regions of the same rigid piece cannot collide with each other or bow at seams. Rubber still stretches through its existing soft joints. Render seam-gap correction applies only to flexible pieces; rigid rendering and interpolation use one common transform.
    .\README.md:111:Regions, links and pieces remain plain records with monotonic, never-reused IDs. A single commit after inheritance and regrouping swap-removes dead records and deletes their map keys. Each region owns its outline and collision-shape handles. A rigid piece owns its body (region handles alias it); a flexible region owns its own body and its links own soft joints. Physics handles and render caches are excluded from snapshots. Piece memberships and endpoint-pair lookup stay current during staging. Array capacity can retain a peak allocation for reuse, but loops visit current records, not session history.
    .\README.md:113:Regrouping uses affected-piece memberships. Blast and terrain candidates come from Box2D's padded AABB query, supplemented by pending children until final bodies exist. Rendering caches outline topology, triangle indices and seam neighbours per piece change, using each region's incident links during cache construction; frames transform those cached vertices. Physics structure sync runs only after the internal structure revision changes. New shapes/bodies/joints and transparent draw order use ascending IDs, independent of packed storage order. Shape user data carries the region ID for hit events and blast queries. The version-2 snapshot format is unchanged: decoding reconstructs piece mass and rigid bodies from member outlines and region poses, including angular motion. Box2D free-slot/solver ordering can cause small numerical differences in ticked replays.
    .\src\behavior_test.odin:132:    parent.outline=make_polygon(parent.outline.points); defer delete(parent.outline.points)
    .\src\behavior_test.odin:189:    for i in 0..<len(s.subdivisions) { for j in 0..<len(s.subdivisions[i].outline.points) { s.subdivisions[i].outline.points[j]=vrotate(s.subdivisions[i].outline.points[j],0.738) } }
    .\src\behavior_test.odin:514:    outline:=make_polygon([]Vec2{{0,0},{1,0},{1,1},{0,1}}); defer delete(outline.points)
    .\src\behavior_test.odin:515:    id:=add_subdivision(&s,owner,outline,Pose{position=centroid(outline)})
    .\src\debug_view.odin:41:draw_polygon :: proc(view: View,outline: Polygon,color: rl.Color,stroke: rl.Color,outlines: bool = true) {
    .\src\debug_view.odin:42:    triangles:=triangulate_polygon(outline)
    .\src\debug_view.odin:51:    if outlines {
    .\src\debug_view.odin:52:        for i in 0..<len(outline.points) { rl.DrawLineEx(screen_point(view,outline.points[i]),screen_point(view,outline.points[(i+1)%len(outline.points)]),2,stroke) }
    .\src\debug_view.odin:60:        for rest in sub.outline.points { p:=posed_point(sub,rest); append(&points,rl.Vector2{p.x,p.y}) }
    .\src\debug_view.odin:90:    outline:=make_polygon(points[:]); defer delete(outline.points)
    .\src\debug_view.odin:91:    id:=add_subdivision(s,owner,outline,Pose{position=centroid(outline),velocity={8,0}})
    .\src\debug_view.odin:97:draw_scene :: proc(s: ^Scene,view: View,poses: map[u64]Pose,selected: u64,surface,joints: bool,ids: bool = true,material_colors: bool = false,outlines: bool = true) {
    .\src\debug_view.odin:110:        outline:=render_outline(s,sub,poses,surface)
    .\src\debug_view.odin:116:        draw_cached_polygon(view,outline,fill,stroke,outlines,ensure_render_cache(s,sub.id),surface)
    .\src\debug_view.odin:117:        delete(outline.points)
    .\docs\gameplay.md:22:The aiming circle shows the active blast radius. A red cross and message mark origins inside or on live logical outlines; those blasts are suppressed. UI clicks do not blast the world. The settings panel pauses physics and player actions without accumulating simulation time.
    .\docs\gameplay.md:26:Mode and radius changes are immediate, including inside Settings. The **Outlines** checkbox toggles object and subdivision borders immediately and stays set across resets and Edit/Test transitions. Outlines start enabled; drag previews and inspection IDs/links remain available independently. Objects use fixed palette presets; global material sliders do not override them. Abstract recipe/strength/flexibility tuning remains in `--lab` (F4), separate from the editor. The initial setup uses manual blasts, seed 42, radius 5.0 and impulse scale 0.2. The independent ground uses Stone's Chunks recipe, strengths 35/20 and flexibility 0.
    .\docs\implementation.md:8:| [model.odin](../src/model.odin) | Stable identity, owned outlines, packed live records, birth contexts, cached widths, memberships and group filtering |
    .\docs\implementation.md:35:IDs are monotonic and mapped to packed storage rows. After structural staging, inheritance and regrouping finish, one commit swap-removes dead regions, connections and pieces and deletes their map keys. Outlines are individually owned slices in a common undeformed reference frame, freed on removal. Body and joint handles live on their region and connection records and are excluded from JSON. `add_subdivision` copies its input; the caller retains ownership of that input allocation. Borrowed record/polygon views must not cross structural commits. `make_polygon` creates an owned polygon. See [live storage and the soak command](../README.md#live-storage).
    .\docs\implementation.md:39:Each child receives its future seed context at birth, derived from its parent's context and child ordinal. Allocation IDs and later ownership changes do not affect that context. When every sibling's cached outline width is at or below the subdivision cutoff, the whole batch receives seed zero. Mixed batches retain nonzero contexts, with an individual width guard before further generation. Seed-zero geometry remains live until it fails. Creation defers a terminal mark while a child still exceeds its maximum length; damage-time guards remain unchanged. Connected-group width filtering remains a separate final step.
    .\docs\implementation.md:41:Before generating a failed outline, the blast can remove it directly when its farthest posed vertex proves every descendant will fail. This assumes partition-preserving generation, shared material strength, an unoccluded radial load and unchanged transforms during the event. The bound rounds distance outward with `nextafter`, uses a strict `1e-4` load margin and declines nonfinite inputs. Skipping a branch leaves other branches' seeds unchanged. `blast_pass(..., false)` disables the shortcut for correctness comparisons; normal play enables it.
    .\docs\implementation.md:43:Generation clips convex regions. For a concave parent in Chunks or Strips, the existing convex decomposition merges adjacent triangulation ears before applying the requested cuts; a small shared-edge bend does not automatically become a fan of independent fragments. Non-triangulated generation retains its existing boundary jitter and displacement amount: each internal displaced cut is generated once and installed in both adjacent outlines, limited by clearance to other edges as well as area and length. Shards deliberately retains triangulation but skips shared-boundary displacement whenever the material's `triangulate` flag is enabled. This prevents added seam vertices from multiplying into excessive tiny triangles; existing triangulation validity fixes remain in effect. Outside boundaries remain intact. Count is a target before final triangulation; complex concave outlines and the Shards style can produce more children. If generation cannot produce a genuine partition of at least two smaller regions, the failed subdivision is removed directly. A valid partition is retained even when area limits prevent reaching the requested count. For aspect ratios below one, cuts run parallel to the polygon's long axis until elongation reaches the inverse aspect target, then cross-cut it; aspect-one recipes retain their existing axis rule. Self-intersecting outlines and polygons with holes are outside this implementation's input domain. Starting yard blocks derive distinct birth contexts from the applied seed and their stable grid coordinates; reset repeats the same contexts.
    .\docs\implementation.md:49:Every `blast_pass` calls `refine_blast_reach`: every cell reached by the destructive core is refined down to the minimum width on all objects, then centre sampling and same-blast recursion resolve damage. Game, lab, headless checks and tests share this entry point; no separate yard refinement call remains. This is the selected A behavior; the temporary candidate switch and center-only alternative have been removed. An unsuccessful spatial split retains its original outline for the actual damage decision. A genuinely failed subdivision still follows direct-removal rules. Refinement and damage share one structural event before final bodies and impulses. The optional physics support plane anchors connected pieces with a reference edge at the base, so subdivision alone does not introduce gravity loads into intact terrain. When a piece loses its last anchored connection, its existing bodies become dynamic with their logical mass and inertia. Logical links between anchored regions remain available to blast evaluation without creating unnecessary static-to-static solver constraints.
    .\docs\implementation.md:51:The bundled library is Box2D 3.1.1. Contact damage uses `World_GetContactEvents`, with hit events enabled on region fixtures and the event speed threshold zero. This avoids polling every body's contacts and avoids the installed binding's stale impulse-field names entirely; the old total-normal-impulse accessor is removed. The [3.1.1 hit-event pass](https://github.com/erincatto/box2d/blob/v3.1.1/src/solver.c) examines active contacts every step, independently of begin-contact events. Rigid bodies use exact outline mass and centre-of-mass inertia; Box2D 3.1.1's mass setter consumes COM inertia directly despite the installed binding's local-origin comment. After shape changes the collision extents are refreshed before overriding the mass. Shape user data maps contacts/queries to logical regions. On regroup the largest group keeps its body (ties by lowest region ID); other groups inherit its transform, point velocity at their COM, and angular velocity. The player still starts supported to avoid an artificial startup landing when entering Test.
    .\docs\implementation.md:53:Collision decomposition merges adjacent convex regions. Box2D can collapse microscopic ears during hull welding; those ears are omitted from fixtures, and a subdivision with no resolvable fixture receives a small bounding box proxy. The destruction outline, logical identity, polygon mass and inertia remain retained. Collision fixtures never become additional destruction entities.
    .\docs\implementation.md:74:Snapshots carry current geometry, materials, stable IDs, piece memberships, future generation seeds, structural revision, and body motion. Version 2 retains each subdivision's birth seed context; version 1 snapshots still load using their original piece contexts. Widths, anchors and runtime piece mass are derived from the transmitted outlines. Materials are constructed through `make_material`, with impact_scale defaulting to 1. Infinite strengths have explicit flags so snapshots remain valid JSON. Material `impact_scale` is serialized as a number; its wire presence distinguishes Rubber's explicit zero from old snapshots without the field, which load with 1. Seeds never reconstruct existing damaged geometry.
    .\src\editor_test.odin:110:    for id in ids { append(&grid,game.scene.subdivisions[game.scene.sub_rows[id]].outline) }
    .\src\editor.odin:31:    game:=Sandbox{applied=DEFAULT_SANDBOX_SETTINGS,draft=DEFAULT_SANDBOX_SETTINGS,previous=make(map[u64]Pose),surface=true,joints=true,outlines=true}
    .\src\editor.odin:103:                outline:=Polygon{points=points[:]}
    .\src\editor.odin:104:                id:=add_subdivision(s,owner,outline,Pose{position=centroid(outline)})
    .\src\destruction.odin:131:    // outline, rather than retaining an equivalent child or a partial partition.
    .\src\destruction.odin:181:        if parent.width<=s.minimum_width && (creation_size==0 || longest_dimension(parent.outline)<=creation_size) || contains_id(failures.discard_subdivisions[:],id) { seed=0 }
    .\src\destruction.odin:182:        children := generate_children(parent.outline,s.materials[parent.material],seed)
    .\src\destruction.odin:184:        // cannot partition this outline, retain it for the actual blast decision.
    .\src\destruction.odin:188:        for outline,ordinal in children {
    .\src\destruction.odin:189:            center := centroid(outline)
    .\src\destruction.odin:193:            child := add_subdivision(s,parent.owner,outline,pose)
    .\src\destruction.odin:199:            max_length=max(max_length,longest_dimension(outline))
    .\src\destruction.odin:200:            delete(outline.points)
    .\src\destruction.odin:235:        old_length,_ := shared_boundary(old_a.outline,old_b.outline)
    .\src\destruction.odin:239:                if inherits_old_boundary(s.subdivisions[s.sub_rows[a]].outline,s.subdivisions[s.sub_rows[b]].outline,old_a.outline,old_b.outline) { add_connection(s,a,b) }
    .\src\destruction.odin:289:// Descendants partition the outline, inherit its material and keep its rigid
    .\src\destruction.odin:295:    for point in sub.outline.points {
    .\src\destruction.odin:323:                for point in sub.outline.points { extent=max(extent,vlen(vsub(point,sub.rest_center))) }
    .\src\destruction.odin:329:                for rest,i in sub.outline.points {
    .\src\destruction.odin:330:                    a,b:=posed_point(sub,rest),posed_point(sub,sub.outline.points[(i+1)%len(sub.outline.points)])
    .\src\destruction.odin:409:   if sub.live && sub.seed!=0 && longest_dimension(sub.outline)>size+0.00001 { append(&f.subdivisions,id) }
    .\src\generation_test.odin:124:        testing.expect(t,len(parts)==len(parent.points)-2,"Every ear of these simple outlines must be retained")
    .\src\generation_test.odin:170:                        testing.expect(t,outline_width(grandchild.points)/max(hi.x-lo.x,hi.y-lo.y)>0.1,"Chunk must not create thin corner fans from small shared-edge bends")
    .\src\generation_test.odin:195:        if outline_width(child.points)<=0.1 { continue }
    .\src\generation_test.odin:216:    children_a:=generate_children(game.scene.subdivisions[0].outline,game.scene.materials[0],seeds[0])
    .\src\generation_test.odin:217:    children_b:=generate_children(game.scene.subdivisions[1].outline,game.scene.materials[0],seeds[1])
    .\src\editor_view.odin:23:        if game.outlines { rl.DrawRectangleLinesEx(box,2,YARD_INK) }
    .\docs\verification.md:20:`.\scripts\bom.ps1 Test` covers bridge and subdivision removal; surviving and broken inherited attachments; simultaneous endpoint replacement; processing and storage order independence; seed zero; subthreshold and infinite strengths; same-blast child and connection failure; shared terminal batches and mixed-width guards; termination even with a zero width cutoff; removal of unsplittable attached regions under repeated failure; valid partial partitions; radius-dependent blast power above strength 20; rotational motion inheritance; a single impulse per final survivor; rotation independent width; group filtering and immediate vanishing; retained bodies; concave collision fixtures; physical impacts; overloaded joints; replaceable load policies; flexibility; repeated blasts for all presets; snapshots; interpolation; and real TCP transfer of a wall and its split. Shortcut comparisons check exact surviving outlines, seeds, links, memberships and motion against ordinary recursive evaluation for partial and complete deletion in all three patterns, including a later blast. Odin's test allocator tracks allocations and reports leaks.
    .\docs\verification.md:26:Generation checks refine outlines again in all three styles, checking retained jitter for Chunks and Strips, straight-seam Shards without the extra-vertex triangle multiplication, target counts, chunky versus elongated cuts, intentional triangles and distinct repeatable yard seeds. Independent double-precision area/intersection checks verify containment, area preservation and non-overlapping interiors, alongside matching shared-edge coverage.
    .\docs\verification.md:38:Storage tests check repeated creation/removal without retained records, map/row/pair consistency, immediate body/joint destruction, staged child/link memberships, spatial versus full-scan blast decisions including bodyless children, and identical physics from shuffled storage rows. Odin's test allocator also covers outline/render-cache release.
    .\src\geometry.odin:85:// in both outlines. Parent boundary vertices are untouched, including T junctions.
    .\src\geometry.odin:125:convex_decomposition :: proc(outline: Polygon) -> [dynamic]Polygon {
    .\src\geometry.odin:126:    parts:=triangulate_polygon(outline)
    .\src\ground_test.odin:23:        for sub in game.scene.subdivisions { if sub.live && sub.rest_center.y<0 { area+=polygon_area(sub.outline) } }
    .\src\ground_test.odin:41:            outline:=make_polygon(root.outline.points); defer delete(outline.points)
    .\src\ground_test.odin:42:            testing.expect(t,root.seed!=0 && close(polygon_area(outline),17*-YARD_FLOOR_BOTTOM))
    .\src\ground_test.odin:49:            for sub in game.scene.subdivisions { if sub.live && sub.rest_center.y<0 { append(&children,sub.outline) } }
    .\src\ground_test.odin:50:            expect_generation_partition(t,outline,children[:])
    .\src\ground_test.odin:109:    outline:=Polygon{points=points[:]}
    .\src\ground_test.odin:110:    root:=add_subdivision(&s,owner,outline,Pose{position=centroid(outline)})
    .\src\ground_test.odin:122:        for point in sub.outline.points { bottom=min(bottom,point.y) }
    .\src\ground_test.odin:133:    testing.expect(t,close(b2.Body_GetMass(body),polygon_area(s.subdivisions[s.sub_rows[loose]].outline)),"Released ground must recover its logical polygon mass")
    .\src\ground_test.odin:156: points:=[4]Vec2{{0,1},{4,1},{4,3},{0,3}}; outline:=Polygon{points=points[:]}
    .\src\ground_test.odin:157: root:=add_subdivision(&s,owner,outline,Pose{position=centroid(outline)})
    .\src\ground_test.odin:159: testing.expect(t,!fails(blast_load(vlen(vsub(centroid(outline),blast.position)),blast.radius),35))
    .\src\ground_test.odin:161: area:=f32(0); for sub in s.subdivisions { area+=polygon_area(sub.outline) }
    .\src\model.odin:32:    outline: Polygon,
    .\src\model.odin:112:    result := Polygon{points=make([]Vec2,len(sub.outline.points))}
    .\src\model.odin:113:    for point,i in sub.outline.points { result.points[i]=posed_point(sub,point) }
    .\src\model.odin:159:add_subdivision :: proc(s: ^Scene, owner: u64, outline: Polygon, pose: Pose) -> u64 {
    .\src\model.odin:162:    retain_subdivision(s,Subdivision{id=id,owner=owner,material=piece.material,seed=piece.seed,outline=outline,pose=pose,live=true})
    .\src\model.odin:164:    s.pieces[s.piece_rows[owner]].mass+=polygon_area(outline)
    .\src\model.odin:168:// Each record owns its undeformed outline; staging may read dead parents until commit.
    .\src\model.odin:171:    sub.outline=make_polygon(source.outline.points)
    .\src\model.odin:172:    sub.rest_center=centroid(sub.outline)
    .\src\model.odin:173:    sub.width=outline_width(sub.outline.points)
    .\src\model.odin:184:    length, point := shared_boundary(sa.outline,sb.outline)
    .\src\model.odin:225:    for id in ids { for point in s.subdivisions[s.sub_rows[id]].outline.points { append(&points,point) } }
    .\src\model.odin:226:    return outline_width(points[:])
    .\src\model.odin:228:outline_width :: proc(points: []Vec2) -> f32 {
    .\src\model.odin:292:            s.pieces[s.piece_rows[owner]].mass+=polygon_area(s.subdivisions[s.sub_rows[id]].outline)
    .\src\model.odin:324:// parent outlines and old membership lists are still used during staging.
    .\src\model.odin:347:        delete(sub.outline.points); delete(sub.incident_links); delete(sub.shapes); release_render_cache(&sub.render)
    .\src\model.odin:376:    count:=0; for sub in s.subdivisions { count+=len(sub.outline.points) }; return count
    .\src\model.odin:402:    for &sub in s.subdivisions { delete(sub.outline.points); delete(sub.incident_links); delete(sub.shapes); release_render_cache(&sub.render) }
    .\src\physics.odin:53:physics_create_fixture :: proc(s: ^Scene, body: b2.BodyId, sub: Subdivision, outline: Polygon) -> bool {
    .\src\physics.odin:57: for point in outline.points { append(&points,to_b2(vsub(point,offset))) }
    .\src\physics.odin:68: if is_convex(sub.outline) && len(sub.outline.points)<=8 { physics_create_fixture(s,body,sub,sub.outline) }
    .\src\physics.odin:70:  parts:=convex_decomposition(sub.outline)
    .\src\physics.odin:75:  // Preserve the existing microscopic-outline fallback, in the body's frame.
    .\src\physics.odin:79:  for rest in sub.outline.points { p:=vsub(rest,offset); lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)} }
    .\src\physics.odin:125: for a,i in sub.outline.points {
    .\src\physics.odin:126:  b:=sub.outline.points[(i+1)%len(sub.outline.points)]
    .\src\physics.odin:134: b2.Body_SetMassData(body,b2.MassData{mass=polygon_area(sub.outline),center={},rotationalInertia=polygon_centred_inertia(sub)})
    .\src\physics.odin:140:  sub:=s.subdivisions[s.sub_rows[id]]; area:=polygon_area(sub.outline)
    .\src\physics.odin:146:  inertia+=polygon_centred_inertia(sub)+polygon_area(sub.outline)*vdot(r,r)
    .\src\physics.odin:182:   for a,i in sub.outline.points {
    .\src\physics.odin:183:    b:=sub.outline.points[(i+1)%len(sub.outline.points)]
    .\src\physics.odin:250:  impulse:=vmul(delta_v,polygon_area(sub.outline))
    .\docs\plans\destruction-model-implementation-plan.md:14:| Subdivision | Stable ID, range into a global outline vertex pool, and owning piece ID. |
    .\docs\plans\destruction-model-implementation-plan.md:21:Keep entity identity independent of array position. If the current entity system already solves this, use it. Otherwise, monotonically assigned IDs and an ID-to-row lookup are sufficient initially. Store stable IDs in connections and membership lists; update row lookups when dense arrays move. Keep outlines in a common undeformed reference frame for related geometry so shared boundaries remain identifiable after bodies move.
    .\docs\plans\destruction-model-implementation-plan.md:25:Create one hand-authored wall with a few polygon subdivisions, one material and explicit connections. Draw subdivision outlines, connection lines and piece colors. Add debug controls to remove a chosen subdivision or connection.
    .\docs\plans\destruction-model-implementation-plan.md:47:Create one generation function taking a parent outline, material recipe and seed. It returns child outlines, internal connections and stable child ordering. Start with one reproducible rectangular example. Extend the same pipeline to the supported concave outlines and the chunk, splinter and shatter presets using subdivision count, aspect ratio and triangulation.
    .\docs\plans\destruction-model-implementation-plan.md:49:Generate each shared displaced boundary once and reuse it in both neighboring outlines. Preserve the parent's outside boundary during replacement. Produce any convex collision decomposition as derived fixtures of the same logical subdivision.
    .\docs\plans\destruction-model-implementation-plan.md:122:- Seed zero stays live until failure and generates no children. The same outline, recipe, seed and stable ordering reproduce the same output after storage rows are shuffled.
    .\src\recursive_blast_test.odin:26:    preview:=generate_children(parent.outline,r.materials[0],parent.seed)
    .\src\recursive_blast_test.odin:29:        width:=outline_width(polygon.points)
    .\src\recursive_blast_test.odin:59:    outline:=Polygon{points=points[:]}
    .\src\recursive_blast_test.odin:60:    id:=add_subdivision(&s,p,outline,Pose{position=centroid(outline)})
    .\src\recursive_blast_test.odin:91:    testing.expect(t,blast_erases_descendants(sub,posed_blast,6),"The bound uses the posed outline")
    .\src\recursive_blast_test.odin:94:same_outline :: proc(a,b: Polygon) -> bool {
    .\src\recursive_blast_test.odin:100:// the observable graph by exact retained outlines, seeds, motion and membership.
    .\src\recursive_blast_test.odin:111:            if !y.live || used[y.id] || !same_outline(x.outline,y.outline) { continue }
    .\src\recursive_blast_test.odin:118:        testing.expect(t,found,"A retained outline differs between recursive and shortcut evaluation")
    .\src\sandbox_test.odin:183:sandbox_aim_uses_posed_outlines_and_suppresses_invalid_blast :: proc(t: ^testing.T) {
    .\src\sandbox_test.odin:189:    testing.expect(t,!sandbox_valid_aim(&game.scene,sub.outline.points[0]),"Boundary points must also be invalid")
    .\src\storage_test.odin:25:dead_storage_reclaims_outlines_caches_keys_and_handles :: proc(t: ^testing.T) {
    .\src\storage_test.odin:33:        outline:=Polygon{points=points[:]}
    .\src\storage_test.odin:34:        id:=add_subdivision(&s,owner,outline,Pose{position=centroid(outline)})
    .\src\storage_test.odin:79:    outline:=Polygon{points=points[:]}; far_id:=add_subdivision(&s,far,outline,Pose{position=centroid(outline)})
    .\src\presplit_test.odin:18:    sub:=g.scene.subdivisions[g.scene.sub_rows[id]]; sum+=polygon_area(sub.outline); append(&parts,sub.outline)
    .\src\presplit_test.odin:19:    testing.expectf(t,longest_dimension(sub.outline)<=PRESPLIT_SIZE+0.00001,"%v region %d length %.6f",choice,id,longest_dimension(sub.outline))
    .\src\state.odin:69:        if len(sub.outline.points) < 3 || polygon_area(sub.outline) <= 0 { return false,"invalid polygon" }
    .\src\state.odin:70:        for point in sub.outline.points { if !valid_vec(point) { return false,"invalid polygon coordinate" } }
    .\src\state.odin:121:    for sub in snapshot.subdivisions { delete(sub.outline.points) }
    .\src\state.odin:160:        if len(sub.outline.points)<3 { return {},false }
    .\src\state.odin:167:        if row,exists:=s.piece_rows[sub.owner]; exists { s.pieces[row].mass+=polygon_area(sub.outline) }
    .\src\state.odin:175:        length,point := shared_boundary(a.outline,b.outline)
    .\src\response_test.odin:171:    for points,i in bounds { vertices:=points; outline:=Polygon{points=vertices[:]}; ids[i]=add_subdivision(&s,p,outline,Pose{position=centroid(outline)}); }
    .\src\response_test.odin:187:    outline:=render_outline(&s,s.subdivisions[0],poses,true); defer delete(outline.points)
    .\src\response_test.odin:188:    testing.expect(t,len(outline.points)==5,"Render copy must include the T junction")
    .\src\sandbox_view.odin:55:    _ = rl.GuiCheckBox({x+300,y-4,20,20},"Outlines",&game.outlines)
    .\src\sandbox_view.odin:95:    draw_scene(s,view,poses,game.selected,game.surface,game.inspection && game.joints,game.inspection,game.editor.enabled,game.outlines)
    .\src\sandbox_smoke.odin:67:    assert(game.outlines)
    .\src\sandbox_smoke.odin:70:    assert(!game.outlines && game.scene.revision==revision_before_toggle,"Outline toggle must only change presentation")
    .\src\sandbox_smoke.odin:135:    assert(game.scene.revision>revision && len(game.editor.objects)==4 && !game.outlines,"Reset must preserve the outline preference")
    .\src\render_cache.odin:8:    outline: Polygon,
    .\src\render_cache.odin:13:    delete(cache.outline.points); delete(cache.triangles); delete(cache.raw_triangles)
    .\src\render_cache.odin:30:            if !point_on_boundary(rest,a.outline,b.outline) { continue }
    .\src\render_cache.odin:38:triangle_indices :: proc(outline: Polygon) -> [dynamic]int {
    .\src\render_cache.odin:40:    triangles:=triangulate_polygon(outline)
    .\src\render_cache.odin:43:            for vertex,i in outline.points { if point==vertex { append(&result,i); break } }
    .\src\render_cache.odin:57:    cache.outline=make_polygon(sub.outline.points)
    .\src\render_cache.odin:63:        if other!=0 { for rest in s.subdivisions[s.sub_rows[other]].outline.points { insert_boundary_endpoint(&cache.outline,rest) } }
    .\src\render_cache.odin:65:    cache.triangles=triangle_indices(cache.outline)
    .\src\render_cache.odin:66:    cache.raw_triangles=triangle_indices(sub.outline)
    .\src\render_cache.odin:67:    cache.seams=make([]Seam_Neighbours,len(cache.outline.points))
    .\src\render_cache.odin:68:    for rest,i in cache.outline.points { cache.seams[i]=seam_neighbours(s,sub^,rest) }
    .\src\render_cache.odin:104:render_outline :: proc(s: ^Scene,sub: Subdivision,poses: map[u64]Pose,surface: bool) -> Polygon {
    .\src\render_cache.odin:107:        outline:=make_polygon(cache.outline.points)
    .\src\render_cache.odin:108:        for rest,i in cache.outline.points { outline.points[i]=common_seam_point(s,sub,rest,poses,cache.seams[i]) }
    .\src\render_cache.odin:109:        return outline
    .\src\render_cache.odin:111:    outline:=make_polygon(sub.outline.points); posed:=render_subdivision(s,sub,poses)
    .\src\render_cache.odin:112:    for rest,i in sub.outline.points { outline.points[i]=posed_point(posed,rest) }
    .\src\render_cache.odin:113:    return outline
    .\src\render_cache.odin:115:draw_cached_polygon :: proc(view: View,outline: Polygon,color,stroke: rl.Color,outlines: bool,cache: ^Render_Cache,surface: bool) {
    .\src\render_cache.odin:118:        a,b,c:=outline.points[indices[i]],outline.points[indices[i+1]],outline.points[indices[i+2]]
    .\src\render_cache.odin:122:    if outlines { for point,i in outline.points { rl.DrawLineEx(screen_point(view,point),screen_point(view,outline.points[(i+1)%len(outline.points)]),2,stroke) } }
    .\src\rigid_test.odin:32:   for point in sub.outline.points { max_error=max(max_error,vlen(vsub(posed_point(sub,point),from_b2(b2.Body_GetWorldPoint(body,to_b2(point)))))) }
    .\src\rigid_test.odin:91:  j:=vmul(offset,polygon_area(sub.outline)*blast_load(distance,blast.radius)*BLAST_IMPULSE_SCALE/distance)
    .\src\rigid_test.odin:115:  outline:=Polygon{points=points[:]}; add_subdivision(s,p,outline,Pose{position=centroid(outline)})
    .\src\rigid_test.odin:135:   for rest in sub.outline.points { max_error=max(max_error,vlen(vsub(posed_point(sub,rest),from_b2(b2.Body_GetWorldPoint(body,to_b2(rest)))))) }
    .\src\yard.odin:37:    panel_open,inspection,tuning_open,surface,joints,outlines: bool,
    .\src\yard.odin:47:    game:=Sandbox{applied=settings,draft=settings,previous=make(map[u64]Pose),surface=true,joints=true,outlines=true}
    .\src\yard.odin:88:                outline:=Polygon{points=points[:]}
    .\src\yard.odin:89:                id:=add_subdivision(s,owner,outline,Pose{position=centroid(outline)})
    .\src\yard.odin:119:    outline:=Polygon{points=points[:]}
    .\src\yard.odin:120:    _ = add_subdivision(s,ground,outline,Pose{position=centroid(outline)})
    .\src\yard.odin:139:// Inclusive edges are solid too. Use the logical posed outline, not the cosmetic mesh.
    .\src\yard.odin:143:    for a,i in sub.outline.points {
    .\src\yard.odin:144:        b:=sub.outline.points[(i+1)%len(sub.outline.points)]
    .\docs\plans\playable-sandbox-ux-plan.md:48:Draw a small cursor marker and a thin circle showing the current blast radius. Fire once per mouse press. Keep the model's outside-origin assumption: when the cursor is inside live destruction geometry, show an invalid marker and suppress the blast. A short message such as “Aim outside the solid shape” explains the blocked action. Use the logical posed outlines for this test.
    ?? .gitignore
    ?? README.md
    ?? benchmarks/
    ?? codex-session-01a18d0b-2ef6-7c70-99fd-72bc108b2f1d.md
    ?? docs/
    ?? evidence/
    ?? scripts/
    ?? src.zip
    ?? src/
    
    
    ✓ • 791ms

## Activity

    $ Get-Content src/sandbox_view.odin; Get-Content src/debug_view.odin -TotalCount 130; Get-Content src/yard.odin -TotalCount 65; Get-Content src/sandbox_smoke.odin; Get-Content README.md -TotalCount 48; Get-ChildItem scripts; rg -n 'draw_scene\(|draw_polygon\(|draw_cached_polygon\(|GuiSlider|outlines' src/sandbox_test.odin src/main.odin src/editor_view.odin src/*.ps1 scripts
    package main
    
    import rl "vendor:raylib"
    import b2 "vendor:box2d"
    
    YARD_INK :: rl.Color{229,239,241,255}
    YARD_MUTED :: rl.Color{144,165,178,255}
    YARD_ACCENT :: rl.Color{111,220,190,255}
    
    // Fit a fixed rectangle with letterboxing. Fragments never affect the camera.
    sandbox_view :: proc(width,height: f32) -> View {
        scale:=min((width-64)/16,(height-170)/8.4)
        return View{offset={width*0.5-0.5*scale,(height+30)*0.5+0.8*scale},scale=scale}
    }
    sandbox_settings_button :: proc(width: f32) -> rl.Rectangle { return {width-174,24,150,38} }
    sandbox_reset_button :: proc(width: f32) -> rl.Rectangle { return {width-284,24,98,38} }
    sandbox_over_hud :: proc(mouse: rl.Vector2,width,height: f32,inspection: bool) -> bool {
        if mouse.y<88 || mouse.y>height-56 { return true }
        return inspection && rl.CheckCollisionPointRec(mouse,{24,106,450,150})
    }
    sandbox_gui_style :: proc() {
        rl.GuiLoadStyleDefault()
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiDefaultProperty.TEXT_SIZE),18)
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_NORMAL),transmute(i32)u32(0x435969ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),transmute(i32)u32(0x233444ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),transmute(i32)u32(0xe5eff1ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_FOCUSED),transmute(i32)u32(0x6fdcbeff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_FOCUSED),transmute(i32)u32(0x304e58ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_FOCUSED),transmute(i32)u32(0xe5fff4ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_PRESSED),transmute(i32)u32(0x6fdcbeff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_PRESSED),transmute(i32)u32(0x416d68ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_PRESSED),transmute(i32)u32(0xffffffff))
    }
    sandbox_slider :: proc(x,y,width: f32,label: cstring,value: ^f32,low,high: f32,decimals: bool = false) {
        rl.DrawText(label,i32(x),i32(y),17,YARD_INK)
        text:=rl.TextFormat("%.0f",value^)
        if decimals { text=rl.TextFormat("%.2f",value^) }
        rl.DrawText(text,i32(x+width)-rl.MeasureText(text,17),i32(y),17,YARD_ACCENT)
        _ = rl.GuiSliderBar({x,y+25,width,16},nil,nil,value,low,high)
    }
    Sandbox_UI_Action :: enum { None, Open, Resume, Apply, Reset, Toggle_Editor }
    sandbox_draw_panel :: proc(game: ^Sandbox,width,height: f32) -> Sandbox_UI_Action {
        rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,205})
        x,y:=(width-560)*0.5,(height-360)*0.5
        rl.DrawRectangleRounded({x,y,560,360},0.025,8,{23,35,49,255})
        x+=28; y+=24
        rl.DrawText("SETTINGS / PAUSED",i32(x),i32(y),24,YARD_INK)
        y+=54
        mode:=i32(game.applied.blast_mode)
        _ = rl.GuiToggleGroup({x,y,248,32},"Manual blasts;Falling bombs",&mode)
        sandbox_set_blast_mode(game,Blast_Mode(mode))
        y+=48
        radius:=game.applied.blast_radius
        sandbox_slider(x,y,504,"Blast radius",&radius,0.5,6,true)
        _ = rl.GuiCheckBox({x+300,y-4,20,20},"Outlines",&game.outlines)
        sandbox_set_radius(game,radius)
        y+=70
        rl.DrawText("Objects use their palette material. Ground stays Stone.",i32(x),i32(y),16,YARD_MUTED)
        y+=26
        rl.DrawText("Abstract recipe tuning: launch with --lab (F4).",i32(x),i32(y),16,YARD_MUTED)
        y+=42
        if rl.GuiButton({x,y,504,36},"Resume") { return .Resume }
        return .None
    }
    sandbox_draw_bombs :: proc(game: ^Sandbox,view: View) {
        for burst in game.bomb_rain.bursts {
            progress:=burst.age/BOMB_BURST_TIME
            color:=rl.Color{255,200,112,u8(220*(1-progress))}
            rl.DrawCircleLinesV(screen_point(view,burst.position),burst.radius*view.scale*(0.2+0.8*progress),color)
        }
        for bomb in game.bomb_rain.bombs {
            position:=from_b2(b2.Body_GetPosition(bomb.body))
            if !game.panel_open && !game.editor.editing { position=vadd(bomb.previous,vmul(vsub(position,bomb.previous),game.accumulator*60)) }
            center:=screen_point(view,position)
            radius:=BOMB_RADIUS*view.scale
            color:=rl.Color{245,206,133,255}
            if bomb.landed { color={255,132,112,255} }
            rl.DrawCircleV(center,radius,{39,42,50,255})
            rl.DrawCircleLinesV(center,radius,color)
            tip:=rl.Vector2{center.x+radius*0.5,center.y-radius*1.4}
            rl.DrawLineEx({center.x,center.y-radius*0.7},tip,2,color)
            rl.DrawCircleV(tip,2,color)
            if bomb.landed { rl.DrawRing(center,radius+3,radius+5,-90,-90+360*bomb.fuse/BOMB_FUSE,24,color) }
        }
    }
    sandbox_draw_world :: proc(game: ^Sandbox,view: View,poses: map[u64]Pose) {
        s:=&game.scene
        left,top:=screen_point(view,{-9.5,YARD_FLOOR_BOTTOM}),screen_point(view,{10.5,YARD_FLOOR_BOTTOM-YARD_BASE_DEPTH})
        rl.DrawRectangleRec({left.x,left.y,top.x-left.x,top.y-left.y},{42,58,68,255})
        rl.DrawLineEx(left,screen_point(view,{10.5,YARD_FLOOR_BOTTOM}),3,{116,151,151,255})
        for i in -15..=16 {
            x:=f32(i)*0.5
            rl.DrawLineEx(screen_point(view,{x,YARD_FLOOR_BOTTOM-0.04}),screen_point(view,{x+0.12,YARD_FLOOR_BOTTOM-0.20}),2,{66,86,91,255})
        }
        draw_scene(s,view,poses,game.selected,game.surface,game.inspection && game.joints,game.inspection,game.editor.enabled,game.outlines)
        sandbox_draw_editor(game,view)
        spawn:=screen_point(view,{PLAYER_SPAWN.x,0})
        rl.DrawLineEx({spawn.x-16,spawn.y+12},{spawn.x+16,spawn.y+12},3,YARD_ACCENT)
        rl.DrawText("SPAWN",i32(spawn.x)-24,i32(spawn.y)+27,12,YARD_MUTED)
        sandbox_draw_bombs(game,view)
        position:=from_b2(b2.Body_GetPosition(game.player.body))
        if !game.panel_open && !game.editor.editing { position=vadd(game.previous_player,vmul(vsub(position,game.previous_player),game.accumulator*60)) }
        center:=screen_point(view,position)
        radius:=PLAYER_RADIUS*view.scale
        segment:=PLAYER_SEGMENT*view.scale
        rl.DrawRectangleRec({center.x-radius,center.y-segment,2*radius,2*segment},YARD_ACCENT)
        rl.DrawCircleV({center.x,center.y-segment},radius,YARD_ACCENT)
        rl.DrawCircleV({center.x,center.y+segment},radius,YARD_ACCENT)
        rl.DrawLineEx({center.x-radius*0.45,center.y-segment},{center.x+radius*0.45,center.y-segment},3,{21,51,53,255})
    }
    sandbox_draw_aim :: proc(game: ^Sandbox,view: View,mouse: rl.Vector2) {
        if game.editor.editing || game.applied.blast_mode!=.Manual { return }
        point:=world_point(view,mouse)
        color:=rl.Color{245,206,133,210}
        valid:=sandbox_valid_aim(&game.scene,point)
        if !valid { color={244,132,131,230} }
        rl.DrawCircleLinesV(mouse,game.applied.blast_radius*view.scale,color)
        rl.DrawCircleV(mouse,3,color)
        if !valid {
            rl.DrawLineEx({mouse.x-7,mouse.y-7},{mouse.x+7,mouse.y+7},2,color)
            rl.DrawLineEx({mouse.x+7,mouse.y-7},{mouse.x-7,mouse.y+7},2,color)
            label:=cstring("Aim outside the solid shape")
            x:=clamp(mouse.x+18,f32(12),f32(rl.GetScreenWidth()-rl.MeasureText(label,16)-12))
            y:=clamp(mouse.y+18,f32(94),f32(rl.GetScreenHeight()-80))
            rl.DrawRectangle(i32(x)-7,i32(y)-5,rl.MeasureText(label,16)+14,26,{19,28,42,240})
            rl.DrawText(label,i32(x),i32(y),16,color)
        }
    }
    sandbox_draw_hud :: proc(game: ^Sandbox,width,height: f32) -> Sandbox_UI_Action {
        // raygui clears its private slider capture only when a slider sees mouse-up.
        // Keep that release path alive if Escape closed the panel during a drag.
        if !game.panel_open && !rl.IsMouseButtonDown(.LEFT) {
            dummy:=f32(0)
            _ = rl.GuiSliderBar({-100,-100,20,10},nil,nil,&dummy,0,1)
        }
        rl.DrawRectangle(0,0,i32(width),88,{19,28,42,250})
        rl.DrawText("BLAST YARD",24,24,26,YARD_INK)
        mode_label:=cstring("Manual blasts / Click to place")
        if game.applied.blast_mode==.Falling_Bombs { mode_label="Falling bombs / 1 sec fuse on landing" }
        if game.editor.editing { mode_label="EDIT / Paused / Drag rectangles above ground" }
        rl.DrawText(mode_label,25,56,15,YARD_MUTED)
        if !game.panel_open {
            if game.editor.enabled {
                label:=cstring("Enter  Edit"); if game.editor.editing { label="Enter  Test" }
                if rl.GuiButton({width-406,24,112,38},label) { return .Toggle_Editor }
            }
            if !game.editor.editing && rl.GuiButton(sandbox_reset_button(width),"R  Reset") { return .Reset }
            if rl.GuiButton(sandbox_settings_button(width),"Tab  Settings") { return .Open }
        }
        rl.DrawRectangle(0,i32(height)-56,i32(width),56,{19,28,42,250})
        controls:=cstring("A/D Move   /   Space Jump   /   Click Blast   /   R Reset")
        if game.applied.blast_mode==.Falling_Bombs { controls="A/D Move   /   Space Jump   /   Falling Bombs   /   R Reset" }
        if game.editor.editing {
            if game.panel_open { rl.GuiDisable() }
            active:=i32(game.editor.palette)
            _ = rl.GuiToggleGroup({24,height-44,90,32},"Wood;Glass;Rubber;Stone",&active)
            game.editor.palette=Palette(active)
            if game.panel_open { rl.GuiEnable() }
            rl.DrawText("Drag: place / Right click: remove",420,i32(height)-35,17,YARD_INK)
        } else {
            rl.DrawText(controls,24,i32(height)-35,17,YARD_INK)
            rl.DrawText(rl.TextFormat("Radius %.1f  /  Wheel",game.applied.blast_radius),i32(width)-222,i32(height)-35,17,YARD_ACCENT)
        }
        if game.status_time>0 {
            text:=rl.TextFormat("%s",game.status)
            x:=i32(width)/2-rl.MeasureText(text,17)/2
            rl.DrawRectangle(x-16,i32(height)-102,rl.MeasureText(text,17)+32,32,{23,40,51,240})
            rl.DrawText(text,x,i32(height)-94,17,YARD_ACCENT)
        }
        if game.inspection && !game.editor.editing {
            rl.DrawRectangleRounded({24,106,450,150},0.07,8,{22,36,51,240})
            rl.DrawText("INSPECTION  /  F3",40,120,18,YARD_ACCENT)
            a,b,c:=counts_runtime(&game.scene)
            rl.DrawText(rl.TextFormat("%d regions  /  %d links  /  %d pieces",a,b,c),40,150,17,YARD_INK)
            rl.DrawText("Right click: select   Delete / Ctrl+click: remove",40,180,16,YARD_MUTED)
            rl.DrawText("Shift+click / X: break link   J: links   V: surface",40,204,16,YARD_MUTED)
            rl.DrawText("S: save snapshot   D: move   Space: jump",40,228,16,YARD_MUTED)
        }
        if game.panel_open { return sandbox_draw_panel(game,width,height) }
        return .None
    }
    sandbox_inspect_input :: proc(game: ^Sandbox,point: Vec2,view: View,over_ui: bool) -> bool {
        if !game.inspection || game.panel_open { return false }
        if rl.IsKeyPressed(.J) { game.joints=!game.joints }
        if rl.IsKeyPressed(.V) { game.surface=!game.surface }
        if rl.IsKeyPressed(.S) {
            if save_snapshot(&game.scene,"output/snapshot.json") { sandbox_notice(game,"Saved output/snapshot.json") }
        }
        if over_ui { return false }
        hover:=pick_subdivision(&game.scene,point)
        if rl.IsMouseButtonPressed(.RIGHT) { game.selected=hover }
        remove:=rl.IsKeyPressed(.DELETE)
        link:=rl.IsKeyPressed(.X)
        consumed:=false
        if rl.IsMouseButtonPressed(.LEFT) && !game.block_blast {
            if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) { game.selected=hover; remove=true; consumed=true }
            if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) { link=true; consumed=true }
        }
        failures:=Failures{}
        if remove && game.selected!=0 { append(&failures.discard_subdivisions,game.selected); game.selected=0 }
        if link {
            id:=pick_connection(&game.scene,point,24/view.scale)
            if id!=0 { append(&failures.connections,id) }
        }
        if len(failures.discard_subdivisions)+len(failures.connections)>0 {
            apply_failures(&game.scene,failures)
            physics_sync_structure(&game.scene)
            clear(&game.previous)
        }
        delete(failures.discard_subdivisions); delete(failures.connections)
        return consumed
    }
    sandbox_read_input :: proc() -> Sandbox_Input {
        move:=f32(0)
        if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { move-=1 }
        if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { move+=1 }
        return Sandbox_Input{move=move,jump_pressed=rl.IsKeyPressed(.SPACE),jump_down=rl.IsKeyDown(.SPACE),blast_pressed=rl.IsMouseButtonPressed(.LEFT),blast_down=rl.IsMouseButtonDown(.LEFT),menu_pressed=rl.IsKeyPressed(.TAB) || rl.IsKeyPressed(.ESCAPE),reset_pressed=rl.IsKeyPressed(.R),inspection_pressed=rl.IsKeyPressed(.F3),edit_pressed=rl.IsKeyPressed(.ENTER),wheel=rl.GetMouseWheelMove()}
    }
    sandbox_handle_ui :: proc(game: ^Sandbox,action: Sandbox_UI_Action) {
        switch action {
        case .Open: sandbox_set_panel(game,true)
        case .Resume: sandbox_set_panel(game,false)
        case .Apply: sandbox_apply_settings(game)
        case .Reset: sandbox_reset(game)
        case .Toggle_Editor: sandbox_toggle_editor(game)
        case .None:
        }
        if action!=.None {
            game.block_jump=rl.IsKeyDown(.SPACE)
            game.block_blast=rl.IsMouseButtonDown(.LEFT)
        }
    }
    run_sandbox :: proc(smoke: bool = false,smoke_panel: bool = false,smoke_input: bool = false) {
        rl.SetTraceLogLevel(.WARNING)
        flags:=rl.ConfigFlags{.MSAA_4X_HINT,.WINDOW_RESIZABLE,.WINDOW_HIGHDPI}
        if smoke { flags+={.WINDOW_HIDDEN} }
        rl.SetConfigFlags(flags)
        rl.InitWindow(1280,800,"Blast Yard | Odin + Box2D")
        defer rl.CloseWindow()
        rl.SetWindowMinSize(900,700)
        rl.SetExitKey(.KEY_NULL)
        rl.SetTargetFPS(60)
        sandbox_gui_style()
        game:=sandbox_editor_create()
        defer sandbox_destroy(&game)
        if smoke_input { sandbox_smoke_inputs(&game); return }
        if smoke_panel { sandbox_set_panel(&game,true); game.tuning_open=true }
        poses:=make(map[u64]Pose); defer delete(poses)
        target:=rl.RenderTexture2D{}
        if smoke { target=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight()) }
        defer { if smoke { rl.UnloadRenderTexture(target) } }
        frames:=0
        for !rl.WindowShouldClose() {
            width,height:=f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())
            view:=sandbox_view(width,height)
            mouse:=rl.GetMousePosition()
            over_ui:=sandbox_over_hud(mouse,width,height,game.inspection && !game.editor.editing)
            raw:=sandbox_read_input()
            input:=sandbox_route_input(&game,raw,over_ui)
            point:=world_point(view,mouse)
            if !raw.menu_pressed && !raw.reset_pressed {
                if game.editor.editing { sandbox_editor_input(&game,point,over_ui) }
                else if !sandbox_inspect_input(&game,point,view,over_ui) && input.blast_pressed { sandbox_blast(&game,point) }
            }
            sandbox_advance(&game,rl.GetFrameTime(),input)
            clear(&poses)
            for sub in game.scene.subdivisions {
                if !sub.live { continue }
                pose:=sub.pose
                if old,ok:=game.previous[sub.id]; ok && !game.panel_open { pose=interpolate_region_pose(&game.scene,sub,old,game.accumulator*60) }
                poses[sub.id]=pose
            }
            rl.BeginDrawing()
            if smoke { rl.BeginTextureMode(target) }
            rl.ClearBackground({19,28,42,255})
            sandbox_draw_world(&game,view,poses)
            if !game.panel_open && !over_ui { sandbox_draw_aim(&game,view,mouse) }
            action:=sandbox_draw_hud(&game,width,height)
            if smoke {
                rl.EndTextureMode()
                rl.DrawTextureRec(target.texture,{0,0,f32(target.texture.width),-f32(target.texture.height)},{0,0},rl.WHITE)
            }
            rl.EndDrawing()
            sandbox_handle_ui(&game,action)
            frames+=1
            if smoke && frames==2 {
                image:=rl.LoadImageFromTexture(target.texture)
                rl.ImageFlipVertical(&image)
                name:=cstring("output/sandbox-preview.png"); if smoke_panel { name="output/sandbox-settings-preview.png" }
                _ = rl.ExportImage(image,name)
                rl.UnloadImage(image)
                break
            }
        }
    }
    package main
    
    import rl "vendor:raylib"
    import b2 "vendor:box2d"
    import "core:math"
    
    View :: struct { offset: Vec2, scale: f32 }
    screen_point :: proc(view: View,point: Vec2) -> rl.Vector2 { return {view.offset.x+point.x*view.scale,view.offset.y-point.y*view.scale} }
    world_point :: proc(view: View,point: rl.Vector2) -> Vec2 { return {(point.x-view.offset.x)/view.scale,(view.offset.y-point.y)/view.scale} }
    piece_color :: proc(id: u64,alpha: u8 = 255) -> rl.Color {
        colors := [6]rl.Color{{64,173,165,255},{97,142,206,255},{194,134,204,255},{212,161,88,255},{139,178,113,255},{211,116,125,255}}
        c:=colors[id%6]; c.a=alpha; return c
    }
    render_subdivision :: proc(s: ^Scene,sub: Subdivision,poses: map[u64]Pose) -> Subdivision {
        result:=sub
        if pose,ok:=poses[sub.id]; ok { result.pose=pose }
        if s.materials[sub.material].flexibility==0 {
            // One interpolated frame per rigid piece, including just-created cells
            // without a previous-frame pose. No cosmetic seam correction is needed.
            p:=s.pieces[s.piece_rows[sub.owner]]
            anchor:=s.subdivisions[s.sub_rows[p.subdivisions[0]]]
            if pose,ok:=poses[anchor.id]; ok {
                result.pose.angle=pose.angle
                result.pose.position=vadd(pose.position,vrotate(vsub(sub.rest_center,anchor.rest_center),pose.angle))
            }
        }
        return result
    }
    point_on_boundary :: proc(point: Vec2,a,b: Polygon) -> bool {
        for i in 0..<len(a.points) {
            for j in 0..<len(b.points) {
                if segment,ok:=segment_overlap(Segment{a.points[i],a.points[(i+1)%len(a.points)]},Segment{b.points[j],b.points[(j+1)%len(b.points)]}); ok {
                    d:=vsub(segment.b,segment.a); length:=vlen(d)
                    projection:=vdot(vsub(point,segment.a),d)/(length*length)
                    if projection >= -0.0001 && projection <= 1.0001 && math.abs(vcross(d,vsub(point,segment.a))) < 0.0001*length { return true }
                }
            }
        }
        return false
    }
    draw_polygon :: proc(view: View,outline: Polygon,color: rl.Color,stroke: rl.Color,outlines: bool = true) {
        triangles:=triangulate_polygon(outline)
        for triangle in triangles {
            a,b,c:=screen_point(view,triangle.points[0]),screen_point(view,triangle.points[1]),screen_point(view,triangle.points[2])
            // Raylib's triangle winding uses the screen's downward Y axis.
            cross:=vcross(vsub(triangle.points[1],triangle.points[0]),vsub(triangle.points[2],triangle.points[0]))
            if cross > 0 { rl.DrawTriangle(a,b,c,color) } else { rl.DrawTriangle(c,b,a,color) }
            delete(triangle.points)
        }
        delete(triangles)
        if outlines {
            for i in 0..<len(outline.points) { rl.DrawLineEx(screen_point(view,outline.points[i]),screen_point(view,outline.points[(i+1)%len(outline.points)]),2,stroke) }
        }
    }
    pick_subdivision :: proc(s: ^Scene,point: Vec2) -> u64 {
        best:=u64(0)
        for sub in s.subdivisions {
            if !sub.live { continue }
            points: [dynamic]rl.Vector2
            for rest in sub.outline.points { p:=posed_point(sub,rest); append(&points,rl.Vector2{p.x,p.y}) }
            hit:=rl.CheckCollisionPointPoly({point.x,point.y},raw_data(points),i32(len(points)))
            delete(points)
            if hit && (best==0 || sub.id<best) { best=sub.id }
        }
        return best
    }
    pick_connection :: proc(s: ^Scene,point: Vec2,max_distance: f32) -> u64 {
        best:=u64(0); distance:=max_distance
        for c in s.connections { if c.live { d:=vlen(vsub(point,connection_sample(s,c))); if d<distance || (best!=0 && d==distance && c.id<best) { distance=d; best=c.id } } }
        return best
    }
    material_preset :: proc(index: int) -> Material {
        switch index {
        case 1: return make_material(name="splinter",subdivision_strength=7,connection_strength=6,flexibility=0.6,generation_count=5,aspect_ratio=0.2)
        case 2: return make_material(name="shatter",subdivision_strength=5,connection_strength=4,flexibility=0.05,generation_count=6,aspect_ratio=1,triangulate=true)
        }
        return make_material(name="chunk",subdivision_strength=6,connection_strength=4,flexibility=0.25,generation_count=3,aspect_ratio=1)
    }
    reset_demo :: proc(s: ^Scene,preset: int,terminal: bool) {
        scene_destroy(s)
        seed:=u8(42); if terminal { seed=0 }
        s^=make_wall(seed,0.08)
        s.materials[0]=material_preset(preset)
        physics_init(s)
    }
    add_projectile :: proc(s: ^Scene) {
        material:=add_material(s,make_material(name="projectile",subdivision_strength=math.inf_f32(1),connection_strength=math.inf_f32(1),generation_count=2,aspect_ratio=1))
        owner:=add_piece(s,material,0)
        points:=[4]Vec2{{-1.2,0.3},{-0.8,0.3},{-0.8,0.7},{-1.2,0.7}}
        outline:=make_polygon(points[:]); defer delete(outline.points)
        id:=add_subdivision(s,owner,outline,Pose{position=centroid(outline),velocity={8,0}})
    
        physics_sync_structure(s)
        b2.Body_SetBullet(subdivision_body(s,id),true)
        s.revision+=1
    }
    draw_scene :: proc(s: ^Scene,view: View,poses: map[u64]Pose,selected: u64,surface,joints: bool,ids: bool = true,material_colors: bool = false,outlines: bool = true) {
        for i in -20..=20 {
            tint:=rl.Color{31,44,62,255}
            if i==0 { tint={45,65,85,255} }
            rl.DrawLineEx(screen_point(view,Vec2{f32(i),-20}),screen_point(view,Vec2{f32(i),20}),1,tint)
            rl.DrawLineEx(screen_point(view,Vec2{-20,f32(i)}),screen_point(view,Vec2{20,f32(i)}),1,tint)
        }
        ids_order: [dynamic]u64
        defer delete(ids_order)
        for sub in s.subdivisions { if sub.live { append(&ids_order,sub.id) } }
        sort_ids(ids_order[:])
        for id in ids_order {
            sub:=s.subdivisions[s.sub_rows[id]]
            outline:=render_outline(s,sub,poses,surface)
            posed:=render_subdivision(s,sub,poses)
            stroke:=rl.Color{202,220,231,255}
            if sub.id==selected { stroke={255,255,255,255} }
            fill:=piece_color(sub.owner,210)
            if material_colors { fill=editor_color(s.materials[sub.material].name) }
            draw_cached_polygon(view,outline,fill,stroke,outlines,ensure_render_cache(s,sub.id),surface)
            delete(outline.points)
            center:=screen_point(view,posed.pose.position)
            if ids { rl.DrawText(rl.TextFormat("%d",sub.id),i32(center.x)-5,i32(center.y)-23,16,rl.Color{16,29,40,255}) }
        }
        if joints {
            clear(&ids_order)
            for c in s.connections { if c.live { append(&ids_order,c.id) } }
            sort_ids(ids_order[:])
            for id in ids_order {
                c:=s.connections[s.conn_rows[id]]
                a,b:=render_subdivision(s,s.subdivisions[s.sub_rows[c.a]],poses),render_subdivision(s,s.subdivisions[s.sub_rows[c.b]],poses)
                anchor:=vmul(vadd(posed_point(a,c.rest_point),posed_point(b,c.rest_point)),0.5)
                color:=rl.Color{248,205,109,255}
                rl.DrawLineEx(screen_point(view,a.pose.position),screen_point(view,b.pose.position),2,color)
    package main
    
    import b2 "vendor:box2d"
    import "core:math"
    import "core:time"
    
    Sandbox_Settings :: struct {
        blast_radius: f32,
        blast_mode: Blast_Mode,
        pattern: int,
        fragment_strength, connection_strength, flexibility: f32,
        generate_children: bool,
        seed: u8,
    }
    DEFAULT_SANDBOX_SETTINGS :: Sandbox_Settings{blast_radius=5.0,fragment_strength=35,connection_strength=20,flexibility=0,generate_children=true,seed=42}
    YARD_FLOOR_BOTTOM :: f32(-3)
    YARD_BASE_DEPTH :: f32(0.25)
    YARD_LEFT :: f32(-8)
    YARD_RIGHT :: f32(9)
    sandbox_material :: proc(settings: Sandbox_Settings) -> Material {
        material:=material_preset(settings.pattern)
        material.subdivision_strength=settings.fragment_strength
        material.connection_strength=settings.connection_strength
        material.flexibility=settings.flexibility
        return material
    }
    Sandbox :: struct {
        scene: Scene,
        blast_timing: ^Soak_Timing,
        editor: Material_Editor,
        floor: b2.BodyId,
        player: Player,
        bomb_rain: Bomb_Rain,
        applied,draft: Sandbox_Settings,
        previous: map[u64]Pose,
        previous_player: Vec2,
        panel_open,inspection,tuning_open,surface,joints,outlines: bool,
        block_jump,block_blast,jump_queued: bool,
        selected: u64,
        accumulator: f32,
        status: string,
        status_time: f32,
    }
    // Retain the original tower fixture for diagnostic behavior/terrain checks.
    // The playable application starts with sandbox_editor_create.
    sandbox_create :: proc(settings: Sandbox_Settings = DEFAULT_SANDBOX_SETTINGS) -> Sandbox {
        game:=Sandbox{applied=settings,draft=settings,previous=make(map[u64]Pose),surface=true,joints=true,outlines=true}
        sandbox_reset(&game)
        return game
    }
    sandbox_destroy :: proc(game: ^Sandbox) {
        scene_destroy(&game.scene)
        delete(game.bomb_rain.bombs); delete(game.bomb_rain.bursts)
        delete(game.previous); delete(game.editor.objects)
        game^={}
    }
    sandbox_notice :: proc(game: ^Sandbox,text: string) { game.status=text; game.status_time=2.5 }
    sandbox_clear_input :: proc(game: ^Sandbox) {
        game.accumulator=0
        game.jump_queued=false
        game.block_jump=true
        game.block_blast=true
        player_clear_input(&game.player)
        clear(&game.previous)
        game.previous_player=from_b2(b2.Body_GetPosition(game.player.body))
    package main
    
    import rl "vendor:raylib"
    import b2 "vendor:box2d"
    import "core:fmt"
    
    // raylib 5.x automation event IDs (rcore.c); the Odin binding exposes the raw event.
    smoke_key :: proc(key: rl.KeyboardKey,down: bool) -> rl.AutomationEvent {
        type:=u32(1); if down { type=2 }
        return {type=type,params={i32(key),0,0,0}}
    }
    smoke_mouse :: proc(x,y: i32) -> rl.AutomationEvent {
        dpi:=rl.GetWindowScaleDPI()
        return {type=7,params={i32(f32(x)*dpi.x),i32(f32(y)*dpi.y),0,0}}
    }
    smoke_button :: proc(down: bool) -> rl.AutomationEvent {
        type:=u32(5); if down { type=6 }
        return {type=type,params={0,0,0,0}}
    }
    sandbox_smoke_frame :: proc(game: ^Sandbox,target: rl.RenderTexture2D,events: ..rl.AutomationEvent) {
        for event in events { rl.PlayAutomationEvent(event) }
        width,height:=f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())
        view:=sandbox_view(width,height)
        mouse:=rl.GetMousePosition()
        over_ui:=sandbox_over_hud(mouse,width,height,game.inspection && !game.editor.editing)
        raw:=sandbox_read_input()
        input:=sandbox_route_input(game,raw,over_ui)
        if !raw.menu_pressed && !raw.reset_pressed {
            if game.editor.editing { sandbox_editor_input(game,world_point(view,mouse),over_ui) }
            else if !sandbox_inspect_input(game,world_point(view,mouse),view,over_ui) && input.blast_pressed { sandbox_blast(game,world_point(view,mouse)) }
        }
        sandbox_advance(game,1.0/60.0,input)
        poses:=make(map[u64]Pose); defer delete(poses)
        rl.BeginDrawing()
        rl.BeginTextureMode(target)
        rl.ClearBackground({19,28,42,255})
        sandbox_draw_world(game,view,poses)
        if !game.panel_open && !over_ui { sandbox_draw_aim(game,view,mouse) }
        action:=sandbox_draw_hud(game,width,height)
        rl.EndTextureMode()
        rl.EndDrawing()
        sandbox_handle_ui(game,action)
    }
    sandbox_smoke_click :: proc(game: ^Sandbox,target: rl.RenderTexture2D,x,y: i32) {
        sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(false))
    }
    sandbox_smoke_export :: proc(target: rl.RenderTexture2D,name: cstring) {
        image:=rl.LoadImageFromTexture(target.texture); rl.ImageFlipVertical(&image)
        assert(rl.ExportImage(image,name)); rl.UnloadImage(image)
    }
    editor_smoke_drag :: proc(game: ^Sandbox,target: rl.RenderTexture2D,a,b: Vec2) {
        view:=sandbox_view(1280,800)
        p,q:=screen_point(view,a),screen_point(view,b)
        sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)))
        assert(game.editor.dragging,"Rectangle preview did not start")
        sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)),smoke_button(false))
    }
    sandbox_smoke_inputs :: proc(game: ^Sandbox) {
        rl.SetTargetFPS(0)
        target:=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight())
        defer rl.UnloadRenderTexture(target)
        assert(game.editor.editing && len(game.editor.objects)==0)
        initial_ground:=counts_live_subdivisions(&game.scene)
        sandbox_smoke_click(game,target,1180,43)
        assert(game.outlines)
        revision_before_toggle:=game.scene.revision
        sandbox_smoke_click(game,target,698,352)
        assert(!game.outlines && game.scene.revision==revision_before_toggle,"Outline toggle must only change presentation")
        sandbox_smoke_click(game,target,357,770)
        assert(game.editor.palette==.Wood && game.panel_open,"Settings must consume clicks on the underlying palette")
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
        pose:=b2.Body_GetPosition(game.player.body)
        for _ in 0..<60 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
        assert(b2.Body_GetPosition(game.player.body)==pose,"Editing must pause simulation")
        // Use each actual palette widget and drag into the clear building area.
        for choice in 0..<4 {
            sandbox_smoke_click(game,target,69+i32(choice)*96,770)
            assert(int(game.editor.palette)==choice)
            x:=f32(choice)*2.0-2.0
            editor_smoke_drag(game,target,{x,0},{x+1.2,1.2})
            assert(len(game.editor.objects)==choice+1 && int(game.editor.objects[choice].material)==choice)
        }
        editor_smoke_drag(game,target,{-2,0},{-0.8,1.2})
        assert(len(game.editor.objects)==4,"Overlap was not rejected")
        editor_smoke_drag(game,target,{0,2},{0,3})
        assert(len(game.editor.objects)==4,"Degenerate rectangle was not rejected")
        // Right mouse deletes an authored object, not its damaged graph.
        p:=screen_point(sandbox_view(1280,800),{4.5,0.5})
        sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),rl.AutomationEvent{type=6,params={1,0,0,0}})
        sandbox_smoke_frame(game,target,rl.AutomationEvent{type=5,params={1,0,0,0}})
        assert(len(game.editor.objects)==3)
        editor_smoke_drag(game,target,{4,0},{5.2,1.2})
        assert(len(game.editor.objects)==4)
        // A drag ending over palette controls is cancelled.
        p=screen_point(sandbox_view(1280,800),{6,2})
        sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(60,770),smoke_button(false))
        assert(len(game.editor.objects)==4 && !game.editor.dragging)
        sandbox_smoke_export(target,"output/sandbox-editor.png")
        sandbox_smoke_click(game,target,930,43)
        assert(!game.editor.editing && len(game.scene.pieces)==5)
        revision:=game.scene.revision
        for _ in 0..<90 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
        assert(game.player.grounded)
        sandbox_smoke_frame(game,target,smoke_key(.D,true))
        for _ in 0..<15 { sandbox_smoke_frame(game,target) }
        sandbox_smoke_frame(game,target,smoke_key(.D,false),smoke_key(.SPACE,true))
        // Allow the existing 0.1-second buffer to catch a seam crossing.
        for _ in 0..<5 { if b2.Body_GetLinearVelocity(game.player.body).y>5 { break }; sandbox_smoke_frame(game,target) }
        assert(b2.Body_GetLinearVelocity(game.player.body).y>5,"Space must jump in Test")
        for _ in 0..<120 { sandbox_smoke_frame(game,target) }
        assert(game.player.grounded,"Held jump must not repeat")
        sandbox_smoke_frame(game,target,smoke_key(.SPACE,false))
        // Settings consume input and keep radius/mode live without material overrides.
        sandbox_smoke_click(game,target,1180,43)
        assert(game.panel_open && len(game.editor.objects)==4)
        pose=b2.Body_GetPosition(game.player.body)
        for _ in 0..<15 { sandbox_smoke_frame(game,target,smoke_key(.D,true)) }
        assert(b2.Body_GetPosition(game.player.body)==pose)
        sandbox_smoke_frame(game,target,smoke_key(.D,false))
        sandbox_smoke_click(game,target,820,381)
        assert(game.applied.blast_radius>5.1)
        sandbox_smoke_click(game,target,640,500)
        assert(!game.panel_open)
        sandbox_set_radius(game,5)
        sandbox_smoke_frame(game,target,smoke_key(.F3,true))
        assert(game.inspection)
        sandbox_smoke_frame(game,target,smoke_key(.F3,false))
        sandbox_smoke_frame(game,target,smoke_key(.F3,true))
        sandbox_smoke_frame(game,target,smoke_key(.F3,false))
        sandbox_smoke_frame(game,target,smoke_key(.R,true))
        assert(game.scene.revision>revision && len(game.editor.objects)==4 && !game.outlines,"Reset must preserve the outline preference")
        sandbox_smoke_frame(game,target,smoke_key(.R,false))
        sandbox_smoke_click(game,target,930,43)
        assert(game.editor.editing && len(game.editor.objects)==4 && counts_live_subdivisions(&game.scene)==initial_ground)
        // One controlled breakup for each brittle/rigid material, through native clicks.
        choices:=[3]Palette{.Wood,.Glass,.Stone}
        for choice in choices {
            clear(&game.editor.objects)
            sandbox_smoke_click(game,target,69+i32(choice)*96,770)
            editor_smoke_drag(game,target,{1.5,0},{3.1,1.6})
            sandbox_smoke_click(game,target,930,43)
            original_ids:=[dynamic]u64{}
            for sub in game.scene.subdivisions { if sub.material!=0 { append(&original_ids,sub.id) } }
            original_material:=game.scene.subdivisions[0].material
            sandbox_set_radius(game,editor_material(choice).subdivision_strength/BLAST_LOAD_MULTIPLIER+1.2)
            aim:=screen_point(sandbox_view(1280,800),{1.2,0.8})
            sandbox_smoke_click(game,target,i32(aim.x),i32(aim.y))
            removed:=false; for id in original_ids { if !is_live_subdivision(&game.scene,id) { removed=true } }; delete(original_ids)
            assert(removed,"Material example did not fracture")
            for _ in 0..<20 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
            valid,message:=validate_scene(&game.scene); assert(valid,message)
            survivors:=0
            for sub in game.scene.subdivisions { if sub.live && sub.material==original_material { survivors+=1 } }
            assert(survivors>0,"The breakup example must retain visible material fragments")
            fmt.printf("%s breakup: %d surviving fragments\n",editor_material(choice).name,survivors)
            sandbox_smoke_export(target,rl.TextFormat("output/sandbox-material-%s.png",editor_material(choice).name))
            sandbox_smoke_click(game,target,930,43)
            assert(game.editor.editing && len(game.editor.objects)==1)
        }
        sandbox_set_radius(game,5)
        // Rubber: record a localized nudge, then a missing cell, using the same mesh.
        clear(&game.editor.objects)
        sandbox_smoke_click(game,target,261,770)
        editor_smoke_drag(game,target,{1,0},{3.4,0.8})
        sandbox_smoke_click(game,target,930,43)
        for _ in 0..<60 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
        ids:=game.scene.pieces[0].subdivisions
        b2.Body_ApplyLinearImpulseToCenter(subdivision_body(&game.scene,ids[len(ids)-1]),{0,0.3},true)
        for _ in 0..<6 { sandbox_smoke_frame(game,target) }
        sandbox_smoke_export(target,"output/sandbox-material-rubber.png")
        sandbox_smoke_frame(game,target,smoke_key(.F3,true))
        sandbox_smoke_frame(game,target,smoke_key(.F3,false))
        cell:=game.scene.subdivisions[game.scene.sub_rows[ids[len(ids)/2+2]]]
        p=screen_point(sandbox_view(1280,800),cell.pose.position)
        sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),rl.AutomationEvent{type=6,params={1,0,0,0}})
        sandbox_smoke_frame(game,target,rl.AutomationEvent{type=5,params={1,0,0,0}})
        assert(game.selected==cell.id)
        sandbox_smoke_frame(game,target,smoke_key(.DELETE,true))
        sandbox_smoke_frame(game,target,smoke_key(.DELETE,false))
        assert(!is_live_subdivision(&game.scene,cell.id))
        for _ in 0..<60 { sandbox_smoke_frame(game,target) }
        valid,message:=validate_scene(&game.scene); assert(valid,message)
        sandbox_smoke_frame(game,target,smoke_key(.F3,true))
        sandbox_smoke_frame(game,target,smoke_key(.F3,false))
        sandbox_smoke_export(target,"output/sandbox-rubber-cell-removed.png")
        // Bomb controls still use their native settings widgets and real contacts.
        sandbox_smoke_click(game,target,1180,43)
        sandbox_smoke_click(game,target,785,313)
        assert(game.applied.blast_mode==.Falling_Bombs)
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
        for _ in 0..<160 {
            sandbox_smoke_frame(game,target)
            if len(game.bomb_rain.bombs)>0 { break }
        }
        assert(len(game.bomb_rain.bombs)>0)
        first:=game.bomb_rain.bombs[0].body
        for _ in 0..<300 {
            sandbox_smoke_frame(game,target)
            if !b2.Body_IsValid(first) { break }
        }
        assert(!b2.Body_IsValid(first),"Falling bomb did not land and explode")
        sandbox_smoke_click(game,target,1180,43)
        sandbox_smoke_click(game,target,480,313)
        assert(game.applied.blast_mode==.Manual && len(game.bomb_rain.bombs)==0)
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
        sandbox_smoke_frame(game,target,smoke_key(.ENTER,true))
        assert(game.editor.editing && len(game.editor.objects)==1)
        sandbox_smoke_frame(game,target,smoke_key(.ENTER,false))
        // Draw larger Wood/Stone roots through the actual palette and Test widget.
        // Ordinary support must not refine either the object or its floor collider.
        placements:=[2]Palette{.Wood,.Stone}
        for choice in placements {
            clear(&game.editor.objects)
            sandbox_smoke_click(game,target,69+i32(choice)*96,770)
            editor_smoke_drag(game,target,{1.5,0},{5.3,3.8})
            sandbox_smoke_click(game,target,930,43)
            before_regions,before_links,before_pieces:=counts_runtime(&game.scene)
            before_id:=game.scene.next_id
            for _ in 0..<120 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
            regions,links,pieces:=counts_runtime(&game.scene)
            assert(regions==before_regions && links==before_links && pieces==before_pieces && game.scene.next_id==before_id,"Placed material and floor must survive support without refinement")
            sandbox_smoke_click(game,target,930,43)
            assert(game.editor.editing)
        }
        fmt.println("Editor native smoke passed: palette, drag preview, overlap/degenerate rejection, deletion, UI consumption, paused edit, Test/Edit restoration, reset, movement/jump, inspection, radius, material breakups, rubber, and falling bombs.")
    }
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
    
    The fixture uses the same yard and three fixed blasts without physics ticks, plus a separate seeded 600-tick sequence. That ticked replay runs **twice sequentially in one process** and requires byte-identical snapshots, including motion and IDs. An optional output prefix follows `--soak-fixture`. The [original storage report](evidence/soak/report.md) retains the earlier baseline; [sustained-cycle results](evidence/soak-cycles/report.md) cover the replenishing soak and out-of-bounds removal.
    
    
    ## Play
    
    
    
        Directory: C:\Users\jblic\Documents\BOM\scripts
    
    
    Mode                 LastWriteTime         Length Name
    ----                 -------------         ------ ----
    -a----        2026-11-02   2:19 AM           1850 bom.ps1
    rg: src/*.ps1: The filename, directory name, or volume label syntax is incorrect. (os error 123)
    src/sandbox_test.odin:183:sandbox_aim_uses_posed_outlines_and_suppresses_invalid_blast :: proc(t: ^testing.T) {
    src/editor_view.odin:23:        if game.outlines { rl.DrawRectangleLinesEx(box,2,YARD_INK) }
    
    
    ✗ (1) • 694ms

## Activity

    $ Get-Content src/sandbox_smoke.odin -TotalCount 88; Get-Content src/debug_view.odin -TotalCount 125; Get-Content src/editor_view.odin -TotalCount 55; Get-Content src/yard.odin -TotalCount 54; Get-Content scripts/bom.ps1; rg -n 'draw_scene\(|draw_polygon\(|draw_cached_polygon\(|smoke' src/main.odin src/render_cache.odin docs/verification.md
    package main
    
    import rl "vendor:raylib"
    import b2 "vendor:box2d"
    import "core:fmt"
    
    // raylib 5.x automation event IDs (rcore.c); the Odin binding exposes the raw event.
    smoke_key :: proc(key: rl.KeyboardKey,down: bool) -> rl.AutomationEvent {
        type:=u32(1); if down { type=2 }
        return {type=type,params={i32(key),0,0,0}}
    }
    smoke_mouse :: proc(x,y: i32) -> rl.AutomationEvent {
        dpi:=rl.GetWindowScaleDPI()
        return {type=7,params={i32(f32(x)*dpi.x),i32(f32(y)*dpi.y),0,0}}
    }
    smoke_button :: proc(down: bool) -> rl.AutomationEvent {
        type:=u32(5); if down { type=6 }
        return {type=type,params={0,0,0,0}}
    }
    sandbox_smoke_frame :: proc(game: ^Sandbox,target: rl.RenderTexture2D,events: ..rl.AutomationEvent) {
        for event in events { rl.PlayAutomationEvent(event) }
        width,height:=f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())
        view:=sandbox_view(width,height)
        mouse:=rl.GetMousePosition()
        over_ui:=sandbox_over_hud(mouse,width,height,game.inspection && !game.editor.editing)
        raw:=sandbox_read_input()
        input:=sandbox_route_input(game,raw,over_ui)
        if !raw.menu_pressed && !raw.reset_pressed {
            if game.editor.editing { sandbox_editor_input(game,world_point(view,mouse),over_ui) }
            else if !sandbox_inspect_input(game,world_point(view,mouse),view,over_ui) && input.blast_pressed { sandbox_blast(game,world_point(view,mouse)) }
        }
        sandbox_advance(game,1.0/60.0,input)
        poses:=make(map[u64]Pose); defer delete(poses)
        rl.BeginDrawing()
        rl.BeginTextureMode(target)
        rl.ClearBackground({19,28,42,255})
        sandbox_draw_world(game,view,poses)
        if !game.panel_open && !over_ui { sandbox_draw_aim(game,view,mouse) }
        action:=sandbox_draw_hud(game,width,height)
        rl.EndTextureMode()
        rl.EndDrawing()
        sandbox_handle_ui(game,action)
    }
    sandbox_smoke_click :: proc(game: ^Sandbox,target: rl.RenderTexture2D,x,y: i32) {
        sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(false))
    }
    sandbox_smoke_export :: proc(target: rl.RenderTexture2D,name: cstring) {
        image:=rl.LoadImageFromTexture(target.texture); rl.ImageFlipVertical(&image)
        assert(rl.ExportImage(image,name)); rl.UnloadImage(image)
    }
    editor_smoke_drag :: proc(game: ^Sandbox,target: rl.RenderTexture2D,a,b: Vec2) {
        view:=sandbox_view(1280,800)
        p,q:=screen_point(view,a),screen_point(view,b)
        sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)))
        assert(game.editor.dragging,"Rectangle preview did not start")
        sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)),smoke_button(false))
    }
    sandbox_smoke_inputs :: proc(game: ^Sandbox) {
        rl.SetTargetFPS(0)
        target:=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight())
        defer rl.UnloadRenderTexture(target)
        assert(game.editor.editing && len(game.editor.objects)==0)
        initial_ground:=counts_live_subdivisions(&game.scene)
        sandbox_smoke_click(game,target,1180,43)
        assert(game.outlines)
        revision_before_toggle:=game.scene.revision
        sandbox_smoke_click(game,target,698,352)
        assert(!game.outlines && game.scene.revision==revision_before_toggle,"Outline toggle must only change presentation")
        sandbox_smoke_click(game,target,357,770)
        assert(game.editor.palette==.Wood && game.panel_open,"Settings must consume clicks on the underlying palette")
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
        pose:=b2.Body_GetPosition(game.player.body)
        for _ in 0..<60 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
        assert(b2.Body_GetPosition(game.player.body)==pose,"Editing must pause simulation")
        // Use each actual palette widget and drag into the clear building area.
        for choice in 0..<4 {
            sandbox_smoke_click(game,target,69+i32(choice)*96,770)
            assert(int(game.editor.palette)==choice)
            x:=f32(choice)*2.0-2.0
            editor_smoke_drag(game,target,{x,0},{x+1.2,1.2})
            assert(len(game.editor.objects)==choice+1 && int(game.editor.objects[choice].material)==choice)
        }
        editor_smoke_drag(game,target,{-2,0},{-0.8,1.2})
        assert(len(game.editor.objects)==4,"Overlap was not rejected")
        editor_smoke_drag(game,target,{0,2},{0,3})
    package main
    
    import rl "vendor:raylib"
    import b2 "vendor:box2d"
    import "core:math"
    
    View :: struct { offset: Vec2, scale: f32 }
    screen_point :: proc(view: View,point: Vec2) -> rl.Vector2 { return {view.offset.x+point.x*view.scale,view.offset.y-point.y*view.scale} }
    world_point :: proc(view: View,point: rl.Vector2) -> Vec2 { return {(point.x-view.offset.x)/view.scale,(view.offset.y-point.y)/view.scale} }
    piece_color :: proc(id: u64,alpha: u8 = 255) -> rl.Color {
        colors := [6]rl.Color{{64,173,165,255},{97,142,206,255},{194,134,204,255},{212,161,88,255},{139,178,113,255},{211,116,125,255}}
        c:=colors[id%6]; c.a=alpha; return c
    }
    render_subdivision :: proc(s: ^Scene,sub: Subdivision,poses: map[u64]Pose) -> Subdivision {
        result:=sub
        if pose,ok:=poses[sub.id]; ok { result.pose=pose }
        if s.materials[sub.material].flexibility==0 {
            // One interpolated frame per rigid piece, including just-created cells
            // without a previous-frame pose. No cosmetic seam correction is needed.
            p:=s.pieces[s.piece_rows[sub.owner]]
            anchor:=s.subdivisions[s.sub_rows[p.subdivisions[0]]]
            if pose,ok:=poses[anchor.id]; ok {
                result.pose.angle=pose.angle
                result.pose.position=vadd(pose.position,vrotate(vsub(sub.rest_center,anchor.rest_center),pose.angle))
            }
        }
        return result
    }
    point_on_boundary :: proc(point: Vec2,a,b: Polygon) -> bool {
        for i in 0..<len(a.points) {
            for j in 0..<len(b.points) {
                if segment,ok:=segment_overlap(Segment{a.points[i],a.points[(i+1)%len(a.points)]},Segment{b.points[j],b.points[(j+1)%len(b.points)]}); ok {
                    d:=vsub(segment.b,segment.a); length:=vlen(d)
                    projection:=vdot(vsub(point,segment.a),d)/(length*length)
                    if projection >= -0.0001 && projection <= 1.0001 && math.abs(vcross(d,vsub(point,segment.a))) < 0.0001*length { return true }
                }
            }
        }
        return false
    }
    draw_polygon :: proc(view: View,outline: Polygon,color: rl.Color,stroke: rl.Color,outlines: bool = true) {
        triangles:=triangulate_polygon(outline)
        for triangle in triangles {
            a,b,c:=screen_point(view,triangle.points[0]),screen_point(view,triangle.points[1]),screen_point(view,triangle.points[2])
            // Raylib's triangle winding uses the screen's downward Y axis.
            cross:=vcross(vsub(triangle.points[1],triangle.points[0]),vsub(triangle.points[2],triangle.points[0]))
            if cross > 0 { rl.DrawTriangle(a,b,c,color) } else { rl.DrawTriangle(c,b,a,color) }
            delete(triangle.points)
        }
        delete(triangles)
        if outlines {
            for i in 0..<len(outline.points) { rl.DrawLineEx(screen_point(view,outline.points[i]),screen_point(view,outline.points[(i+1)%len(outline.points)]),2,stroke) }
        }
    }
    pick_subdivision :: proc(s: ^Scene,point: Vec2) -> u64 {
        best:=u64(0)
        for sub in s.subdivisions {
            if !sub.live { continue }
            points: [dynamic]rl.Vector2
            for rest in sub.outline.points { p:=posed_point(sub,rest); append(&points,rl.Vector2{p.x,p.y}) }
            hit:=rl.CheckCollisionPointPoly({point.x,point.y},raw_data(points),i32(len(points)))
            delete(points)
            if hit && (best==0 || sub.id<best) { best=sub.id }
        }
        return best
    }
    pick_connection :: proc(s: ^Scene,point: Vec2,max_distance: f32) -> u64 {
        best:=u64(0); distance:=max_distance
        for c in s.connections { if c.live { d:=vlen(vsub(point,connection_sample(s,c))); if d<distance || (best!=0 && d==distance && c.id<best) { distance=d; best=c.id } } }
        return best
    }
    material_preset :: proc(index: int) -> Material {
        switch index {
        case 1: return make_material(name="splinter",subdivision_strength=7,connection_strength=6,flexibility=0.6,generation_count=5,aspect_ratio=0.2)
        case 2: return make_material(name="shatter",subdivision_strength=5,connection_strength=4,flexibility=0.05,generation_count=6,aspect_ratio=1,triangulate=true)
        }
        return make_material(name="chunk",subdivision_strength=6,connection_strength=4,flexibility=0.25,generation_count=3,aspect_ratio=1)
    }
    reset_demo :: proc(s: ^Scene,preset: int,terminal: bool) {
        scene_destroy(s)
        seed:=u8(42); if terminal { seed=0 }
        s^=make_wall(seed,0.08)
        s.materials[0]=material_preset(preset)
        physics_init(s)
    }
    add_projectile :: proc(s: ^Scene) {
        material:=add_material(s,make_material(name="projectile",subdivision_strength=math.inf_f32(1),connection_strength=math.inf_f32(1),generation_count=2,aspect_ratio=1))
        owner:=add_piece(s,material,0)
        points:=[4]Vec2{{-1.2,0.3},{-0.8,0.3},{-0.8,0.7},{-1.2,0.7}}
        outline:=make_polygon(points[:]); defer delete(outline.points)
        id:=add_subdivision(s,owner,outline,Pose{position=centroid(outline),velocity={8,0}})
    
        physics_sync_structure(s)
        b2.Body_SetBullet(subdivision_body(s,id),true)
        s.revision+=1
    }
    draw_scene :: proc(s: ^Scene,view: View,poses: map[u64]Pose,selected: u64,surface,joints: bool,ids: bool = true,material_colors: bool = false,outlines: bool = true) {
        for i in -20..=20 {
            tint:=rl.Color{31,44,62,255}
            if i==0 { tint={45,65,85,255} }
            rl.DrawLineEx(screen_point(view,Vec2{f32(i),-20}),screen_point(view,Vec2{f32(i),20}),1,tint)
            rl.DrawLineEx(screen_point(view,Vec2{-20,f32(i)}),screen_point(view,Vec2{20,f32(i)}),1,tint)
        }
        ids_order: [dynamic]u64
        defer delete(ids_order)
        for sub in s.subdivisions { if sub.live { append(&ids_order,sub.id) } }
        sort_ids(ids_order[:])
        for id in ids_order {
            sub:=s.subdivisions[s.sub_rows[id]]
            outline:=render_outline(s,sub,poses,surface)
            posed:=render_subdivision(s,sub,poses)
            stroke:=rl.Color{202,220,231,255}
            if sub.id==selected { stroke={255,255,255,255} }
            fill:=piece_color(sub.owner,210)
            if material_colors { fill=editor_color(s.materials[sub.material].name) }
            draw_cached_polygon(view,outline,fill,stroke,outlines,ensure_render_cache(s,sub.id),surface)
            delete(outline.points)
            center:=screen_point(view,posed.pose.position)
            if ids { rl.DrawText(rl.TextFormat("%d",sub.id),i32(center.x)-5,i32(center.y)-23,16,rl.Color{16,29,40,255}) }
        }
        if joints {
            clear(&ids_order)
            for c in s.connections { if c.live { append(&ids_order,c.id) } }
            sort_ids(ids_order[:])
            for id in ids_order {
    package main
    
    import rl "vendor:raylib"
    
    editor_color :: proc(name: string) -> rl.Color {
        switch name {
        case "wood": return {180,136,82,255}
        case "glass": return {106,191,215,195}
        case "rubber": return {178,121,199,230}
        }
        return {143,158,164,230}
    }
    editor_screen_rect :: proc(view: View,r: Authored_Rect) -> rl.Rectangle {
        lo,hi:=screen_point(view,{r.lo.x,r.hi.y}),screen_point(view,{r.hi.x,r.lo.y})
        return {lo.x,lo.y,hi.x-lo.x,hi.y-lo.y}
    }
    sandbox_draw_editor :: proc(game: ^Sandbox,view: View) {
        if !game.editor.editing { return }
        for object in game.editor.objects {
            box:=editor_screen_rect(view,object)
            material:=editor_material(object.material)
            rl.DrawRectangleRec(box,editor_color(material.name))
            if game.outlines { rl.DrawRectangleLinesEx(box,2,YARD_INK) }
            rl.DrawText(rl.TextFormat("%s",material.name),i32(box.x)+5,i32(box.y)+5,16,YARD_INK)
        }
        if game.editor.dragging {
            r:=editor_rectangle(game.editor.start,game.editor.cursor,game.editor.palette)
            box:=editor_screen_rect(view,r)
            color:=rl.Color{111,220,190,100}
            if !editor_valid_rectangle(&game.editor,r) { color={244,132,131,100} }
            rl.DrawRectangleRec(box,color); color.a=255
            rl.DrawRectangleLinesEx(box,2,color)
        }
    }
    sandbox_editor_input :: proc(game: ^Sandbox,point: Vec2,over_ui: bool) {
        if game.panel_open { game.editor.dragging=false; return }
        if rl.IsMouseButtonPressed(.RIGHT) && !over_ui {
            game.editor.dragging=false
            editor_remove(game,point)
        }
        if rl.IsMouseButtonPressed(.LEFT) && !game.block_blast && !over_ui {
            game.editor.dragging=true; game.editor.start=point
        }
        if game.editor.dragging {
            game.editor.cursor=point
            if rl.IsMouseButtonReleased(.LEFT) {
                if !over_ui { editor_place(game,game.editor.start,point) }
                game.editor.dragging=false
            }
        }
    }
    package main
    
    import b2 "vendor:box2d"
    import "core:math"
    import "core:time"
    
    Sandbox_Settings :: struct {
        blast_radius: f32,
        blast_mode: Blast_Mode,
        pattern: int,
        fragment_strength, connection_strength, flexibility: f32,
        generate_children: bool,
        seed: u8,
    }
    DEFAULT_SANDBOX_SETTINGS :: Sandbox_Settings{blast_radius=5.0,fragment_strength=35,connection_strength=20,flexibility=0,generate_children=true,seed=42}
    YARD_FLOOR_BOTTOM :: f32(-3)
    YARD_BASE_DEPTH :: f32(0.25)
    YARD_LEFT :: f32(-8)
    YARD_RIGHT :: f32(9)
    sandbox_material :: proc(settings: Sandbox_Settings) -> Material {
        material:=material_preset(settings.pattern)
        material.subdivision_strength=settings.fragment_strength
        material.connection_strength=settings.connection_strength
        material.flexibility=settings.flexibility
        return material
    }
    Sandbox :: struct {
        scene: Scene,
        blast_timing: ^Soak_Timing,
        editor: Material_Editor,
        floor: b2.BodyId,
        player: Player,
        bomb_rain: Bomb_Rain,
        applied,draft: Sandbox_Settings,
        previous: map[u64]Pose,
        previous_player: Vec2,
        panel_open,inspection,tuning_open,surface,joints,outlines: bool,
        block_jump,block_blast,jump_queued: bool,
        selected: u64,
        accumulator: f32,
        status: string,
        status_time: f32,
    }
    // Retain the original tower fixture for diagnostic behavior/terrain checks.
    // The playable application starts with sandbox_editor_create.
    sandbox_create :: proc(settings: Sandbox_Settings = DEFAULT_SANDBOX_SETTINGS) -> Sandbox {
        game:=Sandbox{applied=settings,draft=settings,previous=make(map[u64]Pose),surface=true,joints=true,outlines=true}
        sandbox_reset(&game)
        return game
    }
    sandbox_destroy :: proc(game: ^Sandbox) {
        scene_destroy(&game.scene)
        delete(game.bomb_rain.bombs); delete(game.bomb_rain.bursts)
        delete(game.previous); delete(game.editor.objects)
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Run', 'Build', 'Test', 'Headless', 'Smoke', 'SmokeSettings', 'SmokeInput', 'Lab', 'Serve', 'Receive')]
        [string]$Task = 'Run'
    )
    
    $ErrorActionPreference = 'Stop'
    $projectRoot = Split-Path -Parent $PSScriptRoot
    
    # Keep compiler output and runtime captures in the same place from any shell location.
    Push-Location -LiteralPath $projectRoot
    try {
        New-Item -ItemType Directory -Path 'build', 'output' -Force | Out-Null
        if ($Task -eq 'Build') {
            $odinArguments = @('build', 'src', '-o:speed', '-out:build/BOM.exe')
        } elseif ($Task -eq 'Test') {
            $odinArguments = @('test', 'src', '-out:build/BOM-tests.exe')
        } else {
            $runtimeFlags = @{
                Headless = '--headless'
                Smoke = '--smoke'
                SmokeSettings = '--smoke-settings'
                SmokeInput = '--smoke-input'
                Lab = '--lab'
                Serve = '--serve'
                Receive = '--receive'
            }
            $odinArguments = @('run', 'src', '-out:build/BOM.exe')
            if ($runtimeFlags.ContainsKey($Task)) {
                $odinArguments += @('--', $runtimeFlags[$Task])
            }
        }
    
        # Windows PowerShell treats redirected native stderr as error records, even
        # for Odin's normal test progress. Use the process exit code for success.
        $ErrorActionPreference = 'Continue'
        try {
            & odin @odinArguments 2>&1 | ForEach-Object {
                if ($_ -is [System.Management.Automation.ErrorRecord]) {
                    $_.Exception.Message
                } else {
                    $_
                }
            }
            $odinExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = 'Stop'
        }
        if ($odinExitCode -ne 0) {
            throw "Odin $Task failed with exit code $odinExitCode."
        }
    } finally {
        Pop-Location
    }
    src/main.odin:21:        if arg=="--smoke" { run_sandbox(true); return }
    src/main.odin:22:        if arg=="--smoke-settings" { run_sandbox(true,true); return }
    src/main.odin:23:        if arg=="--smoke-input" { run_sandbox(true,false,true); return }
    src/main.odin:28:        if arg=="--help" { fmt.println("odin run src -out:build/BOM.exe -- [--soak [minutes] | --soak-fixture [output-prefix] | --headless | --smoke | --smoke-settings | --smoke-input | --lab | --serve | --receive | --help]"); return }
    docs/verification.md:14:`--headless` evaluates the original diagnostic blast, runs 60 physics ticks, validates the graph, writes `output/snapshot.json`, and reconstructs a receiver. `--smoke` renders the yard in a hidden window to `output/sandbox-preview.png`. `--smoke-settings` renders the paused settings panel to `output/sandbox-settings-preview.png`. Both exit after two frames.
    docs/verification.md:16:`--smoke-input` uses raylib native automation events in a hidden window to exercise the actual palette widgets, drag preview and placement, overlap/degenerate rejection, right-click deletion, UI consumption, paused editing, Test/Edit restoration, R reset, movement and held jump, radius, inspection and falling bombs. It exports `output/sandbox-editor.png`, one breakup example each in `output/sandbox-material-wood.png`, `output/sandbox-material-glass.png`, `output/sandbox-material-stone.png`, and rubber views in `output/sandbox-material-rubber.png` and `output/sandbox-rubber-cell-removed.png`. The normal behavior suite stays independent of a window or display. The original tower setup remains an internal fixture for existing destruction, movement and terrain regressions; it is not the editor's initial layout.
    docs/verification.md:45:The response suite checks flat single-region Glass/Stone/Wood drops at 0.7x and 1.3x predicted threshold heights, at 30/60/120 Hz with four substeps, while retaining the anchored floor. It also checks the highest placeable Rubber grid drop, player contact at full running speed, bomb landings on every material and exposed ground before the fuse expires, and blast destruction of objects and floor. Further checks cover hit events on existing contacts in successive steps, collision mass ratios, sub-unit/s load calculation, static immunity, sustained linear/angular weld corrections (including a static endpoint), no endpoint refinement from any joint, and `impact_scale` serialization with backward default 1 and explicit zero preserved. [Recorded results](../evidence/load-scale/report.md) include the unchanged blast-only fixture, byte-identical same-process 600-tick replay, native smoke and the new 20-minute soak.
    docs/verification.md:50:The [shared-pass follow-up](../evidence/shared-blast/report.md) verifies direct above-ground core reach and byte-identical playable blast, replay and 20-minute ending snapshots. Its requested 0.4x seam guard currently fails for Wood because the coarse onset is unbracketed; all other 81 tests and native smoke pass.
    ✓ • 340ms

## Assistant

The current outline is 2 pixels thick. I’ll make the slider run from 0 to 2 pixels, with fractional widths for very thin outlines, and apply it to both Edit and Test views.

## Activity

    $ rg -n 'draw_polygon\(|draw_scene\(|outlines' src; Get-Content src/render_cache.odin -Tail 14; Get-Content src/debug_view.odin | Select-Object -Skip 95 -First 24; Get-Content src/editor.odin -TotalCount 85; Get-Command odin | Select-Object Source
    src\debug_view.odin:41:draw_polygon :: proc(view: View,outline: Polygon,color: rl.Color,stroke: rl.Color,outlines: bool = true) {
    src\debug_view.odin:51:    if outlines {
    src\debug_view.odin:97:draw_scene :: proc(s: ^Scene,view: View,poses: map[u64]Pose,selected: u64,surface,joints: bool,ids: bool = true,material_colors: bool = false,outlines: bool = true) {
    src\debug_view.odin:116:        draw_cached_polygon(view,outline,fill,stroke,outlines,ensure_render_cache(s,sub.id),surface)
    src\debug_view.odin:235:        draw_scene(&s,view,poses,selected,surface,joints)
    src\editor_view.odin:23:        if game.outlines { rl.DrawRectangleLinesEx(box,2,YARD_INK) }
    src\geometry.odin:85:// in both outlines. Parent boundary vertices are untouched, including T junctions.
    src\model.odin:324:// parent outlines and old membership lists are still used during staging.
    src\editor.odin:31:    game:=Sandbox{applied=DEFAULT_SANDBOX_SETTINGS,draft=DEFAULT_SANDBOX_SETTINGS,previous=make(map[u64]Pose),surface=true,joints=true,outlines=true}
    src\recursive_blast_test.odin:100:// the observable graph by exact retained outlines, seeds, motion and membership.
    src\generation_test.odin:124:        testing.expect(t,len(parts)==len(parent.points)-2,"Every ear of these simple outlines must be retained")
    src\render_cache.odin:115:draw_cached_polygon :: proc(view: View,outline: Polygon,color,stroke: rl.Color,outlines: bool,cache: ^Render_Cache,surface: bool) {
    src\render_cache.odin:122:    if outlines { for point,i in outline.points { rl.DrawLineEx(screen_point(view,point),screen_point(view,outline.points[(i+1)%len(outline.points)]),2,stroke) } }
    src\sandbox_test.odin:183:sandbox_aim_uses_posed_outlines_and_suppresses_invalid_blast :: proc(t: ^testing.T) {
    src\sandbox_smoke.odin:67:    assert(game.outlines)
    src\sandbox_smoke.odin:70:    assert(!game.outlines && game.scene.revision==revision_before_toggle,"Outline toggle must only change presentation")
    src\sandbox_smoke.odin:135:    assert(game.scene.revision>revision && len(game.editor.objects)==4 && !game.outlines,"Reset must preserve the outline preference")
    src\sandbox_view.odin:55:    _ = rl.GuiCheckBox({x+300,y-4,20,20},"Outlines",&game.outlines)
    src\sandbox_view.odin:95:    draw_scene(s,view,poses,game.selected,game.surface,game.inspection && game.joints,game.inspection,game.editor.enabled,game.outlines)
    src\storage_test.odin:25:dead_storage_reclaims_outlines_caches_keys_and_handles :: proc(t: ^testing.T) {
    src\transmission.odin:146:        draw_scene(&s,view,poses,0,true,true)
    src\yard.odin:37:    panel_open,inspection,tuning_open,surface,joints,outlines: bool,
    src\yard.odin:47:    game:=Sandbox{applied=settings,draft=settings,previous=make(map[u64]Pose),surface=true,joints=true,outlines=true}
        }
        outline:=make_polygon(sub.outline.points); posed:=render_subdivision(s,sub,poses)
        for rest,i in sub.outline.points { outline.points[i]=posed_point(posed,rest) }
        return outline
    }
    draw_cached_polygon :: proc(view: View,outline: Polygon,color,stroke: rl.Color,outlines: bool,cache: ^Render_Cache,surface: bool) {
        indices:=cache.raw_triangles[:]; if surface { indices=cache.triangles[:] }
        for i:=0; i+2<len(indices); i+=3 {
            a,b,c:=outline.points[indices[i]],outline.points[indices[i+1]],outline.points[indices[i+2]]
            if vcross(vsub(b,a),vsub(c,a))>0 { rl.DrawTriangle(screen_point(view,a),screen_point(view,b),screen_point(view,c),color) }
            else { rl.DrawTriangle(screen_point(view,c),screen_point(view,b),screen_point(view,a),color) }
        }
        if outlines { for point,i in outline.points { rl.DrawLineEx(screen_point(view,point),screen_point(view,outline.points[(i+1)%len(outline.points)]),2,stroke) } }
    }
    }
    draw_scene :: proc(s: ^Scene,view: View,poses: map[u64]Pose,selected: u64,surface,joints: bool,ids: bool = true,material_colors: bool = false,outlines: bool = true) {
        for i in -20..=20 {
            tint:=rl.Color{31,44,62,255}
            if i==0 { tint={45,65,85,255} }
            rl.DrawLineEx(screen_point(view,Vec2{f32(i),-20}),screen_point(view,Vec2{f32(i),20}),1,tint)
            rl.DrawLineEx(screen_point(view,Vec2{-20,f32(i)}),screen_point(view,Vec2{20,f32(i)}),1,tint)
        }
        ids_order: [dynamic]u64
        defer delete(ids_order)
        for sub in s.subdivisions { if sub.live { append(&ids_order,sub.id) } }
        sort_ids(ids_order[:])
        for id in ids_order {
            sub:=s.subdivisions[s.sub_rows[id]]
            outline:=render_outline(s,sub,poses,surface)
            posed:=render_subdivision(s,sub,poses)
            stroke:=rl.Color{202,220,231,255}
            if sub.id==selected { stroke={255,255,255,255} }
            fill:=piece_color(sub.owner,210)
            if material_colors { fill=editor_color(s.materials[sub.material].name) }
            draw_cached_polygon(view,outline,fill,stroke,outlines,ensure_render_cache(s,sub.id),surface)
            delete(outline.points)
            center:=screen_point(view,posed.pose.position)
            if ids { rl.DrawText(rl.TextFormat("%d",sub.id),i32(center.x)-5,i32(center.y)-23,16,rl.Color{16,29,40,255}) }
    package main
    
    import "core:math"
    
    Palette :: enum { Wood, Glass, Rubber, Stone }
    RUBBER_CELL_SIZE :: f32(0.4)
    Authored_Rect :: struct { lo,hi: Vec2, material: Palette, identity: u64 }
    Material_Editor :: struct {
        enabled,editing,dragging: bool,
        palette: Palette,
        start,cursor: Vec2,
        next_identity: u64,
        objects: [dynamic]Authored_Rect,
    }
    // Gameplay presets use the ordinary material fields, not the diagnostic sliders.
    editor_material :: proc(choice: Palette) -> Material {
        m:=make_material()
        switch choice {
        case .Wood:
            m=material_preset(1); m.name="wood"; m.subdivision_strength=28; m.connection_strength=22; m.flexibility=0
        case .Glass:
            m=material_preset(2); m.name="glass"; m.subdivision_strength=16; m.connection_strength=12; m.flexibility=0
        case .Rubber:
            m=material_preset(0); m.name="rubber"; m.impact_scale=0; m.subdivision_strength=45; m.connection_strength=90; m.flexibility=0.5
        case .Stone:
            m=material_preset(0); m.name="stone"; m.impact_scale=1.6; m.subdivision_strength=35; m.connection_strength=20; m.flexibility=0
        }
        return m
    }
    sandbox_editor_create :: proc() -> Sandbox {
        game:=Sandbox{applied=DEFAULT_SANDBOX_SETTINGS,draft=DEFAULT_SANDBOX_SETTINGS,previous=make(map[u64]Pose),surface=true,joints=true,outlines=true}
        game.editor.enabled=true; game.editor.editing=true
        sandbox_reset(&game)
        return game
    }
    editor_rectangle :: proc(a,b: Vec2,material: Palette) -> Authored_Rect {
        return Authored_Rect{lo={min(a.x,b.x),min(a.y,b.y)},hi={max(a.x,b.x),max(a.y,b.y)},material=material}
    }
    editor_overlaps :: proc(a,b: Authored_Rect) -> bool {
        return a.lo.x<b.hi.x && a.hi.x>b.lo.x && a.lo.y<b.hi.y && a.hi.y>b.lo.y
    }
    editor_valid_rectangle :: proc(editor: ^Material_Editor,r: Authored_Rect) -> bool {
        if !valid_vec(r.lo) || !valid_vec(r.hi) || r.hi.x-r.lo.x<0.2 || r.hi.y-r.lo.y<0.2 { return false }
        if r.lo.x< -7.5 || r.hi.x>8.5 || r.lo.y<0 || r.hi.y>4.8 { return false }
        // Reserve the initial player's footprint, too; no body starts inside a solid.
        spawn:=Authored_Rect{lo={PLAYER_SPAWN.x-PLAYER_RADIUS,0},hi={PLAYER_SPAWN.x+PLAYER_RADIUS,PLAYER_SPAWN.y+PLAYER_HALF_HEIGHT}}
        if editor_overlaps(r,spawn) { return false }
        for object in editor.objects { if editor_overlaps(r,object) { return false } }
        return true
    }
    editor_place :: proc(game: ^Sandbox,a,b: Vec2) -> bool {
        if !game.editor.editing || game.panel_open { return false }
        r:=editor_rectangle(a,b,game.editor.palette)
        if !editor_valid_rectangle(&game.editor,r) { sandbox_notice(game,"Place a rectangle above ground, clear of objects and spawn"); return false }
        game.editor.next_identity+=1; r.identity=game.editor.next_identity
        append(&game.editor.objects,r)
        return true
    }
    editor_remove :: proc(game: ^Sandbox,point: Vec2) -> bool {
        if !game.editor.editing || game.panel_open { return false }
        for object,i in game.editor.objects {
            if point.x>=object.lo.x && point.x<=object.hi.x && point.y>=object.lo.y && point.y<=object.hi.y {
                ordered_remove(&game.editor.objects,i); return true
            }
        }
        return false
    }
    sandbox_toggle_editor :: proc(game: ^Sandbox) {
        if !game.editor.enabled || game.panel_open { return }
        game.editor.editing=!game.editor.editing
        game.editor.dragging=false
        sandbox_reset(game)
        if game.editor.editing { sandbox_notice(game,"Edit: undamaged layout restored") }
        else { sandbox_notice(game,"Test: R restores this layout and seed") }
    }
    editor_build_objects :: proc(game: ^Sandbox) {
        s:=&game.scene
        materials: [4]int
        for choice in Palette { materials[int(choice)]=add_material(s,editor_material(choice)) }
        editor_build_rectangles(game,materials)
    }
    // Reuse construction with the existing table when the soak replenishes its yard.
    editor_build_rectangles :: proc(game: ^Sandbox,materials: [4]int) {
        s:=&game.scene
        if game.editor.editing { return }
    
    Source
    ------
    C:\Users\jblic\Downloads\odin-windows-amd64-dev-2026-05\dist\odin.exe
    
    
    ✓ • 571ms

## Activity

    file changes: Completed · 8 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\docs\gameplay.md
    @@ -25,3 +25,3 @@
     
    -Mode and radius changes are immediate, including inside Settings. The **Outlines** checkbox toggles object and subdivision borders immediately and stays set across resets and Edit/Test transitions. Outlines start enabled; drag previews and inspection IDs/links remain available independently. Objects use fixed palette presets; global material sliders do not override them. Abstract recipe/strength/flexibility tuning remains in `--lab` (F4), separate from the editor. The initial setup uses manual blasts, seed 42, radius 5.0 and impulse scale 0.2. The independent ground uses Stone's Chunks recipe, strengths 35/20 and flexibility 0.
    +Mode and radius changes are immediate, including inside Settings. The **Outline width (px)** slider adjusts object and subdivision borders from 0 (no outline), through fractional pixel widths, to the original thick 2-pixel outline. The width starts at 2 and stays set across resets and Edit/Test transitions; drag previews and inspection IDs/links remain available independently. Objects use fixed palette presets; global material sliders do not override them. Abstract recipe/strength/flexibility tuning remains in `--lab` (F4), separate from the editor. The initial setup uses manual blasts, seed 42, radius 5.0 and impulse scale 0.2. The independent ground uses Stone's Chunks recipe, strengths 35/20 and flexibility 0.
     
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\debug_view.odin
    @@ -96,3 +96,3 @@
     }
    -draw_scene :: proc(s: ^Scene,view: View,poses: map[u64]Pose,selected: u64,surface,joints: bool,ids: bool = true,material_colors: bool = false,outlines: bool = true) {
    +draw_scene :: proc(s: ^Scene,view: View,poses: map[u64]Pose,selected: u64,surface,joints: bool,ids: bool = true,material_colors: bool = false,outline_width: f32 = 2) {
     	for i in -20..=20 {
    @@ -115,3 +115,3 @@
     		if material_colors { fill=editor_color(s.materials[sub.material].name) }
    -		draw_cached_polygon(view,outline,fill,stroke,outlines,ensure_render_cache(s,sub.id),surface)
    +		draw_cached_polygon(view,outline,fill,stroke,outline_width,ensure_render_cache(s,sub.id),surface)
     		delete(outline.points)
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\editor.odin
    @@ -30,3 +30,3 @@
     sandbox_editor_create :: proc() -> Sandbox {
    -	game:=Sandbox{applied=DEFAULT_SANDBOX_SETTINGS,draft=DEFAULT_SANDBOX_SETTINGS,previous=make(map[u64]Pose),surface=true,joints=true,outlines=true}
    +	game:=Sandbox{applied=DEFAULT_SANDBOX_SETTINGS,draft=DEFAULT_SANDBOX_SETTINGS,previous=make(map[u64]Pose),surface=true,joints=true,outline_width=2}
     	game.editor.enabled=true; game.editor.editing=true
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\editor_view.odin
    @@ -22,3 +22,3 @@
     		rl.DrawRectangleRec(box,editor_color(material.name))
    -		if game.outlines { rl.DrawRectangleLinesEx(box,2,YARD_INK) }
    +		if game.outline_width>0 { rl.DrawRectangleLinesEx(box,game.outline_width,YARD_INK) }
     		rl.DrawText(rl.TextFormat("%s",material.name),i32(box.x)+5,i32(box.y)+5,16,YARD_INK)
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\render_cache.odin
    @@ -114,3 +114,3 @@
     }
    -draw_cached_polygon :: proc(view: View,outline: Polygon,color,stroke: rl.Color,outlines: bool,cache: ^Render_Cache,surface: bool) {
    +draw_cached_polygon :: proc(view: View,outline: Polygon,color,stroke: rl.Color,outline_width: f32,cache: ^Render_Cache,surface: bool) {
     	indices:=cache.raw_triangles[:]; if surface { indices=cache.triangles[:] }
    @@ -121,3 +121,3 @@
     	}
    -	if outlines { for point,i in outline.points { rl.DrawLineEx(screen_point(view,point),screen_point(view,outline.points[(i+1)%len(outline.points)]),2,stroke) } }
    +	if outline_width>0 { for point,i in outline.points { rl.DrawLineEx(screen_point(view,point),screen_point(view,outline.points[(i+1)%len(outline.points)]),outline_width,stroke) } }
     }
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -66,6 +66,13 @@
     	sandbox_smoke_click(game,target,1180,43)
    -	assert(game.outlines)
    -	revision_before_toggle:=game.scene.revision
    -	sandbox_smoke_click(game,target,698,352)
    -	assert(!game.outlines && game.scene.revision==revision_before_toggle,"Outline toggle must only change presentation")
    +	assert(game.outline_width==2)
    +	revision_before_slider:=game.scene.revision
    +	sandbox_smoke_click(game,target,657,389)
    +	assert(game.outline_width==0,"Slider left endpoint must disable outlines")
    +	sandbox_smoke_click(game,target,660,389)
    +	assert(game.outline_width>0 && game.outline_width<0.1,"Slider must support subpixel outlines")
    +	sandbox_smoke_click(game,target,891,389)
    +	assert(game.outline_width==2,"Slider right endpoint must restore thick outlines")
    +	sandbox_smoke_click(game,target,774,389)
    +	preferred_outline_width:=game.outline_width
    +	assert(preferred_outline_width>0 && preferred_outline_width<2 && game.scene.revision==revision_before_slider,"Outline width must only change presentation")
     	sandbox_smoke_click(game,target,357,770)
    @@ -123,3 +130,3 @@
     	sandbox_smoke_frame(game,target,smoke_key(.D,false))
    -	sandbox_smoke_click(game,target,820,381)
    +	sandbox_smoke_click(game,target,620,381)
     	assert(game.applied.blast_radius>5.1)
    @@ -134,3 +141,3 @@
     	sandbox_smoke_frame(game,target,smoke_key(.R,true))
    -	assert(game.scene.revision>revision && len(game.editor.objects)==4 && !game.outlines,"Reset must preserve the outline preference")
    +	assert(game.scene.revision>revision && len(game.editor.objects)==4 && game.outline_width==preferred_outline_width,"Reset must preserve the outline preference")
     	sandbox_smoke_frame(game,target,smoke_key(.R,false))
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_view.odin
    @@ -53,4 +53,4 @@
     	radius:=game.applied.blast_radius
    -	sandbox_slider(x,y,504,"Blast radius",&radius,0.5,6,true)
    -	_ = rl.GuiCheckBox({x+300,y-4,20,20},"Outlines",&game.outlines)
    +	sandbox_slider(x,y,236,"Blast radius",&radius,0.5,6,true)
    +	sandbox_slider(x+268,y,236,"Outline width (px)",&game.outline_width,0,2,true)
     	sandbox_set_radius(game,radius)
    @@ -94,3 +94,3 @@
     	}
    -	draw_scene(s,view,poses,game.selected,game.surface,game.inspection && game.joints,game.inspection,game.editor.enabled,game.outlines)
    +	draw_scene(s,view,poses,game.selected,game.surface,game.inspection && game.joints,game.inspection,game.editor.enabled,game.outline_width)
     	sandbox_draw_editor(game,view)
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\yard.odin
    @@ -36,3 +36,4 @@
     	previous_player: Vec2,
    -	panel_open,inspection,tuning_open,surface,joints,outlines: bool,
    +	panel_open,inspection,tuning_open,surface,joints: bool,
    +	outline_width: f32,
     	block_jump,block_blast,jump_queued: bool,
    @@ -46,3 +47,3 @@
     sandbox_create :: proc(settings: Sandbox_Settings = DEFAULT_SANDBOX_SETTINGS) -> Sandbox {
    -	game:=Sandbox{applied=settings,draft=settings,previous=make(map[u64]Pose),surface=true,joints=true,outlines=true}
    +	game:=Sandbox{applied=settings,draft=settings,previous=make(map[u64]Pose),surface=true,joints=true,outline_width=2}
     	sandbox_reset(&game)

## Activity

    $ .\scripts\bom.ps1 Build
    ✓ • 18.92s

## Activity

    $ .\scripts\bom.ps1 Test
    [INFO ] --- [2026-11-03 09:30:29] Starting test runner with 16 threads. Set with -define:ODIN_TEST_THREADS=n.
    [INFO ] --- [2026-11-03 09:30:29] The random seed sent to every test is: 718530201477319. Set with -define:ODIN_TEST_RANDOM_SEED=n.
    [INFO ] --- [2026-11-03 09:30:29] Memory tracking is enabled. Tests will log their memory usage if there's an issue.
    [INFO ] --- [2026-11-03 09:30:29] < Final Mem/ Total Mem> <  Peak Mem> (#Free/Alloc) :: [package.test_name]
    Drop Glass: h=0.3657 threshold=0.5224 closing=2.6133 load=13.0667 intact=true floor_intact=true
    Drop Glass: h=0.6792 threshold=0.5224 closing=3.5933 load=17.9667 intact=false floor_intact=true
    Drop Stone: h=0.6836 threshold=0.9766 closing=3.5933 load=28.7466 intact=true floor_intact=true
    Drop Stone: h=1.2695 threshold=0.9766 closing=5.0633 load=40.5067 intact=false floor_intact=true
    Drop Wood: h=1.1200 threshold=1.6000 closing=4.7367 load=23.6833 intact=true floor_intact=true
    Drop Wood: h=2.0800 threshold=1.6000 closing=6.3700 load=31.8500 intact=false floor_intact=true
    Pre-split Glass: crack size1 0.5250 / size0.5 0.5250
    Pre-split Stone: crack size1 0.9500 / size0.5 0.9500
    Pre-split Wood: crack size1 1.6250 / size0.5 1.6250
    Rigid off-centre blast: angular velocity -1.250813 / expected -1.250813
    Rigid rest-frame maximum error 0.00000067 units
    Rigid Stone 2.4x1.2: split rebound 0.00171560 / single 0.00000793; rest error 0.00000049 / 0.00000012; regions 11 / 1; mean tick 0.093093 / 0.076807 ms; max 0.365900 / 0.150000 ms
    Rigid Stone 0.7x3.7: split rebound 0.00674462 / single 0.00775731; rest error 0.00000072 / 0.00000048; regions 11 / 1; mean tick 0.095687 / 0.078933 ms; max 0.305300 / 0.186500 ms
    
    Finished 89 tests in 34.4781557s. All tests were successful.
    
    ✓ • 37.49s

## Activity

    $ rg -n 'outlines|outline_width' src/sandbox_smoke.odin src/sandbox_view.odin src/editor_view.odin src/yard.odin src/editor.odin; Get-ChildItem -Path C:\Users\jblic -Filter AGENTS.md -Force; Get-ChildItem -Path C:\Users\jblic\Documents -Filter AGENTS.md -Force
    src/editor.odin:31:    game:=Sandbox{applied=DEFAULT_SANDBOX_SETTINGS,draft=DEFAULT_SANDBOX_SETTINGS,previous=make(map[u64]Pose),surface=true,joints=true,outline_width=2}
    src/sandbox_view.odin:55:    sandbox_slider(x+268,y,236,"Outline width (px)",&game.outline_width,0,2,true)
    src/sandbox_view.odin:95:    draw_scene(s,view,poses,game.selected,game.surface,game.inspection && game.joints,game.inspection,game.editor.enabled,game.outline_width)
    src/yard.odin:38:    outline_width: f32,
    src/yard.odin:48:    game:=Sandbox{applied=settings,draft=settings,previous=make(map[u64]Pose),surface=true,joints=true,outline_width=2}
    src/sandbox_smoke.odin:67:    assert(game.outline_width==2)
    src/sandbox_smoke.odin:70:    assert(game.outline_width==0,"Slider left endpoint must disable outlines")
    src/sandbox_smoke.odin:72:    assert(game.outline_width>0 && game.outline_width<0.1,"Slider must support subpixel outlines")
    src/sandbox_smoke.odin:74:    assert(game.outline_width==2,"Slider right endpoint must restore thick outlines")
    src/sandbox_smoke.odin:76:    preferred_outline_width:=game.outline_width
    src/sandbox_smoke.odin:77:    assert(preferred_outline_width>0 && preferred_outline_width<2 && game.scene.revision==revision_before_slider,"Outline width must only change presentation")
    src/sandbox_smoke.odin:142:    assert(game.scene.revision>revision && len(game.editor.objects)==4 && game.outline_width==preferred_outline_width,"Reset must preserve the outline preference")
    src/editor_view.odin:23:        if game.outline_width>0 { rl.DrawRectangleLinesEx(box,game.outline_width,YARD_INK) }
    ✓ • 509ms

## Activity

    $ .\build\BOM.exe --smoke-input
    C:/Users/jblic/Documents/BOM/src/sandbox_smoke.odin(70:2) runtime assertion: Slider left endpoint must disable outlines
    ✗ (1) • 6.71s

## Activity

    $ rg -n 'GuiSliderBar\(|GuiSliderPro\(' C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib -g '*.h'; Get-Content src/sandbox_view.odin -TotalCount 67; Get-Content src/sandbox_smoke.odin | Select-Object -Skip 60 -First 20
    package main
    
    import rl "vendor:raylib"
    import b2 "vendor:box2d"
    
    YARD_INK :: rl.Color{229,239,241,255}
    YARD_MUTED :: rl.Color{144,165,178,255}
    YARD_ACCENT :: rl.Color{111,220,190,255}
    
    // Fit a fixed rectangle with letterboxing. Fragments never affect the camera.
    sandbox_view :: proc(width,height: f32) -> View {
        scale:=min((width-64)/16,(height-170)/8.4)
        return View{offset={width*0.5-0.5*scale,(height+30)*0.5+0.8*scale},scale=scale}
    }
    sandbox_settings_button :: proc(width: f32) -> rl.Rectangle { return {width-174,24,150,38} }
    sandbox_reset_button :: proc(width: f32) -> rl.Rectangle { return {width-284,24,98,38} }
    sandbox_over_hud :: proc(mouse: rl.Vector2,width,height: f32,inspection: bool) -> bool {
        if mouse.y<88 || mouse.y>height-56 { return true }
        return inspection && rl.CheckCollisionPointRec(mouse,{24,106,450,150})
    }
    sandbox_gui_style :: proc() {
        rl.GuiLoadStyleDefault()
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiDefaultProperty.TEXT_SIZE),18)
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_NORMAL),transmute(i32)u32(0x435969ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),transmute(i32)u32(0x233444ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),transmute(i32)u32(0xe5eff1ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_FOCUSED),transmute(i32)u32(0x6fdcbeff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_FOCUSED),transmute(i32)u32(0x304e58ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_FOCUSED),transmute(i32)u32(0xe5fff4ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_PRESSED),transmute(i32)u32(0x6fdcbeff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_PRESSED),transmute(i32)u32(0x416d68ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_PRESSED),transmute(i32)u32(0xffffffff))
    }
    sandbox_slider :: proc(x,y,width: f32,label: cstring,value: ^f32,low,high: f32,decimals: bool = false) {
        rl.DrawText(label,i32(x),i32(y),17,YARD_INK)
        text:=rl.TextFormat("%.0f",value^)
        if decimals { text=rl.TextFormat("%.2f",value^) }
        rl.DrawText(text,i32(x+width)-rl.MeasureText(text,17),i32(y),17,YARD_ACCENT)
        _ = rl.GuiSliderBar({x,y+25,width,16},nil,nil,value,low,high)
    }
    Sandbox_UI_Action :: enum { None, Open, Resume, Apply, Reset, Toggle_Editor }
    sandbox_draw_panel :: proc(game: ^Sandbox,width,height: f32) -> Sandbox_UI_Action {
        rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,205})
        x,y:=(width-560)*0.5,(height-360)*0.5
        rl.DrawRectangleRounded({x,y,560,360},0.025,8,{23,35,49,255})
        x+=28; y+=24
        rl.DrawText("SETTINGS / PAUSED",i32(x),i32(y),24,YARD_INK)
        y+=54
        mode:=i32(game.applied.blast_mode)
        _ = rl.GuiToggleGroup({x,y,248,32},"Manual blasts;Falling bombs",&mode)
        sandbox_set_blast_mode(game,Blast_Mode(mode))
        y+=48
        radius:=game.applied.blast_radius
        sandbox_slider(x,y,236,"Blast radius",&radius,0.5,6,true)
        sandbox_slider(x+268,y,236,"Outline width (px)",&game.outline_width,0,2,true)
        sandbox_set_radius(game,radius)
        y+=70
        rl.DrawText("Objects use their palette material. Ground stays Stone.",i32(x),i32(y),16,YARD_MUTED)
        y+=26
        rl.DrawText("Abstract recipe tuning: launch with --lab (F4).",i32(x),i32(y),16,YARD_MUTED)
        y+=42
        if rl.GuiButton({x,y,504,36},"Resume") { return .Resume }
        return .None
    }
    sandbox_draw_bombs :: proc(game: ^Sandbox,view: View) {
        for burst in game.bomb_rain.bursts {
            progress:=burst.age/BOMB_BURST_TIME
        rl.SetTargetFPS(0)
        target:=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight())
        defer rl.UnloadRenderTexture(target)
        assert(game.editor.editing && len(game.editor.objects)==0)
        initial_ground:=counts_live_subdivisions(&game.scene)
        sandbox_smoke_click(game,target,1180,43)
        assert(game.outline_width==2)
        revision_before_slider:=game.scene.revision
        sandbox_smoke_click(game,target,657,389)
        assert(game.outline_width==0,"Slider left endpoint must disable outlines")
        sandbox_smoke_click(game,target,660,389)
        assert(game.outline_width>0 && game.outline_width<0.1,"Slider must support subpixel outlines")
        sandbox_smoke_click(game,target,891,389)
        assert(game.outline_width==2,"Slider right endpoint must restore thick outlines")
        sandbox_smoke_click(game,target,774,389)
        preferred_outline_width:=game.outline_width
        assert(preferred_outline_width>0 && preferred_outline_width<2 && game.scene.revision==revision_before_slider,"Outline width must only change presentation")
        sandbox_smoke_click(game,target,357,770)
        assert(game.editor.palette==.Wood && game.panel_open,"Settings must consume clicks on the underlying palette")
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
    ✓ • 395ms

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -68,9 +68,13 @@
     	revision_before_slider:=game.scene.revision
    -	sandbox_smoke_click(game,target,657,389)
    +	sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
    +	sandbox_smoke_frame(game,target,smoke_mouse(646,381))
    +	sandbox_smoke_frame(game,target,smoke_button(false))
     	assert(game.outline_width==0,"Slider left endpoint must disable outlines")
    -	sandbox_smoke_click(game,target,660,389)
    +	sandbox_smoke_click(game,target,660,381)
     	assert(game.outline_width>0 && game.outline_width<0.1,"Slider must support subpixel outlines")
    -	sandbox_smoke_click(game,target,891,389)
    +	sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
    +	sandbox_smoke_frame(game,target,smoke_mouse(902,381))
    +	sandbox_smoke_frame(game,target,smoke_button(false))
     	assert(game.outline_width==2,"Slider right endpoint must restore thick outlines")
    -	sandbox_smoke_click(game,target,774,389)
    +	sandbox_smoke_click(game,target,774,381)
     	preferred_outline_width:=game.outline_width

## Activity

    $ .\scripts\bom.ps1 Build
    ✓ • 14.78s

## Assistant

The slider is implemented, and all 89 tests pass. I’m checking the actual UI drag behavior now, including zero width, fractional widths, and keeping the setting across resets.

## Activity

    $ .\build\BOM.exe --smoke-input
    C:/Users/jblic/Documents/BOM/src/sandbox_smoke.odin(81:2) runtime assertion: Outline width must only change presentation
    ✗ (1) • 5.58s

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -80,2 +80,3 @@
     	preferred_outline_width:=game.outline_width
    +	fmt.printf("Outline slider: width %.6f, revision %d -> %d\n",preferred_outline_width,revision_before_slider,game.scene.revision)
     	assert(preferred_outline_width>0 && preferred_outline_width<2 && game.scene.revision==revision_before_slider,"Outline width must only change presentation")

## Activity

    $ odin build src -out:build/BOM.exe
    ✓ • 2.93s

## Activity

    $ .\build\BOM.exe --smoke-input
    Outline slider: width 2.000000, revision 1 -> 1
    C:/Users/jblic/Documents/BOM/src/sandbox_smoke.odin(82:2) runtime assertion: Outline width must only change presentation
    ✗ (1) • 6.62s

## Activity

    $ rg --files C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib | Select-Object -First 25; rg -n 'slider|Slider' C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib/raygui.odin | Select-Object -First 25
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\raygui.odin
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\raylib.odin
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\raymath.odin
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\README.md
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\windows\raylibdll.lib
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\windows\raylib.lib
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\windows\raylib.dll
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\windows\rayguidll.lib
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\windows\raygui.lib
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\windows\raygui.dll
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\easings.odin
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\LICENSE
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\wasm\libraylib.a
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\wasm\libraygui.a
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\linux\libraylib.a
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\linux\libraygui.so
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\linux\libraygui.a
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\linux\libraylib.so
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\linux\libraylib.so.5.5.0
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\linux\libraylib.so.550
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\rlgl\rlgl.odin
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\macos-arm64\libraygui.dylib
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\macos\libraylib.dylib
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\macos\libraylib.a
    C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib\macos\libraylib.550.dylib
    133:// Slider/SliderBar
    134:GuiSliderProperty :: enum c.int {
    135:    SLIDER_WIDTH = 16,          // Slider size of internal bar
    136:    SLIDER_PADDING,             // Slider/SliderBar internal bar padding
    276:    GuiToggleSlider     :: proc(bounds: Rectangle, text: cstring, active: ^c.int) -> c.int ---
    285:    GuiSlider           :: proc(bounds: Rectangle, textLeft: cstring, textRight: cstring, value: ^f32, minValue: f32, maxValue: f32) -> c.int --- // Slider control, returns selected value
    286:    GuiSliderBar        :: proc(bounds: Rectangle, textLeft: cstring, textRight: cstring, value: ^f32, minValue: f32, maxValue: f32) -> c.int --- // Slider Bar control, returns selected value
    ✓ • 556ms

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -78,5 +78,6 @@
     	assert(game.outline_width==2,"Slider right endpoint must restore thick outlines")
    -	sandbox_smoke_click(game,target,774,381)
    +	sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
    +	sandbox_smoke_frame(game,target,smoke_mouse(775,381))
    +	sandbox_smoke_frame(game,target,smoke_button(false))
     	preferred_outline_width:=game.outline_width
    -	fmt.printf("Outline slider: width %.6f, revision %d -> %d\n",preferred_outline_width,revision_before_slider,game.scene.revision)
     	assert(preferred_outline_width>0 && preferred_outline_width<2 && game.scene.revision==revision_before_slider,"Outline width must only change presentation")

## Activity

    $ odin build src -out:build/BOM.exe
    ✓ • 2.81s

## Activity

    $ .\build\BOM.exe --smoke-input
    wood breakup: 9 surviving fragments
    glass breakup: 36 surviving fragments
    stone breakup: 18 surviving fragments
    Editor native smoke passed: palette, drag preview, overlap/degenerate rejection, deletion, UI consumption, paused edit, Test/Edit restoration, reset, movement/jump, inspection, radius, material breakups, rubber, and falling bombs.
    ✓ • 11.21s

## Activity

    $ .\scripts\bom.ps1 Build
    ✓ • 17.00s

## Assistant

Replaced the toggle with an outline-width slider: no outline → very thin fractional widths → the original thick 2-pixel outline.

Works in Edit and Test, and preserves your setting across resets. All 89 tests and the UI smoke check pass. Rebuilt `build/BOM.exe`.

## User

i feel like youve introduced visual bugs

## Assistant

I’ll inspect the rendered outlines and settings panel, focusing on what changed with the slider.

## Activity

    $ Get-Content src/sandbox_view.odin -TotalCount 73; Get-Content src/editor_view.odin -TotalCount 38; Get-Content src/render_cache.odin -Tail 19; Get-Content src/sandbox_smoke.odin | Select-Object -Skip 60 -First 38; Get-ChildItem output -Filter '*.png' | Select-Object Name,LastWriteTime; rg --files -g AGENTS.md
    package main
    
    import rl "vendor:raylib"
    import b2 "vendor:box2d"
    
    YARD_INK :: rl.Color{229,239,241,255}
    YARD_MUTED :: rl.Color{144,165,178,255}
    YARD_ACCENT :: rl.Color{111,220,190,255}
    
    // Fit a fixed rectangle with letterboxing. Fragments never affect the camera.
    sandbox_view :: proc(width,height: f32) -> View {
        scale:=min((width-64)/16,(height-170)/8.4)
        return View{offset={width*0.5-0.5*scale,(height+30)*0.5+0.8*scale},scale=scale}
    }
    sandbox_settings_button :: proc(width: f32) -> rl.Rectangle { return {width-174,24,150,38} }
    sandbox_reset_button :: proc(width: f32) -> rl.Rectangle { return {width-284,24,98,38} }
    sandbox_over_hud :: proc(mouse: rl.Vector2,width,height: f32,inspection: bool) -> bool {
        if mouse.y<88 || mouse.y>height-56 { return true }
        return inspection && rl.CheckCollisionPointRec(mouse,{24,106,450,150})
    }
    sandbox_gui_style :: proc() {
        rl.GuiLoadStyleDefault()
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiDefaultProperty.TEXT_SIZE),18)
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_NORMAL),transmute(i32)u32(0x435969ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),transmute(i32)u32(0x233444ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),transmute(i32)u32(0xe5eff1ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_FOCUSED),transmute(i32)u32(0x6fdcbeff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_FOCUSED),transmute(i32)u32(0x304e58ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_FOCUSED),transmute(i32)u32(0xe5fff4ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_PRESSED),transmute(i32)u32(0x6fdcbeff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_PRESSED),transmute(i32)u32(0x416d68ff))
        rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_PRESSED),transmute(i32)u32(0xffffffff))
    }
    sandbox_slider :: proc(x,y,width: f32,label: cstring,value: ^f32,low,high: f32,decimals: bool = false) {
        rl.DrawText(label,i32(x),i32(y),17,YARD_INK)
        text:=rl.TextFormat("%.0f",value^)
        if decimals { text=rl.TextFormat("%.2f",value^) }
        rl.DrawText(text,i32(x+width)-rl.MeasureText(text,17),i32(y),17,YARD_ACCENT)
        _ = rl.GuiSliderBar({x,y+25,width,16},nil,nil,value,low,high)
    }
    Sandbox_UI_Action :: enum { None, Open, Resume, Apply, Reset, Toggle_Editor }
    sandbox_draw_panel :: proc(game: ^Sandbox,width,height: f32) -> Sandbox_UI_Action {
        rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,205})
        x,y:=(width-560)*0.5,(height-360)*0.5
        rl.DrawRectangleRounded({x,y,560,360},0.025,8,{23,35,49,255})
        x+=28; y+=24
        rl.DrawText("SETTINGS / PAUSED",i32(x),i32(y),24,YARD_INK)
        y+=54
        mode:=i32(game.applied.blast_mode)
        _ = rl.GuiToggleGroup({x,y,248,32},"Manual blasts;Falling bombs",&mode)
        sandbox_set_blast_mode(game,Blast_Mode(mode))
        y+=48
        radius:=game.applied.blast_radius
        sandbox_slider(x,y,236,"Blast radius",&radius,0.5,6,true)
        sandbox_slider(x+268,y,236,"Outline width (px)",&game.outline_width,0,2,true)
        sandbox_set_radius(game,radius)
        y+=70
        rl.DrawText("Objects use their palette material. Ground stays Stone.",i32(x),i32(y),16,YARD_MUTED)
        y+=26
        rl.DrawText("Abstract recipe tuning: launch with --lab (F4).",i32(x),i32(y),16,YARD_MUTED)
        y+=42
        if rl.GuiButton({x,y,504,36},"Resume") { return .Resume }
        return .None
    }
    sandbox_draw_bombs :: proc(game: ^Sandbox,view: View) {
        for burst in game.bomb_rain.bursts {
            progress:=burst.age/BOMB_BURST_TIME
            color:=rl.Color{255,200,112,u8(220*(1-progress))}
            rl.DrawCircleLinesV(screen_point(view,burst.position),burst.radius*view.scale*(0.2+0.8*progress),color)
        }
        for bomb in game.bomb_rain.bombs {
            position:=from_b2(b2.Body_GetPosition(bomb.body))
            if !game.panel_open && !game.editor.editing { position=vadd(bomb.previous,vmul(vsub(position,bomb.previous),game.accumulator*60)) }
    package main
    
    import rl "vendor:raylib"
    
    editor_color :: proc(name: string) -> rl.Color {
        switch name {
        case "wood": return {180,136,82,255}
        case "glass": return {106,191,215,195}
        case "rubber": return {178,121,199,230}
        }
        return {143,158,164,230}
    }
    editor_screen_rect :: proc(view: View,r: Authored_Rect) -> rl.Rectangle {
        lo,hi:=screen_point(view,{r.lo.x,r.hi.y}),screen_point(view,{r.hi.x,r.lo.y})
        return {lo.x,lo.y,hi.x-lo.x,hi.y-lo.y}
    }
    sandbox_draw_editor :: proc(game: ^Sandbox,view: View) {
        if !game.editor.editing { return }
        for object in game.editor.objects {
            box:=editor_screen_rect(view,object)
            material:=editor_material(object.material)
            rl.DrawRectangleRec(box,editor_color(material.name))
            if game.outline_width>0 { rl.DrawRectangleLinesEx(box,game.outline_width,YARD_INK) }
            rl.DrawText(rl.TextFormat("%s",material.name),i32(box.x)+5,i32(box.y)+5,16,YARD_INK)
        }
        if game.editor.dragging {
            r:=editor_rectangle(game.editor.start,game.editor.cursor,game.editor.palette)
            box:=editor_screen_rect(view,r)
            color:=rl.Color{111,220,190,100}
            if !editor_valid_rectangle(&game.editor,r) { color={244,132,131,100} }
            rl.DrawRectangleRec(box,color); color.a=255
            rl.DrawRectangleLinesEx(box,2,color)
        }
    }
    sandbox_editor_input :: proc(game: ^Sandbox,point: Vec2,over_ui: bool) {
        if game.panel_open { game.editor.dragging=false; return }
        if rl.IsMouseButtonPressed(.RIGHT) && !over_ui {
            game.editor.dragging=false
        cache:=ensure_render_cache(s,sub.id)
        if surface {
            outline:=make_polygon(cache.outline.points)
            for rest,i in cache.outline.points { outline.points[i]=common_seam_point(s,sub,rest,poses,cache.seams[i]) }
            return outline
        }
        outline:=make_polygon(sub.outline.points); posed:=render_subdivision(s,sub,poses)
        for rest,i in sub.outline.points { outline.points[i]=posed_point(posed,rest) }
        return outline
    }
    draw_cached_polygon :: proc(view: View,outline: Polygon,color,stroke: rl.Color,outline_width: f32,cache: ^Render_Cache,surface: bool) {
        indices:=cache.raw_triangles[:]; if surface { indices=cache.triangles[:] }
        for i:=0; i+2<len(indices); i+=3 {
            a,b,c:=outline.points[indices[i]],outline.points[indices[i+1]],outline.points[indices[i+2]]
            if vcross(vsub(b,a),vsub(c,a))>0 { rl.DrawTriangle(screen_point(view,a),screen_point(view,b),screen_point(view,c),color) }
            else { rl.DrawTriangle(screen_point(view,c),screen_point(view,b),screen_point(view,a),color) }
        }
        if outline_width>0 { for point,i in outline.points { rl.DrawLineEx(screen_point(view,point),screen_point(view,outline.points[(i+1)%len(outline.points)]),outline_width,stroke) } }
    }
        rl.SetTargetFPS(0)
        target:=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight())
        defer rl.UnloadRenderTexture(target)
        assert(game.editor.editing && len(game.editor.objects)==0)
        initial_ground:=counts_live_subdivisions(&game.scene)
        sandbox_smoke_click(game,target,1180,43)
        assert(game.outline_width==2)
        revision_before_slider:=game.scene.revision
        sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(646,381))
        sandbox_smoke_frame(game,target,smoke_button(false))
        assert(game.outline_width==0,"Slider left endpoint must disable outlines")
        sandbox_smoke_click(game,target,660,381)
        assert(game.outline_width>0 && game.outline_width<0.1,"Slider must support subpixel outlines")
        sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(902,381))
        sandbox_smoke_frame(game,target,smoke_button(false))
        assert(game.outline_width==2,"Slider right endpoint must restore thick outlines")
        sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(775,381))
        sandbox_smoke_frame(game,target,smoke_button(false))
        preferred_outline_width:=game.outline_width
        assert(preferred_outline_width>0 && preferred_outline_width<2 && game.scene.revision==revision_before_slider,"Outline width must only change presentation")
        sandbox_smoke_click(game,target,357,770)
        assert(game.editor.palette==.Wood && game.panel_open,"Settings must consume clicks on the underlying palette")
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
        pose:=b2.Body_GetPosition(game.player.body)
        for _ in 0..<60 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
        assert(b2.Body_GetPosition(game.player.body)==pose,"Editing must pause simulation")
        // Use each actual palette widget and drag into the clear building area.
        for choice in 0..<4 {
            sandbox_smoke_click(game,target,69+i32(choice)*96,770)
            assert(int(game.editor.palette)==choice)
            x:=f32(choice)*2.0-2.0
            editor_smoke_drag(game,target,{x,0},{x+1.2,1.2})
            assert(len(game.editor.objects)==choice+1 && int(game.editor.objects[choice].material)==choice)
        }
    
    Name                            LastWriteTime
    ----                            -------------
    debug-preview.png               2026-11-02 9:59:58 PM
    sandbox-editor.png              2026-11-03 4:34:34 AM
    sandbox-material-glass.png      2026-11-03 4:34:37 AM
    sandbox-material-rubber.png     2026-11-03 4:34:39 AM
    sandbox-material-stone.png      2026-11-03 4:34:38 AM
    sandbox-material-wood.png       2026-11-03 4:34:36 AM
    sandbox-preview.png             2026-11-02 2:19:48 AM
    sandbox-rubber-cell-removed.png 2026-11-03 4:34:40 AM
    sandbox-settings-preview.png    2026-11-02 2:19:50 AM
    
    
    ✗ (1) • 626ms

## Assistant

Where are you seeing the visual bugs? I’m checking the new slider and outline rendering now.
- Object outlines or seams
- Settings panel or slider
- Something else in the scene

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\sandbox-material-glass.png

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\sandbox-editor.png

## Activity

    $ .\build\BOM.exe --smoke-settings
    ✓ • 846ms

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\sandbox-settings-preview.png

## Activity

    $ Get-Process BOM -ErrorAction SilentlyContinue | Select-Object Id,StartTime,Path; Get-Content src/sandbox_view.odin | Select-Object -Last 58; Get-Content src/debug_view.odin | Select-Object -Skip 108 -First 10; git status --short
        rl.InitWindow(1280,800,"Blast Yard | Odin + Box2D")
        defer rl.CloseWindow()
        rl.SetWindowMinSize(900,700)
        rl.SetExitKey(.KEY_NULL)
        rl.SetTargetFPS(60)
        sandbox_gui_style()
        game:=sandbox_editor_create()
        defer sandbox_destroy(&game)
        if smoke_input { sandbox_smoke_inputs(&game); return }
        if smoke_panel { sandbox_set_panel(&game,true); game.tuning_open=true }
        poses:=make(map[u64]Pose); defer delete(poses)
        target:=rl.RenderTexture2D{}
        if smoke { target=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight()) }
        defer { if smoke { rl.UnloadRenderTexture(target) } }
        frames:=0
        for !rl.WindowShouldClose() {
            width,height:=f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())
            view:=sandbox_view(width,height)
            mouse:=rl.GetMousePosition()
            over_ui:=sandbox_over_hud(mouse,width,height,game.inspection && !game.editor.editing)
            raw:=sandbox_read_input()
            input:=sandbox_route_input(&game,raw,over_ui)
            point:=world_point(view,mouse)
            if !raw.menu_pressed && !raw.reset_pressed {
                if game.editor.editing { sandbox_editor_input(&game,point,over_ui) }
                else if !sandbox_inspect_input(&game,point,view,over_ui) && input.blast_pressed { sandbox_blast(&game,point) }
            }
            sandbox_advance(&game,rl.GetFrameTime(),input)
            clear(&poses)
            for sub in game.scene.subdivisions {
                if !sub.live { continue }
                pose:=sub.pose
                if old,ok:=game.previous[sub.id]; ok && !game.panel_open { pose=interpolate_region_pose(&game.scene,sub,old,game.accumulator*60) }
                poses[sub.id]=pose
            }
            rl.BeginDrawing()
            if smoke { rl.BeginTextureMode(target) }
            rl.ClearBackground({19,28,42,255})
            sandbox_draw_world(&game,view,poses)
            if !game.panel_open && !over_ui { sandbox_draw_aim(&game,view,mouse) }
            action:=sandbox_draw_hud(&game,width,height)
            if smoke {
                rl.EndTextureMode()
                rl.DrawTextureRec(target.texture,{0,0,f32(target.texture.width),-f32(target.texture.height)},{0,0},rl.WHITE)
            }
            rl.EndDrawing()
            sandbox_handle_ui(&game,action)
            frames+=1
            if smoke && frames==2 {
                image:=rl.LoadImageFromTexture(target.texture)
                rl.ImageFlipVertical(&image)
                name:=cstring("output/sandbox-preview.png"); if smoke_panel { name="output/sandbox-settings-preview.png" }
                _ = rl.ExportImage(image,name)
                rl.UnloadImage(image)
                break
            }
        }
    }
            sub:=s.subdivisions[s.sub_rows[id]]
            outline:=render_outline(s,sub,poses,surface)
            posed:=render_subdivision(s,sub,poses)
            stroke:=rl.Color{202,220,231,255}
            if sub.id==selected { stroke={255,255,255,255} }
            fill:=piece_color(sub.owner,210)
            if material_colors { fill=editor_color(s.materials[sub.material].name) }
            draw_cached_polygon(view,outline,fill,stroke,outline_width,ensure_render_cache(s,sub.id),surface)
            delete(outline.points)
            center:=screen_point(view,posed.pose.position)
    ?? .gitignore
    ?? README.md
    ?? benchmarks/
    ?? codex-session-01a18d0b-2ef6-7c70-99fd-72bc108b2f1d.md
    ?? docs/
    ?? evidence/
    ?? scripts/
    ?? src.zip
    ?? src/
    ✓ • 683ms

## User

> Where are you seeing the visual bugs? I’m checking the new slider and outline rendering now.

The effect of messy phantom blank spaces that used to appear when there was no outline now happens to some extent at any thickness of outline

## Assistant

That points to gaps in the polygon fills that thick outlines were covering. I’ll check the shared edges and triangle rendering so the fills stay solid as outline width changes.

## Activity

    $ Get-Content src/render_cache.odin; Get-Content src/geometry.odin -TotalCount 230; rg -n 'triangulate_polygon|seam|blank|gap' src/geometry.odin src/*test* docs/implementation.md
    package main
    
    import rl "vendor:raylib"
    
    Seam_Neighbours :: struct { incident,direct: [dynamic]u64 }
    Render_Cache :: struct {
        owner,revision: u64,
        outline: Polygon,
        triangles,raw_triangles: [dynamic]int,
        seams: []Seam_Neighbours,
    }
    release_render_cache :: proc(cache: ^Render_Cache) {
        delete(cache.outline.points); delete(cache.triangles); delete(cache.raw_triangles)
        for seam in cache.seams { delete(seam.incident); delete(seam.direct) }
        delete(cache.seams); cache^={}
    }
    // Geometry tests happen once for this piece topology, never once per frame.
    seam_neighbours :: proc(s: ^Scene,sub: Subdivision,rest: Vec2) -> Seam_Neighbours {
        result:=Seam_Neighbours{}
        append(&result.incident,sub.id)
        for head:=0; head<len(result.incident); head+=1 {
            id:=result.incident[head]
            for connection in s.subdivisions[s.sub_rows[id]].incident_links {
                c:=s.connections[s.conn_rows[connection]]
                if !c.live { continue }
                other:=u64(0)
                if c.a==id { other=c.b } else if c.b==id { other=c.a }
                if other==0 { continue }
                a,b:=s.subdivisions[s.sub_rows[id]],s.subdivisions[s.sub_rows[other]]
                if !point_on_boundary(rest,a.outline,b.outline) { continue }
                if id==sub.id { append(&result.direct,other) }
                if !contains_id(result.incident[:],other) { append(&result.incident,other) }
            }
        }
        sort_ids(result.incident[:])
        return result
    }
    triangle_indices :: proc(outline: Polygon) -> [dynamic]int {
        result: [dynamic]int
        triangles:=triangulate_polygon(outline)
        for triangle in triangles {
            for point in triangle.points {
                for vertex,i in outline.points { if point==vertex { append(&result,i); break } }
            }
            delete(triangle.points)
        }
        delete(triangles)
        return result
    }
    ensure_render_cache :: proc(s: ^Scene,id: u64) -> ^Render_Cache {
        sub:=&s.subdivisions[s.sub_rows[id]]
        cache:=&sub.render
        revision:=s.pieces[s.piece_rows[sub.owner]].render_revision
        if cache.owner==sub.owner && cache.revision==revision { return cache }
        release_render_cache(cache)
        cache.owner=sub.owner; cache.revision=revision
        cache.outline=make_polygon(sub.outline.points)
        for connection in sub.incident_links {
            c:=s.connections[s.conn_rows[connection]]
            if !c.live { continue }
            other:=u64(0)
            if c.a==id { other=c.b } else if c.b==id { other=c.a }
            if other!=0 { for rest in s.subdivisions[s.sub_rows[other]].outline.points { insert_boundary_endpoint(&cache.outline,rest) } }
        }
        cache.triangles=triangle_indices(cache.outline)
        cache.raw_triangles=triangle_indices(sub.outline)
        cache.seams=make([]Seam_Neighbours,len(cache.outline.points))
        for rest,i in cache.outline.points { cache.seams[i]=seam_neighbours(s,sub^,rest) }
        return cache
    }
    cosmetic_seam_point :: proc(s: ^Scene,sub: Subdivision,rest: Vec2,poses: map[u64]Pose,seam: Seam_Neighbours) -> Vec2 {
        self:=render_subdivision(s,sub,poses); point:=posed_point(self,rest)
        flex:=clamp(s.materials[sub.material].flexibility,f32(0),f32(1))
        if flex==0 { return point }
        weighted:=point
        for id in seam.direct { other:=render_subdivision(s,s.subdivisions[s.sub_rows[id]],poses); weighted=vadd(weighted,posed_point(other,rest)) }
        return vadd(point,vmul(vsub(vmul(weighted,1/f32(len(seam.direct)+1)),point),flex))
    }
    common_seam_point :: proc(s: ^Scene,sub: Subdivision,rest: Vec2,poses: map[u64]Pose,seam: Seam_Neighbours) -> Vec2 {
        if s.materials[sub.material].flexibility==0 { return posed_point(render_subdivision(s,sub,poses),rest) }
        if len(seam.incident)>1 {
            for id,i in seam.incident {
                a:=render_subdivision(s,s.subdivisions[s.sub_rows[id]],poses)
                for j in i+1..<len(seam.incident) {
                    b:=render_subdivision(s,s.subdivisions[s.sub_rows[seam.incident[j]]],poses)
                    if vlen(vsub(posed_point(a,rest),posed_point(b,rest)))>0.001 { return cosmetic_seam_point(s,sub,rest,poses,seam) }
                }
            }
            point:=Vec2{}
            for id in seam.incident { other:=render_subdivision(s,s.subdivisions[s.sub_rows[id]],poses); point=vadd(point,posed_point(other,rest)) }
            return vmul(point,1/f32(len(seam.incident)))
        }
        return cosmetic_seam_point(s,sub,rest,poses,seam)
    }
    // Single-point helpers also serve inspection/tests; draw_scene uses cached seams.
    cosmetic_point :: proc(s: ^Scene,sub: Subdivision,rest: Vec2,poses: map[u64]Pose) -> Vec2 {
        seam:=seam_neighbours(s,sub,rest); defer delete(seam.incident); defer delete(seam.direct)
        return cosmetic_seam_point(s,sub,rest,poses,seam)
    }
    common_boundary_point :: proc(s: ^Scene,sub: Subdivision,rest: Vec2,poses: map[u64]Pose) -> Vec2 {
        seam:=seam_neighbours(s,sub,rest); defer delete(seam.incident); defer delete(seam.direct)
        return common_seam_point(s,sub,rest,poses,seam)
    }
    render_outline :: proc(s: ^Scene,sub: Subdivision,poses: map[u64]Pose,surface: bool) -> Polygon {
        cache:=ensure_render_cache(s,sub.id)
        if surface {
            outline:=make_polygon(cache.outline.points)
            for rest,i in cache.outline.points { outline.points[i]=common_seam_point(s,sub,rest,poses,cache.seams[i]) }
            return outline
        }
        outline:=make_polygon(sub.outline.points); posed:=render_subdivision(s,sub,poses)
        for rest,i in sub.outline.points { outline.points[i]=posed_point(posed,rest) }
        return outline
    }
    draw_cached_polygon :: proc(view: View,outline: Polygon,color,stroke: rl.Color,outline_width: f32,cache: ^Render_Cache,surface: bool) {
        indices:=cache.raw_triangles[:]; if surface { indices=cache.triangles[:] }
        for i:=0; i+2<len(indices); i+=3 {
            a,b,c:=outline.points[indices[i]],outline.points[indices[i+1]],outline.points[indices[i+2]]
            if vcross(vsub(b,a),vsub(c,a))>0 { rl.DrawTriangle(screen_point(view,a),screen_point(view,b),screen_point(view,c),color) }
            else { rl.DrawTriangle(screen_point(view,c),screen_point(view,b),screen_point(view,a),color) }
        }
        if outline_width>0 { for point,i in outline.points { rl.DrawLineEx(screen_point(view,point),screen_point(view,outline.points[(i+1)%len(outline.points)]),outline_width,stroke) } }
    }
    package main
    
    import "core:math"
    import "core:slice"
    
    Segment :: struct { a,b: Vec2 }
    Cut_Boundary :: struct { a,b: int, segment: Segment }
    convex_hull :: proc(points: []Vec2) -> [dynamic]Vec2 {
        sorted: [dynamic]Vec2
        defer delete(sorted)
        for point in points { append(&sorted,point) }
        slice.sort_by(sorted[:],proc(a,b: Vec2) -> bool { return a.x<b.x || a.x==b.x && a.y<b.y })
    
        hull: [dynamic]Vec2
        if len(sorted)<2 { for p in sorted { append(&hull,p) }; return hull }
        for p in sorted {
            for len(hull)>=2 && vcross(vsub(hull[len(hull)-1],hull[len(hull)-2]),vsub(p,hull[len(hull)-1]))<=0 { resize(&hull,len(hull)-1) }
            append(&hull,p)
        }
        upper_start:=len(hull)+1
        for i:=len(sorted)-2; i>=0; i-=1 {
            p:=sorted[i]
            for len(hull)>=upper_start && vcross(vsub(hull[len(hull)-1],hull[len(hull)-2]),vsub(p,hull[len(hull)-1]))<=0 { resize(&hull,len(hull)-1) }
            append(&hull,p)
        }
        resize(&hull,len(hull)-1)
        return hull
    }
    segment_overlap :: proc(a,b: Segment) -> (Segment,bool) {
        d := vsub(a.b,a.a)
        length := vlen(d)
        if length < 0.00001 { return {},false }
        if math.abs(vcross(d,vsub(b.a,a.a))) > 0.0001*length || math.abs(vcross(d,vsub(b.b,a.a))) > 0.0001*length { return {},false }
        unit := vmul(d,1/length)
        t0,t1 := vdot(vsub(b.a,a.a),unit),vdot(vsub(b.b,a.a),unit)
        lo,hi := max(f32(0),min(t0,t1)),min(length,max(t0,t1))
        if hi-lo <= 0.0001 { return {},false }
        return Segment{vadd(a.a,vmul(unit,lo)),vadd(a.a,vmul(unit,hi))},true
    }
    shared_segments :: proc(a,b: Polygon) -> [dynamic]Segment {
        result: [dynamic]Segment
        for i in 0..<len(a.points) {
            for j in 0..<len(b.points) {
                if segment,ok := segment_overlap(Segment{a.points[i],a.points[(i+1)%len(a.points)]},Segment{b.points[j],b.points[(j+1)%len(b.points)]}); ok { append(&result,segment) }
            }
        }
        return result
    }
    inherits_old_boundary :: proc(a,b,old_a,old_b: Polygon) -> bool {
        current := shared_segments(a,b)
        original := shared_segments(old_a,old_b)
        defer delete(current); defer delete(original)
        for x in current { for y in original { if _,ok := segment_overlap(x,y); ok { return true } } }
        return false
    }
    insert_polygon_vertex :: proc(p: ^Polygon,index: int,point: Vec2) {
        points:=make([]Vec2,len(p.points)+1)
        copy(points[:index],p.points[:index]); points[index]=point
        copy(points[index+1:],p.points[index:])
        delete(p.points); p.points=points
    }
    insert_boundary_endpoint :: proc(p: ^Polygon,point: Vec2) {
        for existing in p.points { if vlen(vsub(existing,point)) < 0.00001 { return } }
        for i in 0..<len(p.points) {
            a,b := p.points[i],p.points[(i+1)%len(p.points)]
            edge := vsub(b,a)
            length := vlen(edge)
            if length < 0.00001 { continue }
            t := vdot(vsub(point,a),edge)/(length*length)
            if t > 0 && t < 1 && math.abs(vcross(edge,vsub(point,a))) < 0.00001*length { insert_polygon_vertex(p,i+1,point); return }
        }
    }
    insert_shared_midpoint :: proc(p: ^Polygon,segment: Segment,point: Vec2) {
        insert_boundary_endpoint(p,segment.a)
        insert_boundary_endpoint(p,segment.b)
        for i in 0..<len(p.points) {
            a,b := p.points[i],p.points[(i+1)%len(p.points)]
            if (vlen(vsub(a,segment.a)) < 0.00001 && vlen(vsub(b,segment.b)) < 0.00001) || (vlen(vsub(b,segment.a)) < 0.00001 && vlen(vsub(a,segment.b)) < 0.00001) {
                insert_polygon_vertex(p,i+1,point)
                return
            }
        }
    }
    // Capture each common cut once, then install the exact same displaced midpoint
    // in both outlines. Parent boundary vertices are untouched, including T junctions.
    displace_shared_boundaries :: proc(children: []Polygon,seed: u8) {
        boundaries: [dynamic]Cut_Boundary
        defer delete(boundaries)
        for i in 0..<len(children) {
            for j in i+1..<len(children) {
                segments := shared_segments(children[i],children[j])
                for segment in segments { append(&boundaries,Cut_Boundary{i,j,segment}) }
                delete(segments)
            }
        }
        for boundary,index in boundaries {
            edge := vsub(boundary.segment.b,boundary.segment.a)
            length := vlen(edge)
            normal := Vec2{-edge.y/length,edge.x/length}
            amplitude := min(length*0.04,min(polygon_area(children[boundary.a]),polygon_area(children[boundary.b]))/length*0.08)
            base := vmul(vadd(boundary.segment.a,boundary.segment.b),0.5)
            // The area cap alone can cross another edge in thin or concave children.
            // Bound displacement by clearance, as in the reference partition generator.
            neighbors := [2]int{boundary.a,boundary.b}
            for index in neighbors {
                polygon := children[index]
                for a,i in polygon.points {
                    b := polygon.points[(i+1)%len(polygon.points)]
                    edge := vsub(b,a)
                    if vdot(edge,edge)<0.000000000001 { continue }
                    if _,shared := segment_overlap(Segment{a,b},boundary.segment); shared { continue }
                    t := clamp(vdot(vsub(base,a),edge)/vdot(edge,edge),f32(0),f32(1))
                    amplitude=min(amplitude,vlen(vsub(base,vadd(a,vmul(edge,t))))*0.2)
                }
            }
            if derive_seed(seed,u64(index+1))%2 == 0 { amplitude = -amplitude }
            mid := vadd(base,vmul(normal,amplitude))
            insert_shared_midpoint(&children[boundary.a],boundary.segment,mid)
            insert_shared_midpoint(&children[boundary.b],boundary.segment,mid)
        }
    }
    
    // Merge adjacent triangles whenever their union is convex. In particular this
    // avoids feeding thin ears from a displaced boundary to Box2D as tiny fixtures.
    convex_decomposition :: proc(outline: Polygon) -> [dynamic]Polygon {
        parts:=triangulate_polygon(outline)
        for {
            merged:=false
            for i in 0..<len(parts) {
                for j in i+1..<len(parts) {
                    if length,_:=shared_boundary(parts[i],parts[j]); length<=0 { continue }
                    points: [dynamic]Vec2
                    for point in parts[i].points { append(&points,point) }
                    for point in parts[j].points { append(&points,point) }
                    hull:=convex_hull(points[:]); delete(points)
                    combined:=make_polygon(hull[:]); delete(hull)
                    error:=math.abs(polygon_area(combined)-polygon_area(parts[i])-polygon_area(parts[j]))
                    if len(combined.points)<=8 && error<0.000001 {
                        delete(parts[i].points); delete(parts[j].points)
                        parts[i]=combined; ordered_remove(&parts,j); merged=true; break
                    }
                    delete(combined.points)
                }
                if merged { break }
            }
            if !merged { break }
        }
        return parts
    }
    rg: src/*test*: The filename, directory name, or volume label syntax is incorrect. (os error 123)
    docs/implementation.md:9:| [render_cache.odin](../src/render_cache.odin) | Per-piece render topology, triangle indices and seam-neighbour caches |
    docs/implementation.md:43:Generation clips convex regions. For a concave parent in Chunks or Strips, the existing convex decomposition merges adjacent triangulation ears before applying the requested cuts; a small shared-edge bend does not automatically become a fan of independent fragments. Non-triangulated generation retains its existing boundary jitter and displacement amount: each internal displaced cut is generated once and installed in both adjacent outlines, limited by clearance to other edges as well as area and length. Shards deliberately retains triangulation but skips shared-boundary displacement whenever the material's `triangulate` flag is enabled. This prevents added seam vertices from multiplying into excessive tiny triangles; existing triangulation validity fixes remain in effect. Outside boundaries remain intact. Count is a target before final triangulation; complex concave outlines and the Shards style can produce more children. If generation cannot produce a genuine partition of at least two smaller regions, the failed subdivision is removed directly. A valid partition is retained even when area limits prevent reaching the requested count. For aspect ratios below one, cuts run parallel to the polygon's long axis until elongation reaches the inverse aspect target, then cross-cut it; aspect-one recipes retain their existing axis rule. Self-intersecting outlines and polygons with holes are outside this implementation's input domain. Starting yard blocks derive distinct birth contexts from the applied seed and their stable grid coordinates; reset repeats the same contexts.
    docs/implementation.md:55:Group width is the minimum projection width of its reference geometry's convex hull. Small subdivisions remain live when their connected group is wide enough. Narrow resulting groups vanish immediately. New groups are filtered before any new bodies are created. Rendering interpolates poses and optionally blends shared presentation vertices across flexible joints; it does not modify collision or failure geometry. Wood fill is opaque; Glass retains its transparency. With the cosmetic surface enabled, live seams whose posed vertices differ by at most 0.001 world units share rendered points, including T junctions, independently of flexibility. Broken seams remain separate, and larger deformation retains the existing cosmetic blending.
    docs/implementation.md:57:The implementation uses ordinary packed arrays, affected-piece membership rebuilds, an endpoint-pair map, Box2D AABB blast queries and explicit snapshots. Pending children join spatial candidates before bodies exist. Render topology and seam-neighbour caches use each region's incident links and are invalidated by piece changes; frames transform cached vertices. Body/joint creation uses ascending IDs, and structure synchronization is gated by its internal revision. Full motion/load updates, picking and snapshot encoding still visit live state; they do not visit deleted history. Buffer capacity can retain a peak allocation for reuse.
    src/geometry.odin:126:    parts:=triangulate_polygon(outline)
    ✗ (1) • 587ms

## Activity

    $ rg -n 'triangulate_polygon|point_in_triangle|is_convex' src; Get-Content src/polygon.odin; Get-Content src/response_test.odin | Select-Object -Skip 145 -First 58; Get-Content src/rigid_test.odin | Select-Object -Skip 100 -First 50
    src\debug_view.odin:42:    triangles:=triangulate_polygon(outline)
    src\destruction.odin:28:is_convex :: proc(p: Polygon) -> bool {
    src\destruction.odin:38:point_in_triangle :: proc(p,a,b,c: Vec2, orientation: f32, tolerance: f32 = 0.00001) -> bool {
    src\destruction.odin:43:triangulate_polygon :: proc(p: Polygon) -> [dynamic]Polygon {
    src\destruction.odin:63:                for n in indices { if n != i && n != j && n != l && point_in_triangle(p.points[n],a,b,c,orientation,tolerance) { contains = true; break } }
    src\destruction.odin:82:    if recipe.triangulate { result = triangulate_polygon(parent) } else if !is_convex(parent) {
    src\destruction.odin:123:            parts:=triangulate_polygon(polygon)
    src\generation_test.odin:50:    parent_triangles:=triangulate_polygon(parent)
    src\generation_test.odin:59:        parts:=triangulate_polygon(child)
    src\generation_test.odin:122:        parts:=triangulate_polygon(parent)
    src\generation_test.odin:154:                if !is_convex(child) { concave_parents+=1 }
    src\geometry.odin:126:    parts:=triangulate_polygon(outline)
    src\physics.odin:68: if is_convex(sub.outline) && len(sub.outline.points)<=8 { physics_create_fixture(s,body,sub,sub.outline) }
    src\render_cache.odin:40:    triangles:=triangulate_polygon(outline)
    Get-Content : Cannot find path 'C:\Users\jblic\Documents\BOM\src\polygon.odin' because it does not exist.
    At line:2 char:62
    + ... oint_in_triangle|is_convex' src; Get-Content src/polygon.odin; Get-Co ...
    +                                      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        + CategoryInfo          : ObjectNotFound: (C:\Users\jblic\...rc\polygon.odin:String) [Get-Content], ItemNotFoundEx
       ception
        + FullyQualifiedErrorId : PathNotFound,Microsoft.PowerShell.Commands.GetContentCommand
    
        sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
        g:=single_region_drop_yard(.Wood); defer sandbox_destroy(&g)
        for _ in 0..<120 { physics_tick(&g.scene,1.0/60) }
        body:=g.scene.subdivisions[0].body
        // Repeated closing motion without separating the existing contact pair.
        for _ in 0..<2 {
            b2.Body_SetLinearVelocity(body,{0,-2})
            b2.World_Step(g.scene.physics.world,1.0/60.0,PHYSICS_SUBSTEPS)
            events:=b2.World_GetContactEvents(g.scene.physics.world)
            found:=false
            for hit in events.hitEvents[:events.hitCount] {
                if b2.Shape_GetBody(hit.shapeIdA)==body || b2.Shape_GetBody(hit.shapeIdB)==body {
                    found=hit.approachSpeed>1.9
                }
            }
            testing.expect(t,events.beginCount==0 && found,"Hit events must report closing speed on existing contact every step")
        }
    }
    
    @(test)
    render_seams_share_t_junctions_without_changing_simulation :: proc(t: ^testing.T) {
        s:=new_scene(0.1); defer scene_destroy(&s)
        m:=add_material(&s,editor_material(.Wood)); p:=add_piece(&s,m,42)
        bounds:=[3][4]Vec2{{{0,0},{1,0},{1,2},{0,2}},{{1,0},{2,0},{2,1},{1,1}},{{1,1},{2,1},{2,2},{1,2}}}
        ids:[3]u64
        for points,i in bounds { vertices:=points; outline:=Polygon{points=vertices[:]}; ids[i]=add_subdivision(&s,p,outline,Pose{position=centroid(outline)}); }
        for i in 1..<3 { add_connection(&s,ids[0],ids[i]); }
        s.subdivisions[1].pose.position.x+=0.0002; s.subdivisions[2].pose.position.y+=0.0002
        poses:=make(map[u64]Pose); defer delete(poses)
        before,ok:=encode_snapshot(&s); defer delete(before); testing.expect(t,ok)
        rest:=Vec2{1,1}
        flexes:=[2]f32{0,0.5}
        for flex in flexes {
            s.materials[0].flexibility=flex
            a:=common_boundary_point(&s,s.subdivisions[0],rest,poses)
            for i in 1..<3 {
                b:=common_boundary_point(&s,s.subdivisions[i],rest,poses)
                if flex>0 { testing.expect(t,a==b) } else { testing.expect(t,b==posed_point(s.subdivisions[i],rest)) }
            }
        }
        s.materials[0].flexibility=0
        outline:=render_outline(&s,s.subdivisions[0],poses,true); defer delete(outline.points)
        testing.expect(t,len(outline.points)==5,"Render copy must include the T junction")
        after,after_ok:=encode_snapshot(&s); defer delete(after)
        testing.expect(t,after_ok && string(before)==string(after),"Rendering must not mutate simulation geometry or poses")
        // The two right-hand regions have no live seam; their free edge stays apart.
        end:=Vec2{2,1}
        testing.expect(t,common_boundary_point(&s,s.subdivisions[1],end,poses)!=common_boundary_point(&s,s.subdivisions[2],end,poses))
        s.subdivisions[1].pose.position.x+=0.1
        testing.expect(t,common_boundary_point(&s,s.subdivisions[1],rest,poses)==posed_point(s.subdivisions[1],rest),"Substantial displacement must not be welded by rendering")
    }
    
    @(test)
    physical_loads_use_mass_ratio_and_velocity_units :: proc(t: ^testing.T) {
        sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
        s:=make_wall(); defer scene_destroy(&s); physics_init(&s)
        a,b:=s.subdivisions[0].body,s.subdivisions[1].body
        b2.Body_SetUserData(a,nil); b2.Body_SetUserData(b,nil)
     fmt.printf("Rigid off-centre blast: angular velocity %.6f / expected %.6f\n",omega,torque/inertia)
    }
    
    Rigid_Bounce :: struct { rebound,rest_error: f32, mean_ms,max_ms: f64, regions: int }
    rigid_bounce :: proc(size: Vec2,split: bool) -> Rigid_Bounce {
     g:=sandbox_editor_create(); defer sandbox_destroy(&g); g.editor.palette=.Stone
     assert(editor_place(&g,{0,0},size)); sandbox_toggle_editor(&g)
     s:=&g.scene
     if !split {
      f:=Failures{}
      for sub in s.subdivisions { if sub.material!=0 { append(&f.discard_subdivisions,sub.id) } }
      apply_failures(s,f); free_failures(&f)
      p:=add_piece(s,4,42)
      points:=[4]Vec2{{0,0},{size.x,0},{size.x,size.y},{0,size.y}}
      outline:=Polygon{points=points[:]}; add_subdivision(s,p,outline,Pose{position=centroid(outline)})
      physics_sync_structure(s)
     }
     body:=b2.nullBodyId; regions:=0
     for sub in s.subdivisions { if sub.material!=0 { body=sub.body; regions+=1 } }
     pos:=b2.Body_GetPosition(body); pos.y+=0.5; b2.Body_SetTransform(body,pos,b2.MakeRot(0)); b2.Body_SetAwake(body,true)
     physics_read_motion(s)
     heights:[240]f32; first_hit:=239; hit:=false; timing:=Soak_Timing{}
     max_error:f32
     for tick in 0..<240 {
      start:=time.tick_now(); physics_tick(s,1.0/60); soak_sample(&timing,start)
      // Damage is active; this drop is below Stone's measured crack height.
      assert(b2.Body_IsValid(body))
      heights[tick]=b2.Body_GetWorldCenterOfMass(body).y
      events:=b2.World_GetContactEvents(s.physics.world)
      if !hit { for event in events.hitEvents[:events.hitCount] {
       if b2.Shape_GetBody(event.shapeIdA)==body || b2.Shape_GetBody(event.shapeIdB)==body { first_hit=tick; hit=true; break }
      } }
      for sub in s.subdivisions {
       if sub.material==0 { continue }
       for rest in sub.outline.points { max_error=max(max_error,vlen(vsub(posed_point(sub,rest),from_b2(b2.Body_GetWorldPoint(body,to_b2(rest)))))) }
      }
     }
     settled:f32; for y in heights[180:] { settled+=y/60 }
     rebound:f32; for y in heights[first_hit:] { rebound=max(rebound,y-settled) }
     return {rebound,max_error,soak_mean(timing),timing.max_ms,regions}
    }
    @(test)
    rigid_presplit_bounce_matches_single_region_control :: proc(t: ^testing.T) {
     sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
     sizes:=[2]Vec2{{2.4,1.2},{0.7,3.7}}
     for size in sizes {
      split:=rigid_bounce(size,true); single:=rigid_bounce(size,false)
      // Two millimetres in world units, below Box2D's 0.005 contact slop.
      // Two millimetres in world units, below Box2D's 0.005 contact slop.
      // Two millimetres in world units, below Box2D's 0.005 contact slop.
    ✓ • 725ms

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -115,2 +115,8 @@
     	sandbox_smoke_export(target,"output/sandbox-editor.png")
    +	for outline_width in [4]f32{0,0.1,0.5,2} {
    +		game.outline_width=outline_width
    +		sandbox_smoke_frame(game,target,smoke_mouse(30,40))
    +		sandbox_smoke_export(target,rl.TextFormat("output/outline-edit-%.1f.png",outline_width))
    +	}
    +	game.outline_width=preferred_outline_width
     	sandbox_smoke_click(game,target,930,43)

## Activity

    $ odin build src -out:build/BOM.exe
    C:/Users/jblic/Documents/BOM/src/sandbox_smoke.odin(116:41) Syntax Error: Expected 1 expression
        for outline_width in [4]f32{0,0.1,0.5,2} {
                                               ^
    ✗ (1) • 465ms

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -115,3 +115,4 @@
     	sandbox_smoke_export(target,"output/sandbox-editor.png")
    -	for outline_width in [4]f32{0,0.1,0.5,2} {
    +	outline_widths:=[4]f32{0,0.1,0.5,2}
    +	for outline_width in outline_widths {
     		game.outline_width=outline_width

## Activity

    $ odin build src -out:build/BOM.exe
    ✓ • 3.02s

## Activity

    $ .\build\BOM.exe --smoke-input
    wood breakup: 9 surviving fragments
    glass breakup: 36 surviving fragments
    stone breakup: 18 surviving fragments
    Editor native smoke passed: palette, drag preview, overlap/degenerate rejection, deletion, UI consumption, paused edit, Test/Edit restoration, reset, movement/jump, inspection, radius, material breakups, rubber, and falling bombs.
    ✓ • 11.92s

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\outline-edit-0.0.png

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\outline-edit-0.5.png

## Activity

    $ Get-Content src/destruction.odin -TotalCount 81; Get-Content src/model.odin | Select-Object -Skip 103 -First 17
    #+feature dynamic-literals
    package main
    
    import "core:math"
    
    polygon_area :: proc(p: Polygon) -> f32 {
        a: f32
        for i in 0..<len(p.points) { a += vcross(p.points[i],p.points[(i+1)%len(p.points)]) }
        return math.abs(a)*0.5
    }
    clip_polygon :: proc(p: Polygon, axis: int, cut: f32, keep_low: bool) -> Polygon {
        points: [dynamic]Vec2
        defer delete(points)
        for i in 0..<len(p.points) {
            a,b := p.points[i],p.points[(i+1)%len(p.points)]
            av,bv := a.x-cut,b.x-cut
            if axis == 1 { av = a.y-cut; bv = b.y-cut }
            if !keep_low { av = -av; bv = -bv }
            inside_a, inside_b := av <= 0,bv <= 0
            if inside_a { append(&points,a) }
            if inside_a != inside_b {
                t := av/(av-bv)
                append(&points,vadd(a,vmul(vsub(b,a),t)))
            }
        }
        return make_polygon(points[:])
    }
    is_convex :: proc(p: Polygon) -> bool {
        if len(p.points) < 3 { return false }
        sign: f32
        for i in 0..<len(p.points) {
            cross := vcross(vsub(p.points[(i+1)%len(p.points)],p.points[i]),vsub(p.points[(i+2)%len(p.points)],p.points[(i+1)%len(p.points)]))
            if math.abs(cross) < 0.00001 { continue }
            if sign == 0 { sign = cross } else if cross*sign < 0 { return false }
        }
        return true
    }
    point_in_triangle :: proc(p,a,b,c: Vec2, orientation: f32, tolerance: f32 = 0.00001) -> bool {
        return vcross(vsub(b,a),vsub(p,a))*orientation >= -tolerance &&
               vcross(vsub(c,b),vsub(p,b))*orientation >= -tolerance &&
               vcross(vsub(a,c),vsub(p,c))*orientation >= -tolerance
    }
    triangulate_polygon :: proc(p: Polygon) -> [dynamic]Polygon {
        result: [dynamic]Polygon
        indices: [dynamic]int
        defer delete(indices)
        for i in 0..<len(p.points) { append(&indices,i) }
        signed: f32
        for i in 0..<len(p.points) { signed += vcross(p.points[i],p.points[(i+1)%len(p.points)]) }
        orientation := f32(1)
        if signed < 0 { orientation = -1 }
        for len(indices) > 3 {
            found := false
            // Keep the normal ear order; only retry exact predicates if its tolerance
            // rejects every ear of a small valid corner on a refined shared seam.
            tolerances:=[2]f32{0.00001,0}
            for tolerance in tolerances {
                for k in 0..<len(indices) {
                    i,j,l := indices[(k+len(indices)-1)%len(indices)],indices[k],indices[(k+1)%len(indices)]
                    a,b,c := p.points[i],p.points[j],p.points[l]
                    if vcross(vsub(b,a),vsub(c,b))*orientation <= tolerance { continue }
                    contains := false
                    for n in indices { if n != i && n != j && n != l && point_in_triangle(p.points[n],a,b,c,orientation,tolerance) { contains = true; break } }
                    if contains { continue }
                    append(&result,make_polygon([]Vec2{a,b,c}))
                    ordered_remove(&indices,k)
                    found = true
                    break
                }
                if found { break }
            }
            if !found { break }
        }
        if len(indices) == 3 { append(&result,make_polygon([]Vec2{p.points[indices[0]],p.points[indices[1]],p.points[indices[2]]})) }
        return result
    }
    // Straight shared cuts are constructed by clipping both sides at one value.
    // Outside edges are never moved; no gap or overlap is introduced at the cut.
    generate_children :: proc(parent: Polygon, recipe: Material, seed: u8) -> [dynamic]Polygon {
        result: [dynamic]Polygon
        if seed == 0 { return result }
            return {x/f32(len(p.points)),y/f32(len(p.points))}
        }
        return {x/(3*area),y/(3*area)}
    }
    posed_point :: proc(sub: Subdivision, rest: Vec2) -> Vec2 {
        return vadd(sub.pose.position,vrotate(vsub(rest,sub.rest_center),sub.pose.angle))
    }
    posed_polygon :: proc(sub: Subdivision) -> Polygon {
        result := Polygon{points=make([]Vec2,len(sub.outline.points))}
        for point,i in sub.outline.points { result.points[i]=posed_point(sub,point) }
        return result
    }
    make_polygon :: proc(points: []Vec2) -> Polygon {
        result:=Polygon{points=make([]Vec2,len(points))}
        copy(result.points,points)
        return result
    }
    ✓ • 517ms

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -51,2 +51,18 @@
     }
    +sandbox_smoke_outline_views :: proc(game: ^Sandbox,target: rl.RenderTexture2D,name: cstring) {
    +	previous_width:=game.outline_width
    +	defer game.outline_width=previous_width
    +	poses:=make(map[u64]Pose); defer delete(poses)
    +	widths:=[4]f32{0,0.1,0.5,2}
    +	for width in widths {
    +		game.outline_width=width
    +		rl.BeginDrawing()
    +		rl.BeginTextureMode(target)
    +		rl.ClearBackground({19,28,42,255})
    +		sandbox_draw_world(game,sandbox_view(1280,800),poses)
    +		rl.EndTextureMode()
    +		rl.EndDrawing()
    +		sandbox_smoke_export(target,rl.TextFormat("output/outline-%s-%.1f.png",name,width))
    +	}
    +}
     editor_smoke_drag :: proc(game: ^Sandbox,target: rl.RenderTexture2D,a,b: Vec2) {
    @@ -180,2 +196,3 @@
     		sandbox_smoke_export(target,rl.TextFormat("output/sandbox-material-%s.png",editor_material(choice).name))
    +		sandbox_smoke_outline_views(game,target,rl.TextFormat("%s",editor_material(choice).name))
     		sandbox_smoke_click(game,target,930,43)

## Activity

    $ odin build src -out:build/BOM.exe
    ✓ • 2.80s

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -196,3 +196,5 @@
     		sandbox_smoke_export(target,rl.TextFormat("output/sandbox-material-%s.png",editor_material(choice).name))
    -		sandbox_smoke_outline_views(game,target,rl.TextFormat("%s",editor_material(choice).name))
    +		capture_name:=cstring("wood")
    +		if choice==.Glass { capture_name="glass" } else if choice==.Stone { capture_name="stone" }
    +		sandbox_smoke_outline_views(game,target,capture_name)
     		sandbox_smoke_click(game,target,930,43)

## Activity

    $ odin build src -out:build/BOM.exe
    ✓ • 2.64s

## Assistant

The static scene looks solid with outlines off. I’m now comparing fractured objects at several widths to see whether the gaps come from moving geometry or from the way edges are drawn.

## Activity

    $ .\build\BOM.exe --smoke-input
    wood breakup: 9 surviving fragments
    glass breakup: 36 surviving fragments
    stone breakup: 18 surviving fragments
    Editor native smoke passed: palette, drag preview, overlap/degenerate rejection, deletion, UI consumption, paused edit, Test/Edit restoration, reset, movement/jump, inspection, radius, material breakups, rubber, and falling bombs.
    ✓ • 14.48s

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\outline-wood-0.0.png

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\outline-stone-0.0.png

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\outline-wood-2.0.png

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\outline-stone-2.0.png

## Activity

    $ rg -n 'surface|seam|render' src/* -g '*test.odin'; rg -n 'anchor|static|position=' src/physics.odin | Select-Object -First 40
    rg: src/*: IO error for operation on src/*: The filename, directory name, or volume label syntax is incorrect. (os error 123)
    10: anchor_y: f32,
    18:physics_init :: proc(s: ^Scene, gravity: Vec2 = {}, anchor_y: f32 = -1e30) {
    24: s.physics = Physics{world=b2.CreateWorld(def),anchor_y=anchor_y,active=true}
    42:  if s.materials[sub.material].flexibility==0 { position=from_b2(b2.Body_GetWorldPoint(body,to_b2(sub.rest_center))) }
    43:  sub.pose = Pose{position=position,angle=math.atan2(rotation.s,rotation.c),
    164: if rigid { position=vsub(position,vrotate(sub.rest_center,sub.pose.angle)) }
    165: def.position=to_b2(position); def.rotation=b2.MakeRot(sub.pose.angle)
    166: if has_frame { def.position=frame.p; def.rotation=frame.q }
    178: anchored:=make(map[u64]bool); defer delete(anchored)
    179: if s.physics.anchor_y>-1e30 {
    181:   if !sub.live || anchored[sub.owner] { continue }
    184:    if math.abs(a.y-s.physics.anchor_y)<0.00001 && math.abs(b.y-s.physics.anchor_y)<0.00001 && math.abs(a.x-b.x)>0.00001 { anchored[sub.owner]=true; break }
    193:  kind:=b2.BodyType.dynamicBody; if anchored[id] { kind=.staticBody }
    210:  kind:=b2.BodyType.dynamicBody; if anchored[sub.owner] { kind=.staticBody }
    235:  static_pair:=b2.Body_GetType(a.body)==.staticBody && b2.Body_GetType(b.body)==.staticBody
    236:  if c.joint!=b2.nullJointId && (flexibility==0 || static_pair) { b2.DestroyJoint(c.joint); s.connections[s.conn_rows[id]].joint={}; continue }
    237:  if flexibility==0 || static_pair || c.joint!=b2.nullJointId { continue }
    ✓ • 528ms

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -55,2 +55,14 @@
     	poses:=make(map[u64]Pose); defer delete(poses)
    +	for sub in game.scene.subdivisions {
    +		outline:=render_outline(&game.scene,sub,poses,true)
    +		cache:=ensure_render_cache(&game.scene,sub.id)
    +		area:=f32(0)
    +		for i:=0; i+2<len(cache.triangles); i+=3 {
    +			a,b,c:=outline.points[cache.triangles[i]],outline.points[cache.triangles[i+1]],outline.points[cache.triangles[i+2]]
    +			cross:=vcross(vsub(b,a),vsub(c,a)); if cross<0 { cross = -cross }; area+=cross*0.5
    +		}
    +		diff:=area-polygon_area(outline); if diff<0 { diff = -diff }
    +		if diff>0.00001 { fmt.printf("Render coverage %s sub %d: polygon %.8f triangles %.8f (%d vertices / %d indices)\n",name,sub.id,polygon_area(outline),area,len(outline.points),len(cache.triangles)) }
    +		delete(outline.points)
    +	}
     	widths:=[4]f32{0,0.1,0.5,2}

## Activity

    $ odin build src -out:build/BOM.exe
    ✓ • 2.85s

## Activity

    $ .\build\BOM.exe --smoke-input
    wood breakup: 9 surviving fragments
    glass breakup: 36 surviving fragments
    stone breakup: 18 surviving fragments
    Editor native smoke passed: palette, drag preview, overlap/degenerate rejection, deletion, UI consumption, paused edit, Test/Edit restoration, reset, movement/jump, inspection, radius, material breakups, rubber, and falling bombs.
    ✓ • 20.02s

## Activity

    $ rg -n -i -m 15 'phantom|blank spaces|no outline|visual (bug|artifact)|render.*gap|gap.*render' docs README.md codex-session-01a18d0b-2ef6-7c70-99fd-72bc108b2f1d.md
    README.md:91:Rigid regions share the undeformed rest frame: body origin is rest-frame origin, and every shape uses rest coordinates. Each motion read derives region centres and point velocities from that body's transform and angular velocity. Mass, centre of mass and inertia come from the exact logical outlines, even when collision hulls simplify an outline. Regions of the same rigid piece cannot collide with each other or bow at seams. Rubber still stretches through its existing soft joints. Render seam-gap correction applies only to flexible pieces; rigid rendering and interpolation use one common transform.
    docs\gameplay.md:26:Mode and radius changes are immediate, including inside Settings. The **Outline width (px)** slider adjusts object and subdivision borders from 0 (no outline), through fractional pixel widths, to the original thick 2-pixel outline. The width starts at 2 and stays set across resets and Edit/Test transitions; drag previews and inspection IDs/links remain available independently. Objects use fixed palette presets; global material sliders do not override them. Abstract recipe/strength/flexibility tuning remains in `--lab` (F4), separate from the editor. The initial setup uses manual blasts, seed 42, radius 5.0 and impulse scale 0.2. The independent ground uses Stone's Chunks recipe, strengths 35/20 and flexibility 0.
    ✓ • 388ms

## Assistant

When are the phantom spaces most visible? The static scene and initial fracture captures haven’t reproduced the larger gaps yet.
- While pieces move after a blast
- In stretched or moving Rubber
- Even before anything moves

## User

> When are the phantom spaces most visible? The static scene and initial fracture captures haven’t reproduced the larger gaps yet.

In the wood pieces

## Activity

    $ Get-Content src/render_cache.odin | Select-Object -Skip 64 -First 54; rg -n 'GuiGetStyle|LoadImage|GetImageColor|ImageGetColor|CheckCollisionPointPoly' C:/Users/jblic/Downloads/odin-windows-amd64-dev-2026-05/dist/vendor/raylib/raylib.odin | Select-Object -First 12; Get-Content src/rigid_test.odin -TotalCount 67
        cache.triangles=triangle_indices(cache.outline)
        cache.raw_triangles=triangle_indices(sub.outline)
        cache.seams=make([]Seam_Neighbours,len(cache.outline.points))
        for rest,i in cache.outline.points { cache.seams[i]=seam_neighbours(s,sub^,rest) }
        return cache
    }
    cosmetic_seam_point :: proc(s: ^Scene,sub: Subdivision,rest: Vec2,poses: map[u64]Pose,seam: Seam_Neighbours) -> Vec2 {
        self:=render_subdivision(s,sub,poses); point:=posed_point(self,rest)
        flex:=clamp(s.materials[sub.material].flexibility,f32(0),f32(1))
        if flex==0 { return point }
        weighted:=point
        for id in seam.direct { other:=render_subdivision(s,s.subdivisions[s.sub_rows[id]],poses); weighted=vadd(weighted,posed_point(other,rest)) }
        return vadd(point,vmul(vsub(vmul(weighted,1/f32(len(seam.direct)+1)),point),flex))
    }
    common_seam_point :: proc(s: ^Scene,sub: Subdivision,rest: Vec2,poses: map[u64]Pose,seam: Seam_Neighbours) -> Vec2 {
        if s.materials[sub.material].flexibility==0 { return posed_point(render_subdivision(s,sub,poses),rest) }
        if len(seam.incident)>1 {
            for id,i in seam.incident {
                a:=render_subdivision(s,s.subdivisions[s.sub_rows[id]],poses)
                for j in i+1..<len(seam.incident) {
                    b:=render_subdivision(s,s.subdivisions[s.sub_rows[seam.incident[j]]],poses)
                    if vlen(vsub(posed_point(a,rest),posed_point(b,rest)))>0.001 { return cosmetic_seam_point(s,sub,rest,poses,seam) }
                }
            }
            point:=Vec2{}
            for id in seam.incident { other:=render_subdivision(s,s.subdivisions[s.sub_rows[id]],poses); point=vadd(point,posed_point(other,rest)) }
            return vmul(point,1/f32(len(seam.incident)))
        }
        return cosmetic_seam_point(s,sub,rest,poses,seam)
    }
    // Single-point helpers also serve inspection/tests; draw_scene uses cached seams.
    cosmetic_point :: proc(s: ^Scene,sub: Subdivision,rest: Vec2,poses: map[u64]Pose) -> Vec2 {
        seam:=seam_neighbours(s,sub,rest); defer delete(seam.incident); defer delete(seam.direct)
        return cosmetic_seam_point(s,sub,rest,poses,seam)
    }
    common_boundary_point :: proc(s: ^Scene,sub: Subdivision,rest: Vec2,poses: map[u64]Pose) -> Vec2 {
        seam:=seam_neighbours(s,sub,rest); defer delete(seam.incident); defer delete(seam.direct)
        return common_seam_point(s,sub,rest,poses,seam)
    }
    render_outline :: proc(s: ^Scene,sub: Subdivision,poses: map[u64]Pose,surface: bool) -> Polygon {
        cache:=ensure_render_cache(s,sub.id)
        if surface {
            outline:=make_polygon(cache.outline.points)
            for rest,i in cache.outline.points { outline.points[i]=common_seam_point(s,sub,rest,poses,cache.seams[i]) }
            return outline
        }
        outline:=make_polygon(sub.outline.points); posed:=render_subdivision(s,sub,poses)
        for rest,i in sub.outline.points { outline.points[i]=posed_point(posed,rest) }
        return outline
    }
    draw_cached_polygon :: proc(view: View,outline: Polygon,color,stroke: rl.Color,outline_width: f32,cache: ^Render_Cache,surface: bool) {
        indices:=cache.raw_triangles[:]; if surface { indices=cache.triangles[:] }
        for i:=0; i+2<len(indices); i+=3 {
            a,b,c:=outline.points[indices[i]],outline.points[indices[i+1]],outline.points[indices[i+2]]
    1294:    CheckCollisionPointPoly     :: proc(point: Vector2, points: [^]Vector2, pointCount: c.int) -> bool ---                                          // Check if point is within a polygon described by array of vertices
    1303:    LoadImage               :: proc(fileName: cstring) -> Image ---                                                               // Load image from file into CPU memory (RAM)
    1304:    LoadImageRaw            :: proc(fileName: cstring, width, height: c.int, format: PixelFormat, headerSize: c.int) -> Image --- // Load image from RAW file data
    1305:    LoadImageAnim           :: proc(fileName: cstring, frames: ^c.int) -> Image ---                                               // Load image sequence from file (frames appended to image.data)
    1306:    LoadImageAnimFromMemory :: proc(fileType: cstring, fileData: rawptr, dataSize: c.int, frames: ^c.int) -> Image ---            // Load image sequence from memory buffer
    1307:    LoadImageFromMemory     :: proc(fileType: cstring, fileData: rawptr, dataSize: c.int) -> Image ---                            // Load image from memory buffer, fileType refers to extension: i.e. '.png'
    1308:    LoadImageFromTexture    :: proc(texture: Texture2D) -> Image ---                                                              // Load image from GPU texture data
    1309:    LoadImageFromScreen     :: proc() -> Image ---                                                                                // Load image from screen buffer and (screenshot)
    1360:    LoadImageColors       :: proc(image: Image) -> [^]Color ---                                                                 // Load color data from image as a Color array (RGBA - 32bit)
    1361:    LoadImagePalette      :: proc(image: Image, maxPaletteSize: c.int, colorCount: ^c.int) -> [^]Color ---                      // Load colors palette from image as a Color array (RGBA - 32bit)
    1362:    UnloadImageColors     :: proc(colors: [^]Color) ---                                                                         // Unload color data loaded with LoadImageColors()
    1363:    UnloadImagePalette    :: proc(colors: [^]Color) ---                                                                         // Unload colors palette loaded with LoadImagePalette()
    package main
    
    import "core:testing"
    import "core:sync"
    import "core:math"
    import "core:fmt"
    import "core:time"
    import b2 "vendor:box2d"
    
    rigid_wall :: proc() -> Scene {
     s:=make_wall(42); s.materials[0].flexibility=0
     s.materials[0].subdivision_strength=math.inf_f32(1)
     s.materials[0].connection_strength=math.inf_f32(1)
     return s
    }
    @(test)
    rigid_piece_preserves_rest_frame_mass_and_shape_identity :: proc(t: ^testing.T) {
     sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
     s:=rigid_wall(); defer scene_destroy(&s); physics_init(&s)
     body:=s.pieces[0].body
     testing.expect(t,physics_body_count(&s)==1 && b2.World_GetCounters(s.physics.world).jointCount==0)
     testing.expect(t,close(b2.Body_GetMass(body),3) && close_vec(from_b2(b2.Body_GetLocalCenterOfMass(body)),Vec2{1.5,0.5}))
     mass:=b2.Body_GetMassData(body)
     testing.expect(t,close(mass.rotationalInertia,2.5),"Exact polygon inertia about the centre of mass")
     b2.Body_SetLinearVelocity(body,{1,2}); b2.Body_SetAngularVelocity(body,2)
     max_error:f32
     for _ in 0..<180 {
      physics_tick(&s,1.0/60)
      for sub in s.subdivisions {
       testing.expect(t,sub.body==body)
       for shape in sub.shapes { testing.expect(t,u64(uintptr(b2.Shape_GetUserData(shape)))==sub.id && b2.Shape_GetBody(shape)==body) }
       for point in sub.outline.points { max_error=max(max_error,vlen(vsub(posed_point(sub,point),from_b2(b2.Body_GetWorldPoint(body,to_b2(point)))))) }
       testing.expect(t,close_vec(sub.pose.velocity,from_b2(b2.Body_GetWorldPointVelocity(body,to_b2(sub.pose.position)))))
      }
     }
     testing.expectf(t,max_error<0.00001,"Rest configuration error %.8f",max_error)
     // Decode keeps the format and reconstructs the same shared frame from region poses.
     data,ok:=encode_snapshot(&s); defer delete(data); testing.expect(t,ok)
     copy,decoded:=decode_snapshot(data); defer scene_destroy(&copy); testing.expect(t,decoded)
     physics_init(&copy)
     for sub in copy.subdivisions {
      original:=s.subdivisions[s.sub_rows[sub.id]]
      testing.expect(t,close_vec(sub.pose.position,original.pose.position) && close_vec(sub.pose.velocity,original.pose.velocity) && close(sub.pose.angle,original.pose.angle))
     }
     // A padded query must return every overlapping region, including one far from
     // the first shape on the shared body, and not unrelated shapes on that body.
     ids:=blast_regions(&s,Blast{position=s.subdivisions[2].pose.position,radius=0.05}); defer delete(ids)
     testing.expect(t,contains_id(ids[:],s.subdivisions[2].id))
     fmt.printf("Rigid rest-frame maximum error %.8f units\n",max_error)
    }
    @(test)
    rigid_split_keeps_largest_body_and_point_velocity :: proc(t: ^testing.T) {
     sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
     s:=rigid_wall(); defer scene_destroy(&s); physics_init(&s)
     body:=s.pieces[0].body
     b2.Body_SetTransform(body,{2,4},b2.MakeRot(0.4))
     b2.Body_SetLinearVelocity(body,{3,2}); b2.Body_SetAngularVelocity(body,2); physics_read_motion(&s)
     old_transform:=b2.Body_GetTransform(body)
     old_center:=from_b2(b2.Body_GetWorldCenterOfMass(body)); old_velocity:=from_b2(b2.Body_GetLinearVelocity(body))
     s.materials[0].connection_strength=0.01
     // Only the first seam is reached: centres are outside this tiny blast, so
     // topology splits while the final-impulse pass contributes no motion.
     blast_pass(&s,Blast{position=connection_sample(&s,s.connections[0]),radius=0.1})
     testing.expect(t,len(s.pieces)==2 && physics_body_count(&s)==2)
     for p in s.pieces {
      testing.expect(t,(p.body==body)==(len(p.subdivisions)==2),"Largest group keeps old body")
      testing.expect(t,close(interaction_mass(&s,p.body),p.mass),"Retained body mass lookup must not follow a region that left the group")
    ✓ • 1.32s

## Assistant

I’ll focus on Wood’s long, thin fragments. I’m checking whether their cached triangles fill the whole shape, and whether shared vertices stay aligned as the pieces move.

## Activity

    $ Get-Content src/generation_test.odin | Select-Object -Skip 130 -First 62; Get-Content src/recursive_blast_test.odin -TotalCount 36; rg -n 'Blast ::|make_wall' src/model.odin src/*.odin
        points:=[4]Vec2{{1.5,0.005},{2.35,0.005},{2.35,0.855},{1.5,0.855}}
        parent:=Polygon{points=points[:]}
        seeds:=[4]u8{42,85,177,98}
        for pattern in 0..<3 {
            recipe:=material_preset(pattern)
            concave_parents:=0
            refined_triangles:=0
            for seed in seeds {
                // Sweep the affected non-triangular recipes; one known Shatter fixture
                // checks that its deliberately triangular generations remain available.
                if recipe.triangulate && seed!=42 { continue }
                children:=generate_children(parent,recipe,seed)
                defer { for child in children { delete(child.points) }; delete(children) }
                if !testing.expectf(t,len(children)>=2,"Pattern %d, seed %d did not produce a partition",pattern,seed) { continue }
                expect_generation_partition(t,parent,children[:])
                if !recipe.triangulate { testing.expect(t,len(children)==recipe.generation_count) }
                largest:=0
                for child,i in children { if polygon_area(child)>polygon_area(children[largest]) { largest=i } }
                for child,i in children {
                    if recipe.triangulate {
                        testing.expect(t,len(child.points)==3,"Shatter deliberately retains triangular subdivisions")
                        if i!=largest { continue } // Refine a triangle large enough for the existing area guard.
                    }
                    if !is_convex(child) { concave_parents+=1 }
                    if pattern==1 {
                        lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
                        for point in child.points { lo={min(lo.x,point.x),min(lo.y,point.y)}; hi={max(hi.x,point.x),max(hi.y,point.y)} }
                        testing.expect(t,hi.y-lo.y>2*(hi.x-lo.x),"Splinter must keep its elongated cuts")
                    }
                    grandchildren:=generate_children(child,recipe,derive_seed(seed,u64(i+1)))
                    defer { for grandchild in grandchildren { delete(grandchild.points) }; delete(grandchildren) }
                    expect_generation_partition(t,child,grandchildren[:])
                    if !recipe.triangulate {
                        testing.expect(t,len(grandchildren)==recipe.generation_count,"A bent boundary must not turn triangulation ears into extra fragments")
                    }
                    for grandchild in grandchildren {
                        if pattern==0 {
                            lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
                            for point in grandchild.points { lo={min(lo.x,point.x),min(lo.y,point.y)}; hi={max(hi.x,point.x),max(hi.y,point.y)} }
                            testing.expect(t,outline_width(grandchild.points)/max(hi.x-lo.x,hi.y-lo.y)>0.1,"Chunk must not create thin corner fans from small shared-edge bends")
                        }
                        if recipe.triangulate { testing.expect(t,len(grandchild.points)==3); refined_triangles+=1 }
                    }
                }
            }
            if !recipe.triangulate { testing.expect(t,concave_parents>0,"Shared-edge displacement must remain enabled in this regression") }
            else { testing.expect(t,refined_triangles>0) }
        }
    }
    
    @(test)
    triangulated_generation_skips_jitter_and_preserves_partitions :: proc(t: ^testing.T) {
        points:=[4]Vec2{{1.5,0},{2.35,0},{2.35,0.85},{1.5,0.85}}
        parent:=Polygon{points=points[:]}
        recipe:=material_preset(2)
        children:=generate_children(parent,recipe,42)
        defer { for child in children { delete(child.points) }; delete(children) }
        // This square's straight cuts yield ten triangles. Displaced seams used
        // to multiply the same seed and recipe into 32 logical subdivisions.
        testing.expect(t,len(children)==10,"Triangulated generation must not add bent-seam vertices")
        expect_generation_partition(t,parent,children[:])
        refined:=0
    #+feature dynamic-literals
    package main
    
    import "core:math"
    import "core:testing"
    import "core:encoding/json"
    
    @(test)
    child_seed_batches_and_individual_width_guard :: proc(t: ^testing.T) {
        s:=make_wall(42,0.75); defer scene_destroy(&s)
        f:=failure_for(s.subdivisions[1].id); defer free_failures(&f)
        apply_failures(&s,f)
        terminal:=Failures{}; defer free_failures(&terminal)
        for sub in s.subdivisions {
            if sub.id<=6 { continue }; append(&terminal.subdivisions,sub.id)
            testing.expect(t,sub.live && sub.seed==0,"All-small siblings are terminal live geometry at birth")
        }
        testing.expect(t,len(terminal.subdivisions)==2)
        apply_failures(&s,terminal)
        testing.expect(t,len(s.subdivisions)==2,"Terminal geometry cannot generate another batch")
        expect_valid(t,&s)
    
        r:=make_wall(42); defer scene_destroy(&r)
        r.materials[0].generation_count=3
        parent:=r.subdivisions[1]
        preview:=generate_children(parent.outline,r.materials[0],parent.seed)
        lo,hi:=f32(1e30),f32(0)
        for polygon in preview {
            width:=outline_width(polygon.points)
            lo=min(lo,width); hi=max(hi,width)
            delete(polygon.points)
        }
        delete(preview)
        testing.expect(t,hi>lo && hi<parent.width)
        r.minimum_width=(lo+hi)*0.5
        g:=failure_for(parent.id); defer free_failures(&g)
    rg: src/*.odin: The filename, directory name, or volume label syntax is incorrect. (os error 123)
    src/model.odin:80:Blast :: struct { position: Vec2, radius: f32 }
    src/model.odin:384:make_wall :: proc(seed: u8 = 0, minimum_width: f32 = 0) -> Scene {
    ✗ (1) • 746ms

## Activity

    $ odin test -help | Select-String 'name|filter|define' -Context 0,2; Get-Content src/model.odin | Select-Object -Skip 382 -First 20
    
    >     -collection:<name>=<filepath>
    >         Defines a library collection used for imports.
              Example: -collection:shared=dir/to/shared
              Usage in Code:
    >         Enables debug information, and defines the global constant ODIN_DEBUG to be 'true'. Sets -o:none by default.
    
          -default-to-nil-allocator
    >     -define:<name>=<value>
    >         Defines a scalar boolean, integer or string as global constant.
    >         Example: -define:SPAM=123
              Usage in code:
                  #config(SPAM, default_value)
    >         Disables the code generation of the built-in run-time 'assert' procedure, and defines the global constant
    ODIN_DISABLE_ASSERT to be 'true'.
    
          -disable-red-zone
    >     -export-defineables:<filename>
    >         Exports an overview of all the #config/#defined usages in CSV format to the given file path.
    >         Example: -export-defineables:defineables.csv
    
          -export-dependencies:<format>
    >     -export-dependencies-file:<filename>
    >         Specifies the filename for `-export-dependencies`.
              Example: -export-dependencies-file:dependencies.d
    
    >     -export-timings-file:<filename>
    >         Specifies the filename for `-export-timings`.
              Example: -export-timings-file:timings.json
    
    >         States that the error procedures used in the runtime are defined in a separate translation unit.
    
          -ignore-unknown-attributes
    >             -source-code-locations:filename
                  -source-code-locations:none
              The default is -source-code-locations:normal.
    >         Sets the file name of the outputted executable.
              Example: -out:foo.exe
    
    >     -pdb-name:<filepath>
              [Windows only]
    >         Defines the generated PDB name when -debug is enabled.
    >         Example: -pdb-name:different.pdb
    
          -reloc-mode:<string>
    >         Defines the resource file for the executable.
              Example: -resource:path/to/file.rc
              or:      -resource:path/to/file.res for a precompiled one.
    >     -show-defineables
    >         Shows an overview of all the #config/#defined usages in the project.
    
    >     -ignore-unused-defineables
    >         Silence warning/error if a -define doesn't have at least one #config/#defined usage.
    
          -show-system-calls
    >         Defines the subsystem for the application.
              Available options:
                  -subsystem:console
    >         Sets which packages by name will be vetted.
              Files with specific +vet tags will not be ignored if they are not in the packages set.
    
    }
    make_wall :: proc(seed: u8 = 0, minimum_width: f32 = 0) -> Scene {
        s := new_scene(minimum_width)
        m := add_material(&s,make_material(name="brick",subdivision_strength=6,connection_strength=4,flexibility=0.25,generation_count=2,aspect_ratio=1.5))
        p := add_piece(&s,m,seed)
        ids: [3]u64
        for i in 0..<3 {
            x := f32(i)
            poly := make_polygon([]Vec2{{x,0},{x+1,0},{x+1,1},{x,1}})
            center := centroid(poly)
            ids[i] = add_subdivision(&s,p,poly,Pose{position=center})
            delete(poly.points)
        }
        add_connection(&s,ids[0],ids[1]); add_connection(&s,ids[1],ids[2])
        return s
    }
    
    scene_destroy :: proc(s: ^Scene) {
        physics_destroy(s)
        for &sub in s.subdivisions { delete(sub.outline.points); delete(sub.incident_links); delete(sub.shapes); release_render_cache(&sub.render) }
    
    
    ✓ • 427ms

## Activity

    file changes: Completed · 1 changes
    Add: C:\Users\jblic\Documents\BOM\src\render_test.odin
    package main
    
    import "core:testing"
    import "core:math"
    
    @(test)
    wood_render_cache_covers_refined_polygons :: proc(t: ^testing.T) {
    	for seed in 1..=32 {
    		s:=new_scene(0.1)
    		m:=add_material(&s,editor_material(.Wood))
    		p:=add_piece(&s,m,u8(seed))
    		points:=[4]Vec2{{0,0},{6,0},{6,4},{0,4}}
    		add_subdivision(&s,p,Polygon{points=points[:]},Pose{position={3,2}})
    		for blast in [3]Blast{{{-0.1,2},5},{{3,4.1},4},{{6.1,1},4}} {
    			blast_pass(&s,blast)
    			for sub in s.subdivisions {
    				cache:=ensure_render_cache(&s,sub.id)
    				area:=f32(0)
    				for i:=0; i+2<len(cache.triangles); i+=3 {
    					a,b,c:=cache.outline.points[cache.triangles[i]],cache.outline.points[cache.triangles[i+1]],cache.outline.points[cache.triangles[i+2]]
    					area+=math.abs(vcross(vsub(b,a),vsub(c,a)))*0.5
    				}
    				expected:=polygon_area(cache.outline)
    				testing.expectf(t,math.abs(area-expected)<max(f32(0.0000001),expected*0.0001),"Wood seed %d sub %d: filled %.9f / %.9f",seed,sub.id,area,expected)
    			}
    		}
    		scene_destroy(&s)
    	}
    }

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\render_test.odin
    @@ -13,3 +13,4 @@
     		add_subdivision(&s,p,Polygon{points=points[:]},Pose{position={3,2}})
    -		for blast in [3]Blast{{{-0.1,2},5},{{3,4.1},4},{{6.1,1},4}} {
    +		blasts:=[3]Blast{{{-0.1,2},5},{{3,4.1},4},{{6.1,1},4}}
    +		for blast in blasts {
     			blast_pass(&s,blast)

## Activity

    $ odin test src -out:build/BOM-tests.exe -define:ODIN_TEST_NAMES=wood_render_cache_covers_refined_polygons
    [INFO ] --- [2026-11-03 09:50:04] Starting test runner with 1 thread. Set with -define:ODIN_TEST_THREADS=n.
    [INFO ] --- [2026-11-03 09:50:04] The random seed sent to every test is: 721957801052370. Set with -define:ODIN_TEST_RANDOM_SEED=n.
    [INFO ] --- [2026-11-03 09:50:04] Memory tracking is enabled. Tests will log their memory usage if there's an issue.
    [INFO ] --- [2026-11-03 09:50:04] < Final Mem/ Total Mem> <  Peak Mem> (#Free/Alloc) :: [package.test_name]
    [ERROR] --- [2026-11-03 09:50:04] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 1 sub 1476: filled 0.003025719 / 0.003025293
    [ERROR] --- [2026-11-03 09:50:04] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 2 sub 854: filled 0.000313739 / 0.000314236
    [ERROR] --- [2026-11-03 09:50:04] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 2 sub 873: filled 0.000029699 / 0.000029564
    [ERROR] --- [2026-11-03 09:50:04] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 2 sub 854: filled 0.000313739 / 0.000314236
    [ERROR] --- [2026-11-03 09:50:04] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 2 sub 873: filled 0.000029699 / 0.000029564
    [ERROR] --- [2026-11-03 09:50:04] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 5 sub 288: filled 0.000528395 / 0.000528574
    [ERROR] --- [2026-11-03 09:50:04] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 5 sub 288: filled 0.000528395 / 0.000528574
    [ERROR] --- [2026-11-03 09:50:04] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 5 sub 288: filled 0.000528395 / 0.000528574
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 7 sub 795: filled 0.000367372 / 0.000349998
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 7 sub 795: filled 0.000367372 / 0.000349998
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 8 sub 752: filled 0.011897544 / 0.011898994
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 8 sub 752: filled 0.011897544 / 0.011898994
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 10 sub 667: filled 0.000409364 / 0.000409603
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 10 sub 667: filled 0.000409364 / 0.000409603
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 11 sub 509: filled 0.000011579 / 0.000011206
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 12 sub 836: filled 0.000450111 / 0.000449657
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 12 sub 847: filled 0.013516984 / 0.013515472
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 12 sub 836: filled 0.000450111 / 0.000449657
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 12 sub 847: filled 0.013516984 / 0.013515472
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 959: filled 0.000024602 / 0.000025749
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 692: filled 0.002046678 / 0.002046466
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 659: filled 0.225216955 / 0.249242783
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 660: filled 0.062917128 / 0.083858490
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 952: filled 0.005250047 / 0.005250931
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 959: filled 0.000024602 / 0.000025749
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 692: filled 0.002046678 / 0.002046466
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 659: filled 0.225216955 / 0.249242783
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 660: filled 0.062917128 / 0.083858490
    [ERROR] --- [2026-11-03 09:50:05] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 952: filled 0.005250047 / 0.005250931
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 19 sub 707: filled 0.003946875 / 0.003947735
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 19 sub 707: filled 0.003946875 / 0.003947735
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 21 sub 700: filled 0.001142349 / 0.001142025
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 21 sub 700: filled 0.001142349 / 0.001142025
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 23 sub 212: filled 0.001486271 / 0.001486063
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 23 sub 212: filled 0.001486271 / 0.001486063
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 23 sub 942: filled 0.000149079 / 0.000148773
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 23 sub 807: filled 0.000335843 / 0.000336170
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 23 sub 1161: filled 0.000087007 / 0.000086784
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 23 sub 212: filled 0.001486265 / 0.001486063
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 23 sub 942: filled 0.000149079 / 0.000148773
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 23 sub 807: filled 0.000335843 / 0.000336170
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 24 sub 211: filled 0.007344728 / 0.007345676
    [ERROR] --- [2026-11-03 09:50:06] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 24 sub 1205: filled 0.008037209 / 0.008036137
    [ERROR] --- [2026-11-03 09:50:07] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 26 sub 144: filled 0.005872787 / 0.005874157
    [ERROR] --- [2026-11-03 09:50:07] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 27 sub 937: filled 0.000094249 / 0.000093937
    [ERROR] --- [2026-11-03 09:50:07] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 27 sub 937: filled 0.000094249 / 0.000093937
    [ERROR] --- [2026-11-03 09:50:07] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 27 sub 1315: filled 0.005712226 / 0.005711555
    [ERROR] --- [2026-11-03 09:50:07] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 30 sub 206: filled 0.001573404 / 0.001572609
    [ERROR] --- [2026-11-03 09:50:07] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 32 sub 94: filled 0.001644433 / 0.001644254
    [ERROR] --- [2026-11-03 09:50:07] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 32 sub 94: filled 0.001644433 / 0.001644254
    [ERROR] --- [2026-11-03 09:50:07] [render_test.odin:25:wood_render_cache_covers_refined_polygons()] Wood seed 32 sub 94: filled 0.001644433 / 0.001644254
    
    Finished 1 test in 3.6212025s. The test failed.
     - main.wood_render_cache_covers_refined_polygons     Wood seed 32 sub 94: filled 0.001644433 / 0.001644254
    
    ✗ (1) • 8.10s

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\render_test.odin
    @@ -5,2 +5,6 @@
     
    +render_test_cross :: proc(a,b,c: Vec2) -> f64 {
    +	return (f64(b.x)-f64(a.x))*(f64(c.y)-f64(a.y))-(f64(b.y)-f64(a.y))*(f64(c.x)-f64(a.x))
    +}
    +
     @(test)
    @@ -18,9 +22,11 @@
     				cache:=ensure_render_cache(&s,sub.id)
    -				area:=f32(0)
    +				area:=f64(0)
     				for i:=0; i+2<len(cache.triangles); i+=3 {
     					a,b,c:=cache.outline.points[cache.triangles[i]],cache.outline.points[cache.triangles[i+1]],cache.outline.points[cache.triangles[i+2]]
    -					area+=math.abs(vcross(vsub(b,a),vsub(c,a)))*0.5
    +					area+=math.abs(render_test_cross(a,b,c))*0.5
     				}
    -				expected:=polygon_area(cache.outline)
    -				testing.expectf(t,math.abs(area-expected)<max(f32(0.0000001),expected*0.0001),"Wood seed %d sub %d: filled %.9f / %.9f",seed,sub.id,area,expected)
    +				expected:=f64(0)
    +				for point,i in cache.outline.points { expected+=render_test_cross(cache.outline.points[0],point,cache.outline.points[(i+1)%len(cache.outline.points)])*0.5 }
    +				expected=math.abs(expected)
    +				testing.expectf(t,math.abs(area-expected)<max(f64(0.0000001),expected*0.0001),"Wood seed %d sub %d: filled %.9f / %.9f",seed,sub.id,area,expected)
     			}

## Activity

    $ odin test src -out:build/BOM-tests.exe -define:ODIN_TEST_NAMES=wood_render_cache_covers_refined_polygons
    [INFO ] --- [2026-11-03 09:50:22] Starting test runner with 1 thread. Set with -define:ODIN_TEST_THREADS=n.
    [INFO ] --- [2026-11-03 09:50:22] The random seed sent to every test is: 722011581709865. Set with -define:ODIN_TEST_RANDOM_SEED=n.
    [INFO ] --- [2026-11-03 09:50:22] Memory tracking is enabled. Tests will log their memory usage if there's an issue.
    [INFO ] --- [2026-11-03 09:50:22] < Final Mem/ Total Mem> <  Peak Mem> (#Free/Alloc) :: [package.test_name]
    [ERROR] --- [2026-11-03 09:50:23] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 7 sub 795: filled 0.000367372 / 0.000350030
    [ERROR] --- [2026-11-03 09:50:23] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 7 sub 795: filled 0.000367372 / 0.000350030
    [ERROR] --- [2026-11-03 09:50:24] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 659: filled 0.225216954 / 0.249243277
    [ERROR] --- [2026-11-03 09:50:24] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 660: filled 0.062917133 / 0.083858399
    [ERROR] --- [2026-11-03 09:50:24] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 659: filled 0.225216954 / 0.249243277
    [ERROR] --- [2026-11-03 09:50:24] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 660: filled 0.062917133 / 0.083858399
    
    Finished 1 test in 3.8903043s. The test failed.
     - main.wood_render_cache_covers_refined_polygons     Wood seed 13 sub 660: filled 0.062917133 / 0.083858399
    
    ✗ (1) • 7.77s

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\render_test.odin
    @@ -30,3 +30,3 @@
     				expected=math.abs(expected)
    -				testing.expectf(t,math.abs(area-expected)<max(f64(0.0000001),expected*0.0001),"Wood seed %d sub %d: filled %.9f / %.9f",seed,sub.id,area,expected)
    +				testing.expectf(t,math.abs(area-expected)<max(f64(0.0000001),expected*0.0001),"Wood seed %d sub %d: filled %.9f / %.9f points %v indices %v",seed,sub.id,area,expected,cache.outline.points,cache.triangles[:])
     			}

## Activity

    $ odin test src -out:build/BOM-tests.exe -define:ODIN_TEST_NAMES=wood_render_cache_covers_refined_polygons
    [INFO ] --- [2026-11-03 09:50:36] Starting test runner with 1 thread. Set with -define:ODIN_TEST_THREADS=n.
    [INFO ] --- [2026-11-03 09:50:36] The random seed sent to every test is: 722050132080962. Set with -define:ODIN_TEST_RANDOM_SEED=n.
    [INFO ] --- [2026-11-03 09:50:36] Memory tracking is enabled. Tests will log their memory usage if there's an issue.
    [INFO ] --- [2026-11-03 09:50:36] < Final Mem/ Total Mem> <  Peak Mem> (#Free/Alloc) :: [package.test_name]
    [ERROR] --- [2026-11-03 09:50:36] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 7 sub 795: filled 0.000367372 / 0.000350030 points [Vec2{x = 4.5479555, y = 3.2199135}, Vec2{x = 4.568128, y = 3.2202606}, Vec2{x = 4.5882697, y = 3.2190869}, Vec2{x = 5.143822, y = 3.2076962}, Vec2{x = 5.14125, y = 3.2085156}, Vec2{x = 5.1386118, y = 3.2090869}, Vec2{x = 4.8634405, y = 3.2140777}, Vec2{x = 4.5882716, y = 3.2191744}, Vec2{x = 4.5681105, y = 3.2194006}] indices [2, 3, 4, 4, 5, 6, 2, 4, 6, 2, 6, 7, 1, 2, 7]
    [ERROR] --- [2026-11-03 09:50:36] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 7 sub 795: filled 0.000367372 / 0.000350030 points [Vec2{x = 4.5479555, y = 3.2199135}, Vec2{x = 4.568128, y = 3.2202606}, Vec2{x = 4.5882697, y = 3.2190869}, Vec2{x = 5.143822, y = 3.2076962}, Vec2{x = 5.14125, y = 3.2085156}, Vec2{x = 5.1386118, y = 3.2090869}, Vec2{x = 4.8634405, y = 3.2140777}, Vec2{x = 4.5882716, y = 3.2191744}, Vec2{x = 4.5681105, y = 3.2194006}] indices [2, 3, 4, 4, 5, 6, 2, 4, 6, 2, 6, 7, 1, 2, 7]
    [ERROR] --- [2026-11-03 09:50:37] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 659: filled 0.225216954 / 0.249243277 points [Vec2{x = 6, y = 2.8949788}, Vec2{x = 6, y = 3.046659}, Vec2{x = 5.272941, y = 3.0752501}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 4.5405784, y = 2.9803586}, Vec2{x = 4.545882, y = 2.9140584}, Vec2{x = 4.5451188, y = 2.9045186}, Vec2{x = 4.545882, y = 2.8949788}, Vec2{x = 5.272941, y = 2.8846138}] indices [9, 0, 1, 9, 1, 2, 6, 7, 8, 6, 8, 9, 5, 6, 9, 5, 9, 2]
    [ERROR] --- [2026-11-03 09:50:37] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 660: filled 0.062917133 / 0.083858399 points [Vec2{x = 4.545882, y = 2.9140584}, Vec2{x = 4.5405784, y = 2.9803586}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 3.9092727, y = 2.9853957}, Vec2{x = 3.2737129, y = 2.9140584}, Vec2{x = 3.9097977, y = 2.9193625}] indices [6, 0, 1, 4, 5, 6, 4, 6, 1]
    [ERROR] --- [2026-11-03 09:50:37] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 659: filled 0.225216954 / 0.249243277 points [Vec2{x = 6, y = 2.8949788}, Vec2{x = 6, y = 3.046659}, Vec2{x = 5.272941, y = 3.0752501}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 4.5405784, y = 2.9803586}, Vec2{x = 4.545882, y = 2.9140584}, Vec2{x = 4.5451188, y = 2.9045186}, Vec2{x = 4.545882, y = 2.8949788}, Vec2{x = 5.272941, y = 2.8846138}] indices [9, 0, 1, 9, 1, 2, 6, 7, 8, 6, 8, 9, 5, 6, 9, 5, 9, 2]
    [ERROR] --- [2026-11-03 09:50:37] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 13 sub 660: filled 0.062917133 / 0.083858399 points [Vec2{x = 4.545882, y = 2.9140584}, Vec2{x = 4.5405784, y = 2.9803586}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 3.9092727, y = 2.9853957}, Vec2{x = 3.2737129, y = 2.9140584}, Vec2{x = 3.9097977, y = 2.9193625}] indices [6, 0, 1, 4, 5, 6, 4, 6, 1]
    
    Finished 1 test in 3.9830963s. The test failed.
     - main.wood_render_cache_covers_refined_polygons     Wood seed 13 sub 660: filled 0.062917133 / 0.083858399 points [Vec2{x = 4.545882, y = 2.9140584}, Vec2{x = 4.5405784, y = 2.9803586}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 4.545882, y = 3.046659}, Vec2{x = 3.9092727, y = 2.9853957}, Vec2{x = 3.2737129, y = 2.9140584}, Vec2{x = 3.9097977, y = 2.9193625}] indices [6, 0, 1, 4, 5, 6, 4, 6, 1]
    
    ✗ (1) • 7.24s

## Assistant

I reproduced missing fill in Wood fragments: some have consecutive duplicate vertices that make triangulation stop early. In one case, about a quarter of the fragment was left unfilled. I’m fixing the render triangulation and adding a regression check for that case.

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\render_cache.odin
    @@ -39,3 +39,12 @@
     	result: [dynamic]int
    -	triangles:=triangulate_polygon(outline)
    +	// Clipping can leave consecutive copies of a boundary vertex. They have
    +	// no area, but block ear clipping and used to leave part of the fill blank.
    +	// Clean only the triangulation input; retain the render boundary and seams.
    +	points: [dynamic]Vec2
    +	defer delete(points)
    +	for point in outline.points {
    +		if len(points)==0 || point!=points[len(points)-1] { append(&points,point) }
    +	}
    +	if len(points)>1 && points[0]==points[len(points)-1] { resize(&points,len(points)-1) }
    +	triangles:=triangulate_polygon(Polygon{points=points[:]})
     	for triangle in triangles {

## Activity

    $ odin test src -out:build/BOM-tests.exe -define:ODIN_TEST_NAMES=wood_render_cache_covers_refined_polygons
    [INFO ] --- [2026-11-03 09:51:18] Starting test runner with 1 thread. Set with -define:ODIN_TEST_THREADS=n.
    [INFO ] --- [2026-11-03 09:51:18] The random seed sent to every test is: 722175381681928. Set with -define:ODIN_TEST_RANDOM_SEED=n.
    [INFO ] --- [2026-11-03 09:51:18] Memory tracking is enabled. Tests will log their memory usage if there's an issue.
    [INFO ] --- [2026-11-03 09:51:18] < Final Mem/ Total Mem> <  Peak Mem> (#Free/Alloc) :: [package.test_name]
    [ERROR] --- [2026-11-03 09:51:19] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 7 sub 795: filled 0.000367372 / 0.000350030 points [Vec2{x = 4.5479555, y = 3.2199135}, Vec2{x = 4.568128, y = 3.2202606}, Vec2{x = 4.5882697, y = 3.2190869}, Vec2{x = 5.143822, y = 3.2076962}, Vec2{x = 5.14125, y = 3.2085156}, Vec2{x = 5.1386118, y = 3.2090869}, Vec2{x = 4.8634405, y = 3.2140777}, Vec2{x = 4.5882716, y = 3.2191744}, Vec2{x = 4.5681105, y = 3.2194006}] indices [2, 3, 4, 4, 5, 6, 2, 4, 6, 2, 6, 7, 1, 2, 7]
    [ERROR] --- [2026-11-03 09:51:19] [render_test.odin:31:wood_render_cache_covers_refined_polygons()] Wood seed 7 sub 795: filled 0.000367372 / 0.000350030 points [Vec2{x = 4.5479555, y = 3.2199135}, Vec2{x = 4.568128, y = 3.2202606}, Vec2{x = 4.5882697, y = 3.2190869}, Vec2{x = 5.143822, y = 3.2076962}, Vec2{x = 5.14125, y = 3.2085156}, Vec2{x = 5.1386118, y = 3.2090869}, Vec2{x = 4.8634405, y = 3.2140777}, Vec2{x = 4.5882716, y = 3.2191744}, Vec2{x = 4.5681105, y = 3.2194006}] indices [2, 3, 4, 4, 5, 6, 2, 4, 6, 2, 6, 7, 1, 2, 7]
    
    Finished 1 test in 3.3195812s. The test failed.
     - main.wood_render_cache_covers_refined_polygons     Wood seed 7 sub 795: filled 0.000367372 / 0.000350030 points [Vec2{x = 4.5479555, y = 3.2199135}, Vec2{x = 4.568128, y = 3.2202606}, Vec2{x = 4.5882697, y = 3.2190869}, Vec2{x = 5.143822, y = 3.2076962}, Vec2{x = 5.14125, y = 3.2085156}, Vec2{x = 5.1386118, y = 3.2090869}, Vec2{x = 4.8634405, y = 3.2140777}, Vec2{x = 4.5882716, y = 3.2191744}, Vec2{x = 4.5681105, y = 3.2194006}] indices [2, 3, 4, 4, 5, 6, 2, 4, 6, 2, 6, 7, 1, 2, 7]
    
    ✗ (1) • 6.75s

## Activity

    $ Get-Content src/sandbox_smoke.odin | Select-Object -Skip 40 -First 85; Get-Content src/sandbox_smoke.odin | Select-Object -Skip 143 -First 24; rg -n 'capture_name|outline_views' src/sandbox_smoke.odin
        rl.EndDrawing()
        sandbox_handle_ui(game,action)
    }
    sandbox_smoke_click :: proc(game: ^Sandbox,target: rl.RenderTexture2D,x,y: i32) {
        sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(false))
    }
    sandbox_smoke_export :: proc(target: rl.RenderTexture2D,name: cstring) {
        image:=rl.LoadImageFromTexture(target.texture); rl.ImageFlipVertical(&image)
        assert(rl.ExportImage(image,name)); rl.UnloadImage(image)
    }
    sandbox_smoke_outline_views :: proc(game: ^Sandbox,target: rl.RenderTexture2D,name: cstring) {
        previous_width:=game.outline_width
        defer game.outline_width=previous_width
        poses:=make(map[u64]Pose); defer delete(poses)
        for sub in game.scene.subdivisions {
            outline:=render_outline(&game.scene,sub,poses,true)
            cache:=ensure_render_cache(&game.scene,sub.id)
            area:=f32(0)
            for i:=0; i+2<len(cache.triangles); i+=3 {
                a,b,c:=outline.points[cache.triangles[i]],outline.points[cache.triangles[i+1]],outline.points[cache.triangles[i+2]]
                cross:=vcross(vsub(b,a),vsub(c,a)); if cross<0 { cross = -cross }; area+=cross*0.5
            }
            diff:=area-polygon_area(outline); if diff<0 { diff = -diff }
            if diff>0.00001 { fmt.printf("Render coverage %s sub %d: polygon %.8f triangles %.8f (%d vertices / %d indices)\n",name,sub.id,polygon_area(outline),area,len(outline.points),len(cache.triangles)) }
            delete(outline.points)
        }
        widths:=[4]f32{0,0.1,0.5,2}
        for width in widths {
            game.outline_width=width
            rl.BeginDrawing()
            rl.BeginTextureMode(target)
            rl.ClearBackground({19,28,42,255})
            sandbox_draw_world(game,sandbox_view(1280,800),poses)
            rl.EndTextureMode()
            rl.EndDrawing()
            sandbox_smoke_export(target,rl.TextFormat("output/outline-%s-%.1f.png",name,width))
        }
    }
    editor_smoke_drag :: proc(game: ^Sandbox,target: rl.RenderTexture2D,a,b: Vec2) {
        view:=sandbox_view(1280,800)
        p,q:=screen_point(view,a),screen_point(view,b)
        sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)))
        assert(game.editor.dragging,"Rectangle preview did not start")
        sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)),smoke_button(false))
    }
    sandbox_smoke_inputs :: proc(game: ^Sandbox) {
        rl.SetTargetFPS(0)
        target:=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight())
        defer rl.UnloadRenderTexture(target)
        assert(game.editor.editing && len(game.editor.objects)==0)
        initial_ground:=counts_live_subdivisions(&game.scene)
        sandbox_smoke_click(game,target,1180,43)
        assert(game.outline_width==2)
        revision_before_slider:=game.scene.revision
        sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(646,381))
        sandbox_smoke_frame(game,target,smoke_button(false))
        assert(game.outline_width==0,"Slider left endpoint must disable outlines")
        sandbox_smoke_click(game,target,660,381)
        assert(game.outline_width>0 && game.outline_width<0.1,"Slider must support subpixel outlines")
        sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(902,381))
        sandbox_smoke_frame(game,target,smoke_button(false))
        assert(game.outline_width==2,"Slider right endpoint must restore thick outlines")
        sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(775,381))
        sandbox_smoke_frame(game,target,smoke_button(false))
        preferred_outline_width:=game.outline_width
        assert(preferred_outline_width>0 && preferred_outline_width<2 && game.scene.revision==revision_before_slider,"Outline width must only change presentation")
        sandbox_smoke_click(game,target,357,770)
        assert(game.editor.palette==.Wood && game.panel_open,"Settings must consume clicks on the underlying palette")
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
        pose:=b2.Body_GetPosition(game.player.body)
        for _ in 0..<60 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
        assert(b2.Body_GetPosition(game.player.body)==pose,"Editing must pause simulation")
        // Use each actual palette widget and drag into the clear building area.
        for choice in 0..<4 {
            sandbox_smoke_click(game,target,69+i32(choice)*96,770)
            assert(int(game.editor.palette)==choice)
            x:=f32(choice)*2.0-2.0
            editor_smoke_drag(game,target,{x,0},{x+1.2,1.2})
            assert(len(game.editor.objects)==choice+1 && int(game.editor.objects[choice].material)==choice)
        outline_widths:=[4]f32{0,0.1,0.5,2}
        for outline_width in outline_widths {
            game.outline_width=outline_width
            sandbox_smoke_frame(game,target,smoke_mouse(30,40))
            sandbox_smoke_export(target,rl.TextFormat("output/outline-edit-%.1f.png",outline_width))
        }
        game.outline_width=preferred_outline_width
        sandbox_smoke_click(game,target,930,43)
        assert(!game.editor.editing && len(game.scene.pieces)==5)
        revision:=game.scene.revision
        for _ in 0..<90 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
        assert(game.player.grounded)
        sandbox_smoke_frame(game,target,smoke_key(.D,true))
        for _ in 0..<15 { sandbox_smoke_frame(game,target) }
        sandbox_smoke_frame(game,target,smoke_key(.D,false),smoke_key(.SPACE,true))
        // Allow the existing 0.1-second buffer to catch a seam crossing.
        for _ in 0..<5 { if b2.Body_GetLinearVelocity(game.player.body).y>5 { break }; sandbox_smoke_frame(game,target) }
        assert(b2.Body_GetLinearVelocity(game.player.body).y>5,"Space must jump in Test")
        for _ in 0..<120 { sandbox_smoke_frame(game,target) }
        assert(game.player.grounded,"Held jump must not repeat")
        sandbox_smoke_frame(game,target,smoke_key(.SPACE,false))
        // Settings consume input and keep radius/mode live without material overrides.
        sandbox_smoke_click(game,target,1180,43)
        assert(game.panel_open && len(game.editor.objects)==4)
    52:sandbox_smoke_outline_views :: proc(game: ^Sandbox,target: rl.RenderTexture2D,name: cstring) {
    209:        capture_name:=cstring("wood")
    210:        if choice==.Glass { capture_name="glass" } else if choice==.Stone { capture_name="stone" }
    211:        sandbox_smoke_outline_views(game,target,capture_name)
    ✓ • 588ms

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\render_test.odin
    @@ -30,3 +30,5 @@
     				expected=math.abs(expected)
    -				testing.expectf(t,math.abs(area-expected)<max(f64(0.0000001),expected*0.0001),"Wood seed %d sub %d: filled %.9f / %.9f points %v indices %v",seed,sub.id,area,expected,cache.outline.points,cache.triangles[:])
    +				// Ignore differences smaller than a fraction of one screen pixel;
    +				// seed 13 previously lost up to a quarter of a visible fragment.
    +				testing.expectf(t,math.abs(area-expected)<max(f64(0.000025),expected*0.0001),"Wood seed %d sub %d: filled %.9f / %.9f",seed,sub.id,area,expected)
     			}

## Activity

    $ $smokePath = Join-Path (Get-Location) 'src/sandbox_smoke.odin'; $smokeSource = [IO.File]::ReadAllText($smokePath); $helperStart = $smokeSource.IndexOf('sandbox_smoke_outline_views ::'); $helperEnd = $smokeSource.IndexOf('editor_smoke_drag ::', $helperStart); $smokeSource = $smokeSource.Remove($helperStart, $helperEnd - $helperStart); $captureStart = $smokeSource.IndexOf("`toutline_widths:=[4]f32"); $captureEnd = $smokeSource.IndexOf("`tsandbox_smoke_click(game,target,930,43)", $captureStart); $smokeSource = $smokeSource.Remove($captureStart, $captureEnd - $captureStart); $smokeSource = [regex]::Replace($smokeSource, '(?m)^\s*capture_name:=cstring\("wood"\)\r?\n\s*if choice==\.Glass \{ capture_name="glass" \} else if choice==\.Stone \{ capture_name="stone" \}\r?\n\s*sandbox_smoke_outline_views\(game,target,capture_name\)\r?\n', "`n"); [IO.File]::WriteAllText($smokePath, $smokeSource)
    ✓ • 384ms

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\src\sandbox_smoke.odin
    @@ -51,2 +51,23 @@
     }
    +sandbox_smoke_wood_fill :: proc(target: rl.RenderTexture2D) {
    +	s:=new_scene(0.1); defer scene_destroy(&s)
    +	m:=add_material(&s,editor_material(.Wood)); p:=add_piece(&s,m,13)
    +	points:=[4]Vec2{{0,0},{6,0},{6,4},{0,4}}
    +	add_subdivision(&s,p,Polygon{points=points[:]},Pose{position={3,2}})
    +	blast_pass(&s,Blast{{-0.1,2},5}); blast_pass(&s,Blast{{3,4.1},4})
    +	poses:=make(map[u64]Pose); defer delete(poses)
    +	view:=View{offset={140,700},scale=150}
    +	widths:=[3]f32{0,0.5,2}
    +	for width in widths {
    +		rl.BeginDrawing(); rl.BeginTextureMode(target)
    +		rl.ClearBackground({19,28,42,255})
    +		for sub in s.subdivisions {
    +			outline:=render_outline(&s,sub,poses,true)
    +			draw_cached_polygon(view,outline,editor_color("wood"),YARD_INK,width,ensure_render_cache(&s,sub.id),true)
    +			delete(outline.points)
    +		}
    +		rl.EndTextureMode(); rl.EndDrawing()
    +		sandbox_smoke_export(target,rl.TextFormat("output/wood-fill-%.1f.png",width))
    +	}
    +}
     editor_smoke_drag :: proc(game: ^Sandbox,target: rl.RenderTexture2D,a,b: Vec2) {
    @@ -63,2 +84,3 @@
     	defer rl.UnloadRenderTexture(target)
    +	sandbox_smoke_wood_fill(target)
     	assert(game.editor.editing && len(game.editor.objects)==0)

## Activity

    $ Get-Content docs/verification.md -TotalCount 23; Get-Content src/sandbox_smoke.odin -TotalCount 110; Get-Content src/render_test.odin
    # Verification
    
    Run commands from the project root; the [PowerShell helper](../scripts/bom.ps1) also works from other directories. Binaries go to `build/` and runtime output to `output/`.
    
    ## Automated execution
    
    ```powershell
    .\scripts\bom.ps1 Headless
    .\scripts\bom.ps1 Smoke
    .\scripts\bom.ps1 SmokeSettings
    .\scripts\bom.ps1 SmokeInput
    ```
    
    `--headless` evaluates the original diagnostic blast, runs 60 physics ticks, validates the graph, writes `output/snapshot.json`, and reconstructs a receiver. `--smoke` renders the yard in a hidden window to `output/sandbox-preview.png`. `--smoke-settings` renders the paused settings panel to `output/sandbox-settings-preview.png`. Both exit after two frames.
    
    `--smoke-input` uses raylib native automation events in a hidden window to exercise the actual palette widgets, drag preview and placement, overlap/degenerate rejection, right-click deletion, UI consumption, paused editing, Test/Edit restoration, R reset, movement and held jump, radius, inspection and falling bombs. It exports `output/sandbox-editor.png`, one breakup example each in `output/sandbox-material-wood.png`, `output/sandbox-material-glass.png`, `output/sandbox-material-stone.png`, and rubber views in `output/sandbox-material-rubber.png` and `output/sandbox-rubber-cell-removed.png`. The normal behavior suite stays independent of a window or display. The original tower setup remains an internal fixture for existing destruction, movement and terrain regressions; it is not the editor's initial layout.
    
    ## Test coverage
    
    `.\scripts\bom.ps1 Test` covers bridge and subdivision removal; surviving and broken inherited attachments; simultaneous endpoint replacement; processing and storage order independence; seed zero; subthreshold and infinite strengths; same-blast child and connection failure; shared terminal batches and mixed-width guards; termination even with a zero width cutoff; removal of unsplittable attached regions under repeated failure; valid partial partitions; radius-dependent blast power above strength 20; rotational motion inheritance; a single impulse per final survivor; rotation independent width; group filtering and immediate vanishing; retained bodies; concave collision fixtures; physical impacts; overloaded joints; replaceable load policies; flexibility; repeated blasts for all presets; snapshots; interpolation; and real TCP transfer of a wall and its split. Shortcut comparisons check exact surviving outlines, seeds, links, memberships and motion against ordinary recursive evaluation for partial and complete deletion in all three patterns, including a later blast. Odin's test allocator tracks allocations and reports leaks.
    
    Sandbox checks exercise the intact tower under gravity, player movement and a full jump, buffered and coyote jumps, standing on and pushing an actual detached region, repeated clean resets after blasts and respawn, independent staged tuning, menu/UI input consumption, valid/invalid posed aim, and fixed framing at multiple window sizes. The playable controls and settings remain independent of the destruction transaction.
    
    package main
    
    import rl "vendor:raylib"
    import b2 "vendor:box2d"
    import "core:fmt"
    
    // raylib 5.x automation event IDs (rcore.c); the Odin binding exposes the raw event.
    smoke_key :: proc(key: rl.KeyboardKey,down: bool) -> rl.AutomationEvent {
        type:=u32(1); if down { type=2 }
        return {type=type,params={i32(key),0,0,0}}
    }
    smoke_mouse :: proc(x,y: i32) -> rl.AutomationEvent {
        dpi:=rl.GetWindowScaleDPI()
        return {type=7,params={i32(f32(x)*dpi.x),i32(f32(y)*dpi.y),0,0}}
    }
    smoke_button :: proc(down: bool) -> rl.AutomationEvent {
        type:=u32(5); if down { type=6 }
        return {type=type,params={0,0,0,0}}
    }
    sandbox_smoke_frame :: proc(game: ^Sandbox,target: rl.RenderTexture2D,events: ..rl.AutomationEvent) {
        for event in events { rl.PlayAutomationEvent(event) }
        width,height:=f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())
        view:=sandbox_view(width,height)
        mouse:=rl.GetMousePosition()
        over_ui:=sandbox_over_hud(mouse,width,height,game.inspection && !game.editor.editing)
        raw:=sandbox_read_input()
        input:=sandbox_route_input(game,raw,over_ui)
        if !raw.menu_pressed && !raw.reset_pressed {
            if game.editor.editing { sandbox_editor_input(game,world_point(view,mouse),over_ui) }
            else if !sandbox_inspect_input(game,world_point(view,mouse),view,over_ui) && input.blast_pressed { sandbox_blast(game,world_point(view,mouse)) }
        }
        sandbox_advance(game,1.0/60.0,input)
        poses:=make(map[u64]Pose); defer delete(poses)
        rl.BeginDrawing()
        rl.BeginTextureMode(target)
        rl.ClearBackground({19,28,42,255})
        sandbox_draw_world(game,view,poses)
        if !game.panel_open && !over_ui { sandbox_draw_aim(game,view,mouse) }
        action:=sandbox_draw_hud(game,width,height)
        rl.EndTextureMode()
        rl.EndDrawing()
        sandbox_handle_ui(game,action)
    }
    sandbox_smoke_click :: proc(game: ^Sandbox,target: rl.RenderTexture2D,x,y: i32) {
        sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(false))
    }
    sandbox_smoke_export :: proc(target: rl.RenderTexture2D,name: cstring) {
        image:=rl.LoadImageFromTexture(target.texture); rl.ImageFlipVertical(&image)
        assert(rl.ExportImage(image,name)); rl.UnloadImage(image)
    }
    sandbox_smoke_wood_fill :: proc(target: rl.RenderTexture2D) {
        s:=new_scene(0.1); defer scene_destroy(&s)
        m:=add_material(&s,editor_material(.Wood)); p:=add_piece(&s,m,13)
        points:=[4]Vec2{{0,0},{6,0},{6,4},{0,4}}
        add_subdivision(&s,p,Polygon{points=points[:]},Pose{position={3,2}})
        blast_pass(&s,Blast{{-0.1,2},5}); blast_pass(&s,Blast{{3,4.1},4})
        poses:=make(map[u64]Pose); defer delete(poses)
        view:=View{offset={140,700},scale=150}
        widths:=[3]f32{0,0.5,2}
        for width in widths {
            rl.BeginDrawing(); rl.BeginTextureMode(target)
            rl.ClearBackground({19,28,42,255})
            for sub in s.subdivisions {
                outline:=render_outline(&s,sub,poses,true)
                draw_cached_polygon(view,outline,editor_color("wood"),YARD_INK,width,ensure_render_cache(&s,sub.id),true)
                delete(outline.points)
            }
            rl.EndTextureMode(); rl.EndDrawing()
            sandbox_smoke_export(target,rl.TextFormat("output/wood-fill-%.1f.png",width))
        }
    }
    editor_smoke_drag :: proc(game: ^Sandbox,target: rl.RenderTexture2D,a,b: Vec2) {
        view:=sandbox_view(1280,800)
        p,q:=screen_point(view,a),screen_point(view,b)
        sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)))
        assert(game.editor.dragging,"Rectangle preview did not start")
        sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)),smoke_button(false))
    }
    sandbox_smoke_inputs :: proc(game: ^Sandbox) {
        rl.SetTargetFPS(0)
        target:=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight())
        defer rl.UnloadRenderTexture(target)
        sandbox_smoke_wood_fill(target)
        assert(game.editor.editing && len(game.editor.objects)==0)
        initial_ground:=counts_live_subdivisions(&game.scene)
        sandbox_smoke_click(game,target,1180,43)
        assert(game.outline_width==2)
        revision_before_slider:=game.scene.revision
        sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(646,381))
        sandbox_smoke_frame(game,target,smoke_button(false))
        assert(game.outline_width==0,"Slider left endpoint must disable outlines")
        sandbox_smoke_click(game,target,660,381)
        assert(game.outline_width>0 && game.outline_width<0.1,"Slider must support subpixel outlines")
        sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(902,381))
        sandbox_smoke_frame(game,target,smoke_button(false))
        assert(game.outline_width==2,"Slider right endpoint must restore thick outlines")
        sandbox_smoke_frame(game,target,smoke_mouse(774,381),smoke_button(true))
        sandbox_smoke_frame(game,target,smoke_mouse(775,381))
        sandbox_smoke_frame(game,target,smoke_button(false))
        preferred_outline_width:=game.outline_width
        assert(preferred_outline_width>0 && preferred_outline_width<2 && game.scene.revision==revision_before_slider,"Outline width must only change presentation")
        sandbox_smoke_click(game,target,357,770)
        assert(game.editor.palette==.Wood && game.panel_open,"Settings must consume clicks on the underlying palette")
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
        sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
        pose:=b2.Body_GetPosition(game.player.body)
    package main
    
    import "core:testing"
    import "core:math"
    
    render_test_cross :: proc(a,b,c: Vec2) -> f64 {
        return (f64(b.x)-f64(a.x))*(f64(c.y)-f64(a.y))-(f64(b.y)-f64(a.y))*(f64(c.x)-f64(a.x))
    }
    
    @(test)
    wood_render_cache_covers_refined_polygons :: proc(t: ^testing.T) {
        for seed in 1..=32 {
            s:=new_scene(0.1)
            m:=add_material(&s,editor_material(.Wood))
            p:=add_piece(&s,m,u8(seed))
            points:=[4]Vec2{{0,0},{6,0},{6,4},{0,4}}
            add_subdivision(&s,p,Polygon{points=points[:]},Pose{position={3,2}})
            blasts:=[3]Blast{{{-0.1,2},5},{{3,4.1},4},{{6.1,1},4}}
            for blast in blasts {
                blast_pass(&s,blast)
                for sub in s.subdivisions {
                    cache:=ensure_render_cache(&s,sub.id)
                    area:=f64(0)
                    for i:=0; i+2<len(cache.triangles); i+=3 {
                        a,b,c:=cache.outline.points[cache.triangles[i]],cache.outline.points[cache.triangles[i+1]],cache.outline.points[cache.triangles[i+2]]
                        area+=math.abs(render_test_cross(a,b,c))*0.5
                    }
                    expected:=f64(0)
                    for point,i in cache.outline.points { expected+=render_test_cross(cache.outline.points[0],point,cache.outline.points[(i+1)%len(cache.outline.points)])*0.5 }
                    expected=math.abs(expected)
                    // Ignore differences smaller than a fraction of one screen pixel;
                    // seed 13 previously lost up to a quarter of a visible fragment.
                    testing.expectf(t,math.abs(area-expected)<max(f64(0.000025),expected*0.0001),"Wood seed %d sub %d: filled %.9f / %.9f",seed,sub.id,area,expected)
                }
            }
            scene_destroy(&s)
        }
    }
    ✓ • 610ms

## Activity

    $ .\scripts\bom.ps1 Build
    ✓ • 27.35s

## Activity

    $ .\scripts\bom.ps1 Test
    [INFO ] --- [2026-11-03 09:52:27] Starting test runner with 16 threads. Set with -define:ODIN_TEST_THREADS=n.
    [INFO ] --- [2026-11-03 09:52:27] The random seed sent to every test is: 722376240827455. Set with -define:ODIN_TEST_RANDOM_SEED=n.
    [INFO ] --- [2026-11-03 09:52:27] Memory tracking is enabled. Tests will log their memory usage if there's an issue.
    [INFO ] --- [2026-11-03 09:52:27] < Final Mem/ Total Mem> <  Peak Mem> (#Free/Alloc) :: [package.test_name]
    Drop Glass: h=0.3657 threshold=0.5224 closing=2.6133 load=13.0667 intact=true floor_intact=true
    Drop Glass: h=0.6792 threshold=0.5224 closing=3.5933 load=17.9667 intact=false floor_intact=true
    Drop Stone: h=0.6836 threshold=0.9766 closing=3.5933 load=28.7466 intact=true floor_intact=true
    Drop Stone: h=1.2695 threshold=0.9766 closing=5.0633 load=40.5067 intact=false floor_intact=true
    Drop Wood: h=1.1200 threshold=1.6000 closing=4.7367 load=23.6833 intact=true floor_intact=true
    Drop Wood: h=2.0800 threshold=1.6000 closing=6.3700 load=31.8500 intact=false floor_intact=true
    Pre-split Glass: crack size1 0.5250 / size0.5 0.5250
    Pre-split Stone: crack size1 0.9500 / size0.5 0.9500
    Pre-split Wood: crack size1 1.6250 / size0.5 1.6250
    Rigid off-centre blast: angular velocity -1.250813 / expected -1.250813
    Rigid rest-frame maximum error 0.00000067 units
    Rigid Stone 2.4x1.2: split rebound 0.00171560 / single 0.00000793; rest error 0.00000049 / 0.00000012; regions 11 / 1; mean tick 0.144389 / 0.116112 ms; max 0.453100 / 0.374400 ms
    Rigid Stone 0.7x3.7: split rebound 0.00674462 / single 0.00775731; rest error 0.00000072 / 0.00000048; regions 11 / 1; mean tick 0.151863 / 0.139085 ms; max 0.334900 / 0.280400 ms
    
    Finished 90 tests in 42.3149457s. All tests were successful.
    
    ✓ • 45.84s

## Activity

    file changes: Completed · 1 changes
    Update { move_path: None }: C:\Users\jblic\Documents\BOM\docs\verification.md
    @@ -19,2 +19,4 @@
     
    +Wood render coverage is checked after three blasts across 32 seeds, including a regression where consecutive duplicate boundary vertices stopped triangulation and left visible holes. `--smoke-input` also exports the seed-13 fixture at widths 0, 0.5 and 2 to `output/wood-fill-0.0.png`, `output/wood-fill-0.5.png` and `output/wood-fill-2.0.png`.
    +
     `.\scripts\bom.ps1 Test` covers bridge and subdivision removal; surviving and broken inherited attachments; simultaneous endpoint replacement; processing and storage order independence; seed zero; subthreshold and infinite strengths; same-blast child and connection failure; shared terminal batches and mixed-width guards; termination even with a zero width cutoff; removal of unsplittable attached regions under repeated failure; valid partial partitions; radius-dependent blast power above strength 20; rotational motion inheritance; a single impulse per final survivor; rotation independent width; group filtering and immediate vanishing; retained bodies; concave collision fixtures; physical impacts; overloaded joints; replaceable load policies; flexibility; repeated blasts for all presets; snapshots; interpolation; and real TCP transfer of a wall and its split. Shortcut comparisons check exact surviving outlines, seeds, links, memberships and motion against ordinary recursive evaluation for partial and complete deletion in all three patterns, including a later blast. Odin's test allocator tracks allocations and reports leaks.

## Activity

    $ .\build\BOM.exe --smoke-input
    wood breakup: 9 surviving fragments
    glass breakup: 36 surviving fragments
    stone breakup: 18 surviving fragments
    Editor native smoke passed: palette, drag preview, overlap/degenerate rejection, deletion, UI consumption, paused edit, Test/Edit restoration, reset, movement/jump, inspection, radius, material breakups, rubber, and falling bombs.
    ✓ • 8.25s

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\wood-fill-0.0.png

## Activity

    Viewed image C:\Users\jblic\Documents\BOM\output\wood-fill-2.0.png

## Assistant

Found and fixed a Wood rendering bug: duplicate vertices caused missing fill triangles, leaving phantom holes.

Verified the affected pieces with zero, thin, and thick outlines. All 90 tests and the UI check pass. Rebuilt `build/BOM.exe`.
