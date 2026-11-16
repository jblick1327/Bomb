package shared
import t "core:testing"
import b2 "vendor:box2d"
import math "core:math"
import rand "core:math/rand"

// G-N5: the prediction world rebuild reuses cached hulls and the proxy pass
// resolves history brackets once per tick. Both must be exact, not approximate.

test_prediction_hull_scene :: proc() -> Scene {
 s:=new_scene(0);s.epoch=1;s.structure_revision=1;s.anchor_y=-3
 append(&s.materials,Material{},Material{flexibility=.5})
 add :: proc(s:^Scene,id,owner:u64,material:int,points:[]Vec2,rest:Vec2) {
  s.sub_rows[id]=len(s.subdivisions);append(&s.subdivisions,Subdivision{id=id,owner=owner,material=material,outline=make_polygon(points),rest_center=rest,live=true})
  if row,found:=s.piece_rows[owner];found { append(&s.pieces[row].subdivisions,id);return }
  piece:=Piece{id=owner,material=material,live=true,ref_rest=rest,has_ref_rest=true};append(&piece.subdivisions,id)
  s.piece_rows[owner]=len(s.pieces);append(&s.pieces,piece)
 }
 floor:=[4]Vec2{{-8,-3},{9,-3},{9,0},{-8,0}};add(&s,200,100,0,floor[:],{.5,-1.5})
 // Non-convex (decomposed), many-sided convex (decomposed), a sliver whose hull
 // welds away (fallback box), a loose piece (kinematic proxy) and rubber.
 l_shape:=[6]Vec2{{-6,0},{-3,0},{-3,1},{-5,1},{-5,3},{-6,3}};add(&s,201,100,0,l_shape[:],{-5,1})
 ring:[12]Vec2;for &p,i in ring { a:=f32(i)*math.TAU/12;p={4+1.2*math.cos(a),1.3+1.2*math.sin(a)} };add(&s,202,100,0,ring[:],{4,1.3})
 sliver:=[3]Vec2{{1,0},{1.0001,0},{1.00005,0.00001}};add(&s,203,100,0,sliver[:],{1,0})
 loose:=[5]Vec2{{6,2},{8,2},{8,3},{7,3.5},{6,3}};add(&s,204,101,0,loose[:],{7,2.7})
 band:=[4]Vec2{{-2,0},{0,0},{0,.3},{-2,.3}};add(&s,205,102,1,band[:],{-1,.15})
 s.subdivisions[s.sub_rows[205]].provenance.motion=.Anchored;s.subdivisions[s.sub_rows[205]].provenance.pinned=true
 return s
}

expect_same_prediction_shapes :: proc(test:^t.T,a,b:^Static_Prediction) {
 t.expect(test,len(a.scene.subdivisions)==len(b.scene.subdivisions) && len(a.proxies)==len(b.proxies))
 for sa,i in a.scene.subdivisions {
  sb:=b.scene.subdivisions[i]
  t.expect(test,sa.id==sb.id && sa.fixture_count==sb.fixture_count && len(sa.shapes)==len(sb.shapes))
  t.expect(test,b2.Body_GetType(sa.body)==b2.Body_GetType(sb.body))
  for shape,k in sa.shapes {
   pa,pb:=b2.Shape_GetPolygon(shape),b2.Shape_GetPolygon(sb.shapes[k])
   t.expect(test,pa==pb,"cached hull shapes must be bit-identical to the authoritative decomposition")
   fa,fb:=b2.Shape_GetFilter(shape),b2.Shape_GetFilter(sb.shapes[k])
   t.expect(test,fa.categoryBits==fb.categoryBits && fa.maskBits==fb.maskBits && fa.groupIndex==fb.groupIndex)
   t.expectf(test,b2.Shape_GetUserData(shape)==b2.Shape_GetUserData(sb.shapes[k]),"user data %v vs %v",b2.Shape_GetUserData(shape),b2.Shape_GetUserData(sb.shapes[k]))
  }
 }
}

