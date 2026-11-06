package main

import nc "netcode"
import rl "vendor:raylib"
import "core:math"
import "core:slice"

// In-process client for step 2b: a netcode endpoint, a physics-free replica, the pose
// tables of complete frames, an adaptive render clock and the interpolated poses to draw.

NET_STEP_DT :: f64(1.0/60.0)
NET_CLOCK_GAIN :: 0.02 // fraction of a tick of rate change per tick of clock error
NET_CLOCK_MAX_ADJUST :: 0.05
NET_CLOCK_SNAP_TICKS :: 30.0 // 0.5 s
NET_DELAY_MIN :: 2
NET_DELAY_MAX :: 12
NET_JITTER_WINDOW :: 2.0 // seconds
NET_LOSS_TICKS :: 8 // a frame still missing once a frame this much newer completed is lost
NET_PENDING_FRAMES :: 16
NET_HIDDEN :: f32(10000)

Net_Queued :: struct { tick: u64, event: bool, data: []u8 }
Frame_Asm :: struct {
 tick: u64, has_base: bool, base_tick: u64, count: int,
 have: [NET_MAX_PARTS]bool, got: int,
 gone: [dynamic]u64, entries: [dynamic]Frame_Entry,
}
Complete_Frame :: struct { valid: bool, tick: u64, table: Pose_Table }
Arrival :: struct { time: f64, tick: u64 }
Net_Drawn :: struct { x,y,angle: f32, landed: bool, fuse: f32 }
Applied_Struct :: struct { epoch: u32, revision: u64, hash: u64 }

Net_Client_Stats :: struct {
 frames_complete,frame_parts,frame_parts_duplicate,frame_parts_old,frames_wrong_epoch,frames_undecodable,frames_malformed: int,
 structure_applied,structure_errors,events_played: int,
 late_messages,late_structure,late_events: int, late_max_ticks: f64,
 snaps,clock_ticks,clock_saturated: int, adjust_sum,adjust_abs_max: f64,
 resets: int,
 jumps_pressed,blasts_issued,blasts_dropped,blast_rejections_seen: int,
 delay_history: [dynamic]u8,
 frames_lost: int,
 input_bytes,input_count,input_max: int,
}
Net_Client :: struct {
 nc_client: nc.Client,
 real_gate: bool,real_hello_sent: bool,real_hello_ok: bool,
 real_is_host: bool,real_host_left: bool,
 real_has_settings: bool,real_settings: Sandbox_Settings,
 real_protocol: u32,real_build: string,real_host_token: string,
 real_reason: string,
 rep: Replica,
 epoch: u32, has_epoch: bool,
 queue: [dynamic]Net_Queued,
 pending: [dynamic]^Frame_Asm,
 ring: [NET_CLIENT_RING]Complete_Frame,
 newest_complete: u64, has_complete: bool,
 newest_seen: u64, has_seen: bool, confirmed_blast: u16,
 clock: f64, has_clock: bool, delay: int,
 arrivals: [dynamic]Arrival,
 missing: [dynamic]u64,
 loss_times: [dynamic]f64,
 // inputs
 bot: Bot, bot_enabled,idle: bool,
 human_move: f32, human_jump_pending: bool,
 input_seq,jump_counter,blast_seq: u16,
 radius_q: u8,
 blasts: [dynamic]Net_Blast,
 last_ack_sent: u64, has_ack_sent: bool, acks_to_check: [dynamic]u64,
 // presentation
 drawn: map[u64]Net_Drawn,
 anchored: map[u64]bool, anchored_valid: bool,
 caches: Render_Cache_State,
 bursts: [dynamic]Bomb_Burst,
 verify: bool, applied: [dynamic]Applied_Struct,
 stats: Net_Client_Stats,
 dbg_lower,dbg_upper: u64, // the frame ticks that bracketed the last draw
}

