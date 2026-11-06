package shared
import t "core:testing"
import b2 "vendor:box2d"

@(test)
known_fracture_is_not_replayed_with_old_geometry_and_fresh_owner_recovers :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 c:Net_Client;net_client_init(&c,1236,0);defer net_client_destroy(&c)
 c.real_gate=true;c.nc_client.client_index=0;c.epoch=1;c.has_epoch=true
 _=collision_history_record_topology(&c.collision_history,&source,0)
 source.structure_revision=2;source.subdivisions[0].id=201;source.subdivisions[0].owner=101
 source.subdivisions[0].outline.points[2].y=-1;source.subdivisions[0].outline.points[3].y=-1;source.subdivisions[0].rest_center={.5,-2}
 source.pieces[0].id=101;source.pieces[0].subdivisions[0]=201
 clear(&source.sub_rows);source.sub_rows[201]=0;clear(&source.piece_rows);source.piece_rows[101]=0
 _=collision_history_record_topology(&c.collision_history,&source,3)
 id:=Input_Identity{1,1,1};command_history_begin(&c.input_link.history,{id,1,1})
 for i in 0..<5 { _,_=command_history_push(&c.input_link.history,0,0) }
 c.input_link.active=true;c.input_link.has_owner=true
 c.input_link.owner=Owner_State{identity=id,state_tick=1,finalized_through=1,topology_revision=1,position=PLAYER_SPAWN,teleport_serial=1}
 net_prediction_update(&c,0)
 t.expect(test,c.prediction.mode==.Conservative && c.prediction.reason==.Wrong_Revision && c.prediction.world.state_tick==2)
 c.input_link.owner.state_tick=3;c.input_link.owner.finalized_through=3;c.input_link.owner.topology_revision=2
 c.input_link.owner.position={-4.5,.56};c.input_link.owner.velocity={0,-.1633}
 net_prediction_update(&c,.016)
 t.expect(test,c.prediction.mode==.Predicting && c.prediction.recoveries==1 && c.prediction.world.revision==2 && c.prediction.world.state_tick==5)
 t.expect(test,200 not_in c.prediction.world.scene.sub_rows && 201 in c.prediction.world.scene.sub_rows && c.prediction.world.player.pose.position.y<.56)
}

@(test)
bomb_contact_uncertainty_is_explicit_and_recovers_without_old_impulses :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 c:Net_Client;net_client_init(&c,1237,0);defer net_client_destroy(&c)
 c.real_gate=true;c.nc_client.client_index=0;c.epoch=1;c.has_epoch=true
 _=collision_history_record_topology(&c.collision_history,&source,0)
 id:=Input_Identity{1,1,1};command_history_begin(&c.input_link.history,{id,1,1})
 for i in 0..<5 { _,_=command_history_push(&c.input_link.history,0,0) }
 c.input_link.active=true;c.input_link.has_owner=true
 c.input_link.owner=Owner_State{identity=id,state_tick=5,finalized_through=5,topology_revision=1,position=PLAYER_SPAWN,teleport_serial=1}
 poses:=make(Pose_Table);defer delete(poses)
 poses[ent_key(.Bomb,1)]=pose_state_make(PLAYER_SPAWN.x,PLAYER_SPAWN.y+1,0)
 _=collision_history_record_frame(&c.collision_history,1,5,&poses)
 net_prediction_update(&c,0)
 t.expect(test,c.prediction.mode==.Conservative && c.prediction.reason==.Dynamic_History_Required)
 clear(&poses);_=collision_history_record_frame(&c.collision_history,1,6,&poses)
 net_prediction_update(&c,.2)
 t.expect(test,c.prediction.mode==.Predicting && c.prediction.recoveries==1 && c.prediction.conservative_seconds<1)
}

@(test)
native_controller_predicts_locally_and_visual_offset_never_moves_body :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 c:Net_Client;net_client_init(&c,1234,0);defer net_client_destroy(&c)
 c.real_gate=true;c.nc_client.client_index=0;c.epoch=1;c.has_epoch=true
 _=collision_history_record_topology(&c.collision_history,&source,0)
 id:=Input_Identity{1,1,1};command_history_begin(&c.input_link.history,{id,1,9007199254740993})
 c.input_link.active=true;c.input_link.has_owner=true
 c.input_link.owner=Owner_State{identity=id,topology_revision=1,position=PLAYER_SPAWN,teleport_serial=1}
 for i in 0..<5 { _,_=command_history_push(&c.input_link.history,127,0) }
 net_prediction_update(&c,0)
 t.expect(test,c.prediction.mode==.Predicting && c.prediction.world.state_tick==5 && c.prediction.world.player.pose.position.x>PLAYER_SPAWN.x)
 body:=c.prediction.world.player.body;position:=from_b2(b2.Body_GetPosition(body))
 c.prediction.visual_offset={.1,.2};net_client_compute_drawn(&c)
 drawn:=c.drawn[ent_key(.Player,0)]
 t.expect(test,drawn.x==position.x+.1 && drawn.y==position.y+.2 && from_b2(b2.Body_GetPosition(body))==position)
 next:=c.input_link.history.next_tick;c.prediction_enabled=false;net_prediction_update(&c,.016)
 t.expect(test,c.prediction.mode==.Disabled && c.input_link.history.next_tick==next)
 net_client_compute_drawn(&c);t.expect(test,len(c.drawn)==0)
}

@(test)
native_controller_missing_revision_falls_back_and_fresh_history_recovers :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 c:Net_Client;net_client_init(&c,1235,0);defer net_client_destroy(&c)
 c.real_gate=true;c.nc_client.client_index=0;c.epoch=1;c.has_epoch=true
 id:=Input_Identity{1,1,1};command_history_begin(&c.input_link.history,{id,1,1})
 for i in 0..<5 { _,_=command_history_push(&c.input_link.history,127,0) }
 c.input_link.active=true;c.input_link.has_owner=true
 c.input_link.owner=Owner_State{identity=id,state_tick=5,finalized_through=5,topology_revision=2,position=PLAYER_SPAWN,teleport_serial=1}
 net_prediction_update(&c,0)
 t.expect(test,c.prediction.mode==.Conservative && c.prediction.reason==.Wrong_Revision)
 source.structure_revision=2;_=collision_history_record_topology(&c.collision_history,&source,1)
 net_prediction_update(&c,.016)
 t.expect(test,c.prediction.mode==.Predicting && c.prediction.recoveries==1 && c.prediction.conservative_seconds<1)
 t.expect(test,c.prediction.world.state_tick==5 && c.prediction.world.player.pose.position==PLAYER_SPAWN)
}