@(test)
prediction_hull_cache_rebuilds_bit_identical_worlds_and_trajectories :: proc(test:^t.T) {
 source:=test_prediction_hull_scene();defer scene_destroy(&source)
 cache:Prediction_Hull_Cache;defer prediction_hull_cache_destroy(&cache)
 plain,cold,warm:Static_Prediction
 defer { prediction_static_destroy(&plain);prediction_static_destroy(&cold);prediction_static_destroy(&warm) }
 t.expect(test,prediction_static_build(&plain,&source,true))
 t.expect(test,prediction_static_build(&cold,&source,true,nil,&cache) && len(cache.entries)==len(source.subdivisions))
 t.expect(test,prediction_static_build(&warm,&source,true,nil,&cache))
 t.expect(test,len(plain.scene.subdivisions[plain.scene.sub_rows[201]].shapes)>1 && plain.scene.subdivisions[plain.scene.sub_rows[203]].fixture_count==1 && len(plain.proxies)==1)
 expect_same_prediction_shapes(test,&plain,&cold);expect_same_prediction_shapes(test,&plain,&warm)
 // Same commands in all three worlds: positions must match exactly, tick by tick.
 worlds:=[3]^Static_Prediction{&plain,&cold,&warm}
 for w in worlds { b2.Body_SetTransform(w.player.body,{-4,4},b2.MakeRot(0)) }
 for tick in 0..<180 {
  move:=f32(tick<90?1:-1);jump:=tick==40||tick==130
  for w in worlds { player_before_step(&w.player,move,jump,f32(NET_STEP_DT));b2.World_Step(w.scene.physics.world,f32(NET_STEP_DT),PHYSICS_SUBSTEPS);player_after_movement_step(&w.player) }
  t.expect(test,cold.player.pose==plain.player.pose && warm.player.pose==plain.player.pose)
 }
 // An identity whose outline or offset changed is recomputed, and unused ones are dropped.
 row:=source.sub_rows[201];delete(source.subdivisions[row].outline.points)
 cut:=[4]Vec2{{-6,0},{-3,0},{-3,1},{-6,1}};source.subdivisions[row].outline=make_polygon(cut[:])
 source.subdivisions[source.sub_rows[202]].live=false
 prediction_static_destroy(&plain);prediction_static_destroy(&warm)
 t.expect(test,prediction_static_build(&plain,&source,true) && prediction_static_build(&warm,&source,true,nil,&cache))
 expect_same_prediction_shapes(test,&plain,&warm)
 _,kept:=cache.entries[202];t.expect(test,!kept && len(cache.entries)==len(source.subdivisions)-1)
}

// The pre-G-N5 lookup, kept verbatim as the reference.
reference_collision_history_pose :: proc(h:^Collision_History,tick,key:u64) -> (pose:Net_Drawn,estimated,valid:bool) {
 lower,upper:^Collision_Frame
 for &frame in h.frames {
  if !frame.valid || frame.epoch!=h.epoch { continue }
  if frame.tick<=tick && (lower==nil || frame.tick>lower.tick) { lower=&frame }
  if frame.tick>=tick && (upper==nil || frame.tick<upper.tick) { upper=&frame }
 }
 if lower==nil { return }
 a,found:=lower.poses[key];if !found { return }
 if upper!=nil {
  b,exists:=upper.poses[key];if !exists { return }
  if upper.tick==lower.tick { return net_drawn_single(a),false,true }
  if upper.tick-lower.tick>PREDICTION_EXTRAPOLATE_TICKS { return }
  return net_drawn_from(a,b,f32(tick-lower.tick)/f32(upper.tick-lower.tick)),false,true
 }
 if tick-lower.tick>PREDICTION_EXTRAPOLATE_TICKS { return }
 previous:^Collision_Frame
 for &frame in h.frames { if frame.valid && frame.epoch==h.epoch && frame.tick<lower.tick && (previous==nil || frame.tick>previous.tick) { previous=&frame } }
 if previous==nil { return }
 if lower.tick-previous.tick>PREDICTION_EXTRAPOLATE_TICKS { return }
 b,exists:=previous.poses[key];if !exists { return }
 current:=net_drawn_single(a);old:=net_drawn_single(b)
 delta:=f32(lower.tick-previous.tick);ahead:=f32(tick-lower.tick)
 current.x+=(current.x-old.x)/delta*ahead;current.y+=(current.y-old.y)/delta*ahead
 current.angle+=radians_delta(current.angle,old.angle)/delta*ahead
 if !finite(current.x) || !finite(current.y) || math.abs(current.x)>1e6 || math.abs(current.y)>1e6 { return }
 return current,true,true
}

@(test)
collision_history_bracket_matches_the_full_scan_on_sparse_lossy_histories :: proc(test:^t.T) {
 state:=rand.create(20261116);context.random_generator=rand.default_random_generator(&state)
 compared,valid_count,estimated_count:=0,0,0
 for round in 0..<40 {
  h:Collision_History;h.epoch=1
  poses:=make(Pose_Table);defer delete(poses)
  tick:=u64(1000+round*37)
  for _ in 0..<300 {
   tick+=u64(1+rand.int_max(round%4==0?9:3))
   if rand.int_max(5)==0 { continue } // lost frame
   clear(&poses)
   for key in u64(1)..=12 { if rand.int_max(6)!=0 { poses[ent_key(.Piece,key)]=pose_state_make(rand.float32_range(-20,20),rand.float32_range(-20,20),rand.float32_range(-3,3)) } }
   _=collision_history_record_frame(&h,1,tick,&poses)
  }
  if round%3==0 { h.frames[rand.int_max(PREDICTION_HISTORY_TICKS)].epoch=2 } // a stale epoch frame is ignored
  for query in h.newest-280..=h.newest+10 {
   bracket:=collision_history_bracket(&h,query)
   for key in u64(1)..=13 {
    k:=ent_key(.Piece,key)
    p,e,v:=collision_history_bracket_pose(bracket,query,k);rp,re,rv:=reference_collision_history_pose(&h,query,k)
    t.expect(test,v==rv && e==re && (!v || p==rp));compared+=1
    if v { valid_count+=1;if e { estimated_count+=1 } }
   }
  }
  collision_history_destroy(&h)
 }
 t.expect(test,compared>100000 && valid_count>10000 && estimated_count>100)
}