net_client_init :: proc(c: ^Net_Client,salt: u32,now: f64,bot_seed: u64 = 0,bot_enabled: bool = false) {
 c^={}
 nc.client_init(&c.nc_client)
 nc.client_connect(&c.nc_client,salt,now)
 c.real_protocol=GAME_PROTOCOL_VERSION
 c.real_build=GAME_BUILD_ID
 replica_init(&c.rep)
 c.delay=NET_DELAY_MIN
 c.drawn=make(map[u64]Net_Drawn); c.anchored=make(map[u64]bool)
 c.radius_q=radius_quantize(DEFAULT_SANDBOX_SETTINGS.blast_radius)
 c.real_settings=DEFAULT_SANDBOX_SETTINGS
 c.bot_enabled=bot_enabled
 if bot_enabled { bot_init(&c.bot,bot_seed,true) }
}
net_frame_asm_free :: proc(a: ^Frame_Asm) { delete(a.gone); delete(a.entries); free(a) }
net_client_clear_state :: proc(c: ^Net_Client) {
 for q in c.queue { delete(q.data) }; clear(&c.queue)
 for a in c.pending { net_frame_asm_free(a) }; clear(&c.pending)
 for i in 0..<NET_CLIENT_RING { if c.ring[i].valid { delete(c.ring[i].table) }; c.ring[i]={} }
 c.has_complete=false; c.newest_complete=0; c.has_seen=false; c.confirmed_blast=0
 c.has_clock=false; c.clock=0; c.delay=NET_DELAY_MIN
 clear(&c.arrivals); clear(&c.missing); clear(&c.loss_times)
 clear(&c.blasts); clear(&c.drawn); clear(&c.acks_to_check); c.has_ack_sent=false
 clear(&c.anchored); c.anchored_valid=false
 clear(&c.bursts)
}
net_client_destroy :: proc(c: ^Net_Client) {
 net_client_clear_state(c)
 nc.client_destroy(&c.nc_client)
 delete(c.real_reason)
 replica_destroy(&c.rep)
 release_render_caches(&c.caches)
 delete(c.queue); delete(c.pending); delete(c.arrivals); delete(c.missing); delete(c.loss_times)
 delete(c.blasts); delete(c.acks_to_check); delete(c.drawn); delete(c.anchored); delete(c.bursts); delete(c.applied)
 delete(c.stats.delay_history)
 c^={}
}

