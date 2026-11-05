package main

import nc "netcode"
import "core:math"
import "core:slice"

// Step 2b wire formats: pose frames (unreliable, server -> client), inputs (unreliable,
// client -> server) and reliable events. The netcode quantizers stay as they are; the
// pose grid below is the game-side quantizer chosen by the resolution measurement.

POSE_POS_STEP :: f64(1.0/256)
POSE_ANGLE_STEPS :: 4096
FRAME_PART_MAX :: 1150
FRAME_BUDGET :: 2*FRAME_PART_MAX
FRAME_HEADER_RESERVE :: 24
NET_SENT_RING :: 64
NET_CLIENT_RING :: 128
NET_MAX_PARTS :: 32
NET_MSG_FRAME :: u8(0xA1)
NET_MSG_INPUT :: u8(0xA2)
NET_MSG_EVENT :: u8(0xB6)
NET_EVENT_EXPLOSION :: u8(1)
NET_EVENT_BLAST_REJECTED :: u8(2)
NET_MAX_BLASTS :: 8
NET_BLAST_RATE_TICKS :: 60 // 4 accepted blasts per second per player
NET_BLAST_RATE_COUNT :: 4
NET_YARD_CEILING :: f32(12)

Ent_Kind :: enum u8 { Piece, Rubber, Player, Bomb }
ent_key :: proc(kind: Ent_Kind,id: u64) -> u64 { return (u64(kind)<<62)|id }
key_kind :: proc(key: u64) -> Ent_Kind { return Ent_Kind(key>>62) }
key_id :: proc(key: u64) -> u64 { return key&((u64(1)<<62)-1) }

// Quantized pose of one entity. landed and fuse are only meaningful for bombs.
Pose_State :: struct { x,y: i32, a: u16, landed: bool, fuse: u8 }
Pose_Table :: map[u64]Pose_State

pose_q_pos :: proc(v: f32) -> i32 {
 f:=f64(v); if f!=f { return 0 }
 s:=math.round(f/POSE_POS_STEP)
 if s>=f64(max(i32)) { return max(i32) }
 if s<=f64(min(i32)) { return min(i32) }
 return i32(s)
}
pose_dq_pos :: proc(q: i32) -> f32 { return f32(f64(q)*POSE_POS_STEP) }
pose_q_angle :: proc(radians: f32) -> u16 {
 f:=f64(radians); if f!=f || math.is_inf(f) { return 0 }
 a:=math.mod(f,2*math.PI); if a<0 { a+=2*math.PI }
 return u16(i64(math.round(a/(2*math.PI)*f64(POSE_ANGLE_STEPS)))%i64(POSE_ANGLE_STEPS))
}
pose_dq_angle :: proc(q: u16) -> f32 { return f32(f64(q)*2*math.PI/f64(POSE_ANGLE_STEPS)) }
pose_q_fuse :: proc(fuse: f32) -> u8 {
 f:=f64(fuse); if f!=f { return 0 }
 return u8(clamp(math.round(f/f64(BOMB_FUSE)*255),0,255))
}
pose_dq_fuse :: proc(q: u8) -> f32 { return f32(f64(q)/255*f64(BOMB_FUSE)) }
pose_state_make :: proc(x,y,angle: f32) -> Pose_State { return {x=pose_q_pos(x),y=pose_q_pos(y),a=pose_q_angle(angle)} }
// Signed shortest difference on the angle ring.
angle_delta :: proc(current,base: u16) -> i64 {
 n:=i64(POSE_ANGLE_STEPS); half:=n/2
 return ((i64(current)-i64(base)+half)%n+n)%n-half
}
angle_apply :: proc(base: u16,delta: i64) -> u16 {
 n:=i64(POSE_ANGLE_STEPS)
 return u16(((i64(base)%n+delta%n)%n+n)%n)
}
// Shortest signed arc between two angles in radians.
radians_delta :: proc(to,from: f32) -> f32 {
 d:=math.mod(f64(to)-f64(from),2*math.PI)
 if d>math.PI { d-=2*math.PI } else if d<-math.PI { d+=2*math.PI }
 return f32(d)
}

table_clone :: proc(t: ^Pose_Table) -> Pose_Table {
 n:=8; if t!=nil { n=max(len(t^),8) }
 out:=make(Pose_Table,n)
 if t!=nil { for key,state in t^ { out[key]=state } }
 return out
}
tables_equal :: proc(a,b: ^Pose_Table) -> bool {
 if len(a^)!=len(b^) { return false }
 for key,state in a^ { other,ok:=b^[key]; if !ok || other!=state { return false } }
 return true
}

