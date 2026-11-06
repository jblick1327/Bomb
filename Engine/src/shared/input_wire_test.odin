package shared
import t "core:testing"
import nc "../netcode"
import b2 "vendor:box2d"

@(test)
scheduled_wire_integer_roundtrip_budget_and_truncation :: proc(test:^t.T) {
 input:=Scheduled_Input{identity={9007199254740999,7,4294967301},has_ack=true,ack=9007199254742001,count=4}
 for &c,i in input.commands { c={9007199254743001+u64(i),9007199254744001+u64(i),i8(i*20-30),9007199254745001+u64(i)} }
 w:nc.Writer;nc.writer_init(&w,256);defer nc.writer_destroy(&w)
 t.expect(test,scheduled_input_encode(&w,input));t.expect(test,len(w.data)<200)
 decoded,ok:=scheduled_input_decode(w.data[:]);t.expect(test,ok && decoded==input)
 for size in 0..<len(w.data) { _,valid:=scheduled_input_decode(w.data[:size]);t.expect(test,!valid) }
 append(&w.data,u8(0));_,ok=scheduled_input_decode(w.data[:]);t.expect(test,!ok)
}

@(test)
owner_wire_full_state_precision_and_truncation :: proc(test:^t.T) {
 o:=Owner_State{identity={9007199254740999,7,4294967301},state_tick=9007199254742001,topology_revision=9007199254742003,
 finalized_through=9007199254742001,last_applied_sequence=9007199254743001,teleport_serial=9007199254744001,
 position={1.234567,-2.345678},velocity={3.456789,-4.567891},support_velocity={0.333333,0.444444},coyote=.073,buffered_jump=.056,
 support_cell=9007199254745001,grounded=true,support_kind=1,held=-127,missing=3}
 w:nc.Writer;nc.writer_init(&w,256);defer nc.writer_destroy(&w);owner_state_encode(&w,o)
 decoded,ok:=owner_state_decode(w.data[:]);t.expect(test,ok && decoded==o && len(w.data)<200)
 for size in 0..<len(w.data) { _,valid:=owner_state_decode(w.data[:size]);t.expect(test,!valid) }
 o.velocity.x=transmute(f32)u32(0x7fc00000);nc.writer_reset(&w);owner_state_encode(&w,o)
 _,ok=owner_state_decode(w.data[:]);t.expect(test,!ok)
}

@(test)
schedule_control_exact_origin_and_invalid_enum :: proc(test:^t.T) {
 c:=Schedule_Control{kind=.Accepted,proposal={{9007199254740999,7,9007199254741001},9007199254742001,9007199254743001},server={9007199254741999,0.5}}
 w:nc.Writer;nc.writer_init(&w,128);defer nc.writer_destroy(&w);schedule_control_encode(&w,c)
 decoded,ok:=schedule_control_decode(w.data[:]);t.expect(test,ok && decoded==c)
 for size in 0..<len(w.data) { _,valid:=schedule_control_decode(w.data[:size]);t.expect(test,!valid) }
 w.data[1]=255;_,ok=schedule_control_decode(w.data[:]);t.expect(test,!ok)
}

@(test)
owner_restore_all_movement_state_and_no_prediction_respawn :: proc(test:^t.T) {
 def:=b2.DefaultWorldDef();def.gravity={0,-9.8};world:=b2.CreateWorld(def);defer b2.DestroyWorld(world)
 player:=player_create(world,2.3)
 o:=Owner_State{identity={1,2,3},state_tick=100,finalized_through=100,last_applied_sequence=99,teleport_serial=9007199254740993,
 position={1.234567,1.3},velocity={2.345678,3.456789},support_velocity={.3,.4},coyote=.073,buffered_jump=.056,
 support_cell=9007199254745001,grounded=true,support_kind=1}
 t.expect(test,owner_state_restore(world,&player,o))
 t.expect_value(test,from_b2(b2.Body_GetPosition(player.body)),o.position)
 t.expect_value(test,from_b2(b2.Body_GetLinearVelocity(player.body)),o.velocity)
 t.expect(test,player.grounded && player.coyote==o.coyote && player.buffered_jump==o.buffered_jump && player.support_velocity==o.support_velocity && player.support_cell==o.support_cell && player.teleport_serial==o.teleport_serial)
 // First replay uses the owner's support cache, then the identical movement kernel.
 player_movement_from_support(&player,1,false,1.0/60.0)
 v:=from_b2(b2.Body_GetLinearVelocity(player.body));t.expect(test,v.y==PLAYER_TUNING.jump_speed+o.support_velocity.y)
 b2.World_Step(world,1.0/60.0,PHYSICS_SUBSTEPS);player_after_movement_step(&player)
 t.expect(test,finite(player.pose.position.x) && finite(player.pose.position.y))
 b2.Body_SetTransform(player.body,{100,100},b2.MakeRot(0));serial:=player.teleport_serial
 player_after_movement_step(&player);t.expect(test,player_out_of_bounds(&player) && player.teleport_serial==serial && player.pose.position.x==100)
 bad:=o;bad.coyote=-1;position:=player.pose.position
 t.expect(test,!owner_state_restore(world,&player,bad) && player.pose.position==position)
 t.expect(test,player_after_step(&player) && player.teleport_serial==serial+1)
}
