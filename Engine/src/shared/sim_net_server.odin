#+feature dynamic-literals
package shared

import nc "../netcode"
import b2 "vendor:box2d"
import math "core:math"
import fmt "core:fmt"
import slice "core:slice"
import time "core:time"

Net_Entity :: struct { state: Pose_State, fx,fy,fa: f32, speed,area,angular_speed: f32 }

Net_Server_Stats :: struct {
 frame_bytes: [dynamic]i32, // payload bytes of this client's pose frame parts, per tick
 frame_parts: [dynamic]i32,
 build_ms: [dynamic]f64,
 saturated_ticks,ticks: int, // ticks where some candidate did not fit the budget
 staleness_max: u64,
 staleness_samples: [dynamic]u16,
 staleness_count:u64,
 jumps_applied,jump_presses_seen: int,
 blasts_applied,blasts_rejected,blast_duplicates: int,
 rejected_rate,rejected_outside,rejected_solid: int,
 inputs,inputs_stale,acks: int,
 entries_sent,gone_sent,forced_sent,parts_sent: int,
}

Net_Server_Client :: struct {
 round_credentials:Round_Credentials,
 schedule: Input_Schedule,
 incarnation: u64,
 echo_nonce: u64,
 requests: ^Request_Cache,
 active: bool,
 is_host: bool, // validated only in the real-process app handshake
 ring: [NET_SENT_RING]Pose_Table,
 ring_tick: [NET_SENT_RING]u64,
 ring_valid: [NET_SENT_RING]bool,
 has_ack: bool, acked: u64,
 priority: map[u64]f32,
 last_sent: map[u64]Pose_State,
 pending: map[u64]u64,
 has_input: bool, input_seq: u16,
 move: f32, radius: f32, jump_counter: u16, jump_pending: bool,
 last_blast_seq: u16,
 blast_queue: [dynamic]Net_Blast,
 blast_ticks: [dynamic]u64,
 recent_seqs: [16]u16, recent_count: int,
 stats: Net_Server_Stats,
}

Net_Server :: struct {
 rounds:Round_Controller,
 round_admission:Round_Admission,
 round_dirty,round_mode_pending:bool,
 round_next_mode:Game_Mode,
 async_rebuild:bool,
 rebuild,rebuild_cleanup:^Net_Rebuild_Job,
 rebuild_test_gate:^b32,
 next_incarnation: u64,
 next_event_id: u64,
 game: Headless_Game,
 srv: nc.Server,
 repl: Repl_Server,
 clients: [nc.MAX_CLIENTS]Net_Server_Client,
 real_hash_generation: [nc.MAX_CLIENTS]u64,
 tick: u64,
 frame_epoch: u32,
 current: map[u64]Net_Entity,
 keys: [dynamic]u64,
 tick_ms,world_ms: [dynamic]f64,
 record_hashes: bool,real_logging: bool,
 real_gate: bool, // application Hello required before a World player is created
 real_host_token: string, // CLI-owned for lifetime of process
 real_host_index: int,
 real_host_seen: bool,
 real_host_left_at: f64,
 real_reject_at: [nc.MAX_CLIENTS]f64,
 real_hash_checks,real_hash_mismatch,real_hash_unrecorded: int,
 hashes: map[u64]u64, // (epoch<<40 | revision) -> hash of the canonical structure
 reliable_bytes: int,
 explosions_emitted: int,
 pre_events: Tick_Events,
}

net_hash_key :: proc(epoch: u32,revision: u64) -> u64 { return (u64(epoch)<<40)|(revision&((u64(1)<<40)-1)) }

net_server_init_world :: proc(ns: ^Net_Server,game: Headless_Game,record_hashes: bool = false) {
 ns^={}
 ns.game=game
 ns.real_host_index=-1
 ns.real_host_left_at=-1
 ns.record_hashes=record_hashes
 nc.server_init(&ns.srv)
 ns.current=make(map[u64]Net_Entity)
 ns.hashes=make(map[u64]u64)
 // Establish the shared structure index; joiners get a Baseline at the current revision.
 first:=repl_server_update(&ns.repl,&ns.game.world.scene,0); repl_output_destroy(&first)
 ns.frame_epoch=ns.game.world.scene.epoch
 net_record_hash(ns)
}

