package ffi
import t "core:testing"
import core "../shared"
import nc "../netcode"
import math "core:math"

@(test)
local_terminal_results_cannot_skip_an_earlier_unresolved_request :: proc(test:^t.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);t.expect(test,status==OK);context=s.ctx
 core.net_client_init(&s.client,1234,0);s.live=true;defer t.expect(test,bom_client_destroy(handle)==OK)
 s.client.request_counter=1;s.client.request_pending[1]={true,1,core.REQUEST_BLAST}
 t.expect(test,core.net_request_client_local_result(&s.client,core.REQUEST_BLAST,.Expired,0))
 result:=BomRequestResult{struct_size=u32(size_of(BomRequestResult)),version=1}
 t.expect(test,bom_client_next_request_result(handle,0,&result)==OK && result.flags==0)
 s.client.request_pending[1]={};s.client.completed_requests[1]={kind=core.REQUEST_BLAST,result={request_id=1,status=.Rejected}}
 t.expect(test,bom_client_next_request_result(handle,0,&result)==OK && result.request_id==1 && result.flags==1)
 t.expect(test,bom_client_next_request_result(handle,1,&result)==OK && result.request_id==2 && result.flags==5 && result.status==u32(core.Request_Status.Expired))
}

@(test)
terminal_request_stream_preserves_u64_identity_status_and_effect_tick :: proc(test:^t.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);t.expect(test,status==OK);context=s.ctx
 core.net_client_init(&s.client,1234,0);s.live=true;defer t.expect(test,bom_client_destroy(handle)==OK)
 base:=u64(9007199254740993)
 for id in base+1..=base+2 { s.client.completed_requests[id%1024]={kind=core.REQUEST_BLAST,result=core.Request_Result{request_id=id,effect_tick=base+100,event_id=base+200,status=.Accepted}} }
 s.client.highest_completed_request=base+2
 result:=BomRequestResult{struct_size=u32(size_of(BomRequestResult)),version=1}
 t.expect(test,bom_client_next_request_result(handle,base,&result)==OK && result.flags==1 && result.request_id==base+1 && result.effect_tick==base+100 && result.event_id==base+200 && result.status==u32(core.Request_Status.Accepted))
 t.expect(test,bom_client_next_request_result(handle,result.request_id,&result)==OK && result.request_id==base+2)
 t.expect(test,bom_client_next_request_result(handle,result.request_id,&result)==OK && result.flags==0)
 t.expect(test,bom_client_next_request_result(handle,0,&result)==OK && result.flags==3 && result.request_id==base+1)
}

@(test)
identical_held_snapshots_coalesce_without_losing_transition_time_or_order :: proc(test:^t.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);t.expect(test,status==OK);context=s.ctx
 core.net_client_init(&s.client,1234,0);s.live=true;defer t.expect(test,bom_client_destroy(handle)==OK)
 for i in 0..<100000 { t.expect(test,bom_client_set_held_input(handle,f64(i)/100000,1)==OK) }
 t.expect(test,len(s.held)==1 && s.held[0].timestamp==0 && s.held[0].move==1)
 t.expect(test,bom_client_set_held_input(handle,.5,-1)==BAD_ARGUMENT)
 for i in 1..<256 { value:=i%2==0?f32(1):f32(-1);t.expect(test,bom_client_set_held_input(handle,f64(i+1),value)==OK) }
 t.expect(test,len(s.held)==256 && bom_client_set_held_input(handle,257,1)==OVERFLOW)
 t.expect(test,bom_client_set_held_input(handle,258,-1)==OK && len(s.held)==256)
}

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
 core.net_client_init(&s.client,1234,0);
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
