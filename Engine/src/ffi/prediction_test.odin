package ffi
import t "core:testing"
import core "../shared"
import nc "../netcode"
import math "core:math"

@(test)
prediction_api_versions_busy_clear_and_full_width_owner :: proc(test:^t.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);t.expect(test,status==OK);context=s.ctx
 core.net_client_init(&s.client,1234,0);s.live=true
 defer t.expect(test,bom_client_destroy(handle)==OK)
 o:=core.Owner_State{identity={9007199254740999,7,9007199254742001},state_tick=9007199254743001,finalized_through=9007199254743001,last_applied_sequence=9007199254744001,last_jump_edge=9007199254745001,teleport_serial=9007199254746001,support_cell=9007199254747001,support_kind=1,grounded=true,position={1.2345,2.3456},velocity={3.4567,4.5678},coyote=.073,buffered_jump=.056}
 s.client.input_link.owner=o;s.client.input_link.has_owner=true
 state:=BomOwnerState{struct_size=u32(size_of(BomOwnerState)),version=1}
 t.expect(test,bom_client_get_owner_state(handle,&state)==OK && state.connection_incarnation==o.identity.incarnation && state.input_generation==o.identity.generation && state.last_applied_sequence==o.last_applied_sequence && state.last_jump_edge==o.last_jump_edge && state.support_cell==o.support_cell && state.velocity_x==o.velocity.x && state.coyote==o.coyote)
 state.version=99;t.expect(test,bom_client_get_owner_state(handle,&state)==BAD_ARGUMENT)
 t.expect(test,bom_client_set_prediction(handle,2)==BAD_ARGUMENT)
 t.expect(test,bom_client_enqueue_jump(handle,1)==OK && bom_client_enqueue_action(handle,1,0,0)==OK && bom_client_set_held_input(handle,1,1)==OK)
 s.acquired=true;t.expect(test,bom_client_clear_intent(handle)==BUSY && bom_client_set_prediction(handle,0)==BUSY);s.acquired=false
 t.expect(test,bom_client_clear_intent(handle)==OK && len(s.jumps)==0 && len(s.actions)==0 && len(s.held)==0 && !s.client.input_link.active)
 t.expect(test,bom_client_set_prediction(handle,0)==OK && !s.client.prediction_enabled)
 stats:=BomPredictionStats{struct_size=u32(size_of(BomPredictionStats)),version=1}
 t.expect(test,bom_client_get_prediction_stats(handle,&stats)==OK && stats.status==0)
}

scheduled_timing_fixture :: proc(test:^t.T,fps:int) -> (u64,u64,u64,u64) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);t.expect(test,status==OK);context=s.ctx
 core.net_client_init(&s.client,1234,0);nc.endpoint_init(&s.client.nc_client.endpoint,1234)
 s.client.nc_client.state=.Connected;s.client.real_gate=true;s.client.real_hello_ok=true;s.client.real_hello_sent=true;s.client.prediction_enabled=false;s.live=true
 defer t.expect(test,bom_client_destroy(handle)==OK)
 id:=core.Input_Identity{9007199254740999,1,9007199254742001}
 proposal:=core.Schedule_Proposal{id,9007199254743001,9007199254744001}
 core.command_history_begin(&s.client.input_link.history,proposal)
 s.client.input_link.offer=proposal;s.client.input_link.has_offer=true;s.client.input_link.active=true
 s.client.input_link.clock=core.Input_Clock{valid=true,estimate={9007199254742998,0},rtt=.05,lead=4}
 s.client.has_epoch=true;s.client.epoch=1;s.input_epoch=1;s.input_generation=id.generation
 t.expect(test,bom_client_set_held_input(handle,0,1)==OK && bom_client_set_held_input(handle,1.25,-1)==OK)
 t.expect(test,bom_client_enqueue_jump(handle,1.025)==OK && bom_client_enqueue_jump(handle,1.03)==OK)
 t.expect(test,bom_client_enqueue_action(handle,2.141,-6.4,2.3)==OK && bom_client_enqueue_action(handle,2.142,1000,1000)==OK)
 t.expect(test,bom_client_update(handle,0)==OK)
 for frame in 1..=fps*3 {
  now:=f64(frame)/f64(fps);s.client.nc_client.last_recv=now
  t.expect(test,bom_client_update(handle,now)==OK)
 }
 t.expect(test,s.stall_count==0 && s.client.request_counter==2 && math.abs(s.fixed_transport_now-3)<1e-9)
 return u64(s.client.stats.input_count),s.client.stats.input_payload_hash,s.client.stats.request_payload_hash,s.client.input_link.history.next_tick
}
@(test)
scheduled_commands_actions_and_targets_match_at_30_60_144_fps :: proc(test:^t.T) {
 count,digest,actions,target:=scheduled_timing_fixture(test,30)
 t.expect(test,count==180)
 for fps in ([3]int{60,144,1000}) {
  n,d,a,last:=scheduled_timing_fixture(test,fps)
  t.expect(test,n==count && d==digest && a==actions && last==target,"exact scheduled command bytes, reliable action bytes and u64 targets are render-rate independent")
 }
}
