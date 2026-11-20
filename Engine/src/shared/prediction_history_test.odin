package shared
import t "core:testing"
import math "core:math"

@(test)
collision_history_versions_are_effective_at_tick_and_bounded :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 h:Collision_History;defer collision_history_destroy(&h)
 t.expect(test,collision_history_record_topology(&h,&source,10))
 source.structure_revision=2;t.expect(test,collision_history_record_topology(&h,&source,20))
 t.expect(test,collision_history_topology(&h,9)==nil)
 t.expect_value(test,collision_history_topology(&h,19).scene.structure_revision,u64(1))
 t.expect_value(test,collision_history_topology(&h,20).scene.structure_revision,u64(2))
 t.expect(test,collision_history_topology(&h,19,2)==nil)
 for revision in u64(3)..=20 { source.structure_revision=revision;t.expect(test,collision_history_record_topology(&h,&source,revision*10)) }
 t.expect(test,len(h.topology)<=PREDICTION_TOPOLOGY_LIMIT && h.bytes<=PREDICTION_TOPOLOGY_BYTES && h.dropped_windows==1)
 t.expect(test,collision_history_topology(&h,10)==nil)
 source.epoch=2;source.structure_revision=1;t.expect(test,collision_history_record_topology(&h,&source,300))
 t.expect(test,h.epoch==2 && len(h.topology)==1 && !h.has_frame)
}

@(test)
collision_pose_history_interpolates_and_limits_extrapolation :: proc(test:^t.T) {
 h:=Collision_History{epoch=1};defer collision_history_destroy(&h)
 poses:=make(Pose_Table);defer delete(poses);key:=ent_key(.Piece,9007199254740993)
 poses[key]=pose_state_make(0,1,0);t.expect(test,collision_history_record_frame(&h,1,100,&poses))
 poses[key]=pose_state_make(2,3,f32(math.PI/2));t.expect(test,collision_history_record_frame(&h,1,102,&poses))
 pose,estimated,valid:=collision_history_pose(&h,101,key)
 t.expect(test,valid && !estimated && math.abs(pose.x-1)<1e-6 && math.abs(pose.angle-f32(math.PI/4))<1e-6)
 pose,estimated,valid=collision_history_pose(&h,108,key)
 t.expect(test,valid && estimated && math.abs(pose.x-8)<1e-6)
 _,_,valid=collision_history_pose(&h,109,key);t.expect(test,!valid)
 _,_,valid=collision_history_pose(&h,99,key);t.expect(test,!valid)
 _,_,valid=collision_history_pose(&h,101,key+1);t.expect(test,!valid)
 poses[key]=pose_state_make(300,0,0);t.expect(test,collision_history_record_frame(&h,1,400,&poses))
 t.expect(test,!collision_history_record_frame(&h,1,100,&poses))
}