// ---------------------------------------------------------------- frame codec
Frame_Entry :: struct { key: u64, state: Pose_State }
Frame_Part :: struct {
 epoch: u32, tick: u64, has_base: bool, base_tick: u64,
 index,count: int, blast_seq: u16,
 gone: [dynamic]u64, entries: [dynamic]Frame_Entry,
}
frame_part_destroy :: proc(p: ^Frame_Part) { delete(p.gone); delete(p.entries); p^={} }

frame_write_header :: proc(w: ^nc.Writer,epoch: u32,tick: u64,has_base: bool,base_tick: u64,index,count: int,blast_seq: u16) {
 nc.write_u8(w,NET_MSG_FRAME); nc.write_varint(w,u64(epoch)); nc.write_varint(w,tick)
 if has_base { nc.write_varint(w,base_tick+1) } else { nc.write_varint(w,0) }
 nc.write_varint(w,u64(index)); nc.write_varint(w,u64(count)); nc.write_u16(w,blast_seq)
}
frame_read_header :: proc(r: ^nc.Reader,p: ^Frame_Part) -> bool {
 if nc.read_u8(r)!=NET_MSG_FRAME { return false }
 epoch:=nc.read_varint(r); p.tick=nc.read_varint(r)
 base:=nc.read_varint(r)
 p.index=int(min(nc.read_varint(r),u64(1<<20))); p.count=int(min(nc.read_varint(r),u64(1<<20)))
 p.blast_seq=nc.read_u16(r)
 if !r.ok || epoch>u64(max(u32)) || p.count<1 || p.count>NET_MAX_PARTS || p.index>=p.count { return false }
 p.epoch=u32(epoch)
 if base>0 { p.has_base=true; p.base_tick=base-1 }
 return true
}

// Appends one entry; `previous` tracks the id-delta chain within a part.
frame_write_entry :: proc(w: ^nc.Writer,e: Frame_Entry,base: ^Pose_Table,previous: ^u64,have_previous: ^bool) {
 kind:=key_kind(e.key); id:=key_id(e.key)
 delta:=id
 if have_previous^ && key_kind(previous^)==kind { delta=id-key_id(previous^) }
 nc.write_varint(w,delta)
 row:Pose_State; has:=false
 if base!=nil { row,has=base^[e.key] }
 flags:=u8(kind)
 if !has { flags|=4 }
 if e.state.landed { flags|=8 }
 nc.write_u8(w,flags)
 if has {
  nc.write_zigzag(w,i64(e.state.x)-i64(row.x)); nc.write_zigzag(w,i64(e.state.y)-i64(row.y)); nc.write_zigzag(w,angle_delta(e.state.a,row.a))
 } else {
  nc.write_zigzag(w,i64(e.state.x)); nc.write_zigzag(w,i64(e.state.y)); nc.write_zigzag(w,i64(e.state.a))
 }
 if kind==.Bomb { nc.write_u8(w,e.state.fuse) }
 previous^=e.key; have_previous^=true
}
// Exact encoded size of an entry in the current chain, without advancing it.
frame_entry_size :: proc(scratch: ^nc.Writer,e: Frame_Entry,base: ^Pose_Table,previous: u64,have_previous: bool) -> int {
 nc.writer_reset(scratch)
 p,h:=previous,have_previous
 frame_write_entry(scratch,e,base,&p,&h)
 return len(scratch.data)
}
// Estimated size for budgeting before the final chain is known (id delta assumed 2 bytes).
frame_entry_estimate :: proc(e: Frame_Entry,base: ^Pose_Table) -> int {
 row:Pose_State; has:=false
 if base!=nil { row,has=base^[e.key] }
 size:=2+1
 if has { size+=nc.varint_size(nc.zigzag_encode(i64(e.state.x)-i64(row.x)))+nc.varint_size(nc.zigzag_encode(i64(e.state.y)-i64(row.y)))+nc.varint_size(nc.zigzag_encode(angle_delta(e.state.a,row.a))) }
 else { size+=nc.varint_size(nc.zigzag_encode(i64(e.state.x)))+nc.varint_size(nc.zigzag_encode(i64(e.state.y)))+nc.varint_size(nc.zigzag_encode(i64(e.state.a))) }
 if key_kind(e.key)==.Bomb { size+=1 }
 return size
}