// ---------------------------------------------------------------- receiving
net_client_record_applied :: proc(c: ^Net_Client) {
 c.stats.structure_applied+=1
 c.anchored_valid=false
 if c.rep.rebuilt { release_render_caches(&c.caches) }
 if c.verify {
  data:=canonical_encode(&c.rep.scene); defer delete(data)
  append(&c.applied,Applied_Struct{c.rep.scene.epoch,c.rep.scene.structure_revision,repl_hash(data)})
 }
}
net_client_note_late :: proc(c: ^Net_Client,tick: u64,event: bool) {
 if !c.has_clock || c.clock<=f64(tick) { return }
 late:=c.clock-f64(tick)
 c.stats.late_messages+=1; c.stats.late_max_ticks=max(c.stats.late_max_ticks,late)
 if event { c.stats.late_events+=1 } else { c.stats.late_structure+=1 }
}
// A new epoch's Baseline resets the replica, the tables and the clock.
net_client_reset :: proc(c: ^Net_Client) {
 c.stats.resets+=1
 net_client_clear_state(c)
 release_render_caches(&c.caches)
}
net_client_on_structure :: proc(c: ^Net_Client,message: []u8) {
 kind,tick,epoch,ok:=repl_peek(message)
 if !ok { delete(message); c.stats.structure_errors+=1; return }
 if kind==.Baseline && (!c.has_epoch || epoch!=u64(c.epoch)) {
  net_client_reset(c)
  if err:=replica_apply_message(&c.rep,message); err!="" { c.stats.structure_errors+=1 }
  else { c.epoch=u32(epoch); c.has_epoch=true; net_client_record_applied(c) }
  delete(message); return
 }
 if !c.has_epoch { delete(message); return }
 net_client_note_late(c,tick,false)
 append(&c.queue,Net_Queued{tick=tick,data=message})
}
net_client_on_reliable :: proc(c: ^Net_Client,data: []u8) {
 if len(data)==0 { return }
 switch data[0] {
 case REPL_PART_MARK:
  message,complete,err:=replica_collect(&c.rep,data)
  if err!="" { c.stats.structure_errors+=1; return }
  if complete { net_client_on_structure(c,message) }
 case NET_MSG_EVENT:
  e,ok:=event_decode(data)
  if !ok { return }
  net_client_note_late(c,e.tick,true)
  append(&c.queue,Net_Queued{tick=e.tick,event=true,data=slice.clone(data)})
 }
}
net_client_complete_frame :: proc(c: ^Net_Client,a: ^Frame_Asm,now: f64) {
 base:^Pose_Table
 if a.has_base {
  slot:=a.base_tick%NET_CLIENT_RING
  if !c.ring[slot].valid || c.ring[slot].tick!=a.base_tick { c.stats.frames_undecodable+=1; return }
  base=&c.ring[slot].table
 }
 table:=table_clone(base)
 for key in a.gone { delete_key(&table,key) }
 for e in a.entries { table[e.key]=e.state }
 slot:=a.tick%NET_CLIENT_RING
 if c.ring[slot].valid { delete(c.ring[slot].table) }
 c.ring[slot]=Complete_Frame{valid=true,tick=a.tick,table=table}
 c.stats.frames_complete+=1
 append(&c.arrivals,Arrival{now,a.tick})
 if c.has_complete {
  if a.tick>c.newest_complete {
   if a.tick-c.newest_complete<600 { for m in c.newest_complete+1..<a.tick { append(&c.missing,m) } }
   c.newest_complete=a.tick
  } else if index,found:=slice.linear_search(c.missing[:],a.tick); found { unordered_remove(&c.missing,index) }
 } else { c.has_complete=true; c.newest_complete=a.tick }
}
net_client_on_frame :: proc(c: ^Net_Client,data: []u8,now: f64) {
 r:nc.Reader; nc.reader_init(&r,data)
 part:Frame_Part; defer frame_part_destroy(&part)
 if !frame_read_header(&r,&part) { c.stats.frames_malformed+=1; return }
 if !c.has_epoch || part.epoch!=c.epoch { c.stats.frames_wrong_epoch+=1; return }
 c.stats.frame_parts+=1
 slot:=part.tick%NET_CLIENT_RING
 if c.ring[slot].valid && c.ring[slot].tick==part.tick { c.stats.frame_parts_duplicate+=1; return }
 if c.has_complete && part.tick+NET_CLIENT_RING<=c.newest_complete { c.stats.frame_parts_old+=1; return }
 var:^Frame_Asm
 for a in c.pending { if a.tick==part.tick { var=a } }
 if var==nil {
  if len(c.pending)>=NET_PENDING_FRAMES { net_frame_asm_free(c.pending[0]); ordered_remove(&c.pending,0) }
  var=new(Frame_Asm); var.tick=part.tick; var.count=part.count; var.has_base=part.has_base; var.base_tick=part.base_tick
  append(&c.pending,var)
 }
 if var.count!=part.count || var.has_base!=part.has_base || var.base_tick!=part.base_tick { c.stats.frames_malformed+=1; return }
 if var.have[part.index] { c.stats.frame_parts_duplicate+=1; return }
 base:^Pose_Table
 if part.has_base {
  bslot:=part.base_tick%NET_CLIENT_RING
  if !c.ring[bslot].valid || c.ring[bslot].tick!=part.base_tick { c.stats.frames_undecodable+=1; return }
  base=&c.ring[bslot].table
 }
 if !frame_read_body(&r,&part,base) { c.stats.frames_malformed+=1; return }
 var.have[part.index]=true; var.got+=1
 append(&var.gone,..part.gone[:]); append(&var.entries,..part.entries[:])
 if !c.has_seen || part.tick>=c.newest_seen {
  c.has_seen=true; c.newest_seen=part.tick; c.confirmed_blast=part.blast_seq
  for len(c.blasts)>0 && !seq16_newer(c.blasts[0].seq,part.blast_seq) { ordered_remove(&c.blasts,0) }
 }
 if var.got==var.count {
  net_client_complete_frame(c,var,now)
  for a,i in c.pending { if a==var { ordered_remove(&c.pending,i); break } }
  net_frame_asm_free(var)
 }
}

