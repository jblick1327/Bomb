package main

import shared "shared"
import "core:testing"
import "core:sync"
import "core:strings"
@(test)
cover_chords_endpoints_concavity_and_self :: proc(t:^testing.T) {
 points:=[6]Vec2{{0,0},{2,0},{2,1},{1,1},{1,2},{0,2}}
 cover:=Cover{}; append(&cover.cells,Cover_Cell{id=1,owner=7,resistance=3,points=points[:],lo={0,0},hi={2,2}}); defer { delete(cover.cells); delete(cover.cuts); delete(cover.candidates) }
 shared.active_cover=&cover; defer { shared.active_cover=nil }
 testing.expect(t,close(cover_distance({3,0.5},{-1,0.5},8),10))
 testing.expect(t,close(cover_distance({3,0.5},{-1,0.5},7),4))
 testing.expect(t,close(cover_distance({0.5,0.5},{-1,0.5},8),3))
 testing.expect(t,close(cover_distance({3,1.5},{-1,1.5},8),7))
 testing.expect(t,close(cover_distance({3,0},{-1,0},8),4))
 testing.expect(t,close(cover_distance({3,3},{-1,3},8),4))
}
@(test)
cover_material_roundtrip :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 g.world.scene.materials[0].blast_resistance=transmute(f32)u32(0x80000000)
 data,ok:=encode_world_snapshot(&g.world); defer delete(data); testing.expect(t,ok && strings.contains(string(data),"blast_resistance"))
 copy,decoded:=decode_world_snapshot(data); testing.expect(t,decoded); defer { scene_destroy(&copy.scene); delete(copy.bombs) }
 for m,i in g.world.scene.materials { testing.expect(t,transmute(u32)m.blast_resistance==transmute(u32)copy.scene.materials[i].blast_resistance) }
 again,encoded:=encode_world_snapshot(&copy); defer delete(again); testing.expect(t,encoded && string(data)==string(again))
 legacy,loaded:=decode_world_snapshot(transmute([]byte)#load("../evidence/world-v3/before-v2-ticked.json")); testing.expect(t,loaded); defer { scene_destroy(&legacy.scene); delete(legacy.bombs) }
 for m in legacy.scene.materials { testing.expect(t,m.blast_resistance==0) }
 wire:=read_world_state(&g.world); defer release_world_state(&wire); wire.scene.materials[0].blast_resistance=f32(-1)
 invalid,_:=exact_json_encode(wire); defer delete(invalid)
 rejected,accepted:=decode_world_snapshot(invalid); testing.expect(t,!accepted); if accepted { scene_destroy(&rejected.scene); delete(rejected.bombs) }
}

@(test)
cover_wall_protects_wood :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 g.editor.palette=recipe_slot(.Stone); testing.expect(t,editor_place(&g,{2,0},{2.4,2.4})); g.editor.palette=recipe_slot(.Wood); testing.expect(t,editor_place(&g,{2.6,0},{3.6,1.6})); sandbox_toggle_editor(&g)
 when #config(BOM_COVER_TEST_BASELINE,false) { for &m in g.world.scene.materials { m.blast_resistance=0 } }
 shared.cover_wood_failures=0; blast_pass(&g.world.scene,Blast{{1,1},5})
 area:f32; for sub in g.world.scene.subdivisions { if sub.live && g.world.scene.materials[sub.material].name=="wood" { area+=polygon_area(sub.outline) } }
 testing.expect(t,1.6-area<0.001 && shared.cover_wood_failures==0,"Wall must prevent Wood cell failure")
}

@(test)
cover_grid_matches_exhaustive_rays :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 g.editor.palette=recipe_slot(.Stone); testing.expect(t,editor_place(&g,{-3,0},{-2.6,3})); g.editor.palette=recipe_slot(.Wood); testing.expect(t,editor_place(&g,{-2,0},{0,2})); sandbox_toggle_editor(&g)
 c:=cover_begin(&g.world.scene); defer cover_destroy(&c); shared.active_cover=&c; defer { shared.active_cover=nil }
 grid:=c.grid
 for x in -8..=8 { for y in -2..=8 {
  origin:=Vec2{-4,1}; point:=Vec2{f32(x)*0.5,f32(y)*0.5}
  indexed:=cover_distance(point,origin,0)
  c.grid=nil; exhaustive:=cover_distance(point,origin,0); c.grid=grid
  testing.expect(t,transmute(u32)indexed==transmute(u32)exhaustive,"Grid must preserve exact chord sums")
 } }
}
@(test)
cover_shadow_overlap_includes_crossing_edges_and_tangency :: proc(t:^testing.T) {
 a:=[4]Vec2{{-2,-0.1},{2,-0.1},{2,0.1},{-2,0.1}}
 b:=[4]Vec2{{-0.1,-2},{0.1,-2},{0.1,2},{-0.1,2}}
 distant:=[3]Vec2{{3,3},{4,3},{3,4}}
 touching:=[3]Vec2{{2,-0.1},{3,-0.1},{2,0.1}}
 testing.expect(t,cover_polygons_overlap(a[:],b[:]))
 testing.expect(t,!cover_polygons_overlap(a[:],distant[:]))
 testing.expect(t,!cover_polygons_overlap(a[:],touching[:]))
}