Frame_Plan :: struct { gone_lo,gone_hi,entry_lo,entry_hi: int }
// Splits the sorted gone keys and sorted entries into independent parts of at most
// FRAME_PART_MAX bytes and appends each part (caller-owned) to `parts`.
frame_encode :: proc(epoch: u32,tick: u64,has_base: bool,base_tick: u64,blast_seq: u16,base: ^Pose_Table,entries: []Frame_Entry,gone: []u64,parts: ^[dynamic][]u8) {
 plans:[dynamic]Frame_Plan; defer delete(plans)
 scratch:nc.Writer; nc.writer_init(&scratch,64); defer nc.writer_destroy(&scratch)
 gi,ei:=0,0
 for {
  plan:=Frame_Plan{gone_lo=gi,entry_lo=ei}
  size:=FRAME_HEADER_RESERVE+4
  previous_gone:=u64(0)
  for gi<len(gone) {
   need:=nc.varint_size(gone[gi]-previous_gone)
   if size+need>FRAME_PART_MAX { break }
   size+=need; previous_gone=gone[gi]; gi+=1
  }
  plan.gone_hi=gi
  if gi==len(gone) {
   previous,have_previous:=u64(0),false
   for ei<len(entries) {
    need:=frame_entry_size(&scratch,entries[ei],base,previous,have_previous)
    if size+need>FRAME_PART_MAX { break }
    size+=need; previous=entries[ei].key; have_previous=true; ei+=1
   }
  }
  plan.entry_hi=ei
  append(&plans,plan)
  if (gi>=len(gone) && ei>=len(entries)) || (plan.gone_hi==plan.gone_lo && plan.entry_hi==plan.entry_lo) { break }
 }
 for plan,index in plans {
  w:nc.Writer; nc.writer_init(&w,FRAME_PART_MAX)
  frame_write_header(&w,epoch,tick,has_base,base_tick,index,len(plans),blast_seq)
  nc.write_varint(&w,u64(plan.gone_hi-plan.gone_lo))
  previous_gone:=u64(0)
  for key in gone[plan.gone_lo:plan.gone_hi] { nc.write_varint(&w,key-previous_gone); previous_gone=key }
  nc.write_varint(&w,u64(plan.entry_hi-plan.entry_lo))
  previous,have_previous:=u64(0),false
  for e in entries[plan.entry_lo:plan.entry_hi] { frame_write_entry(&w,e,base,&previous,&have_previous) }
  assert(len(w.data)<=FRAME_PART_MAX,"frame part exceeds its limit")
  append(parts,w.data[:])
 }
}
// Decodes the body (after the header). Delta entries need the base table row.
frame_read_body :: proc(r: ^nc.Reader,p: ^Frame_Part,base: ^Pose_Table) -> bool {
 gone_count:=nc.read_varint(r)
 if !r.ok || gone_count>u64(nc.reader_remaining(r)) { return false }
 key:=u64(0)
 for _ in 0..<int(gone_count) { key+=nc.read_varint(r); append(&p.gone,key) }
 entry_count:=nc.read_varint(r)
 if !r.ok || entry_count>u64(nc.reader_remaining(r)) { return false }
 previous:=u64(0); have_previous:=false
 for _ in 0..<int(entry_count) {
  delta:=nc.read_varint(r); flags:=nc.read_u8(r)
  if !r.ok || flags&0xF0!=0 { return false }
  kind:=Ent_Kind(flags&3)
  id:=delta
  if have_previous && key_kind(previous)==kind { id=key_id(previous)+delta }
  if id>=(u64(1)<<62) { return false }
  k:=ent_key(kind,id)
  e:=Frame_Entry{key=k}
  e.state.landed=flags&8!=0
  if flags&4==0 {
   if base==nil { return false }
   row,has:=base^[k]
   if !has { return false }
   dx,dy,da:=nc.read_zigzag(r),nc.read_zigzag(r),nc.read_zigzag(r)
   x,y:=i64(row.x)+dx,i64(row.y)+dy
   if !r.ok || x<i64(min(i32)) || x>i64(max(i32)) || y<i64(min(i32)) || y>i64(max(i32)) { return false }
   e.state.x=i32(x); e.state.y=i32(y); e.state.a=angle_apply(row.a,da)
  } else {
   x,y,a:=nc.read_zigzag(r),nc.read_zigzag(r),nc.read_zigzag(r)
   if !r.ok || x<i64(min(i32)) || x>i64(max(i32)) || y<i64(min(i32)) || y>i64(max(i32)) || a<0 || a>=i64(POSE_ANGLE_STEPS) { return false }
   e.state.x=i32(x); e.state.y=i32(y); e.state.a=u16(a)
  }
  if kind==.Bomb { e.state.fuse=nc.read_u8(r) }
  if !r.ok { return false }
  append(&p.entries,e); previous=k; have_previous=true
 }
 return r.ok && nc.reader_remaining(r)==0
}
// Whole-part decode for tests and fuzzing.
frame_decode_part :: proc(data: []u8,base: ^Pose_Table) -> (p: Frame_Part,ok: bool) {
 r:nc.Reader; nc.reader_init(&r,data)
 if !frame_read_header(&r,&p) { frame_part_destroy(&p); return {},false }
 if !frame_read_body(&r,&p,base) { frame_part_destroy(&p); return {},false }
 return p,true
}