// ---------------------------------------------------------------- clock and delay
net_client_update_delay :: proc(c: ^Net_Client,now: f64) {
 for len(c.arrivals)>0 && now-c.arrivals[0].time>NET_JITTER_WINDOW { ordered_remove(&c.arrivals,0) }
 for len(c.loss_times)>0 && now-c.loss_times[0]>NET_JITTER_WINDOW { ordered_remove(&c.loss_times,0) }
 // Frames still missing once a much newer frame completed are lost.
 i:=0
 for i<len(c.missing) {
  if c.has_complete && c.newest_complete>=c.missing[i]+NET_LOSS_TICKS {
   append(&c.loss_times,now); c.stats.frames_lost+=1; unordered_remove(&c.missing,i)
  } else { i+=1 }
 }
 if len(c.arrivals)==0 { c.delay=clamp(1+(len(c.loss_times)>0 ? 2 : 0),NET_DELAY_MIN,NET_DELAY_MAX); return }
 offsets:[256]f64
 count:=min(len(c.arrivals),len(offsets))
 lowest:=f64(1e30)
 for k in 0..<count {
  a:=c.arrivals[len(c.arrivals)-count+k]
  offsets[k]=a.time-f64(a.tick)*NET_STEP_DT
  lowest=min(lowest,offsets[k])
 }
 for k in 0..<count { offsets[k]-=lowest }
 slice.sort(offsets[:count])
 p95:=offsets[min(count-1,int(math.ceil(0.95*f64(count)))-1)]
 jitter_ticks:=int(math.ceil(p95/NET_STEP_DT-0.001))
 delay:=1+jitter_ticks
 if len(c.loss_times)>0 { delay+=2 }
 c.delay=clamp(delay,NET_DELAY_MIN,NET_DELAY_MAX)
}
net_client_update_clock :: proc(c: ^Net_Client) {
 if !c.has_complete { return }
 target:=f64(c.newest_complete)-f64(c.delay)
 if !c.has_clock { c.clock=target; c.has_clock=true; c.stats.snaps+=1; return }
 err:=target-c.clock
 if math.abs(err)>NET_CLOCK_SNAP_TICKS { c.clock=target; c.stats.snaps+=1; return }
 adjust:=clamp(err*NET_CLOCK_GAIN,-NET_CLOCK_MAX_ADJUST,NET_CLOCK_MAX_ADJUST)
 c.clock+=1+adjust
 c.stats.clock_ticks+=1; c.stats.adjust_sum+=adjust; c.stats.adjust_abs_max=max(c.stats.adjust_abs_max,math.abs(adjust))
 if math.abs(adjust)>=NET_CLOCK_MAX_ADJUST-1e-12 { c.stats.clock_saturated+=1 }
}
// Applies queued structure messages and events whose tick the clock has reached, in order.
net_client_apply_queue :: proc(c: ^Net_Client) {
 for len(c.queue)>0 {
  q:=c.queue[0]
  if !c.has_clock || f64(q.tick)>c.clock { break }
  ordered_remove(&c.queue,0)
  if q.event {
   if e,ok:=event_decode(q.data); ok {
    switch e.kind {
    case NET_EVENT_EXPLOSION: append(&c.bursts,Bomb_Burst{position=e.position,radius=e.radius}); c.stats.events_played+=1
    case NET_EVENT_BLAST_REJECTED: c.stats.blast_rejections_seen+=1
    }
   }
  } else {
   if err:=replica_apply_message(&c.rep,q.data); err!="" { c.stats.structure_errors+=1 } else { net_client_record_applied(c) }
  }
  delete(q.data)
 }
}

