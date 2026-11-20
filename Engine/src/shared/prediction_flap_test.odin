package shared
import t "core:testing"
import b2 "vendor:box2d"
import math "core:math"

// The client predicts ~9 ticks past its newest frame; proxies there are held
// when at rest, estimated when the estimate is good enough or out of reach, and
// otherwise still require history.

@(test)
resting_proxy_is_held_past_the_extrapolation_window :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 source.anchor_y=-1e30;source.pieces[0].ref_rest={.5,-1.5}
 p:Static_Prediction;defer prediction_static_destroy(&p)
 t.expect(test,prediction_static_build(&p,&source,true) && len(p.proxies)==1)
 h:=Collision_History{epoch=1};defer collision_history_destroy(&h)
 poses:=make(Pose_Table);defer delete(poses);key:=ent_key(.Piece,100)
 for tick in u64(100)..=106 {
  // One position step of jitter, as under a standing player.
  x:=f32(.5);if tick==104 { x+=1.0/256 }
  poses[key]=pose_state_make(x,-1.5,0);_=collision_history_record_frame(&h,1,tick,&poses)
 }
 // 13 ticks past the newest frame, far outside the 6-tick extrapolation window.
 t.expect(test,prediction_proxy_positions(&p,&h,119))
 body:=p.proxies[0].body
 t.expect(test,vlen(from_b2(b2.Body_GetPosition(body)))<1e-6 && vlen(from_b2(b2.Body_GetLinearVelocity(body)))<1e-6)
 // Once it starts falling under the player it is neither at rest nor a good
 // estimate (1.2 m/s for 13 ticks), so the step needs history again.
 poses[key]=pose_state_make(.5,-1.52,0);_=collision_history_record_frame(&h,1,107,&poses)
 t.expect(test,!prediction_proxy_positions(&p,&h,119) && p.reason==.Dynamic_History_Required)
}

@(test)
slow_platform_under_the_player_is_estimated_within_tolerance :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 source.anchor_y=-1e30;source.pieces[0].ref_rest={.5,-1.5}
 p:Static_Prediction;defer prediction_static_destroy(&p)
 t.expect(test,prediction_static_build(&p,&source,true) && len(p.proxies)==1)
 h:=Collision_History{epoch=1};defer collision_history_destroy(&h)
 poses:=make(Pose_Table);defer delete(poses);key:=ent_key(.Piece,100)
 // Rising one position step per tick: not at rest, 0.23 m/s.
 for tick in u64(100)..=106 { poses[key]=pose_state_make(.5,-1.5+f32(tick-100)/256,0);_=collision_history_record_frame(&h,1,tick,&poses) }
 // tick+1 is 7 ticks ahead: error 0.067 (gravity) + 0.027 (stopping) <= 0.2.
 t.expect(test,prediction_proxy_positions(&p,&h,112))
 velocity:=from_b2(b2.Body_GetLinearVelocity(p.proxies[0].body))
 t.expect(test,math.abs(velocity.y-60.0/256)<1e-3 && math.abs(velocity.x)<1e-6)
 // The same motion 20 ticks ahead is too uncertain under the player.
 t.expect(test,!prediction_proxy_positions(&p,&h,125) && p.reason==.Dynamic_History_Required)
}

@(test)
fast_fragment_is_estimated_only_out_of_the_players_reach :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 // The slab stays anchored ground; a small fragment flies far from the player.
 points:=[4]Vec2{{20,20},{21,20},{21,21},{20,21}}
 sub:=Subdivision{id=300,owner=110,material=0,outline=make_polygon(points[:]),rest_center={20.5,20.5},live=true}
 source.sub_rows[300]=len(source.subdivisions);append(&source.subdivisions,sub)
 piece:=Piece{id=110,material=0,live=true,ref_rest={20.5,20.5}};append(&piece.subdivisions,u64(300))
 source.piece_rows[110]=len(source.pieces);append(&source.pieces,piece)
 p:Static_Prediction;defer prediction_static_destroy(&p)
 t.expect(test,prediction_static_build(&p,&source,true) && len(p.proxies)==1 && p.proxies[0].key==ent_key(.Piece,110))
 h:=Collision_History{epoch=1};defer collision_history_destroy(&h)
 poses:=make(Pose_Table);defer delete(poses);key:=ent_key(.Piece,110)
 poses[key]=pose_state_make(20.5,20.5,0);_=collision_history_record_frame(&h,1,100,&poses)
 poses[key]=pose_state_make(20.6,20.5,0);_=collision_history_record_frame(&h,1,101,&poses)
 // 6 m/s, 9 ticks ahead: about 1 m of error, but 25 m from the player.
 t.expect(test,prediction_proxy_positions(&p,&h,110))
 position:=from_b2(b2.Body_GetPosition(p.proxies[0].body))
 t.expect(test,math.abs(position.x-1)<.03 && math.abs(position.y)<1e-3)
 // The same flight just above the player's head is not guessed.
 poses[key]=pose_state_make(-4.5,1.6,0);_=collision_history_record_frame(&h,1,102,&poses)
 poses[key]=pose_state_make(-4.4,1.6,0);_=collision_history_record_frame(&h,1,103,&poses)
 t.expect(test,!prediction_proxy_positions(&p,&h,112) && p.reason==.Dynamic_History_Required)
 // A fragment seen in only one frame has no known velocity.
 fresh:=Collision_History{epoch=1};defer collision_history_destroy(&fresh)
 clear(&poses);_=collision_history_record_frame(&fresh,1,99,&poses)
 poses[key]=pose_state_make(20.5,20.5,0);_=collision_history_record_frame(&fresh,1,100,&poses)
 t.expect(test,!prediction_proxy_positions(&p,&fresh,108) && p.reason==.Dynamic_History_Required)
}