// ---------------------------------------------------------------- input codec
Net_Blast :: struct { seq: u16, x,y: i32, radius_q: u8 }
Net_Input :: struct {
 epoch: u32, seq: u16,
 has_ack: bool, ack: u64,
 move: i8, radius_q: u8, jump_counter: u16,
 blast_count: int, blasts: [NET_MAX_BLASTS]Net_Blast,
}
radius_quantize :: proc(r: f32) -> u8 {
 f:=f64(r); if f!=f { return 0 }
 return u8(clamp(math.round((clamp(f,0.5,6)-0.5)/5.5*255),0,255))
}
radius_dequantize :: proc(q: u8) -> f32 { return f32(0.5+f64(q)*5.5/255) }
move_quantize :: proc(m: f32) -> i8 { return i8(clamp(math.round(f64(m)*127),-127,127)) }
move_dequantize :: proc(q: i8) -> f32 { return f32(q)/127 }

input_encode :: proc(in_: Net_Input,w: ^nc.Writer) {
 nc.write_u8(w,NET_MSG_INPUT); nc.write_varint(w,u64(in_.epoch)); nc.write_u16(w,in_.seq)
 if in_.has_ack { nc.write_varint(w,in_.ack+1) } else { nc.write_varint(w,0) }
 nc.write_u8(w,u8(in_.move)); nc.write_u8(w,in_.radius_q); nc.write_u16(w,in_.jump_counter)
 nc.write_u8(w,u8(in_.blast_count))
 for i in 0..<in_.blast_count {
  b:=in_.blasts[i]
  nc.write_u16(w,b.seq); nc.write_zigzag(w,i64(b.x)); nc.write_zigzag(w,i64(b.y)); nc.write_u8(w,b.radius_q)
 }
}
input_decode :: proc(data: []u8) -> (in_: Net_Input,ok: bool) {
 r:nc.Reader; nc.reader_init(&r,data)
 if nc.read_u8(&r)!=NET_MSG_INPUT { return {},false }
 epoch:=nc.read_varint(&r); in_.seq=nc.read_u16(&r)
 ack:=nc.read_varint(&r)
 in_.move=i8(nc.read_u8(&r)); in_.radius_q=nc.read_u8(&r); in_.jump_counter=nc.read_u16(&r)
 count:=int(nc.read_u8(&r))
 if !r.ok || epoch>u64(max(u32)) || count>NET_MAX_BLASTS { return {},false }
 in_.epoch=u32(epoch)
 if ack>0 { in_.has_ack=true; in_.ack=ack-1 }
 in_.blast_count=count
 for i in 0..<count {
  seq:=nc.read_u16(&r); x,y:=nc.read_zigzag(&r),nc.read_zigzag(&r); rq:=nc.read_u8(&r)
  if !r.ok || x<i64(min(i32)) || x>i64(max(i32)) || y<i64(min(i32)) || y>i64(max(i32)) { return {},false }
  in_.blasts[i]={seq=seq,x=i32(x),y=i32(y),radius_q=rq}
 }
 if !r.ok || nc.reader_remaining(&r)!=0 { return {},false }
 return in_,true
}
// a is newer than b on the u16 ring.
seq16_newer :: proc(a,b: u16) -> bool { d:=a-b; return d!=0 && d<32768 }

// ---------------------------------------------------------------- reliable events
event_encode_explosion :: proc(w: ^nc.Writer,tick: u64,position: Vec2,radius: f32) {
 nc.write_u8(w,NET_MSG_EVENT); nc.write_u8(w,NET_EVENT_EXPLOSION); nc.write_varint(w,tick)
 nc.write_f32(w,position.x); nc.write_f32(w,position.y); nc.write_f32(w,radius)
}
event_encode_rejected :: proc(w: ^nc.Writer,tick: u64,seq: u16) {
 nc.write_u8(w,NET_MSG_EVENT); nc.write_u8(w,NET_EVENT_BLAST_REJECTED); nc.write_varint(w,tick); nc.write_u16(w,seq)
}
Net_Event :: struct { kind: u8, tick: u64, position: Vec2, radius: f32, seq: u16 }
event_decode :: proc(data: []u8) -> (e: Net_Event,ok: bool) {
 r:nc.Reader; nc.reader_init(&r,data)
 if nc.read_u8(&r)!=NET_MSG_EVENT { return {},false }
 e.kind=nc.read_u8(&r); e.tick=nc.read_varint(&r)
 switch e.kind {
 case NET_EVENT_EXPLOSION: e.position={nc.read_f32(&r),nc.read_f32(&r)}; e.radius=nc.read_f32(&r)
 case NET_EVENT_BLAST_REJECTED: e.seq=nc.read_u16(&r)
 case: return {},false
 }
 if !r.ok || nc.reader_remaining(&r)!=0 { return {},false }
 return e,true
}

sorted_keys :: proc(m: ^map[u64]$V,out: ^[dynamic]u64) {
 clear(out)
 for key in m^ { append(out,key) }
 slice.sort(out[:])
}
