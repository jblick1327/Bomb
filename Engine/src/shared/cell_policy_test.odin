package shared
import t "core:testing"
import b2 "vendor:box2d"

test_policy_scene :: proc(motion:Motion_Policy,damage:Damage_Policy) -> (s:Scene,lower,upper,link:u64) {
 s=new_scene(0);material:=add_material(&s,editor_material(.Stone));owner:=add_piece(&s,material,0)
 bottom:=[4]Vec2{{0,0},{1,0},{1,1},{0,1}};top:=[4]Vec2{{0,1},{1,1},{1,2},{0,2}}
 lower=add_subdivision(&s,owner,Polygon{bottom[:]},Pose{position={.5,.5}})
 upper=add_subdivision(&s,owner,Polygon{top[:]},Pose{position={.5,1.5}})
 link=add_connection(&s,lower,upper)
 anchors:=Source_Part_Anchors{source_identity=9007199254741001,source_part_id=9007199254742001}
 append(&anchors.segments,Segment{{0,0},{1,0}});append(&s.source_parts,anchors)
 for id in ([2]u64{lower,upper}) { s.subdivisions[s.sub_rows[id]].provenance={9007199254741001,9007199254742001,motion,damage,false};cell_resolve_pin(&s,id) }
 physics_init(&s,{0,-9.8})
 return
}
@(test)
six_motion_damage_policies_are_enforced_in_real_physics_and_failures :: proc(test:^t.T) {
 for motion in ([3]Motion_Policy{.Dynamic,.Fixed,.Anchored}) { for damage in Damage_Policy {
  s,lower,upper,link:=test_policy_scene(motion,damage);defer scene_destroy(&s)
  low:=s.subdivisions[s.sub_rows[lower]];high:=s.subdivisions[s.sub_rows[upper]]
  expected:=motion==.Dynamic?b2.BodyType.dynamicBody:b2.BodyType.staticBody
  t.expect(test,b2.Body_GetType(low.body)==expected&&b2.Body_GetType(high.body)==expected,"any pinned member pins a rigid body")
  t.expect(test,low.provenance.pinned==(motion!=.Dynamic)&&high.provenance.pinned==(motion==.Fixed))
  failures:Failures;defer free_failures(&failures);append(&failures.connections,link)
  apply_failures(&s,failures);physics_sync_structure(&s)
  if damage==.Indestructible {
   t.expect(test,s.connections[s.conn_rows[link]].live,"internal protected bond must survive")
   append(&failures.discard_subdivisions,lower,upper);apply_failures(&s,failures);physics_sync_structure(&s)
   blast_pass(&s,Blast{{.5,1},100});physics_sync_structure(&s)
   t.expect(test,is_live_subdivision(&s,lower)&&is_live_subdivision(&s,upper),"direct, impact, refinement and discard cannot remove protected cells")
  }else{
   t.expect(test,link not_in s.conn_rows)
   low=s.subdivisions[s.sub_rows[lower]];high=s.subdivisions[s.sub_rows[upper]]
   t.expect(test,low.owner!=high.owner&&b2.Body_GetType(high.body)==(motion==.Fixed?b2.BodyType.staticBody:b2.BodyType.dynamicBody),"detached anchored child must become dynamic")
   append(&failures.discard_subdivisions,upper);apply_failures(&s,failures);physics_sync_structure(&s);t.expect(test,!is_live_subdivision(&s,upper),"fixed does not imply indestructible")
  }
  before:=s.subdivisions[s.sub_rows[lower]].pose.position.y
  for tick in 0..<10 { physics_tick(&s,1.0/60) }
  after:=s.subdivisions[s.sub_rows[lower]].pose.position.y
  t.expect(test,motion==.Dynamic?after<before-.01:abs(after-before)<1e-5,"indestructible dynamics and permanent pins are independent")
 } }
}
@(test)
provenance_refinement_recomputes_boundary_pin_and_external_glue_is_not_protected :: proc(test:^t.T) {
 s,lower,upper,_:=test_policy_scene(.Anchored,.Destructible);defer scene_destroy(&s)
 parent:=s.subdivisions[s.sub_rows[lower]];owner:=parent.owner
 detached:=[4]Vec2{{0,.5},{1,.5},{1,1},{0,1}};anchored:=[4]Vec2{{0,0},{1,0},{1,.5},{0,.5}}
 top:=add_subdivision(&s,owner,Polygon{detached[:]},Pose{position={.5,.75}});bottom:=add_subdivision(&s,owner,Polygon{anchored[:]},Pose{position={.5,.25}})
 cell_inherit_provenance(&s,top,parent);cell_inherit_provenance(&s,bottom,parent)
 t.expect(test,!s.subdivisions[s.sub_rows[top]].provenance.pinned&&s.subdivisions[s.sub_rows[bottom]].provenance.pinned)
 t.expect(test,s.subdivisions[s.sub_rows[top]].provenance.source_identity==parent.provenance.source_identity&&s.subdivisions[s.sub_rows[top]].provenance.source_part_id==parent.provenance.source_part_id)
 s.subdivisions[s.sub_rows[lower]].provenance.damage=.Indestructible;s.subdivisions[s.sub_rows[upper]].provenance.damage=.Indestructible
 connection:=Connection{a=lower,b=upper};t.expect(test,!connection_damage_allowed(&s,connection))
 s.subdivisions[s.sub_rows[upper]].provenance.source_identity+=1;t.expect(test,connection_damage_allowed(&s,connection),"external glue may fail normally")
 admin:=Failures{administrative=true};defer free_failures(&admin);append(&admin.discard_subdivisions,upper);apply_failures(&s,admin);t.expect(test,!is_live_subdivision(&s,upper),"explicit administrative removal remains available")
}
