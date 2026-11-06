package shared

// Native schedule handshake state. Both frontends use this; no frontend may
// invent target ticks or shift already-issued commands after a rejected origin.
Input_Link :: struct {
 clock: Input_Clock,
 history: Command_History,
 offer,pending: Schedule_Proposal,
 has_offer,awaiting,active: bool,
 next_generation,jump_edge_counter: u64,
 has_owner: bool,
 owner: Owner_State,
 resets,rejections,retired_slots: u64,
}

input_link_offer :: proc(c:^Input_Link,offer:Schedule_Control) -> bool {
 if offer.kind!=.Offer || offer.proposal.identity.incarnation==0 || offer.proposal.identity.generation==0 { return false }
 // A stale offer cannot revive the previous epoch or connection.
 if c.has_offer && offer.proposal.identity.incarnation==c.offer.identity.incarnation && offer.proposal.identity.epoch<c.offer.identity.epoch { return false }
 c.offer=offer.proposal;c.has_offer=true;c.awaiting=false;c.active=false;c.history={};c.has_owner=false
 c.next_generation=max(c.next_generation,offer.proposal.identity.generation)
 c.resets+=1
 return true
}

input_link_prepare_reset :: proc(c:^Input_Link,now:f64) -> (request:Schedule_Control,ready:bool) {
 if !c.has_offer || c.awaiting || c.active || c.next_generation==max(u64) { return }
 tick,ok:=input_clock_target_origin(&c.clock,now);if !ok { return }
 // The clock determines the target. The server's offered tick is only a lower
 // bound; it is not a hidden mapping of the client's sequence onto another slot.
 tick=max(tick,c.offer.first_tick)
 c.pending={identity=c.offer.identity,first_tick=tick,first_sequence=c.offer.first_sequence}
 c.pending.identity.generation=c.next_generation;c.next_generation+=1
 if c.jump_edge_counter==max(u64) { c.jump_edge_counter=0 }
 c.awaiting=true;command_history_begin(&c.history,c.pending)
 return {kind=.Request,proposal=c.pending},true
}

input_link_control_result :: proc(c:^Input_Link,result:Schedule_Control) -> bool {
 if !c.awaiting || result.proposal!=c.pending { return false }
 if result.kind==.Accepted {
  c.awaiting=false;c.active=true;c.clock.resync=false;c.has_owner=false;return true
 }
 if result.kind==.Rejected {
  c.awaiting=false;c.active=false;c.history={};c.rejections+=1
  // A rejected proposal's command bytes are terminal, never retargeted. A new
  // attempt uses a fresh generation and a fresh clock-derived origin.
  return true
 }
 return false
}

input_link_clear_intent :: proc(c:^Input_Link) {
 c.active=false;c.awaiting=false;c.history={};c.has_owner=false;c.resets+=1
}

input_link_command :: proc(c:^Input_Link,move:i8,jump:bool) -> (Scheduled_Command,bool) {
 if !c.active && !c.awaiting { return {},false }
 held:=move;press:=jump
 if !c.active { held=0;press=false }
 edge:=u64(0)
 if press {
  if c.jump_edge_counter==max(u64) { input_link_clear_intent(c);return {},false }
  c.jump_edge_counter+=1;edge=c.jump_edge_counter
 }
 command,ok:=command_history_push(&c.history,held,edge)
 if !ok { input_link_clear_intent(c) }
 return command,ok
}

input_link_packet :: proc(c:^Input_Link,has_ack:bool,ack:u64) -> (packet:Scheduled_Input,ready:bool) {
 if !c.active { return }
 packet.identity=c.history.identity;packet.has_ack=has_ack;packet.ack=ack
 packet.commands,packet.count=command_history_redundancy(&c.history)
 return packet,true
}

input_link_owner :: proc(c:^Input_Link,owner:Owner_State) -> bool {
 if !c.active || owner.identity!=c.history.identity || !owner_state_valid(owner) || (c.has_owner && owner.state_tick<=c.owner.state_tick) { return false }
 if owner.finalized_through>=c.history.next_tick {
  // The server advanced past all locally issued targets. Clear and negotiate;
  // no replay or silently shifted origin can rescue a stalled schedule.
  input_link_clear_intent(c);return false
 }
 previous:=c.history.finalized_through
 if !command_history_finalize(&c.history,owner.identity,owner.finalized_through) { return false }
 baseline:=max(previous,c.history.first_tick-1)
 if owner.finalized_through>baseline { c.retired_slots+=owner.finalized_through-baseline }
 c.owner=owner;c.has_owner=true
 return true
}
