package main

import "core:fmt"
import "core:sync"
import "core:testing"

hub_test_rest_point :: proc(cache: ^Render_Cache,index: int,center: Vec2) -> Vec2 {
 if index==len(cache.outline.points) { return center }
 return cache.outline.points[index]
}
hub_test_vertex_fan :: proc(cache: ^Render_Cache) -> bool { return !cache.hub_fan }
hub_test_render :: proc(s: ^Scene,caches: ^Render_Cache_State,sub: Subdivision) -> (Polygon,Vec2) {
 render_cache_prepass(s,caches)
 hub:Vec2; outline:=render_outline(s,caches,sub,nil,true,nil,&hub)
 return outline,hub
}

@(test)
rubber_fill_triangles_have_positive_rest_area_and_keep_orientation :: proc(t: ^testing.T) {
 cache_state:=Render_Cache_State{}; defer release_render_caches(&cache_state)
 caches:=&cache_state
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 angles:=[2]f32{10,30}
 for degrees in angles {
  s:=rubber_bend_scene(degrees)
  render_cache_prepass(&s,caches)
  invalid,flipped:=0,0
  for sub in s.subdivisions {
   outline,hub:=hub_test_render(&s,caches,sub)
   cache:=&caches.cells[sub.id]
   orientation:=partition_area(cache.outline.points)
   for i:=0; i<len(cache.triangles); i+=3 {
    rest,world:[3]Vec2
    for j in 0..<3 {
     index:=cache.triangles[i+j]; rest[j]=hub_test_rest_point(cache,index,sub.rest_center)
     if index==len(outline.points) { world[j]=hub } else { world[j]=outline.points[index] }
    }
    a:=render_test_cross(rest[0],rest[1],rest[2])
    b:=render_test_cross(world[0],world[1],world[2])
    if a*orientation<=0 { invalid+=1 }
    // Degenerate rest triangles have no orientation: count inward-facing
    // world triangles against the outline's orientation as well.
    if b*orientation<0 { flipped+=1 }
   }
   delete(outline.points)
  }
  fmt.printf("Hub checks 1/2: degrees=%.0f invalid_rest=%d flipped_world=%d\n",degrees,invalid,flipped)
  testing.expect(t,invalid==0 && flipped==0)
  scene_destroy(&s)
  release_render_caches(caches)
 }
}

@(test)
rubber_editor_blast_needs_no_vertex_fan_fallback :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g); g.editor.palette=recipe_slot(.Rubber)
 testing.expect(t,editor_place(&g,{0,0},{3,1})); sandbox_toggle_editor(&g)
 caches:=&g.render_caches
 for stage in 0..<2 {
  if stage==1 { sandbox_fixture_radius(&g,6); sandbox_explode(&g,{1.5,0.5}) }
  render_cache_prepass(&g.world.scene,caches)
  fallback,cells:=0,0
  for sub in g.world.scene.subdivisions {
   if g.world.scene.materials[sub.material].flexibility<=0 { continue }
   cache:=&caches.cells[sub.id]; cells+=1
   if hub_test_vertex_fan(cache) { fallback+=1 }
  }
  fmt.printf("Hub check 3: stage=%d vertex_fan_cells=%d live_rubber_cells=%d\n",stage,fallback,cells)
  testing.expect(t,(stage==1 || cells>0) && fallback==0)
 }
}