net_client_state_clear :: proc(c: ^Net_Server_Client) {
 for i in 0..<NET_SENT_RING { if c.ring_valid[i] { delete(c.ring[i]) }; c.ring[i]={}; c.ring_valid[i]=false }
 c.has_ack=false; c.acked=0
 clear(&c.priority); clear(&c.last_sent); clear(&c.pending)
}

net_server_destroy :: proc(ns: ^Net_Server) {
 net_rebuild_destroy(ns)
 for &c in ns.clients {
  if c.requests!=nil { free(c.requests);c.requests=nil }
  net_client_state_clear(&c)
  delete(c.priority); delete(c.last_sent); delete(c.pending); delete(c.blast_queue); delete(c.blast_ticks)
  delete(c.stats.frame_bytes); delete(c.stats.frame_parts); delete(c.stats.build_ms); delete(c.stats.staleness_samples)
 }
 nc.server_destroy(&ns.srv)
 repl_server_destroy(&ns.repl)
 headless_game_destroy(&ns.game)
 delete(ns.current); delete(ns.keys); delete(ns.tick_ms); delete(ns.world_ms); delete(ns.hashes)
 delete(ns.pre_events.explosions)
 ns^={}
}

net_send_reliable_parts :: proc(ns: ^Net_Server,client: int,out: ^Repl_Output) {
 queued:=true
 for part in out.parts { if nc.server_send_reliable(&ns.srv,client,part) { ns.reliable_bytes+=len(part) } else { queued=false } }
 if ns.record_hashes && ns.real_logging {
  s:=&ns.game.world.scene
  fmt.printf("HASH EXPECT client=%d connection=%d epoch=%d revision=%d tick=%d queued=%s\n",client,ns.real_hash_generation[client],s.epoch,s.structure_revision,ns.tick,queued?"yes":"no")
 }
}

net_record_hash :: proc(ns: ^Net_Server) {
 if !ns.record_hashes { return }
 s:=&ns.game.world.scene
 data:=canonical_encode(s); defer delete(data)
 ns.hashes[net_hash_key(s.epoch,s.structure_revision)]=repl_hash(data)
}

net_server_join :: proc(ns: ^Net_Server,index: int) {
 ns.round_dirty=true
 ns.real_hash_generation[index]+=1
 c:=&ns.clients[index]
 ns.next_incarnation+=1;c.incarnation=ns.next_incarnation;c.schedule={};c.echo_nonce=0
 if c.requests==nil { c.requests=new(Request_Cache) }
 c.requests^=Request_Cache{incarnation=c.incarnation}
 net_client_state_clear(c)
 if c.priority==nil { c.priority=make(map[u64]f32) }
 if c.last_sent==nil { c.last_sent=make(map[u64]Pose_State) }
 if c.pending==nil { c.pending=make(map[u64]u64) }
 c.has_input=false; c.input_seq=0; c.move=0; c.jump_counter=0; c.jump_pending=false
 c.last_blast_seq=0; c.recent_count=0
 clear(&c.blast_queue); clear(&c.blast_ticks)
 c.active=true; c.is_host=false; c.radius=ns.game.world.settings.blast_radius
 world_add_player(&ns.game.world,index)
 out:=repl_server_baseline(&ns.repl,&ns.game.world.scene,ns.tick); defer repl_output_destroy(&out)
 net_send_reliable_parts(ns,index,&out)
 if ns.real_gate { net_scheduled_server_offer(ns,index) }
}

