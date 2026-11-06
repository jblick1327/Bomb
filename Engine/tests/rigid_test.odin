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
  center:=from_b2(b2.Body_GetWorldCenterOfMass(p.body)); r:=vsub(center,old_center)
  expected:=vadd(old_velocity,Vec2{-2*r.y,2*r.x})
  testing.expect(t,close_vec(from_b2(b2.Body_GetLinearVelocity(p.body)),expected) && close(b2.Body_GetAngularVelocity(p.body),2))
  testing.expect(t,b2.Body_GetTransform(p.body)==old_transform,"Split groups retain the exact shared frame")
 }
 // Equal-sized split keeps the body on the lowest member ID.
 seam:=s.connections[0]
 old:=subdivision_body(&s,seam.a)
 low:=min(seam.a,seam.b)
 f:=Failures{}; append(&f.connections,seam.id); apply_failures(&s,f); free_failures(&f); physics_sync_structure(&s)
 testing.expect(t,subdivision_body(&s,low)==old)
 testing.expect(t,b2.World_GetCounters(s.physics.world).jointCount==0)
 expect_packed_storage(t,&s)
}
@(test)
rigid_off_centre_blast_has_expected_angular_impulse :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=rigid_wall(); defer scene_destroy(&s); physics_init(&s)
 body:=s.pieces[0].body; center:=from_b2(b2.Body_GetWorldCenterOfMass(body))
 blast:=Blast{position={-0.5,-0.5},radius=4}
 torque:f32; impulse:=Vec2{}
 for sub in s.subdivisions {
  offset:=vsub(sub.pose.position,blast.position); distance:=vlen(offset)
  j:=vmul(offset,polygon_area(sub.outline)*blast_load(distance,blast.radius)*BLAST_IMPULSE_SCALE/distance)
  impulse=vadd(impulse,j); torque+=vcross(vsub(sub.pose.position,center),j)
 }
 mass:=b2.Body_GetMassData(body)
 inertia:=mass.rotationalInertia
 blast_pass(&s,blast)
 omega:=b2.Body_GetAngularVelocity(body)
 testing.expect(t,torque<0 && omega<0 && math.abs(omega-torque/inertia)<0.00001)
 testing.expect(t,close_vec(from_b2(b2.Body_GetLinearVelocity(body)),vmul(impulse,1/mass.mass)))
 for sub in s.subdivisions { testing.expect(t,close_vec(sub.pose.velocity,from_b2(b2.Body_GetWorldPointVelocity(body,to_b2(sub.pose.position)))) && close(sub.pose.angular_velocity,omega)) }
 fmt.printf("Rigid off-centre blast: angular velocity %.6f / expected %.6f\n",omega,torque/inertia)
}

Rigid_Bounce :: struct { rebound,rest_error: f32, mean_ms,max_ms: f64, regions: int }
rigid_bounce :: proc(size: Vec2,split: bool) -> Rigid_Bounce {
 g:=sandbox_editor_create(); defer sandbox_destroy(&g); g.editor.palette=recipe_slot(.Stone)
 assert(editor_place(&g,{0,0},size)); sandbox_toggle_editor(&g)
 s:=&g.world.scene
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
  // Changed generation changes contact tiling. Allow twice Box2D's 0.005
  // contact slop for correction/rocking; exact rigid-frame checks stay strict.
  testing.expectf(t,math.abs(split.rebound-single.rebound)<0.01 && split.rebound<0.01 && single.rebound<0.01,"Stone %v rebound split %.8f / control %.8f",size,split.rebound,single.rebound)
  testing.expect(t,split.rest_error<0.00001 && single.rest_error<0.00001)
  fmt.printf("Rigid Stone %.1fx%.1f: split rebound %.8f / single %.8f; rest error %.8f / %.8f; regions %d / %d; mean tick %.6f / %.6f ms; max %.6f / %.6f ms\n",size.x,size.y,split.rebound,single.rebound,split.rest_error,single.rest_error,split.regions,single.regions,split.mean_ms,single.mean_ms,split.max_ms,single.max_ms)
 }
}


@(test)
rigid_refinement_keeps_body_and_surviving_shapes :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=rigid_wall(); defer scene_destroy(&s); physics_init(&s)
 body:=s.pieces[0].body; retained:=s.subdivisions[0].id
 shape:=s.subdivisions[0].shapes[0]; parent:=s.subdivisions[1].id
 f:=failure_for(parent); apply_failures(&s,f); free_failures(&f); physics_sync_structure(&s)
 testing.expect(t,!is_live_subdivision(&s,parent) && len(s.subdivisions)>3 && len(s.pieces)==1)
 testing.expect(t,s.pieces[0].body==body && s.subdivisions[s.sub_rows[retained]].shapes[0]==shape)
 testing.expect(t,close(b2.Body_GetMass(body),3) && close(b2.Body_GetRotationalInertia(body),2.5))
 for sub in s.subdivisions { for fixture in sub.shapes { testing.expect(t,b2.Shape_GetBody(fixture)==body && u64(uintptr(b2.Shape_GetUserData(fixture)))==sub.id) } }
 expect_packed_storage(t,&s)
}
@(test)
rigid_partial_cleanup_updates_shared_shapes_and_mass :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=Sandbox{world=World{scene=new_scene(0)}}; defer sandbox_destroy(&g); s:=&g.world.scene
 m:=add_material(s,editor_material(.Stone)); p:=add_piece(s,m,0)
 previous:=u64(0); first:=u64(0)
 for y in 0..<3 {
  points:=[4]Vec2{{0,f32(y)},{1,f32(y)},{1,f32(y+1)},{0,f32(y+1)}}
  poly:=Polygon{points=points[:]}; id:=add_subdivision(s,p,poly,Pose{position=centroid(poly)})
  if previous!=0 { add_connection(s,previous,id) } else { first=id }
  previous=id
 }
 physics_init(s)
 body:=s.pieces[0].body; b2.Body_SetTransform(body,{0,-5.6},b2.MakeRot(0)); physics_read_motion(s)
 sandbox_remove_out_of_bounds(&g)
 testing.expect(t,!is_live_subdivision(s,first) && len(s.subdivisions)==2 && len(s.pieces)==1)
 testing.expect(t,s.pieces[0].body==body && b2.Body_GetShapeCount(body)==2 && close(b2.Body_GetMass(body),2))
 expect_packed_storage(t,s)
}

@(test)
rigid_staged_keeper_removal_retains_remaining_body :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=rigid_wall(); defer scene_destroy(&s); physics_init(&s)
 body:=s.pieces[0].body; first:=s.subdivisions[0].id
 b2.Body_SetTransform(body,{2,4},b2.MakeRot(0.4)); physics_read_motion(&s)
 frame:=b2.Body_GetTransform(body)
 f:=Failures{}; append(&f.connections,s.connections[0].id)
 apply_failures(&s,f); free_failures(&f)
 // No physics sync between these stages, as in reach refinement + blast damage.
 for sub in s.subdivisions { if sub.id!=first { append(&f.discard_subdivisions,sub.id) } }
 apply_failures(&s,f); free_failures(&f); physics_sync_structure(&s)
 testing.expect(t,len(s.subdivisions)==1 && len(s.pieces)==1 && s.pieces[0].body==body)
 testing.expect(t,b2.Body_GetTransform(body)==frame && close(b2.Body_GetMass(body),1))
 testing.expect(t,b2.Body_GetShapeCount(body)==1 && subdivision_body(&s,first)==body)
 expect_packed_storage(t,&s)
}
