package shared
import t "core:testing"
import b2 "vendor:box2d"
import math "core:math"

@(test)
moving_rotating_proxy_uses_reference_frame_and_bounded_history :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 source.anchor_y=-1e30;source.pieces[0].ref_rest={.5,-1.5}
 p:Static_Prediction;defer prediction_static_destroy(&p)
 t.expect(test,prediction_static_build(&p,&source,true) && len(p.proxies)==1)
 h:=Collision_History{epoch=1};defer collision_history_destroy(&h)
 poses:=make(Pose_Table);defer delete(poses);key:=ent_key(.Piece,100)
 poses[key]=pose_state_make(.5,-1.5,0);_=collision_history_record_frame(&h,1,100,&poses)
 poses[key]=pose_state_make(1.5,-1.5,f32(math.PI/2));_=collision_history_record_frame(&h,1,102,&poses)
 t.expect(test,prediction_proxy_positions(&p,&h,100))
 body:=p.proxies[0].body
 t.expect(test,b2.Body_GetType(body)==.kinematicBody && vlen(from_b2(b2.Body_GetPosition(body)))<1e-6)
 t.expect(test,math.abs(b2.Body_GetAngularVelocity(body)-f32(math.PI/4)*60)<.001)
 t.expect(test,!prediction_proxy_positions(&p,&h,109) && p.reason==.Dynamic_History_Required)
}

@(test)
rubber_proxy_is_a_cell_center_body_and_static_ground_stays_static :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 source.anchor_y=-1e30;source.materials[0].flexibility=1
 p:Static_Prediction;defer prediction_static_destroy(&p)
 t.expect(test,prediction_static_build(&p,&source,true) && len(p.proxies)==1)
 t.expect(test,p.proxies[0].key==ent_key(.Rubber,200) && !p.proxies[0].rigid)
 h:=Collision_History{epoch=1};defer collision_history_destroy(&h)
 poses:=make(Pose_Table);defer delete(poses)
 poses[ent_key(.Rubber,200)]=pose_state_make(3,4,0);_=collision_history_record_frame(&h,1,100,&poses);_=collision_history_record_frame(&h,1,101,&poses)
 t.expect(test,prediction_proxy_positions(&p,&h,100))
 position:=from_b2(b2.Body_GetPosition(p.proxies[0].body));t.expect(test,position==Vec2{3,4})
 source.anchor_y=-3;t.expect(test,prediction_static_build(&p,&source) && len(p.proxies)==0)
 t.expect(test,prediction_proxy_positions(&p,nil,100))
}