// Frames 0..newest with the slab at x; the owner at rest on it.
test_flap_frames :: proc(c:^Net_Client,first,last:u64,x:f32) {
 poses:=make(Pose_Table);defer delete(poses)
 poses[ent_key(.Piece,100)]=pose_state_make(x,-1.5,0)
 for tick in first..=last { _=collision_history_record_frame(&c.collision_history,1,tick,&poses) }
}
test_flap_advance :: proc(c:^Net_Client,now:^f64) {
 _,_=command_history_push(&c.input_link.history,0,0)
 c.input_link.owner.state_tick+=1;c.input_link.owner.finalized_through+=1
 now^+=1.0/60;net_prediction_update(c,now^)
}
test_flap_present :: proc(c:^Net_Client,interpolated:Vec2) -> Vec2 {
 key:=ent_key(.Player,0);clear(&c.drawn);c.drawn_serial+=1;c.drawn[key]=Net_Drawn{x=interpolated.x,y=interpolated.y}
 net_prediction_apply(c);d:=c.drawn[key];return {d.x,d.y}
}

@(test)
dynamic_history_gap_dwells_before_recovery_and_blends_both_ways :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 source.anchor_y=-1e30;source.pieces[0].ref_rest={.5,-1.5}
 c:Net_Client;net_client_init(&c,1250,0);defer net_client_destroy(&c)
 c.real_gate=true;c.nc_client.client_index=0;c.epoch=1;c.has_epoch=true
 _=collision_history_record_topology(&c.collision_history,&source,0)
 id:=Input_Identity{1,1,1};command_history_begin(&c.input_link.history,{id,1,1})
 for _ in 0..<14 { _,_=command_history_push(&c.input_link.history,0,0) }
 c.input_link.active=true;c.input_link.has_owner=true
 c.input_link.owner=Owner_State{identity=id,state_tick=5,finalized_through=5,topology_revision=1,position=PLAYER_SPAWN,teleport_serial=1}
 test_flap_frames(&c,0,5,.5)
 // The slab is 9 ticks behind the target but at rest: predicted, not conservative.
 now:=0.0;net_prediction_update(&c,now)
 t.expect(test,c.prediction.mode==.Predicting && c.prediction.world.state_tick==14)
 predicted:=test_flap_present(&c,{-4.5,.3})
 t.expect(test,predicted==c.prediction.world.player.pose.position)
 // The slab jumps 1 m in one tick under the player: genuinely unknown.
 test_flap_frames(&c,6,6,1.5);test_flap_advance(&c,&now)
 t.expect(test,c.prediction.mode==.Conservative && c.prediction.reason==.Dynamic_History_Required && c.prediction.conservative_transitions==1)
 // The drawn position does not jump to the interpolated one; it blends.
 interpolated:=Vec2{-4.5,.3}
 t.expect(test,vlen(vsub(test_flap_present(&c,interpolated),predicted))<1e-5)
 net_prediction_apply(&c)
 d:=c.drawn[ent_key(.Player,0)];t.expect(test,vlen(vsub(Vec2{d.x,d.y},predicted))<1e-5,"a second apply on one interpolation is idempotent")
 // History is usable again (the slab now stands still), but recovery waits.
 for i in u64(1)..<PREDICTION_RECOVER_UPDATES {
  test_flap_frames(&c,c.input_link.owner.state_tick+1,c.input_link.owner.state_tick+1,1.5);test_flap_advance(&c,&now)
  t.expect(test,c.prediction.mode==.Conservative && c.prediction.recover_streak==i)
 }
 // Closer to the interpolated position after the dwell's decay, never past it.
 blended:=test_flap_present(&c,interpolated)
 t.expect(test,vlen(vsub(blended,interpolated))<vlen(vsub(predicted,interpolated))*.5 && vlen(vsub(blended,interpolated))>0)
 test_flap_frames(&c,c.input_link.owner.state_tick+1,c.input_link.owner.state_tick+1,1.5);test_flap_advance(&c,&now)
 t.expect(test,c.prediction.mode==.Predicting && c.prediction.recoveries==1 && c.prediction.conservative_transitions==1)
 // Back on the predicted world, again without a jump.
 t.expect(test,vlen(vsub(test_flap_present(&c,interpolated),blended))<1e-5)
 t.expect(test,c.prediction.visual_offset==vsub(blended,c.prediction.world.player.pose.position))
}
