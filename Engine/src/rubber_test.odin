package main

import "core:fmt"
import "core:math"
import "core:slice"
import "core:sync"
import "core:testing"
import b2 "vendor:box2d"

@(test)
rubber_bend_skin_is_continuous_smooth_and_render_only :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=rubber_bend_scene(); defer scene_destroy(&s)
 before,ok:=encode_snapshot(&s); defer delete(before); testing.expect(t,ok)
 poses:=make(map[u64]Pose); defer delete(poses)
 for sub in s.subdivisions { poses[sub.id]=sub.pose }
 seen:=make(map[Vec2]u64); defer delete(seen)
 Top_Point :: struct { rest,world: Vec2, id: u64 }
 top:[dynamic]Top_Point; defer delete(top)
 repeats,mismatches:=0,0; deviation,max_turn:f32
 for sub in s.subdivisions {
  cache:=ensure_render_cache(&s,sub.id)
  outline:=render_outline(&s,sub,poses,true); defer delete(outline.points)
  raw:=render_outline(&s,sub,poses,false); defer delete(raw.points)
  for rest,i in cache.outline.points {
   point:=outline.points[i]; bits:=transmute(u64)point
   if previous,found:=seen[rest]; found { repeats+=1; if previous!=bits { mismatches+=1 } } else { seen[rest]=bits }
   own:=posed_point(sub,rest); deviation=max(deviation,vlen(vsub(point,own)))
   testing.expect(t,transmute(u64)raw.points[i]==transmute(u64)own,"V must show each body's unblended pose")
   if rest.y==1 {
    found:=false
    for &p in top { if p.rest.x==rest.x { found=true; if sub.id<p.id { p={rest,point,sub.id} }; break } }
    if !found { append(&top,Top_Point{rest,point,sub.id}) }
   }
  }
 }
 slice.sort_by(top[:],proc(a,b: Top_Point) -> bool { return a.rest.x<b.rest.x })
 for i in 1..<len(top)-1 {
  a,b:=vsub(top[i].world,top[i-1].world),vsub(top[i+1].world,top[i].world)
  angle:=math.abs(math.atan2(vcross(a,b),vdot(a,b)))*180/f32(math.PI)
  max_turn=max(max_turn,angle)
 }
 after,encoded:=encode_snapshot(&s); defer delete(after)
 unchanged:=encoded && string(before)==string(after)
 fmt.printf("A: shared=%d mismatches=%d max_turn_deg=%.6f max_deviation=%.6f snapshot_identical=%v\n",repeats,mismatches,max_turn,deviation,unchanged)
 testing.expect(t,repeats>0 && mismatches==0,"Shared rest points must render with identical bits")
 testing.expectf(t,max_turn<=4,"Top film turns %.6f degrees",max_turn)
 testing.expectf(t,deviation<=0.06,"Skin deviates %.6f from its own body",deviation)
 testing.expect(t,unchanged)
}

@(test)
finished_strip_impacts_leave_revision_and_regions_unchanged :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 sandbox_toggle_editor(&g)
 s:=&g.scene; m:=add_material(s,editor_material(.Wood)); owner:=add_piece(s,m,0)
 points:=[4]Vec2{{1.5,0.5},{1.9,0.5},{1.9,0.65},{1.5,0.65}}; p:=Polygon{points=points[:]}
 id:=add_subdivision(s,owner,p,Pose{position=centroid(p)})
 physics_sync_structure(s)
 body:=subdivision_body(s,id); b2.Body_SetLinearVelocity(body,{0,-10})
 revision,regions:=s.revision,len(s.subdivisions); max_load:f32
 for _ in 0..<120 {
  b2.World_Step(s.physics.world,1.0/60,PHYSICS_SUBSTEPS); physics_read_motion(s)
  events:=b2.World_GetContactEvents(s.physics.world)
  for hit in events.hitEvents[:events.hitCount] {
   a,b:=b2.Shape_GetBody(hit.shapeIdA),b2.Shape_GetBody(hit.shapeIdB)
   if a==body { max_load=max(max_load,contact_damage_load(s,a,b,hit.approachSpeed,1)) }
   if b==body { max_load=max(max_load,contact_damage_load(s,b,a,hit.approachSpeed,1)) }
  }
  f:=calculate_physics_loads(s,1.0/60); apply_failures(s,f); free_failures(&f); physics_sync_structure(s)
 }
 fmt.printf("E: revision_delta=%d regions_delta=%d live=%v max_impact_load=%.6f\n",s.revision-revision,len(s.subdivisions)-regions,is_live_subdivision(s,id),max_load)
 testing.expect(t,max_load>editor_material(.Wood).subdivision_strength,"Fixture must exceed Wood's impact strength")
 testing.expect(t,s.revision==revision && len(s.subdivisions)==regions && is_live_subdivision(s,id))
 expect_valid(t,s)
}