net_server_leave :: proc(ns: ^Net_Server,index: int) {
 round_disconnect(&ns.rounds,index);ns.round_dirty=true
 if ns.record_hashes && ns.real_logging { fmt.printf("HASH CLOSED client=%d connection=%d tick=%d\n",index,ns.real_hash_generation[index],ns.tick) }
 net_client_state_clear(&ns.clients[index])
 ns.clients[index].active=false
 ns.clients[index].is_host=false
 world_remove_player(&ns.game.world,index)
}

net_server_ack :: proc(ns: ^Net_Server,c: ^Net_Server_Client,tick: u64) {
 slot:=tick%NET_SENT_RING
 if !c.ring_valid[slot] || c.ring_tick[slot]!=tick { return }
 if c.has_ack && tick<=c.acked { return }
 c.has_ack=true; c.acked=tick; c.stats.acks+=1
}

net_server_input :: proc(ns: ^Net_Server,index: int,in_: Net_Input) {
 c:=&ns.clients[index]
 if !c.active { return }
 c.stats.inputs+=1
 if in_.epoch==ns.game.world.scene.epoch && in_.has_ack { net_server_ack(ns,c,in_.ack) }
 // The jump counter and blast sequence are cumulative: they survive lost and reordered inputs.
 if seq16_newer(in_.jump_counter,c.jump_counter) { c.jump_counter=in_.jump_counter; c.jump_pending=true; c.stats.jumps_applied+=1 }
 for k in 0..<in_.blast_count {
  b:=in_.blasts[k]
  if !seq16_newer(b.seq,c.last_blast_seq) { continue }
  queued:=false
  for q in c.blast_queue { if q.seq==b.seq { queued=true } }
  if !queued { append(&c.blast_queue,b) }
 }
 if c.has_input && !seq16_newer(in_.seq,c.input_seq) { c.stats.inputs_stale+=1; return }
 c.has_input=true; c.input_seq=in_.seq
 c.move=move_dequantize(in_.move); if !ns.real_gate { c.radius=radius_dequantize(in_.radius_q) }
}

net_server_blast :: proc(ns: ^Net_Server,index: int,b: Net_Blast) {
 c:=&ns.clients[index]; w:=&ns.game.world
 c.last_blast_seq=b.seq
 for i in 0..<min(c.recent_count,len(c.recent_seqs)) { if c.recent_seqs[i]==b.seq { c.stats.blast_duplicates+=1; return } }
 c.recent_seqs[c.recent_count%len(c.recent_seqs)]=b.seq; c.recent_count+=1
 point:=Vec2{nc.dequantize_pos(b.x),nc.dequantize_pos(b.y)}
 radius:=c.radius; if !ns.real_gate { radius=radius_dequantize(b.radius_q) }
 inside:=point.x>=YARD_LEFT && point.x<=YARD_RIGHT && point.y>YARD_FLOOR_BOTTOM && point.y<=NET_YARD_CEILING
 recent:=0
 for t in c.blast_ticks { if ns.tick+1-t<NET_BLAST_RATE_TICKS { recent+=1 } }
 reason:=0
 if ns.rounds.mode==.Elimination || (ns.real_gate && !c.is_host) {reason=4}
 else if !inside { reason=1 } else if recent>=NET_BLAST_RATE_COUNT { reason=2 } else if !sandbox_valid_aim(&w.scene,point) { reason=3 }
 if reason!=0 {
  c.stats.blasts_rejected+=1
  switch reason { case 1: c.stats.rejected_outside+=1; case 2: c.stats.rejected_rate+=1; case 3: c.stats.rejected_solid+=1 }
  ns.pre_events.blast_rejected[index]=true
  wr:nc.Writer; nc.writer_init(&wr,16); defer nc.writer_destroy(&wr)
  event_encode_rejected(&wr,ns.tick+1,b.seq)
  nc.server_send_reliable(&ns.srv,index,wr.data[:])
  return
 }
 world_explode(w,point,radius,&ns.pre_events)
 c.stats.blasts_applied+=1
 append(&c.blast_ticks,ns.tick+1)
}

