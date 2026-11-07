#+feature dynamic-literals
package shared

import nc "../netcode"
import math "core:math"
import slice "core:slice"
import "core:strings"

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
NET_MAX_QUEUED_MESSAGES :: 128
NET_MAX_QUEUED_BYTES :: 32*1024*1024
// Takes ownership on both success and failure. Overflow is an explicit session error.
net_client_queue_owned :: proc(c:^Net_Client,q:Net_Queued) -> bool {
 bytes:=len(q.data)
 for existing in c.queue { bytes+=len(existing.data) }
 if len(c.queue)>=NET_MAX_QUEUED_MESSAGES || bytes>NET_MAX_QUEUED_BYTES {
  delete(q.data);c.stats.structure_errors+=1
  if c.real_reason=="" { c.real_reason=strings.clone("presentation queue overflow; reconnect required") }
  return false
 }
 append(&c.queue,q);return true
}

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
 input_payload_hash: u64, // Diagnostic digest of the complete fixed-command byte stream.
 request_payload_hash:u64,
 request_payload_count:u64,
}

Net_Client :: struct {
 input_link: Input_Link,
 input_probe_at: f64,
 request_counter,host_request_id: u64,
 request_pending: [1024]Pending_Request,
 last_request_result: Request_Result,
 completed_requests:[1024]Completed_Request,
 highest_completed_request:u64,
 last_request_created_tick,last_request_deadline_tick:u64,
 collision_history: Collision_History,
 prediction:^Prediction_Controller,
 prediction_enabled:bool,
 nc_client: nc.Client,
 real_gate: bool,real_hello_sent: bool,real_hello_ok: bool,
 real_is_host: bool,real_host_left: bool,
 real_has_settings: bool,real_settings: Sandbox_Settings,
 real_protocol: u32,real_build: string,real_host_token: string,
 has_expected_manifest:bool,expected_manifest:[32]u8,
 real_reason: string,
 control_serial: u64, control_kind: u8, control_ok: bool, control_reason: string,
 rep: Replica, // Presented topology, advanced only at the presentation clock.
 received: Replica, // Validated received truth; never used to render early topology.
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
 idle: bool,
 human_move: f32, human_jump_pending: bool,
 input_seq,jump_counter,blast_seq: u16,
 radius_q: u8,
 blasts: [dynamic]Net_Blast,
 blast_ages:[NET_MAX_BLASTS]f64,
 last_ack_sent: u64, has_ack_sent: bool, acks_to_check: [dynamic]u64,
 // presentation
 drawn: map[u64]Net_Drawn,
 anchored: map[u64]bool, anchored_valid: bool,
 presentation_reset_serial: u64, // Incremented when frontend caches must be invalidated.
 events: [dynamic]Net_Event, // Due immutable events, consumed by the caller before the next fixed step.
 verify: bool, applied: [dynamic]Applied_Struct,
 stats: Net_Client_Stats,
 dbg_lower,dbg_upper: u64, // the frame ticks that bracketed the last draw
}

net_client_init :: proc(c: ^Net_Client,salt: u32,now: f64) {
 c^={}
 c.prediction_enabled=true
 nc.client_init(&c.nc_client)
 nc.client_connect(&c.nc_client,salt,now)
 c.real_protocol=GAME_PROTOCOL_VERSION
 c.real_build=GAME_BUILD_ID
 replica_init(&c.rep)
 replica_init(&c.received)
 c.delay=NET_DELAY_MIN
 c.drawn=make(map[u64]Net_Drawn); c.anchored=make(map[u64]bool)
 c.radius_q=radius_quantize(DEFAULT_SANDBOX_SETTINGS.blast_radius)
 c.real_settings=DEFAULT_SANDBOX_SETTINGS
}

net_frame_asm_free :: proc(a: ^Frame_Asm) { delete(a.gone); delete(a.entries); free(a) }

net_client_clear_intent :: proc(c:^Net_Client) {
 input_link_clear_intent(&c.input_link)
 c.human_move=0;c.human_jump_pending=false;clear(&c.blasts)
 c.blast_ages={}
}

