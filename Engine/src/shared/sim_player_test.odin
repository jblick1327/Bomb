package shared

import t "core:testing"
import b2 "vendor:box2d"
import math "core:math"
import log "core:log"

@(test)
player_default_acceleration_reaches_seven_within_point_twelve_seconds :: proc(test:^t.T) {
 def:=b2.DefaultWorldDef();world:=b2.CreateWorld(def);defer b2.DestroyWorld(world)
 player:=player_create(world)
 t.expect(test,PLAYER_TUNING.speed==7&&PLAYER_TUNING.acceleration==70)
 reached:=0
 for tick in 1..=7 {
  player_movement_from_support(&player,1,false,1.0/60)
  speed:=b2.Body_GetLinearVelocity(player.body).x
  t.expect(test,speed>=0&&speed<=7)
  if speed==7&&reached==0 {reached=tick}
 }
 t.expect(test,reached>0&&f32(reached)/60<=.12)
 for _ in 0..<6 {player_movement_from_support(&player,0,false,1.0/60)}
 t.expect(test,b2.Body_GetLinearVelocity(player.body).x==0,"standing stop uses the same acceleration")
 for _ in 0..<6 {player_movement_from_support(&player,-1,false,1.0/60)}
 t.expect(test,b2.Body_GetLinearVelocity(player.body).x== -7)
 log.infof("N1 standing start: full_speed_tick=%d seconds=%.3f speed=7",reached,f32(reached)/60)
}

@(test)
player_jump_is_two_point_five_units_with_point_nine_second_airtime :: proc(test:^t.T) {
 w:=World{scene=new_scene(0)};defer scene_destroy(&w.scene);defer delete(w.bombs)
 physics_init(&w.scene,DEFAULT_GAMEPLAY_CONFIG.gravity)
 player:=player_create(w.scene.physics.world)
 // Empty flight fixture: a single grounded launch with no terrain/contact lift.
 player.grounded=true;player_movement_from_support(&player,0,true,1.0/60)
 start:=b2.Body_GetPosition(player.body).y;peak:=start;return_tick:=0
 world_bomb_spawn(&w,{20,100})
 debris_def:=b2.DefaultBodyDef();debris_def.type=.dynamicBody;debris_def.position={30,100}
 debris:=b2.CreateBody(w.scene.physics.world,debris_def)
 _=b2.CreatePolygonShape(debris,b2.DefaultShapeDef(),b2.MakeBox(.2,.2))
 for tick in 1..=60 {
  b2.World_Step(w.scene.physics.world,1.0/60,PHYSICS_SUBSTEPS)
  height:=b2.Body_GetPosition(player.body).y;peak=max(peak,height)
  if height<=start&&return_tick==0 {return_tick=tick}
 }
 rise:=peak-start;airtime:=f32(return_tick)/60
 t.expect(test,math.abs(PLAYER_TUNING.jump_speed-math.sqrt(f32(125)))<1e-6)
 t.expect(test,math.abs(rise-2.5)<.04&&return_tick>0&&airtime>=.88&&airtime<=.92)
 t.expect(test,math.abs(b2.Body_GetLinearVelocity(player.body).y-(PLAYER_TUNING.jump_speed-25))<.001)
 t.expect(test,b2.World_GetGravity(w.scene.physics.world)==b2.Vec2{0,-9.8})
 t.expect(test,b2.Body_GetGravityScale(w.bombs[0].body)==1&&b2.Body_GetGravityScale(debris)==1)
 t.expect(test,math.abs(b2.Body_GetLinearVelocity(w.bombs[0].body).y+9.8)<.001&&math.abs(b2.Body_GetLinearVelocity(debris).y+9.8)<.001,"bomb and debris free fall stays at world gravity")
 log.infof("N1 jump: rise=%.6f airtime=%.6f player_gravity=25 world_gravity=9.8",rise,airtime)
}

@(test)
player_custom_gravity_survives_respawn_rewind_and_world_rebuild :: proc(test:^t.T) {
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_level_layout(&level)
 level.gameplay_config.player.gravity_scale=1.75
 // world_rebuild_layout borrows the level; its lifetime remains with this fixture.
 layout:=Layout{level=&level,next_identity=level.next_identity}
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};world_rebuild_layout(&w,&layout,false);defer scene_destroy(&w.scene);defer delete(w.bombs)
 for i in 1..<MAX_PLAYERS {t.expect(test,world_add_player(&w,i))}
 for &player in w.players {
  t.expect(test,player.tuning.gravity_scale==1.75&&b2.Body_GetGravityScale(player.body)==1.75)
  player_respawn_at(&player,{10,20})
  t.expect(test,b2.Body_GetGravityScale(player.body)==1.75)
  owner:=Owner_State{identity={1,1,1},position={10,20},teleport_serial=player.teleport_serial}
  t.expect(test,owner_state_restore(w.scene.physics.world,&player,owner))
  t.expect(test,b2.Body_GetGravityScale(player.body)==1.75)
 }
 world_rebuild_layout(&w,&layout,false)
 for player in w.players {t.expect(test,player.active&&player.tuning.gravity_scale==1.75&&b2.Body_GetGravityScale(player.body)==1.75)}
}