// ---------------------------------------------------------------- draw poses
net_lerp :: proc(a,b: f32,t: f32) -> f32 { return a+(b-a)*t }
net_drawn_from :: proc(s0,s1: Pose_State,alpha: f32) -> Net_Drawn {
 a0,a1:=pose_dq_angle(s0.a),pose_dq_angle(s1.a)
 landed:=s0.landed; if alpha>=0.5 { landed=s1.landed }
 return {x=net_lerp(pose_dq_pos(s0.x),pose_dq_pos(s1.x),alpha),y=net_lerp(pose_dq_pos(s0.y),pose_dq_pos(s1.y),alpha),angle=a0+radians_delta(a1,a0)*alpha,landed=landed,fuse=net_lerp(pose_dq_fuse(s0.fuse),pose_dq_fuse(s1.fuse),alpha)}
}
net_drawn_single :: proc(s: Pose_State) -> Net_Drawn {
 return {x=pose_dq_pos(s.x),y=pose_dq_pos(s.y),angle=pose_dq_angle(s.a),landed=s.landed,fuse=pose_dq_fuse(s.fuse)}
}
net_in_structure :: proc(c: ^Net_Client,key: u64) -> bool {
 switch key_kind(key) {
 case .Piece: row,ok:=c.rep.scene.piece_rows[key_id(key)]; return ok && c.rep.scene.pieces[row].live
 case .Rubber: row,ok:=c.rep.scene.sub_rows[key_id(key)]; return ok && c.rep.scene.subdivisions[row].live
 case .Player,.Bomb: return true
 }
 return false
}
// Interpolates between the tables of the complete frames that bracket the render tick.
net_client_compute_drawn :: proc(c: ^Net_Client) {
 clear(&c.drawn)
 if !c.has_clock || !c.has_complete || !c.has_epoch { return }
 floor_tick:=u64(max(math.floor(c.clock),0))
 lower,upper:^Complete_Frame
 start:=min(floor_tick,c.newest_complete)
 for step in 0..<u64(NET_CLIENT_RING) {
  if step>start { break }
  f:=&c.ring[(start-step)%NET_CLIENT_RING]
  if f.valid && f.tick==start-step { lower=f; break }
 }
 for t:=floor_tick+1; t<=c.newest_complete && t<=floor_tick+NET_CLIENT_RING; t+=1 {
  f:=&c.ring[t%NET_CLIENT_RING]
  if f.valid && f.tick==t { upper=f; break }
 }
 c.dbg_lower=0; c.dbg_upper=0
 if lower!=nil { c.dbg_lower=lower.tick }; if upper!=nil { c.dbg_upper=upper.tick }
 if lower==nil && upper==nil { return }
 if lower==nil {
  for key,s in upper.table { if net_in_structure(c,key) { c.drawn[key]=net_drawn_single(s) } }
  return
 }
 if upper==nil || upper.tick<=lower.tick {
  for key,s in lower.table { if net_in_structure(c,key) { c.drawn[key]=net_drawn_single(s) } }
  return
 }
 alpha:=f32((c.clock-f64(lower.tick))/f64(upper.tick-lower.tick))
 alpha=clamp(alpha,0,1)
 for key,s0 in lower.table {
  if !net_in_structure(c,key) { continue }
  if s1,ok:=upper.table[key]; ok { c.drawn[key]=net_drawn_from(s0,s1,alpha) }
  else { c.drawn[key]=net_drawn_single(s0) } // gone at the upper frame: drawn until the clock reaches it
 }
 // Rows only in the upper table are new there and show from that frame on.
}

net_client_ensure_anchored :: proc(c: ^Net_Client) {
 if c.anchored_valid { return }
 clear(&c.anchored)
 s:=&c.rep.scene
 for p in s.pieces { if p.live && piece_anchored(s,p.id,s.anchor_y) { c.anchored[p.id]=true } }
 c.anchored_valid=true
}
// Piece frames map to rigid cell poses; rubber cells and anchored pieces keep their own rule.
// Dynamic pieces and cells without a drawn row are moved far off screen.
net_client_draw_inputs :: proc(c: ^Net_Client) -> (poses: map[u64]Pose,frames: map[u64]Pose) {
 net_client_ensure_anchored(c)
 s:=&c.rep.scene
 poses=make(map[u64]Pose); frames=make(map[u64]Pose)
 for p in s.pieces {
  if !p.live || s.materials[p.material].flexibility>0 || len(p.subdivisions)==0 { continue }
  frame:Pose
  if d,ok:=c.drawn[ent_key(.Piece,p.id)]; ok { frame=reference_to_frame(Pose{position={d.x,d.y},angle=d.angle},p.ref_rest) }
  else if !c.anchored[p.id] { frame=Pose{position={NET_HIDDEN,NET_HIDDEN}} }
  frames[p.id]=frame
  for id in p.subdivisions {
   row,ok:=s.sub_rows[id]; if !ok || !s.subdivisions[row].live { continue }
   sub:=s.subdivisions[row]
   poses[id]=Pose{position=rigid_render_point(frame,sub.rest_center),angle=frame.angle}
  }
 }
 for sub in s.subdivisions {
  if !sub.live || s.materials[sub.material].flexibility<=0 { continue }
  if d,ok:=c.drawn[ent_key(.Rubber,sub.id)]; ok { poses[sub.id]=Pose{position={d.x,d.y},angle=d.angle} }
  else if c.anchored[sub.owner] { poses[sub.id]=Pose{position=sub.rest_center} }
  else { poses[sub.id]=Pose{position={NET_HIDDEN,NET_HIDDEN}} }
 }
 return
}
// Draws the replica through the existing draw path.
net_client_draw :: proc(c: ^Net_Client,view: View,outline_width:f32=2) {
 poses,frames:=net_client_draw_inputs(c); defer { delete(poses); delete(frames) }
 yard_draw_backdrop(view)
 draw_scene(&c.rep.scene,&c.caches,view,poses,0,true,false,false,true,outline_width,frames)
 yard_draw_spawn(view)
 for burst in c.bursts { draw_burst(view,burst) }
 keys:[dynamic]u64; defer delete(keys)
 for key in c.drawn { if kind:=key_kind(key); kind==.Bomb || kind==.Player { append(&keys,key) } }
 slice.sort(keys[:])
 for key in keys { if key_kind(key)==.Bomb { d:=c.drawn[key]; draw_bomb_at(view,{d.x,d.y},d.landed,d.fuse) } }
 for key in keys { if key_kind(key)==.Player { d:=c.drawn[key]; draw_player_at(view,{d.x,d.y},int(key_id(key))) } }
}