net_client_clear_state :: proc(c: ^Net_Client) {
 for q in c.queue { delete(q.data) }; clear(&c.queue)
 for a in c.pending { net_frame_asm_free(a) }; clear(&c.pending)
 for i in 0..<NET_CLIENT_RING { if c.ring[i].valid { delete(c.ring[i].table) }; c.ring[i]={} }
 c.has_complete=false; c.newest_complete=0; c.has_seen=false; c.confirmed_blast=0
 c.has_clock=false; c.clock=0; c.delay=NET_DELAY_MIN
 clear(&c.arrivals); clear(&c.missing); clear(&c.loss_times)
 clear(&c.blasts); clear(&c.drawn); clear(&c.acks_to_check); c.has_ack_sent=false
 c.blast_ages={}
 clear(&c.anchored); c.anchored_valid=false
 clear(&c.events)
}

net_client_destroy :: proc(c: ^Net_Client) {
 prediction_controller_destroy(c.prediction);c.prediction=nil
 collision_history_destroy(&c.collision_history)
 net_client_clear_state(c)
 nc.client_destroy(&c.nc_client)
 delete(c.real_reason)
 delete(c.control_reason)
 replica_destroy(&c.rep)
 replica_destroy(&c.received)
 c.presentation_reset_serial+=1
 delete(c.queue); delete(c.pending); delete(c.arrivals); delete(c.missing); delete(c.loss_times)
 delete(c.blasts); delete(c.acks_to_check); delete(c.drawn); delete(c.anchored); delete(c.events); delete(c.applied)
 delete(c.stats.delay_history)
 c^={}
}

net_client_record_applied :: proc(c: ^Net_Client) {
 c.stats.structure_applied+=1
 c.anchored_valid=false
 if c.rep.rebuilt { c.presentation_reset_serial+=1 }
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

net_client_reset :: proc(c: ^Net_Client) {
 prediction_controller_reset(c)
 c.stats.resets+=1
 net_client_clear_state(c)
 input_link_clear_intent(&c.input_link)
 c.presentation_reset_serial+=1
}

net_client_on_structure :: proc(c: ^Net_Client,message: []u8) {
 kind,tick,epoch,ok:=repl_peek(message)
 if !ok { delete(message); c.stats.structure_errors+=1; return }
 if err:=replica_apply_message(&c.received,message); err!="" {
  delete(message);c.stats.structure_errors+=1
  if c.real_reason=="" { c.real_reason=strings.clone(err) }
  return
 }
 if c.real_gate { _=collision_history_record_topology(&c.collision_history,&c.received.scene,c.received.tick) }
 if kind==.Baseline && (!c.has_epoch || epoch!=u64(c.epoch)) {
  net_client_reset(c)
  if err:=replica_apply_message(&c.rep,message); err!="" { c.stats.structure_errors+=1 }
  else { c.epoch=u32(epoch); c.has_epoch=true; net_client_record_applied(c) }
  delete(message); return
 }
 if !c.has_epoch { delete(message); return }
 net_client_note_late(c,tick,false)
 net_client_queue_owned(c,Net_Queued{tick=tick,data=message})
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
  net_client_queue_owned(c,Net_Queued{tick=e.tick,event=true,data=slice.clone(data)})
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
 if c.real_gate { _=collision_history_record_frame(&c.collision_history,c.epoch,a.tick,&table) }
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
  if !c.real_gate { for len(c.blasts)>0 && !seq16_newer(c.blasts[0].seq,part.blast_seq) { ordered_remove(&c.blasts,0) } }
 }
 if var.got==var.count {
  net_client_complete_frame(c,var,now)
  for a,i in c.pending { if a==var { ordered_remove(&c.pending,i); break } }
  net_frame_asm_free(var)
 }
}

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
 if c.newest_complete<c.rep.tick { c.has_clock=false;return }
 floor:=f64(c.rep.tick);ceiling:=max(floor,f64(c.newest_complete))
 target:=clamp(f64(c.newest_complete)-f64(c.delay),floor,ceiling)
 if !c.has_clock { c.clock=clamp(max(c.clock,target),floor,ceiling); c.has_clock=true; c.stats.snaps+=1; return }
 err:=target-c.clock
 if math.abs(err)>NET_CLOCK_SNAP_TICKS { c.clock=clamp(max(c.clock,target),floor,ceiling); c.stats.snaps+=1; return }
 adjust:=clamp(err*NET_CLOCK_GAIN,-NET_CLOCK_MAX_ADJUST,NET_CLOCK_MAX_ADJUST)
 c.clock=clamp(c.clock+1+adjust,floor,ceiling)
 c.stats.clock_ticks+=1; c.stats.adjust_sum+=adjust; c.stats.adjust_abs_max=max(c.stats.adjust_abs_max,math.abs(adjust))
 if math.abs(adjust)>=NET_CLOCK_MAX_ADJUST-1e-12 { c.stats.clock_saturated+=1 }
}

