package ffi

import "base:runtime"
import "core:math"
import "core:strings"
import w "core:sys/windows"
import nc "../netcode"
import core "../shared"

// Initial live polling bridge. Prediction/provenance and the full M3 gates remain pending.
OK :: u32(0)
INVALID_HANDLE :: u32(1)
BAD_ARGUMENT :: u32(2)
BUSY :: u32(3)
WRONG_THREAD :: u32(4)
CAPACITY :: u32(5)
NOT_CONNECTED :: u32(6)
IO_ERROR :: u32(7)
OVERFLOW :: u32(8)
BUILD_TAG :: u64(#config(BOM_CORE_BUILD_TAG,0))
Held :: struct { timestamp: f64, move: f32 }
Action :: struct { timestamp: f64, x,y: f32 }
Client_Slot :: struct {
 active,live,acquired,has_time,has_geometry: bool,
 generation: u32,
 ctx: runtime.Context,
 client: core.Net_Client,
 socket: nc.Socket,
 endpoint: nc.Address,
 token: string,
 connection_generation,sample_sequence,event_sequence,ack_event_id: u64,
 cached_epoch,input_epoch: u32, cached_revision,canonical_hash,stall_count: u64,
 input_error: u32,
 last_now,next_tick,transport_now,accumulator: f64,
 held_move: f32,
 held: [dynamic]Held,
 jumps: [dynamic]f64,
 actions: [dynamic]Action,
 cells: [dynamic]BomCell,
 vertices: [dynamic]BomVertex,
 poses: [dynamic]BomPose,
 events: [dynamic]BomEvent,
}
slots: [16]Client_Slot
owner_thread: u32

get_slot :: proc "contextless" (handle: u64) -> (^Client_Slot,u32) {
 if owner_thread!=u32(w.GetCurrentThreadId()) { return nil,WRONG_THREAD }
 index:=u32(handle&0xffffffff)
 if index==0 || index>u32(len(slots)) { return nil,INVALID_HANDLE }
 s:=&slots[index-1]
 if !s.active || s.generation!=u32(handle>>32) { return nil,INVALID_HANDLE }
 return s,OK
}
close_client :: proc(s:^Client_Slot) {
 if s.live {
  nc.client_disconnect(&s.client.nc_client)
  outgoing:=nc.client_take_outgoing(&s.client.nc_client)
  for p in outgoing { _=nc.socket_send(&s.socket,s.endpoint,p.data) }
  nc.outgoing_free(&outgoing)
  core.net_client_destroy(&s.client);nc.socket_close(&s.socket)
 }
 delete(s.token);s.token="";s.live=false;s.has_time=false;s.has_geometry=false
 clear(&s.held);clear(&s.jumps);clear(&s.actions);clear(&s.events)
 clear(&s.cells);clear(&s.vertices);clear(&s.poses)
 s.held_move=0;s.accumulator=0;s.transport_now=0;s.canonical_hash=0
}
@(export)
bom_abi_version :: proc "c" () -> u32 { return 1 }
@(export)
bom_build_tag :: proc "c" () -> u64 { return BUILD_TAG }
@(export)
bom_client_create :: proc "c" (info:^BomCreateInfo,handle:^u64) -> u32 {
 context=runtime.default_context()
 if info==nil || handle==nil { return BAD_ARGUMENT }
 handle^=0
 if info.struct_size<u32(size_of(BomCreateInfo)) || info.version!=1 || info.flags!=0 || info.reserved!=0 { return BAD_ARGUMENT }
 thread:=u32(w.GetCurrentThreadId())
 if owner_thread!=0 && owner_thread!=thread { return WRONG_THREAD }
 owner_thread=thread
 for &s,i in slots {
  if s.active { continue }
  generation:=s.generation+1;if generation==0 { generation=1 }
  s=Client_Slot{active=true,generation=generation,ctx=context}
  handle^=(u64(generation)<<32)|u64(i+1)
  return OK
 }
 return CAPACITY
}
@(export)
bom_client_destroy :: proc "c" (handle:u64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY }
 close_client(s)
 delete(s.held);delete(s.jumps);delete(s.actions);delete(s.cells);delete(s.vertices);delete(s.poses);delete(s.events)
 generation:=s.generation;s^=Client_Slot{generation=generation}
 return OK
}
@(export)
bom_client_connect :: proc "c" (handle:u64,info:^BomConnectInfo) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY }
 if info==nil || info.struct_size<u32(size_of(BomConnectInfo)) || info.version!=1 || info.port==0 || info.port>65535 || info.token_length>128 || (info.token_length>0 && info.token==nil) || info.reserved!=0 { return BAD_ARGUMENT }
 close_client(s)
 if !nc.socket_open(&s.socket) { return IO_ERROR }
 ip:=info.ipv4
 s.endpoint=nc.address_make({u8(ip>>24),u8(ip>>16),u8(ip>>8),u8(ip)},u16(info.port))
 if info.token_length>0 { s.token=strings.clone(string(info.token[:info.token_length])) }
 core.net_client_init(&s.client,nc.random_salt(),0)
 s.client.real_gate=true;s.client.real_host_token=s.token;s.client.verify=true
 s.connection_generation+=1;s.live=true
 return OK
}
@(export)
bom_client_disconnect :: proc "c" (handle:u64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };close_client(s);return OK
}
@(export)
bom_client_set_held_input :: proc "c" (handle:u64,timestamp:f64,move:f32) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };if !s.live { return NOT_CONNECTED }
 if math.is_nan(timestamp) || math.is_inf(timestamp) || !core.finite(move) { return BAD_ARGUMENT }
 if len(s.held)>=256 { return OVERFLOW }
 if len(s.held)>0 && timestamp<s.held[len(s.held)-1].timestamp { return BAD_ARGUMENT }
 append(&s.held,Held{timestamp,clamp(move,f32(-1),f32(1))});return OK
}
@(export)
bom_client_enqueue_jump :: proc "c" (handle:u64,timestamp:f64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };if !s.live { return NOT_CONNECTED }
 if math.is_nan(timestamp) || math.is_inf(timestamp) { return BAD_ARGUMENT }
 if len(s.jumps)>=64 { return OVERFLOW }
 if len(s.jumps)>0 && timestamp<s.jumps[len(s.jumps)-1] { return BAD_ARGUMENT }
 append(&s.jumps,timestamp);return OK
}
@(export)
bom_client_enqueue_action :: proc "c" (handle:u64,timestamp:f64,x,y:f32) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };if !s.live { return NOT_CONNECTED }
 if math.is_nan(timestamp) || math.is_inf(timestamp) || !core.finite(x) || !core.finite(y) { return BAD_ARGUMENT }
 if len(s.actions)>=64 { return OVERFLOW }
 if len(s.actions)>0 && timestamp<s.actions[len(s.actions)-1].timestamp { return BAD_ARGUMENT }
 append(&s.actions,Action{timestamp,x,y});return OK
}
flush :: proc(s:^Client_Slot) {
 outgoing:=nc.client_take_outgoing(&s.client.nc_client)
 for p in outgoing { _=nc.socket_send(&s.socket,s.endpoint,p.data) }
 nc.outgoing_free(&outgoing)
}
ffi_input_source :: proc(c:^core.Net_Client,data:rawptr) {
 s:=cast(^Client_Slot)data
 if c.epoch!=s.input_epoch {
  clear(&s.held);clear(&s.jumps);clear(&s.actions)
  s.held_move=0;c.human_jump_pending=false;s.input_epoch=c.epoch
 }
 for len(s.held)>0 && s.held[0].timestamp<=s.next_tick+1e-9 { s.held_move=s.held[0].move;ordered_remove(&s.held,0) }
 c.human_move=s.held_move
 if len(s.jumps)>0 && s.jumps[0]<=s.next_tick+1e-9 { c.human_jump_pending=true;ordered_remove(&s.jumps,0) }
 for len(s.actions)>0 && s.actions[0].timestamp<=s.next_tick+1e-9 {
  if len(c.blasts)>=core.NET_MAX_BLASTS { s.input_error=OVERFLOW;return }
  a:=s.actions[0];ordered_remove(&s.actions,0)
  if s.next_tick-a.timestamp>0.5 { continue }
  c.blast_seq+=1
  append(&c.blasts,core.Net_Blast{seq=c.blast_seq,x=nc.quantize_pos(a.x),y=nc.quantize_pos(a.y),radius_q=c.radius_q})
 }
}
@(export)
bom_client_update :: proc "c" (handle:u64,now:f64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };if !s.live { return NOT_CONNECTED }
 if math.is_nan(now) || math.is_inf(now) { return BAD_ARGUMENT }
 if !s.has_time { s.has_time=true;s.last_now=now;s.next_tick=now+core.NET_STEP_DT }
 dt:=now-s.last_now;s.last_now=now;s.transport_now+=max(f64(0),dt)
 if dt<0 || dt>0.25 || s.accumulator+dt>core.NET_STEP_DT*4+1e-8 {
  s.stall_count+=1
  clear(&s.held);clear(&s.jumps);clear(&s.actions);clear(&s.client.blasts)
  s.held_move=0;s.client.human_jump_pending=false;s.client.has_clock=false
  s.accumulator=0;s.next_tick=now+core.NET_STEP_DT
 } else { s.accumulator+=dt }
 buffer:[nc.MAX_PACKET+64]u8
 for _ in 0..<256 {
  packet,from,has:=nc.socket_receive(&s.socket,buffer[:]);if !has { break }
  if from==s.endpoint { nc.client_receive(&s.client.nc_client,packet,s.transport_now) }
 }
 for _ in 0..<4 {
  if s.accumulator+1e-9<core.NET_STEP_DT { break }
  epoch:=s.client.epoch
  core.net_client_step(&s.client,s.transport_now,ffi_input_source,s)
  if s.input_error!=OK { error:=s.input_error;s.input_error=OK;close_client(s);return error }
  if s.client.epoch!=epoch { clear(&s.events);s.has_geometry=false }
  for event in s.client.events {
   if len(s.events)>=256 { close_client(s);return OVERFLOW }
   s.event_sequence+=1;append(&s.events,BomEvent{id=s.event_sequence,tick=event.tick,kind=u32(event.kind),x=event.position.x,y=event.position.y,radius=event.radius})
  }
  for applied in s.client.applied {
   writer:nc.Writer;nc.writer_init(&writer,32)
   nc.write_u8(&writer,core.NET_REAL_HASH_REPORT);nc.write_u32(&writer,applied.epoch);nc.write_u64(&writer,applied.revision);nc.write_u64(&writer,applied.hash)
   _=nc.client_send_reliable(&s.client.nc_client,writer.data[:]);nc.writer_destroy(&writer)
   s.canonical_hash=applied.hash
  }
  clear(&s.client.applied)
  s.accumulator-=core.NET_STEP_DT;s.next_tick+=core.NET_STEP_DT
 }
 nc.client_update(&s.client.nc_client,s.transport_now);flush(s)
 return OK
}
@(export)
bom_client_acquire_sample :: proc "c" (handle:u64,sample:^BomSample) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY }
 if sample==nil || sample.struct_size<u32(size_of(BomSample)) || sample.version!=1 { return BAD_ARGUMENT }
 scene:=&s.client.rep.scene
 if !s.has_geometry || s.cached_epoch!=s.client.epoch || s.cached_revision!=scene.structure_revision {
  clear(&s.cells);clear(&s.vertices)
  for sub in scene.subdivisions {
   if !sub.live { continue }
   m:=scene.materials[sub.material];kind:=core.Ent_Kind.Piece;if m.flexibility>0 { kind=.Rubber }
   color:=u32(m.color[0])|(u32(m.color[1])<<8)|(u32(m.color[2])<<16)|0xff000000
   pivot:=sub.rest_center
   if kind==.Piece { if row,found:=scene.piece_rows[sub.owner];found { pivot=scene.pieces[row].ref_rest } }
   append(&s.cells,BomCell{id=sub.id,piece_id=sub.owner,material=u32(sub.material),pose_kind=u32(kind),rest_x=sub.rest_center.x,rest_y=sub.rest_center.y,pivot_x=pivot.x,pivot_y=pivot.y,vertex_start=u32(len(s.vertices)),vertex_count=u32(len(sub.outline.points)),color_rgba=color})
   for p in sub.outline.points { append(&s.vertices,BomVertex{p.x,p.y}) }
  }
  s.cached_epoch=s.client.epoch;s.cached_revision=scene.structure_revision;s.has_geometry=true
 }
 clear(&s.poses)
 for key,d in s.client.drawn { append(&s.poses,BomPose{id=core.key_id(key),kind=u32(core.key_kind(key)),flags=u32(d.landed),x=d.x,y=d.y,angle=d.angle,fuse=d.fuse}) }
 if s.client.rep.has_baseline {
  core.net_client_ensure_anchored(&s.client)
  for piece in scene.pieces {
   if !piece.live || !s.client.anchored[piece.id] || scene.materials[piece.material].flexibility>0 { continue }
   if _,exists:=s.client.drawn[core.ent_key(.Piece,piece.id)];!exists { append(&s.poses,BomPose{id=piece.id,kind=u32(core.Ent_Kind.Piece),x=piece.ref_rest.x,y=piece.ref_rest.y}) }
  }
  for sub in scene.subdivisions {
   if !sub.live || scene.materials[sub.material].flexibility<=0 || !s.client.anchored[sub.owner] { continue }
   if _,exists:=s.client.drawn[core.ent_key(.Rubber,sub.id)];!exists { append(&s.poses,BomPose{id=sub.id,kind=u32(core.Ent_Kind.Rubber),x=sub.rest_center.x,y=sub.rest_center.y}) }
  }
 }
 flags:=u32(0);if s.client.real_hello_ok { flags|=1 };if s.client.rep.has_baseline { flags|=2 }
 local_id:=u32(0xffffffff);if s.client.nc_client.client_index>=0 { local_id=u32(s.client.nc_client.client_index) }
 s.sample_sequence+=1;s.ack_event_id=0;if len(s.events)>0 { s.ack_event_id=s.events[len(s.events)-1].id }
 sample^=BomSample{struct_size=u32(size_of(BomSample)),version=1,connection_generation=s.connection_generation,epoch=s.client.epoch,connection_state=u32(s.client.nc_client.state),revision=scene.structure_revision,sample_sequence=s.sample_sequence,presentation_tick=s.client.clock,canonical_hash=s.canonical_hash,input_count=u64(s.client.stats.input_count),stall_count=s.stall_count,local_player_id=local_id,flags=flags,cell_count=u32(len(s.cells)),vertex_count=u32(len(s.vertices)),pose_count=u32(len(s.poses)),event_count=u32(len(s.events)),cells=raw_data(s.cells),vertices=raw_data(s.vertices),poses=raw_data(s.poses),events=raw_data(s.events),error_text=raw_data(s.client.real_reason),error_length=u32(len(s.client.real_reason))}
 s.acquired=true;return OK
}
@(export)
bom_client_release_sample :: proc "c" (handle,sequence:u64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status }
 if !s.acquired || sequence!=s.sample_sequence { return BAD_ARGUMENT }
 s.acquired=false;return OK
}
@(export)
bom_client_ack_sample :: proc "c" (handle,sequence:u64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };if sequence!=s.sample_sequence { return BAD_ARGUMENT }
 for len(s.events)>0 && s.events[0].id<=s.ack_event_id { ordered_remove(&s.events,0) }
 return OK
}
@(export)
bom_client_host_command :: proc "c" (handle:u64,op,mode:u32,radius:f32) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };if !s.live { return NOT_CONNECTED }
 if op>255 || mode>255 || !core.finite(radius) { return BAD_ARGUMENT }
 if !core.net_host_client_send_command(&s.client,u8(op),u8(mode),radius) { return BAD_ARGUMENT }
 return OK
}
