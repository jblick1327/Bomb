package shared
import t "core:testing"
import b2 "vendor:box2d"
import math "core:math"
import log "core:log"

@(test)
moving_rotating_support_replay_has_real_contacts_and_bounded_error :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 source.anchor_y=-1e30;source.pieces[0].ref_rest={.5,-1.5}
 predicted:Static_Prediction;defer prediction_static_destroy(&predicted)
 t.expect(test,prediction_static_build(&predicted,&source,true))
 collision:Collision_History;defer collision_history_destroy(&collision)
 _=collision_history_record_topology(&collision,&source,0)
 poses:=make(Pose_Table);defer delete(poses)
 def:=b2.DefaultWorldDef();def.gravity={0,-9.8};world:=b2.CreateWorld(def);defer b2.DestroyWorld(world)
 bd:=b2.DefaultBodyDef();bd.type=.kinematicBody;platform:=b2.CreateBody(world,bd)
 _=b2.CreatePolygonShape(platform,physics_shape_def(200),b2.MakeOffsetBox(8.5,1.5,{.5,-1.5},b2.MakeRot(0)))
 floor_def:=b2.DefaultBodyDef();floor_def.position={.5,YARD_FLOOR_BOTTOM-YARD_BASE_DEPTH*.5};floor:=b2.CreateBody(world,floor_def)
 sd:=b2.DefaultShapeDef();sd.material.friction=.65;_=b2.CreatePolygonShape(floor,sd,b2.MakeBox(10,YARD_BASE_DEPTH*.5))
 player:=player_create(world);id:=Input_Identity{1,1,1}
 history:Command_History;command_history_begin(&history,{id,1,1})
 schedule:=Input_Schedule{identity=id,synchronized=true}
 owners:[256]Owner_State;future:[256]Vec2;future_valid:[256]bool
 max_error:f32;compared,contacts:=0,0
 for tick in u64(1)..=180 {
  for history.next_tick<=tick+2 { target:=history.next_tick;_,_=command_history_push(&history,0,target==60?u64(1):u64(0)) }
  b2.Body_SetLinearVelocity(platform,{.5,0});b2.Body_SetAngularVelocity(platform,.05)
  command:=history.slots[tick%INPUT_HISTORY].command
  player_before_step(&player,0,command.jump_edge!=0,f32(NET_STEP_DT))
  b2.World_Step(world,f32(NET_STEP_DT),PHYSICS_SUBSTEPS);player_after_movement_step(&player)
  if player.grounded && player.support_cell==200 { contacts+=1 }
  ref:=from_b2(b2.Body_GetWorldPoint(platform,{.5,-1.5}));rotation:=b2.Body_GetRotation(platform)
  poses[ent_key(.Piece,100)]=pose_state_make(ref.x,ref.y,math.atan2(rotation.s,rotation.c))
  _=collision_history_record_frame(&collision,1,tick,&poses)
  schedule.finalized_through=tick;schedule.last_applied_sequence=command.sequence;if command.jump_edge!=0 { schedule.last_jump_edge=command.jump_edge }
  owners[tick%256]=owner_state_capture(&player,&schedule,tick,1)
  if future_valid[tick%256] { max_error=max(max_error,vlen(vsub(future[tick%256],player.pose.position)));compared+=1 }
  if tick>4 {
   owner:=owners[(tick-2)%256]
   t.expect(test,prediction_static_replay(&predicted,owner,&history,&collision))
   t.expect(test,predicted.state_tick==tick+2 && finite(predicted.player.pose.position.x) && finite(predicted.player.pose.position.y))
   future[predicted.state_tick%256]=predicted.player.pose.position;future_valid[predicted.state_tick%256]=true
   _=command_history_finalize(&history,id,owner.finalized_through)
  }
 }
 t.expect(test,contacts>60 && compared>150 && max_error<.2)
 log.infof("moving/rotating support: contact_ticks=%d replay_comparisons=%d max_position_error=%.6f",contacts,compared,max_error)
}
