package shared
import t "core:testing"
import b2 "vendor:box2d"

@(test)
nearby_static_collision_window_matches_the_full_authoritative_world_and_refuses_exit :: proc(test:^t.T) {
 s:=new_scene(0);defer scene_destroy(&s);s.epoch=1;s.level_policy.active=true;s.level_policy.config=DEFAULT_GAMEPLAY_CONFIG;s.level_policy.kill={{-1000,-1000},{1000,1000}}
 material:=add_material(&s,editor_material(.Stone));owner:=add_piece(&s,material,0)
 ground:=[4]Vec2{{-8,-1},{9,-1},{9,0},{-8,0}};id:=add_subdivision(&s,owner,Polygon{ground[:]},Pose{position={.5,-.5}});s.subdivisions[s.sub_rows[id]].provenance={1,1,.Fixed,.Destructible,true}
 for row in 0..<50 {for col in 0..<100 {
  x,y:=f32(100)+f32(col)*1.1,f32(-100)+f32(row)*1.1;points:=[4]Vec2{{x,y},{x+1,y},{x+1,y+1},{x,y+1}}
  cell:=add_subdivision(&s,owner,Polygon{points[:]},Pose{position={x+.5,y+.5}});s.subdivisions[s.sub_rows[cell]].provenance={1,1,.Fixed,.Destructible,true}
 }}
 physics_init(&s,{0,-9.8});authoritative:=player_create(s.physics.world)
 p:Static_Prediction;defer prediction_static_destroy(&p)
 t.expect(test,!prediction_static_build(&p,&s)&&p.reason==.Capacity)
 window:=Level_Bounds{{-12.5,-7.435},{3.5,8.565}};t.expect(test,prediction_static_build(&p,&s,true,&window)&&len(p.scene.subdivisions)==1&&len(p.proxies)==0)
 o:=Owner_State{identity={1,1,1},position=PLAYER_SPAWN,teleport_serial=1};t.expect(test,owner_state_restore(p.scene.physics.world,&p.player,o))
 maximum:f32
 for tick in 1..=90 {
  jump:=tick==30;player_before_step(&authoritative,1,jump,1.0/60);b2.World_Step(s.physics.world,1.0/60,PHYSICS_SUBSTEPS);player_after_movement_step(&authoritative)
  command:=Scheduled_Command{sequence=u64(tick),target_tick=u64(tick),move=127,jump_edge=jump?u64(1):u64(0)}
  t.expect(test,prediction_world_step(&p,command));maximum=max(maximum,vlen(vsub(authoritative.pose.position,p.player.pose.position)))
 };t.expect(test,maximum<.00001,"omitted remote static terrain cannot change local run/jump contacts")
 b2.Body_SetTransform(p.player.body,{3.4,1},b2.MakeRot(0))
 t.expect(test,!prediction_world_step(&p,Scheduled_Command{sequence=91,target_tick=91,move=127})&&p.reason==.Outside_Collision_Window&&p.state_tick==90,"window exit must fall back before an unsupported physics step")
}
