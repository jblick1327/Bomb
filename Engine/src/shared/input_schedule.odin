package shared

// M5 scheduling kernel. Integration into the v4 wire path follows separately.
// All identities and target arithmetic remain integer; no presentation clock here.
INPUT_FUTURE_WINDOW :: u64(32)
INPUT_HELD_GRACE :: u32(6)
INPUT_HISTORY :: 256

Scheduled_Command :: struct {
 sequence, target_tick: u64,
 move: i8,
 jump_edge: u64,
}
Input_Identity :: struct { incarnation: u64, epoch: u32, generation: u64 }
Schedule_Proposal :: struct { identity: Input_Identity, first_tick, first_sequence: u64 }
Schedule_Result :: enum { Accepted, Wrong_Connection, Wrong_Epoch, Old_Generation, Obsolete, Too_Far, Overflow }
Command_Result :: enum { Accepted, Duplicate, Conflict, Too_Late, Too_Far, Wrong_Identity, Wrong_Slot, Invalid_Move, Not_Synchronized }
Schedule_Slot :: struct { occupied: bool, command: Scheduled_Command }
Input_Schedule :: struct {
 identity: Input_Identity,
 synchronized: bool,
 first_tick,first_sequence,finalized_through,last_applied_sequence,last_jump_edge: u64,
 slots: [32]Schedule_Slot,
 held: i8,
 missing: u32,
 accepted,duplicates,conflicts,too_late,wrong_identity,starved,neutralized,duplicate_jumps: u64,
}
Scheduled_Step :: struct { command: Scheduled_Command, applied,carried,neutralized: bool }

input_schedule_reset :: proc(s: ^Input_Schedule,incarnation: u64,epoch: u32,now_tick: u64,p: Schedule_Proposal) -> Schedule_Result {
 if p.identity.incarnation!=incarnation || incarnation==0 { return .Wrong_Connection }
 if p.identity.epoch!=epoch { return .Wrong_Epoch }
 if p.identity.generation==0 || (s.synchronized && p.identity.incarnation==s.identity.incarnation && p.identity.generation<=s.identity.generation) { return .Old_Generation }
 if now_tick>max(u64)-INPUT_FUTURE_WINDOW || p.first_sequence==0 || p.first_sequence>max(u64)-INPUT_FUTURE_WINDOW { return .Overflow }
 if p.first_tick<now_tick+2 { return .Obsolete }
 if p.first_tick>now_tick+INPUT_FUTURE_WINDOW { return .Too_Far }
 // Rejection above leaves the previous schedule completely unchanged.
 s^=Input_Schedule{identity=p.identity,synchronized=true,first_tick=p.first_tick,first_sequence=p.first_sequence,finalized_through=now_tick}
 return .Accepted
}

input_schedule_insert :: proc(s: ^Input_Schedule,identity: Input_Identity,now_tick: u64,c: Scheduled_Command) -> Command_Result {
 if !s.synchronized { return .Not_Synchronized }
 if identity!=s.identity { s.wrong_identity+=1;return .Wrong_Identity }
 if c.move==min(i8) { return .Invalid_Move }
 if c.target_tick<=s.finalized_through || c.target_tick<=now_tick { s.too_late+=1;return .Too_Late }
 if c.target_tick-now_tick>INPUT_FUTURE_WINDOW { return .Too_Far }
 if c.target_tick<s.first_tick { return .Wrong_Slot }
 offset:=c.target_tick-s.first_tick
 if offset>max(u64)-s.first_sequence || c.sequence!=s.first_sequence+offset { return .Wrong_Slot }
 slot:=&s.slots[c.target_tick%u64(len(s.slots))]
 if slot.occupied && slot.command.target_tick>s.finalized_through {
  if slot.command==c { s.duplicates+=1;return .Duplicate }
  s.conflicts+=1;return .Conflict
 }
 slot^={occupied=true,command=c};s.accepted+=1
 return .Accepted
}

input_schedule_consume :: proc(s: ^Input_Schedule,tick: u64) -> (step: Scheduled_Step) {
 if !s.synchronized || tick<=s.finalized_through { return }
 // A discontinuity cannot carry stale held movement across the skipped interval.
 if tick!=s.finalized_through+1 { s.held=0;s.missing=INPUT_HELD_GRACE }
 slot:=&s.slots[tick%u64(len(s.slots))]
 if tick>=s.first_tick && slot.occupied && slot.command.target_tick==tick {
  step.command=slot.command;step.applied=true;slot^={}
  s.held=step.command.move;s.missing=0;s.last_applied_sequence=step.command.sequence
  if step.command.jump_edge!=0 {
   if step.command.jump_edge<=s.last_jump_edge { step.command.jump_edge=0;s.duplicate_jumps+=1 }
   else { s.last_jump_edge=step.command.jump_edge }
  }
 } else {
  s.missing=min(s.missing+1,INPUT_HELD_GRACE+1);s.starved+=1
  step.command.target_tick=tick
  if tick>=s.first_tick && s.missing<=INPUT_HELD_GRACE { step.command.move=s.held;step.carried=true }
  else { s.held=0;step.neutralized=true;s.neutralized+=1 }
 }
 s.finalized_through=tick
 return
}

Command_History :: struct {
 identity: Input_Identity,
 first_tick,first_sequence,next_tick,next_sequence,finalized_through: u64,
 accepted: bool,
 slots: [INPUT_HISTORY]Schedule_Slot,
}
command_history_begin :: proc(h: ^Command_History,p: Schedule_Proposal) {
 h^={identity=p.identity,first_tick=p.first_tick,first_sequence=p.first_sequence,next_tick=p.first_tick,next_sequence=p.first_sequence,accepted=true}
}
command_history_push :: proc(h: ^Command_History,move: i8,jump_edge: u64) -> (Scheduled_Command,bool) {
 if !h.accepted || move==min(i8) || h.next_tick==max(u64) || h.next_sequence==max(u64) { return {},false }
 slot:=&h.slots[h.next_tick%INPUT_HISTORY]
 if slot.occupied && slot.command.target_tick>h.finalized_through { return {},false }
 c:=Scheduled_Command{sequence=h.next_sequence,target_tick=h.next_tick,move=move,jump_edge=jump_edge}
 slot^={occupied=true,command=c};h.next_sequence+=1;h.next_tick+=1
 return c,true
}
command_history_finalize :: proc(h: ^Command_History,identity: Input_Identity,tick: u64) -> bool {
 if !h.accepted || identity!=h.identity || tick<h.finalized_through { return false }
 // An owner may finalize missing slots; it may not ACK commands from the future.
 if tick>=h.next_tick { return false }
 h.finalized_through=tick
 for &slot in h.slots { if slot.occupied && slot.command.target_tick<=tick { slot={} } }
 return true
}
command_history_redundancy :: proc(h: ^Command_History) -> (out: [4]Scheduled_Command,count: int) {
 if !h.accepted || h.next_tick<=h.first_tick { return }
 tick:=h.next_tick-1
 for count<4 && tick>=h.first_tick {
  slot:=h.slots[tick%INPUT_HISTORY]
  if !slot.occupied || slot.command.target_tick!=tick { break }
  out[count]=slot.command;count+=1
  if tick==0 { break };tick-=1
 }
 return
}