net_client_apply_queue :: proc(c: ^Net_Client) {
 slice.stable_sort_by(c.queue[:],proc(a,b:Net_Queued)->bool {
  if a.tick!=b.tick { return a.tick<b.tick }
  return !a.event && b.event
 })
 for len(c.queue)>0 {
  q:=c.queue[0]
  if !c.has_clock || f64(q.tick)>c.clock { break }
  ordered_remove(&c.queue,0)
  if q.event {
   if e,ok:=event_decode(q.data); ok {
    switch e.kind {
    case NET_EVENT_EXPLOSION: append(&c.events,e); c.stats.events_played+=1
    case NET_EVENT_BLAST_REJECTED: c.stats.blast_rejections_seen+=1
    }
   }
  } else {
   if err:=replica_apply_message(&c.rep,q.data); err!="" { c.stats.structure_errors+=1 } else { net_client_record_applied(c) }
  }
  delete(q.data)
 }
}

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

net_client_compute_drawn :: proc(c:^Net_Client) {
 net_client_compute_interpolated(c);net_prediction_apply(c)
}
net_client_compute_interpolated :: proc(c: ^Net_Client) {
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

net_client_make_input :: proc(c: ^Net_Client) {
 if c.real_gate { net_scheduled_client_input(c);return }
 move:f32
 index:=c.nc_client.client_index
 move=c.human_move
 if c.human_jump_pending {
  c.jump_counter+=1
  c.stats.jumps_pressed+=1
  c.human_jump_pending=false
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
 if c.stats.input_count==0 { c.stats.input_payload_hash=14695981039346656037 }
 for byte in w.data { c.stats.input_payload_hash=(c.stats.input_payload_hash~u64(byte))*1099511628211 }
 c.stats.input_bytes+=len(w.data); c.stats.input_count+=1; c.stats.input_max=max(c.stats.input_max,len(w.data))
 nc.client_send_unreliable(&c.nc_client,w.data[:])
}

net_client_step :: proc(c: ^Net_Client,now: f64,input_source: proc(c: ^Net_Client,data: rawptr)=nil,source_data: rawptr=nil) {
 clear(&c.events)
 if c.nc_client.state==.Connected {
  net_app_client_send_hello(c)
  msgs:=nc.client_take_messages(&c.nc_client); defer nc.messages_free(&msgs)
  for m in msgs {
   if c.real_gate && net_scheduled_client_message(c,m.channel,m.data,now) { continue }
   if m.channel==nc.CHANNEL_RELIABLE {
    if !net_app_client_control(c,m.data) { net_client_on_reliable(c,m.data) }
   }
   else if len(m.data)>0 && m.data[0]==NET_MSG_FRAME { net_client_on_frame(c,m.data,now) }
  }
  net_client_update_delay(c,now)
  net_client_update_clock(c)
  net_client_apply_queue(c)
  net_client_compute_drawn(c)
  append(&c.stats.delay_history,u8(c.delay))
  if !c.real_gate || c.real_hello_ok {
   if c.real_gate { net_scheduled_client_update(c,now) }
   if input_source!=nil { input_source(c,source_data) }
   net_client_make_input(c)
   net_prediction_update(c,now);net_prediction_apply(c)
  }
 }
 nc.client_update(&c.nc_client,now)
}