net_collect :: proc(ns: ^Net_Server) {
 clear(&ns.current)
 w:=&ns.game.world; s:=&w.scene
 for p in s.pieces {
  if !p.live || p.body==b2.nullBodyId || s.materials[p.material].flexibility>0 { continue }
  if b2.Body_GetType(p.body)!=.dynamicBody { continue }
  pos,rot:=b2.Body_GetPosition(p.body),b2.Body_GetRotation(p.body)
  angle:=f32(math.atan2(rot.s,rot.c))
  reference:=frame_to_reference(Pose{position=from_b2(pos),angle=angle},p.ref_rest)
  pos=to_b2(reference.position)
  velocity:=b2.Body_GetLocalPointVelocity(p.body,to_b2(p.ref_rest))
  ns.current[ent_key(.Piece,p.id)]=Net_Entity{state=pose_state_make(pos.x,pos.y,angle),fx=pos.x,fy=pos.y,fa=angle,speed=math.sqrt(velocity.x*velocity.x+velocity.y*velocity.y),area=p.mass,angular_speed=math.abs(b2.Body_GetAngularVelocity(p.body))}
 }
 for sub in s.subdivisions {
  if !sub.live || sub.body==b2.nullBodyId || s.materials[sub.material].flexibility<=0 { continue }
  if b2.Body_GetType(sub.body)!=.dynamicBody { continue }
  pose:=sub.pose
  ns.current[ent_key(.Rubber,sub.id)]=Net_Entity{state=pose_state_make(pose.position.x,pose.position.y,pose.angle),fx=pose.position.x,fy=pose.position.y,fa=pose.angle,speed=vlen(pose.velocity),area=polygon_area(sub.outline)}
 }
 for player,i in w.players {
  if !player.active { continue }
  pose:=player.pose
  ns.current[ent_key(.Player,u64(i))]=Net_Entity{state=pose_state_make(pose.position.x,pose.position.y,pose.angle),fx=pose.position.x,fy=pose.position.y,fa=pose.angle}
 }
 for bomb in w.bombs {
  pose:=bomb.pose
  state:=pose_state_make(pose.position.x,pose.position.y,pose.angle)
  state.landed=bomb.landed; state.fuse=pose_q_fuse(bomb.fuse)
  ns.current[ent_key(.Bomb,bomb.id)]=Net_Entity{state=state,fx=pose.position.x,fy=pose.position.y,fa=pose.angle}
 }
 sorted_keys(&ns.current,&ns.keys)
}

Net_Candidate :: struct { entry: Frame_Entry, accumulator: f32, fresh: bool }

