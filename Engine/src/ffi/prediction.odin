package ffi
import core "../shared"

@(export)
bom_client_next_request_result :: proc "c" (handle,after_request_id:u64,result:^BomRequestResult) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status }
 if result==nil || result.struct_size<u32(size_of(BomRequestResult)) || result.version!=1 { return BAD_ARGUMENT }
 result^={struct_size=u32(size_of(BomRequestResult)),version=1}
 if !s.live || after_request_id>=s.client.highest_completed_request { return OK }
 best:^core.Completed_Request
 for &entry in s.client.completed_requests {
  if entry.result.request_id<=after_request_id { continue }
  if best==nil || entry.result.request_id<best.result.request_id { best=&entry }
 }
 if best!=nil {
  result.flags=1
  if best.result.request_id!=after_request_id+1 { result.flags|=2 }
  result.kind=u32(best.kind);result.request_id=best.result.request_id;result.effect_tick=best.result.effect_tick;result.event_id=best.result.event_id
  result.status=u32(best.result.status);result.reason=u32(best.result.reason)
 }
 return OK
}

@(export)
bom_client_reset_prediction_metrics :: proc "c" (handle:u64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY }
 p:=s.client.prediction
 if p!=nil {
  p.correction_histogram={};p.corrections=0;p.snaps=0;p.conservative_transitions=0;p.recoveries=0;p.reset_count=0;p.correction_max=0;p.conservative_seconds=0
 }
 return OK
}

@(export)
bom_client_clear_intent :: proc "c" (handle:u64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };if !s.live { return NOT_CONNECTED }
 clear(&s.held);clear(&s.jumps);clear(&s.actions);s.held_move=0;s.input_generation=0
 core.net_client_clear_intent(&s.client)
 core.prediction_controller_reset(&s.client)
 return OK
}
@(export)
bom_client_set_prediction :: proc "c" (handle:u64,enabled:u32) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };if enabled>1 { return BAD_ARGUMENT }
 s.prediction_disabled=enabled==0
 if s.live {
  s.client.prediction_enabled=enabled!=0;core.prediction_controller_reset(&s.client)
  if enabled==0 && s.client.prediction!=nil { s.client.prediction.mode=.Disabled }
 }
 return OK
}
@(export)
bom_client_get_owner_state :: proc "c" (handle:u64,state:^BomOwnerState) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status }
 context=s.ctx
 if state==nil || state.struct_size<u32(size_of(BomOwnerState)) || state.version!=1 { return BAD_ARGUMENT }
 state^={struct_size=u32(size_of(BomOwnerState)),version=1}
 if !s.live || !s.client.input_link.has_owner { return OK }
 o:=s.client.input_link.owner
 state.flags=1;if o.grounded { state.flags|=2 };if s.client.input_link.clock.valid { state.flags|=4 }
 state.connection_incarnation=o.identity.incarnation;state.input_generation=o.identity.generation;state.epoch=o.identity.epoch
 state.state_tick=o.state_tick;state.topology_revision=o.topology_revision;state.finalized_through_tick=o.finalized_through
 state.last_applied_sequence=o.last_applied_sequence;state.last_jump_edge=o.last_jump_edge;state.teleport_serial=o.teleport_serial
 state.support_cell=o.support_cell;state.support_kind=u32(o.support_kind);state.missing_held_ticks=o.missing
 state.position_x=o.position.x;state.position_y=o.position.y;state.velocity_x=o.velocity.x;state.velocity_y=o.velocity.y
 state.support_velocity_x=o.support_velocity.x;state.support_velocity_y=o.support_velocity.y
 state.coyote=o.coyote;state.buffered_jump=o.buffered_jump;state.held_move=core.move_dequantize(o.held)
 return OK
}
@(export)
bom_client_get_prediction_stats :: proc "c" (handle:u64,stats:^BomPredictionStats) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status }
 context=s.ctx
 if stats==nil || stats.struct_size<u32(size_of(BomPredictionStats)) || stats.version!=1 { return BAD_ARGUMENT }
 stats^={struct_size=u32(size_of(BomPredictionStats)),version=1}
 if !s.live { return OK }
 link:=&s.client.input_link
 stats.input_generation=link.history.identity.generation
 stats.rtt_seconds=link.clock.rtt;stats.positive_jitter_p95_seconds=link.clock.jitter95;stats.clock_error_ticks=link.clock.raw_error;stats.lead_ticks=link.clock.lead
 if link.has_owner { stats.owner_tick=link.owner.state_tick;stats.finalized_through_tick=link.owner.finalized_through;stats.last_applied_sequence=link.owner.last_applied_sequence }
 for slot in link.history.slots { if slot.occupied && slot.command.target_tick>link.history.finalized_through { stats.pending_commands+=1 } }
 p:=s.client.prediction
 if p==nil { if s.client.prediction_enabled { stats.status=3 };return OK }
 stats.status=u32(p.mode);stats.reason=u32(p.reason);stats.predicted_tick=p.world.state_tick
 stats.correction_count=p.corrections;stats.snap_count=p.snaps;stats.conservative_transitions=p.conservative_transitions;stats.recoveries=p.recoveries;stats.reset_count=p.reset_count
 stats.correction_p95=core.prediction_quantile(p,95);stats.correction_p99=core.prediction_quantile(p,99);stats.correction_max=p.correction_max
 stats.visual_offset_x=p.visual_offset.x;stats.visual_offset_y=p.visual_offset.y;stats.conservative_seconds=p.conservative_seconds
 return OK
}
