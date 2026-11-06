package shared
import t "core:testing"
import b2 "vendor:box2d"
import log "core:log"

test_prediction_static_scene :: proc() -> Scene {
 s:=new_scene(0);s.epoch=1;s.structure_revision=1;s.anchor_y=-3
 append(&s.materials,Material{})
 points:=[4]Vec2{{-8,-3},{9,-3},{9,0},{-8,0}}
 sub:=Subdivision{id=200,owner=100,material=0,outline=make_polygon(points[:]),rest_center={.5,-1.5},live=true}
 s.sub_rows[200]=0;append(&s.subdivisions,sub)
 piece:=Piece{id=100,material=0,live=true};append(&piece.subdivisions,u64(200));s.piece_rows[100]=0;append(&s.pieces,piece)
 return s
}

@(test)
static_prediction_replays_shared_run_jump_without_sandbox_respawn :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 predicted:Static_Prediction;defer prediction_static_destroy(&predicted)
 t.expect(test,prediction_static_build(&predicted,&source))
 def:=b2.DefaultWorldDef();def.gravity={0,-9.8};world:=b2.CreateWorld(def);defer b2.DestroyWorld(world)
 bd:=b2.DefaultBodyDef();bd.position={.5,-1.5};ground:=b2.CreateBody(world,bd)
 _=b2.CreatePolygonShape(ground,physics_shape_def(200),b2.MakeBox(8.5,1.5))
 player:=player_create(world)
 id:=Input_Identity{9007199254740999,1,9007199254741001}
 history:Command_History;command_history_begin(&history,{id,1,9007199254742001})
 schedule:=Input_Schedule{identity=id,synchronized=true}
 owners:[256]Owner_State
 future:[256]Vec2;future_valid:[256]bool
 max_error:f32;compared:=0
 for tick in u64(1)..=240 {
  for history.next_tick<=tick+3 {
   target:=history.next_tick;move:=target<120?i8(127):i8(-127)
   edge:=target==30 || target==150?target:u64(0)
   _,ok:=command_history_push(&history,move,edge);t.expect(test,ok)
  }
  command:=history.slots[tick%INPUT_HISTORY].command
  player_before_step(&player,move_dequantize(command.move),command.jump_edge!=0,f32(NET_STEP_DT))
  b2.World_Step(world,f32(NET_STEP_DT),PHYSICS_SUBSTEPS);player_after_movement_step(&player)
  schedule.finalized_through=tick;schedule.last_applied_sequence=command.sequence
  if command.jump_edge!=0 { schedule.last_jump_edge=command.jump_edge }
  owners[tick%256]=owner_state_capture(&player,&schedule,tick,1)
  if future_valid[tick%256] { max_error=max(max_error,vlen(vsub(future[tick%256],player.pose.position)));compared+=1 }
  if tick>6 {
   owner:=owners[(tick-6)%256]
   t.expect(test,prediction_static_replay(&predicted,owner,&history))
   t.expect(test,predicted.state_tick==tick+3 && predicted.reason==.None)
   future[predicted.state_tick%256]=predicted.player.pose.position;future_valid[predicted.state_tick%256]=true
   t.expect(test,command_history_finalize(&history,id,owner.finalized_through))
  }
 }
 t.expect(test,compared>200 && max_error<.03)
 log.infof("static shared-kernel replay comparisons=%d max_position_error=%.6f",compared,max_error)
}

@(test)
static_prediction_rejects_dynamic_or_incompatible_history :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 predicted:Static_Prediction;defer prediction_static_destroy(&predicted)
 source.anchor_y=-1e30
 t.expect(test,!prediction_static_build(&predicted,&source) && predicted.reason==.Dynamic_History_Required)
 source.anchor_y=-3;t.expect(test,prediction_static_build(&predicted,&source))
 history:Command_History;command_history_begin(&history,{{1,1,1},1,1});_,_=command_history_push(&history,0,0)
 owner:=Owner_State{identity={1,2,1},topology_revision=1}
 t.expect(test,!prediction_static_replay(&predicted,owner,&history) && predicted.reason==.Wrong_Epoch)
 owner.identity.epoch=1;owner.topology_revision=2
 t.expect(test,!prediction_static_replay(&predicted,owner,&history) && predicted.reason==.Wrong_Revision)
}