net_build_frame :: proc(ns: ^Net_Server,index: int) {
 c:=&ns.clients[index]; w:=&ns.game.world
 started:=time.tick_now()
 base:^Pose_Table; has_base:=false; base_tick:=u64(0)
 if c.has_ack {
  slot:=c.acked%NET_SENT_RING
  if c.ring_valid[slot] && c.ring_tick[slot]==c.acked { base=&c.ring[slot]; has_base=true; base_tick=c.acked }
 }
 player_position:=Vec2{}; if w.players[index].active { player_position=w.players[index].pose.position }
 candidates:[dynamic]Net_Candidate; defer delete(candidates)
 forced:[dynamic]Frame_Entry; defer delete(forced)
 for key in ns.keys {
  entity:=ns.current[key]
  row:Pose_State; has:=false
  if base!=nil { row,has=base^[key] }
  // Staleness: when did this state first differ from what was last sent?
  last,sent_before:=c.last_sent[key]
  matches_base:=has && row==entity.state
  if matches_base { delete_key(&c.pending,key) } // the acked table already shows this state
  else if !sent_before || last!=entity.state { if key not_in c.pending { c.pending[key]=ns.tick } }
  if matches_base { delete_key(&c.priority,key); continue }
  kind:=key_kind(key)
  if kind==.Player || kind==.Bomb { append(&forced,Frame_Entry{key,entity.state}); continue }
  near:=vlen(vsub(Vec2{entity.fx,entity.fy},player_position))<4
  gain:=(1+entity.speed)*(0.5+min(entity.area,1))*(near?2:1)
  accumulator:=c.priority[key]+gain
  c.priority[key]=accumulator
  append(&candidates,Net_Candidate{entry={key,entity.state},accumulator=accumulator,fresh=!has})
 }
 gone:[dynamic]u64; defer delete(gone)
 if base!=nil { for key in base^ { if key not_in ns.current { append(&gone,key) } } }
 slice.sort(gone[:])
 // Budget: gone ids first, then candidates by priority (entities without a row go first).
 slice.sort_by(candidates[:],proc(a,b: Net_Candidate) -> bool {
  if a.fresh!=b.fresh { return a.fresh }
  if a.accumulator!=b.accumulator { return a.accumulator>b.accumulator }
  return a.entry.key<b.entry.key
 })
 budget:=FRAME_BUDGET
 gone_count:=min(len(gone),budget/3)
 budget-=gone_count*3
 chosen:[dynamic]Frame_Entry; defer delete(chosen)
 unsent:=0
 for cand in candidates {
  size:=frame_entry_estimate(cand.entry,base)
  if size<=budget { append(&chosen,cand.entry); budget-=size } else { unsent+=1 }
 }
 c.stats.ticks+=1; if unsent>0 { c.stats.saturated_ticks+=1 }
 c.stats.entries_sent+=len(chosen)+len(forced); c.stats.forced_sent+=len(forced); c.stats.gone_sent+=gone_count
 entries:[dynamic]Frame_Entry; defer delete(entries)
 append(&entries,..chosen[:]); append(&entries,..forced[:])
 slice.sort_by(entries[:],proc(a,b: Frame_Entry) -> bool { return a.key<b.key })
 parts:[dynamic][]u8; defer delete(parts)
 frame_encode(w.scene.epoch,ns.tick,has_base,base_tick,c.last_blast_seq,base,entries[:],gone[:gone_count],&parts)
 total:=0
 for part in parts { total+=len(part); nc.server_send_unreliable(&ns.srv,index,part); delete(part) }
 // The table the client will hold for this frame: base - gone + entries, bit for bit.
 table:=table_clone(base)
 for key in gone[:gone_count] { delete_key(&table,key) }
 for e in entries { table[e.key]=e.state }
 slot:=ns.tick%NET_SENT_RING
 if c.ring_valid[slot] { delete(c.ring[slot]) }
 c.ring[slot]=table; c.ring_tick[slot]=ns.tick; c.ring_valid[slot]=true
 for e in entries {
  if since,ok:=c.pending[e.key]; ok {
   late:=ns.tick-since
   c.stats.staleness_max=max(c.stats.staleness_max,late); net_record_bounded_sample(&c.stats.staleness_samples,c.stats.staleness_count,u16(min(late,65535)))
   delete_key(&c.pending,e.key)
  } else { net_record_bounded_sample(&c.stats.staleness_samples,c.stats.staleness_count,u16(0)) }
  c.stats.staleness_count+=1
  c.last_sent[e.key]=e.state
  if e.key in c.priority { c.priority[e.key]=0 }
 }
 // Forget bookkeeping for entities that no longer exist.
 stale:[dynamic]u64; defer delete(stale)
 for key in c.last_sent { if key not_in ns.current { append(&stale,key) } }
 for key in stale { delete_key(&c.last_sent,key); delete_key(&c.pending,key); delete_key(&c.priority,key) }
 c.stats.parts_sent+=len(parts)
 net_record_bounded_sample(&c.stats.frame_bytes,u64(c.stats.ticks-1),i32(total)); net_record_bounded_sample(&c.stats.frame_parts,u64(c.stats.ticks-1),i32(len(parts)))
 net_server_record_timing(&c.stats.build_ms,u64(c.stats.ticks-1),f64(time.tick_diff(started,time.tick_now()))/f64(time.Millisecond))
}

