package main
import "core:testing"
import "core:sync"
import b2 "vendor:box2d"
@(test)
finished_wood_survives_impacts_but_blasts_remove_it :: proc(t: ^testing.T) {
 s:=new_scene(0.1); defer scene_destroy(&s)
 m:=add_material(&s,editor_material(.Wood)); p:=add_piece(&s,m,42)
 vertices:=[4]Vec2{{0,0},{0.4,0},{0.4,0.15},{0,0.15}}; poly:=Polygon{points=vertices[:]}
 id:=add_subdivision(&s,p,poly,Pose{position=centroid(poly)})
 for _ in 0..<3 {
  f:=failure_for(id); f.impact=true; apply_failures(&s,f); free_failures(&f)
  testing.expect(t,is_live_subdivision(&s,id) && s.subdivisions[s.sub_rows[id]].seed==0)
 }
 f:=failure_for(id); apply_failures(&s,f); free_failures(&f)
 testing.expect(t,len(s.subdivisions)==0)
 dust_owner:=add_piece(&s,m,0)
 dust_points:=[4]Vec2{{0,0},{1,0},{1,0.05},{0,0.05}}; dust:=Polygon{points=dust_points[:]}
 dust_id:=add_subdivision(&s,dust_owner,dust,Pose{position=centroid(dust)})
 df:=failure_for(dust_id); df.impact=true; apply_failures(&s,df); free_failures(&df)
 testing.expect(t,!is_live_subdivision(&s,dust_id),"Impact dust must still vanish")
}
@(test)
finished_wood_drop_keeps_non_dust_geometry :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 testing.expect(t,editor_place(&g,{0,0},{0.4,0.21})); sandbox_toggle_editor(&g)
 body:=g.scene.subdivisions[0].body
 b2.Body_SetTransform(body,{0,3},b2.MakeRot(0)); b2.Body_SetLinearVelocity(body,{3,-4}); physics_read_motion(&g.scene)
 initial:=f32(0.084)
 for _ in 0..<180 { sandbox_tick(&g,0,false) }
 area:f32
 for sub in g.scene.subdivisions { if sub.material!=0 { area+=polygon_area(sub.outline); testing.expect(t,sub.width>g.scene.minimum_width) } }
 testing.expect(t,close(area,initial),"Thrown finished Wood must retain its non-dust mass")
}
@(test)
grained_cuts_do_not_fall_back_across_grain :: proc(t: ^testing.T) {
 recipe:=editor_material(.Wood)
 for seed in 1..=32 {
  vertices:=[4]Vec2{{0,0},{0.4,0},{0.4,0.15},{0,0.15}}
  children:=generate_children(Polygon{points=vertices[:]},recipe,u8(seed),0.1)
  testing.expect(t,len(children)==0,"Thickness cut cannot fit; cross-grain fallback is forbidden")
  for c in children { delete(c.points) }; delete(children)
 }
}