@(test)
cover_zero_load_early_exit_preserves_load :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 g.editor.palette=recipe_slot(.Stone); testing.expect(t,editor_place(&g,{1,0},{2,3})); g.editor.palette=recipe_slot(.Wood); testing.expect(t,editor_place(&g,{3,0},{5,2})); sandbox_toggle_editor(&g)
 c:=cover_begin(&g.world.scene); defer cover_destroy(&c); shared.active_cover=&c; defer { shared.active_cover=nil }
 saved:=c.cache; c.cache=nil; defer { c.cache=saved }
 for x in -2..=16 { for y in -4..=8 {
  point:=Vec2{f32(x)*0.5,f32(y)*0.5}; origin:=Vec2{0,1}
  c.load_limit=0; full:=cover_distance(point,origin,0)
  c.load_limit=5; limited:=cover_distance(point,origin,0)
  testing.expect(t,transmute(u32)blast_load(full,5)==transmute(u32)blast_load(limited,5))
 } }
}

@(test)
blast_shape_cache_matches_uncached_and_checks_collisions :: proc(t:^testing.T) {
 c:=Cover{}; shared.active_cover=&c; defer { shared.active_cover=nil; cover_destroy(&c) }
 points:=[6]Vec2{{0,0},{2,0},{2,1},{1,0.5},{1,2},{0,2}}
 for _ in 0..<3 {
  testing.expect(t,transmute(u32)blast_cached_width(points[:])==transmute(u32)outline_width_uncached(points[:]))
  testing.expect(t,blast_cached_simple(Polygon{points[:]})==simple_polygon_uncached(Polygon{points[:]}))
 }
 key:=blast_shape_key(points[:]); previous:=c.shape_queries[key]; delete(previous.points)
 fake:=make([]Vec2,3); fake[0]={0,0}; fake[1]={1,1}; fake[2]={2,2}
 c.shape_queries[key]={points=fake,width=-123,width_known=true,simple_known=true,simple=false}
 testing.expect(t,transmute(u32)blast_cached_width(points[:])==transmute(u32)outline_width_uncached(points[:]))
 testing.expect(t,blast_cached_simple(Polygon{points[:]})==simple_polygon_uncached(Polygon{points[:]}))
 points[3]={3,3}
 testing.expect(t,blast_cached_simple(Polygon{points[:]})==simple_polygon_uncached(Polygon{points[:]}))
}

@(test)
blast_width_stack_hull_matches_original :: proc(t:^testing.T) {
 sorted:[32]Vec2; storage:[64]Vec2; points:[32]Vec2
 for seed in 1..=32 {
  for i in 0..<32 { points[i]={f32(derive_seed(u8(seed),u64(i)))/10,f32(derive_seed(u8(seed),u64(i+32)))/10} }
  for n in 0..=32 {
   expected:=convex_hull(points[:n]); actual:=convex_hull_into(points[:n],sorted[:],storage[:])
   testing.expect(t,len(expected)==len(actual))
   if len(expected)==len(actual) { for p,i in expected { testing.expect(t,transmute(u32)p.x==transmute(u32)actual[i].x && transmute(u32)p.y==transmute(u32)actual[i].y) } }
   delete(expected)
  }
 }
}

@(test)
blast_generation_arena_matches_owned_generation :: proc(t:^testing.T) {
 c:=Cover{}; defer { shared.active_cover=nil; cover_destroy(&c) }
 points:=[4]Vec2{{0,0},{3,0},{3,2},{0,2}}
 for material in Recipe { for seed in 1..=8 {
  recipe:=editor_material(material); shared.active_cover=nil
  expected:=generate_children_impl(Polygon{points[:]},recipe,u8(seed),0.1,false)
  shared.active_cover=&c; actual:=generate_children(Polygon{points[:]},recipe,u8(seed),0.1,false)
  testing.expect(t,len(expected)==len(actual))
  if len(expected)==len(actual) { for polygon,i in expected {
   testing.expect(t,len(polygon.points)==len(actual[i].points))
   if len(polygon.points)==len(actual[i].points) { for p,j in polygon.points { testing.expect(t,transmute(u32)p.x==transmute(u32)actual[i].points[j].x && transmute(u32)p.y==transmute(u32)actual[i].points[j].y) } }
  } }
  for polygon in expected { delete(polygon.points) }; delete(expected)
  for polygon in actual { delete(polygon.points) }; delete(actual)
 } }
}
