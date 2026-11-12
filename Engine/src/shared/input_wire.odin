package shared
import nc "../netcode"

// V4 codecs are not dispatched by protocol-3 sessions. Switch the application
// version only when the client/server scheduled path is installed together.
SCHEDULED_MSG_INPUT :: u8(0xD0)
SCHEDULED_MSG_PROBE :: u8(0xD1)
SCHEDULED_MSG_ECHO :: u8(0xD2)
SCHEDULED_MSG_CONTROL :: u8(0xD3)
SCHEDULED_MSG_OWNER :: u8(0xD4)
SCHEDULED_MSG_REQUEST :: u8(0xD5)
SCHEDULED_MSG_RESULT :: u8(0xD6)

Scheduled_Input :: struct { identity: Input_Identity, has_ack: bool, ack: u64, count: int, commands: [4]Scheduled_Command }
Schedule_Control_Kind :: enum u8 { Offer, Request, Accepted, Rejected }
Schedule_Control :: struct { kind: Schedule_Control_Kind, proposal: Schedule_Proposal, server: Server_Stamp, reason: Schedule_Result }

input_write_identity :: proc(w:^nc.Writer,id:Input_Identity) {
 nc.write_u64(w,id.incarnation);nc.write_u32(w,id.epoch);nc.write_u64(w,id.generation)
}
input_read_identity :: proc(r:^nc.Reader) -> Input_Identity { return {nc.read_u64(r),nc.read_u32(r),nc.read_u64(r)} }
scheduled_input_encode :: proc(w:^nc.Writer,input:Scheduled_Input) -> bool {
 if input.count<0 || input.count>4 { return false }
 nc.write_u8(w,SCHEDULED_MSG_INPUT);input_write_identity(w,input.identity)
 nc.write_bool(w,input.has_ack);nc.write_u64(w,input.ack);nc.write_u8(w,u8(input.count))
 for i in 0..<input.count {
  c:=input.commands[i];if c.move==min(i8) { return false }
  nc.write_u64(w,c.sequence);nc.write_u64(w,c.target_tick);nc.write_u8(w,u8(c.move));nc.write_u64(w,c.jump_edge)
 }
 return len(w.data)<=1150
}
scheduled_input_decode :: proc(data:[]u8) -> (input:Scheduled_Input,ok:bool) {
 r:nc.Reader;nc.reader_init(&r,data)
 if nc.read_u8(&r)!=SCHEDULED_MSG_INPUT { return }
 input.identity=input_read_identity(&r);input.has_ack=nc.read_bool(&r);input.ack=nc.read_u64(&r);input.count=int(nc.read_u8(&r))
 if !r.ok || input.count>4 { return {},false }
 for i in 0..<input.count {
  input.commands[i]={nc.read_u64(&r),nc.read_u64(&r),i8(nc.read_u8(&r)),nc.read_u64(&r)}
  if input.commands[i].move==min(i8) { return {},false }
 }
 return input,r.ok && r.pos==len(data)
}
schedule_control_encode :: proc(w:^nc.Writer,c:Schedule_Control) {
 nc.write_u8(w,SCHEDULED_MSG_CONTROL);nc.write_u8(w,u8(c.kind));input_write_identity(w,c.proposal.identity)
 nc.write_u64(w,c.proposal.first_tick);nc.write_u64(w,c.proposal.first_sequence)
 nc.write_u64(w,c.server.tick);nc.write_f32(w,f32(c.server.phase));nc.write_u8(w,u8(c.reason))
}
schedule_control_decode :: proc(data:[]u8) -> (c:Schedule_Control,ok:bool) {
 r:nc.Reader;nc.reader_init(&r,data)
 if nc.read_u8(&r)!=SCHEDULED_MSG_CONTROL { return }
 kind:=nc.read_u8(&r);c.proposal.identity=input_read_identity(&r)
 c.proposal.first_tick=nc.read_u64(&r);c.proposal.first_sequence=nc.read_u64(&r)
 c.server.tick=nc.read_u64(&r);c.server.phase=f64(nc.read_f32(&r));reason:=nc.read_u8(&r)
 if !r.ok || r.pos!=len(data) || kind>u8(Schedule_Control_Kind.Rejected) || reason>u8(Schedule_Result.Overflow) || !finite(f32(c.server.phase)) || c.server.phase<0 || c.server.phase>=1 { return {},false }
 c.kind=Schedule_Control_Kind(kind);c.reason=Schedule_Result(reason);return c,true
}
owner_state_encode :: proc(w:^nc.Writer,o:Owner_State) {
 nc.write_u8(w,SCHEDULED_MSG_OWNER);input_write_identity(w,o.identity)
 nc.write_u64(w,o.state_tick);nc.write_u64(w,o.topology_revision);nc.write_u64(w,o.finalized_through)
 nc.write_u64(w,o.last_applied_sequence);nc.write_u64(w,o.last_jump_edge);nc.write_u64(w,o.teleport_serial)
 nc.write_f32(w,o.position.x);nc.write_f32(w,o.position.y);nc.write_f32(w,o.velocity.x);nc.write_f32(w,o.velocity.y)
 nc.write_f32(w,o.support_velocity.x);nc.write_f32(w,o.support_velocity.y);nc.write_f32(w,o.coyote);nc.write_f32(w,o.buffered_jump)
 nc.write_u64(w,o.support_cell);nc.write_bool(w,o.grounded);nc.write_u8(w,o.support_kind);nc.write_u8(w,u8(o.held));nc.write_u8(w,u8(o.missing))
 nc.write_u8(w,u8(o.speed_effect));nc.write_u32(w,o.speed_ticks)
}
owner_state_decode :: proc(data:[]u8) -> (o:Owner_State,ok:bool) {
 r:nc.Reader;nc.reader_init(&r,data)
 if nc.read_u8(&r)!=SCHEDULED_MSG_OWNER { return }
 o.identity=input_read_identity(&r)
 o.state_tick=nc.read_u64(&r);o.topology_revision=nc.read_u64(&r);o.finalized_through=nc.read_u64(&r)
 o.last_applied_sequence=nc.read_u64(&r);o.last_jump_edge=nc.read_u64(&r);o.teleport_serial=nc.read_u64(&r)
 o.position={nc.read_f32(&r),nc.read_f32(&r)};o.velocity={nc.read_f32(&r),nc.read_f32(&r)}
 o.support_velocity={nc.read_f32(&r),nc.read_f32(&r)};o.coyote=nc.read_f32(&r);o.buffered_jump=nc.read_f32(&r)
 o.support_cell=nc.read_u64(&r);o.grounded=nc.read_bool(&r);o.support_kind=nc.read_u8(&r);o.held=i8(nc.read_u8(&r));o.missing=u32(nc.read_u8(&r))
 effect:=nc.read_u8(&r);o.speed_ticks=nc.read_u32(&r)
 if effect>u8(Speed_Effect.Slow) { return {},false }
 o.speed_effect=Speed_Effect(effect)
 return o,r.ok && r.pos==len(data) && owner_state_valid(o)
}