net_server_reset_frames :: proc(ns: ^Net_Server) {
 for &c in ns.clients { net_client_state_clear(&c) }
 ns.frame_epoch=ns.game.world.scene.epoch
}

net_server_tick :: proc(ns: ^Net_Server,now: f64) {
 if ns.async_rebuild {net_rebuild_poll(ns)}
 started:=time.tick_now()
 w:=&ns.game.world
 events:=nc.server_take_events(&ns.srv); defer nc.server_events_free(&events)
 for ev in events {
  switch ev.kind {
  case .Connected:
   if ns.real_logging { fmt.printf("CONNECT client=%d\n",ev.client) }
   ns.real_reject_at[ev.client]=0
   if !ns.real_gate { net_server_join(ns,ev.client) }
  case .Disconnected:
   if ns.real_logging { fmt.printf("DISCONNECT client=%d reason=%v\n",ev.client,ev.reason) }
   net_app_server_disconnect(ns,ev.client,now)
   ns.real_reject_at[ev.client]=0
   net_server_leave(ns,ev.client)
  case .Message:
   if ns.real_gate && !ns.clients[ev.client].active {
    if ev.channel==nc.CHANNEL_RELIABLE && len(ev.data)>0 && ev.data[0]==NET_APP_HELLO {
     net_app_server_hello(ns,ev.client,ev.data,now)
    }
    continue // no input, hash or host command before authorization
   }
   if ns.real_gate && net_scheduled_server_message(ns,ev.client,ev.channel,ev.data) { continue }
   if !ns.real_gate && ev.channel==nc.CHANNEL_UNRELIABLE && len(ev.data)>0 && ev.data[0]==NET_MSG_INPUT {
    if in_,ok:=input_decode(ev.data); ok { net_server_input(ns,ev.client,in_) }
   } else if ns.record_hashes && ev.channel==nc.CHANNEL_RELIABLE && len(ev.data)>0 && ev.data[0]==NET_REAL_HASH_REPORT {
    r:nc.Reader;nc.reader_init(&r,ev.data)
    _=nc.read_u8(&r)
    epoch:=nc.read_u32(&r);revision:=nc.read_u64(&r);hash:=nc.read_u64(&r)
    if !r.ok || r.pos!=len(ev.data) { continue }
    ns.real_hash_checks+=1
    result:="unrecorded"
    if expected,found:=ns.hashes[net_hash_key(epoch,revision)]; found {
     if expected!=hash { ns.real_hash_mismatch+=1;result="mismatch" } else {
      result="match"
      if epoch==w.scene.epoch {round_ready(&ns.rounds,ev.client,ns.clients[ev.client].incarnation,true)}
     }
    } else { ns.real_hash_unrecorded+=1 }
    if ns.real_logging { fmt.printf("HASH REPORT client=%d connection=%d epoch=%d revision=%d hash=%d tick=%d result=%s\n",ev.client,ns.real_hash_generation[ev.client],epoch,revision,hash,ns.tick,result) }
   }
  }
 }
 round_server_prepare(ns)
 // Apply inputs: blasts in player order and sequence order, then the world tick.
 commands:Tick_Commands
 for i in 0..<nc.MAX_CLIENTS {
  c:=&ns.clients[i]
  if !c.active || !w.players[i].active { continue }
  if c.has_input { w.players[i].blast_radius=c.radius }
  if ns.real_gate {
   if c.schedule.identity.epoch==w.scene.epoch {
    step:=input_schedule_consume(&c.schedule,ns.tick+1)
    commands.players[i].move=move_dequantize(step.command.move);commands.players[i].jump=step.command.jump_edge!=0
    if commands.players[i].jump { c.stats.jumps_applied+=1 }
   }
  } else { commands.players[i].move=c.move;commands.players[i].jump=c.jump_pending }
  c.jump_pending=false
  slice.sort_by(c.blast_queue[:],proc(a,b: Net_Blast) -> bool { return seq16_newer(b.seq,a.seq) })
  for b in c.blast_queue { net_server_blast(ns,i,b) }
  clear(&c.blast_queue)
  for len(c.blast_ticks)>0 && ns.tick+1-c.blast_ticks[0]>=NET_BLAST_RATE_TICKS { ordered_remove(&c.blast_ticks,0) }
 }
 world_started:=time.tick_now()
 post:Tick_Events
 if ns.rounds.mode==.Sandbox || ns.rounds.state==.Playing {post=world_tick(w,commands,1.0/60.0)}
 round_server_finish(ns,post)
 net_server_record_timing(&ns.world_ms,ns.tick,f64(time.tick_diff(world_started,time.tick_now()))/f64(time.Millisecond))
 ns.tick+=1
 round_server_broadcast(ns)
 // Structure and events, reliable, to every client.
 out:=repl_server_update(&ns.repl,&w.scene,ns.tick); defer repl_output_destroy(&out)
 epoch_changed:=w.scene.epoch!=ns.frame_epoch
 if epoch_changed { net_server_reset_frames(ns) }
 if out.kind!=.None {
  net_record_hash(ns)
  for i in 0..<nc.MAX_CLIENTS { if ns.clients[i].active { net_send_reliable_parts(ns,i,&out) } }
 }
 if ns.real_gate {
  for i in 0..<nc.MAX_CLIENTS {
   if !ns.clients[i].active { continue }
   if epoch_changed || post.player_respawned[i] { net_scheduled_server_offer(ns,i) }
   net_scheduled_server_owner(ns,i)
  }
 }
 for list in ([2][dynamic]Explosion_Event{ns.pre_events.explosions,post.explosions}) {
  for e in list {
   event_id:=e.event_id
   if event_id==0 { ns.next_event_id+=1;event_id=ns.next_event_id }
   wr:nc.Writer; nc.writer_init(&wr,24)
   event_encode_explosion(&wr,ns.tick,e.position,e.radius,event_id)
   for i in 0..<nc.MAX_CLIENTS { if ns.clients[i].active { nc.server_send_reliable(&ns.srv,i,wr.data[:]) } }
   nc.writer_destroy(&wr); ns.explosions_emitted+=1
  }
 }
 delete(post.explosions); clear(&ns.pre_events.explosions); ns.pre_events.blast_rejected={}
 // Pose frames, unreliable, one per client.
 net_collect(ns)
 for i in 0..<nc.MAX_CLIENTS { if ns.clients[i].active { net_build_frame(ns,i) } }
 // Delay a rejected peer's removal long enough to deliver its reliable reason.
 if ns.real_gate {
  for i in 0..<nc.MAX_CLIENTS {
   if ns.real_reject_at[i]>0 && now>=ns.real_reject_at[i] {
    ns.real_reject_at[i]=0
    nc.server_kick(&ns.srv,i)
   }
  }
 }
 nc.server_update(&ns.srv,now)
 net_server_record_timing(&ns.tick_ms,ns.tick-1,f64(time.tick_diff(started,time.tick_now()))/f64(time.Millisecond))
}

// Diagnostics must not grow for the entire lifetime of a dedicated server.
// Keep the latest 65,536 complete samples in a bounded ring, independently of
// physics/scheduling. The exported report records the cursor and total count.
NET_SERVER_TIMING_CAPACITY :: 65536
net_server_record_timing :: proc(samples:^[dynamic]f64,tick:u64,milliseconds:f64) {net_record_bounded_sample(samples,tick,milliseconds)}
net_record_bounded_sample :: proc(samples:^[dynamic]$T,index:u64,value:T) {
 if len(samples^)<NET_SERVER_TIMING_CAPACITY {append(samples,value)}
 else {samples^[index%NET_SERVER_TIMING_CAPACITY]=value}
}