// ---------------------------------------------------------------- one client step
net_client_make_input :: proc(c: ^Net_Client) {
 move:f32
 index:=c.nc_client.client_index
 if c.bot_enabled && !c.idle && c.has_epoch && c.has_complete {
  position:Vec2; have:=false
  if d,ok:=c.drawn[ent_key(.Player,u64(index))]; ok { position={d.x,d.y}; have=true }
  else if f:=&c.ring[c.newest_complete%NET_CLIENT_RING]; f.valid { if s,ok:=f.table[ent_key(.Player,u64(index))]; ok { position={pose_dq_pos(s.x),pose_dq_pos(s.y)}; have=true } }
  if have {
   commands:Player_Commands
   bot_step_scene(&c.bot,&c.rep.scene,position,f32(NET_STEP_DT),&commands)
   move=commands.move
   if commands.jump { c.jump_counter+=1; c.stats.jumps_pressed+=1 }
   for point in commands.blasts {
    c.blast_seq+=1
    if len(c.blasts)>=NET_MAX_BLASTS { ordered_remove(&c.blasts,0); c.stats.blasts_dropped+=1 }
    append(&c.blasts,Net_Blast{seq=c.blast_seq,x=nc.quantize_pos(point.x),y=nc.quantize_pos(point.y),radius_q=c.radius_q})
    c.stats.blasts_issued+=1
   }
   delete(commands.blasts)
  }
 } else if !c.bot_enabled {
  move=c.human_move
  if c.human_jump_pending {
   c.jump_counter+=1
   c.stats.jumps_pressed+=1
   c.human_jump_pending=false
  }
 }
 c.input_seq+=1
 in_:=Net_Input{seq=c.input_seq,move=move_quantize(move),radius_q=c.radius_q,jump_counter=c.jump_counter}
 if c.has_epoch { in_.epoch=c.epoch }
 if c.has_complete {
  in_.has_ack=true; in_.ack=c.newest_complete
  if !c.has_ack_sent || c.last_ack_sent!=c.newest_complete { c.last_ack_sent=c.newest_complete; c.has_ack_sent=true; append(&c.acks_to_check,c.newest_complete) }
 }
 in_.blast_count=len(c.blasts)
 for b,i in c.blasts { in_.blasts[i]=b }
 w:nc.Writer; nc.writer_init(&w,64); defer nc.writer_destroy(&w)
 input_encode(in_,&w)
 c.stats.input_bytes+=len(w.data); c.stats.input_count+=1; c.stats.input_max=max(c.stats.input_max,len(w.data))
 nc.client_send_unreliable(&c.nc_client,w.data[:])
}
// Process everything delivered since the last step, then produce this tick's input.
net_client_step :: proc(c: ^Net_Client,now: f64) {
 if c.nc_client.state==.Connected {
  net_app_client_send_hello(c)
  msgs:=nc.client_take_messages(&c.nc_client); defer nc.messages_free(&msgs)
  for m in msgs {
   if m.channel==nc.CHANNEL_RELIABLE {
    if !net_app_client_control(c,m.data) { net_client_on_reliable(c,m.data) }
   }
   else if len(m.data)>0 && m.data[0]==NET_MSG_FRAME { net_client_on_frame(c,m.data,now) }
  }
  net_client_update_delay(c,now)
  net_client_update_clock(c)
  net_client_apply_queue(c)
  for &burst in c.bursts { burst.age+=f32(NET_STEP_DT) }
  count:=0
  for burst in c.bursts { if burst.age<BOMB_BURST_TIME { c.bursts[count]=burst; count+=1 } }
  resize(&c.bursts,count)
  net_client_compute_drawn(c)
  append(&c.stats.delay_history,u8(c.delay))
  if !c.real_gate || c.real_hello_ok { net_client_make_input(c) }
 }
 nc.client_update(&c.nc_client,now)
}
_ :: rl
