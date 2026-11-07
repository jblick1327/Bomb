package ffi

import "base:runtime"
import "core:math"
import "core:mem"
import "core:strings"
import "core:fmt"
import w "core:sys/windows"
import nc "../netcode"
import core "../shared"

// Live shared-native polling bridge. M5 scheduled input is being validated;
// prediction, provenance and round capabilities have separate milestone gates.
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
 allocations: mem.Tracking_Allocator,
 last_error: string,
 client: core.Net_Client,
 socket: nc.Socket,
 local_port:u16,last_salt:u32,
 endpoint: nc.Address,
 token: string,
 connection_generation,sample_sequence,event_sequence,ack_event_id: u64,
 input_generation: u64,
 prediction_disabled: bool,
 has_expected_manifest:bool,expected_manifest:[32]u8,
 has_held_timestamp:bool,
 last_held_timestamp:f64,
 cached_epoch,input_epoch,journal_epoch: u32, cached_revision,canonical_hash,stall_count: u64,
 presented_tick: f64,
 input_error: u32,
 last_now,next_tick,transport_now,fixed_transport_now,accumulator: f64,
 held_move: f32,
 held: [dynamic]Held,
 jumps: [dynamic]f64,
 actions: [dynamic]Action,
 cells: [dynamic]BomCell,
 bindings:[dynamic]BomCellBinding,
 sources:[dynamic]BomSourceBinding,
 vertices: [dynamic]BomVertex,
 poses: [dynamic]BomPose,
 events: [dynamic]BomEvent,
 command_id,command_counter,command_serial: u64,command_pending,command_ok: bool,
 topology_sequence,topology_accepted,topology_from,accepted_revision: u64,
 accepted_epoch: u32,
 last_connection_state: u32,
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
  s.last_connection_state=u32(s.client.nc_client.state)
  if s.client.real_reason!="" { delete(s.last_error);s.last_error=strings.clone(s.client.real_reason) }
  nc.client_disconnect(&s.client.nc_client)
  outgoing:=nc.client_take_outgoing(&s.client.nc_client)
  for p in outgoing { _=nc.socket_send(&s.socket,s.endpoint,p.data) }
  nc.outgoing_free(&outgoing)
  core.net_client_destroy(&s.client);nc.socket_close(&s.socket)
 }
 delete(s.token);s.token="";s.live=false;s.has_time=false;s.has_geometry=false
 clear(&s.held);clear(&s.jumps);clear(&s.actions);clear(&s.events)
 clear(&s.cells);clear(&s.vertices);clear(&s.poses)
 s.held_move=0;s.accumulator=0;s.transport_now=0;s.canonical_hash=0;s.presented_tick=0;s.journal_epoch=0;s.input_epoch=0
 s.fixed_transport_now=0;s.input_generation=0
 s.has_held_timestamp=false;s.last_held_timestamp=0
 s.command_pending=false;s.command_id=0;s.command_ok=false;s.command_serial=0
 s.topology_accepted=0;s.topology_from=0;s.accepted_revision=0;s.accepted_epoch=0
}
fail_client :: proc(s:^Client_Slot,code:u32,reason:string) -> u32 {
 delete(s.last_error);s.last_error=strings.clone(reason);close_client(s);return code
}
@(export)
bom_abi_version :: proc "c" () -> u32 { return 1 }
@(export)
bom_build_tag :: proc "c" () -> u64 { return BUILD_TAG }
@(export)
bom_build_info :: proc "c" (info:^BomBuildInfo) -> u32 {
 if info==nil || info.struct_size<u32(size_of(BomBuildInfo)) || info.version!=1 { return BAD_ARGUMENT }
 info^=BomBuildInfo{struct_size=u32(size_of(BomBuildInfo)),version=1,abi_major=BOM_ABI_MAJOR,abi_minor=BOM_ABI_MINOR,game_protocol=core.GAME_PROTOCOL_VERSION,canonical_version=u32(core.REPL_CANON_VERSION),source_build_tag=BUILD_TAG,game_build=raw_data(string(core.GAME_BUILD_ID)),game_build_length=u32(len(core.GAME_BUILD_ID)),compiler_version=raw_data(string(ODIN_VERSION)),compiler_version_length=u32(len(ODIN_VERSION)),compiler_hash=raw_data(string(ODIN_VERSION_HASH)),compiler_hash_length=u32(len(ODIN_VERSION_HASH))}
 return OK
}
// Pure shape metadata keeps cosmetic fallback feet/radii aligned with the
// authoritative constructors without implementing collision in Unity.
@(export)
bom_actor_shape_info :: proc "c" (info:^BomActorShapeInfo) -> u32 {
 if info==nil || info.struct_size<u32(size_of(BomActorShapeInfo)) || info.version!=1 { return BAD_ARGUMENT }
 info^=BomActorShapeInfo{struct_size=u32(size_of(BomActorShapeInfo)),version=1,player_radius=core.PLAYER_RADIUS,player_segment=core.PLAYER_SEGMENT,bomb_radius=core.BOMB_RADIUS}
 return OK
}
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
  if s.active || s.generation==0xffffffff { continue }
  generation:=s.generation+1
  s=Client_Slot{active=true,generation=generation,ctx=context}
  mem.tracking_allocator_init(&s.allocations,context.allocator,context.allocator)
  s.ctx.allocator=mem.tracking_allocator(&s.allocations)
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
 delete(s.bindings);delete(s.sources)
 delete(s.last_error)
 remaining:=s.allocations.current_memory_allocated
 mem.tracking_allocator_destroy(&s.allocations)
 generation:=s.generation;s^=Client_Slot{generation=generation}
 if remaining!=0 { return IO_ERROR }
 return OK
}
@(export)
bom_client_connect :: proc "c" (handle:u64,info:^BomConnectInfo) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY }
 if info==nil || info.struct_size<u32(size_of(BomConnectInfo)) || info.version!=1 || info.port==0 || info.port>65535 || info.token_length>128 || (info.token_length>0 && info.token==nil) || info.reserved!=0 { return BAD_ARGUMENT }
 close_client(s)
 delete(s.last_error);s.last_error=""
 if !nc.socket_open(&s.socket,s.local_port) { return fail_client(s,IO_ERROR,"could not bind or reopen the local IPv4 UDP port") }
 s.local_port=nc.socket_port(&s.socket)
 ip:=info.ipv4
 s.endpoint=nc.address_make({u8(ip>>24),u8(ip>>16),u8(ip>>8),u8(ip)},u16(info.port))
 if info.token_length>0 { s.token=strings.clone(string(info.token[:info.token_length])) }
 salt:=nc.random_salt();for salt==s.last_salt {salt=nc.random_salt()};s.last_salt=salt
 core.net_client_init(&s.client,salt,0)
 s.client.real_gate=true;s.client.real_host_token=s.token;s.client.verify=true
 s.client.has_expected_manifest=s.has_expected_manifest;s.client.expected_manifest=s.expected_manifest
 s.client.prediction_enabled=!s.prediction_disabled
 s.connection_generation+=1;s.live=true;s.last_connection_state=u32(nc.Client_State.Connecting)
 return OK
}
@(export)
bom_client_disconnect :: proc "c" (handle:u64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };close_client(s);s.last_connection_state=u32(nc.Client_State.Disconnected);return OK
}
@(export)
bom_client_set_held_input :: proc "c" (handle:u64,timestamp:f64,move:f32) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY };if !s.live { return NOT_CONNECTED }
 if math.is_nan(timestamp) || math.is_inf(timestamp) || !core.finite(move) { return BAD_ARGUMENT }
 if s.has_held_timestamp && timestamp<s.last_held_timestamp { return BAD_ARGUMENT }
 value:=clamp(move,f32(-1),f32(1))
 previous:=s.held_move;if len(s.held)>0 { previous=s.held[len(s.held)-1].move }
 if value==previous { s.last_held_timestamp=timestamp;s.has_held_timestamp=true;return OK }
 if len(s.held)>=256 { return OVERFLOW }
 append(&s.held,Held{timestamp,value});s.last_held_timestamp=timestamp;s.has_held_timestamp=true;return OK
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
collect_presented :: proc(s:^Client_Slot) -> u32 {
 if s.command_pending && s.client.control_serial>s.command_serial { s.command_pending=false;s.command_ok=s.client.control_ok }
 if s.client.stats.structure_errors>0 { return IO_ERROR }
 if s.journal_epoch!=s.client.epoch { clear(&s.events);s.has_geometry=false;s.journal_epoch=s.client.epoch;s.presented_tick=0 }
 for event in s.client.events {
  if !core.finite(event.position.x) || !core.finite(event.position.y) || !core.finite(event.radius) || event.radius<0 { return IO_ERROR }
  if len(s.events)>=256 { return OVERFLOW }
  s.event_sequence+=1;append(&s.events,BomEvent{id=s.event_sequence,tick=event.tick,kind=u32(event.kind),x=event.position.x,y=event.position.y,radius=event.radius})
 }
 clear(&s.client.events)
 for applied in s.client.applied {
  writer:nc.Writer;nc.writer_init(&writer,32)
  nc.write_u8(&writer,core.NET_REAL_HASH_REPORT);nc.write_u32(&writer,applied.epoch);nc.write_u64(&writer,applied.revision);nc.write_u64(&writer,applied.hash)
  _=nc.client_send_reliable(&s.client.nc_client,writer.data[:]);nc.writer_destroy(&writer)
  s.canonical_hash=applied.hash
 }
 clear(&s.client.applied)
 clear(&s.client.acks_to_check) // Verification-only history; ACK fields remain in native input packets.
 return OK
}
ffi_input_source :: proc(c:^core.Net_Client,data:rawptr) {
 s:=cast(^Client_Slot)data
 generation:=c.input_link.history.identity.generation
 if c.epoch!=s.input_epoch || (c.real_gate && generation!=s.input_generation) {
  clear(&s.held);clear(&s.jumps);clear_queued_actions(s)
  s.held_move=0;c.human_jump_pending=false;s.input_epoch=c.epoch;s.input_generation=generation
 }
 for len(s.held)>0 && s.held[0].timestamp<=s.next_tick+1e-9 { s.held_move=s.held[0].move;ordered_remove(&s.held,0) }
 c.human_move=s.held_move
 if len(s.jumps)>0 && s.jumps[0]<=s.next_tick+1e-9 { c.human_jump_pending=true;ordered_remove(&s.jumps,0) }
 for len(s.actions)>0 && s.actions[0].timestamp<=s.next_tick+1e-9 {
  if len(c.blasts)>=core.NET_MAX_BLASTS { s.input_error=OVERFLOW;return }
  a:=s.actions[0];ordered_remove(&s.actions,0)
  if s.next_tick-a.timestamp>0.5 { if c.real_gate && !core.net_request_client_local_result(c,core.REQUEST_BLAST,.Expired,0) { s.input_error=OVERFLOW;return };c.stats.blasts_dropped+=1;continue }
  c.blast_ages[len(c.blasts)]=max(0.0,s.next_tick-a.timestamp)
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
  core.input_link_clear_intent(&s.client.input_link)
  clear(&s.held);clear(&s.jumps);clear_queued_actions(s);clear(&s.client.blasts)
  s.held_move=0;s.client.human_jump_pending=false;s.client.has_clock=false
  s.accumulator=0;s.next_tick=now+core.NET_STEP_DT
  s.fixed_transport_now=s.transport_now
 } else { s.accumulator+=dt }
 buffer:[nc.MAX_PACKET+64]u8
 for _ in 0..<256 {
  packet,from,has:=nc.socket_receive(&s.socket,buffer[:]);if !has { break }
  if from==s.endpoint { nc.client_receive(&s.client.nc_client,packet,s.transport_now) }
 }
 for _ in 0..<4 {
  if s.accumulator+1e-9<core.NET_STEP_DT { break }
  s.fixed_transport_now+=core.NET_STEP_DT
  core.net_client_step(&s.client,s.fixed_transport_now,ffi_input_source,s)
  if len(s.client.stats.delay_history)>256 {
   history:=s.client.stats.delay_history
   copy(history[:256],history[len(history)-256:])
   resize(&s.client.stats.delay_history,256)
  }
  if s.input_error!=OK { error:=s.input_error;s.input_error=OK;return fail_client(s,error,"native input queue overflow; reconnect required") }
  collected:=collect_presented(s);if collected!=OK { return fail_client(s,collected,"invalid or overflowing native presentation; reconnect required") }
  s.accumulator-=core.NET_STEP_DT;s.next_tick+=core.NET_STEP_DT
 }
 nc.client_update(&s.client.nc_client,s.transport_now);flush(s)
 s.last_connection_state=u32(s.client.nc_client.state)
 if s.client.real_reason!="" || s.client.nc_client.state==.Failed || s.client.nc_client.state==.Timed_Out || s.client.nc_client.state==.Disconnected { reason:=fmt.aprintf("connection %v: %s; reconnect required",s.client.nc_client.state,s.client.nc_client.reject_reason);defer delete(reason);return fail_client(s,IO_ERROR,reason) }
 return OK
}
@(export)
bom_client_acquire_sample :: proc "c" (handle:u64,sample:^BomSample) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired { return BUSY }
 if sample==nil || sample.struct_size<u32(size_of(BomSample)) || sample.version!=1 { return BAD_ARGUMENT }
 // The fixed clock schedules commands; fractional presentation never advances it.
 if s.client.has_clock {
  fixed_clock:=s.client.clock
  target:=min(f64(s.client.newest_complete),fixed_clock+max(f64(0),s.accumulator)/core.NET_STEP_DT)
  s.client.clock=max(s.presented_tick,target)
  core.net_client_apply_queue(&s.client);core.net_client_compute_drawn(&s.client)
  presented:=s.client.clock
  collected:=collect_presented(s)
  s.client.clock=fixed_clock
  if collected!=OK { return fail_client(s,collected,"invalid or overflowing fractional presentation; reconnect required") }
  s.presented_tick=presented
 }
 scene:=&s.client.rep.scene
 if !s.has_geometry || s.cached_epoch!=s.client.epoch || s.cached_revision!=scene.structure_revision {
  s.topology_sequence+=1;s.topology_from=s.accepted_epoch==s.client.epoch?s.accepted_revision:0
  clear(&s.cells);clear(&s.vertices)
  for sub in scene.subdivisions {
   if !sub.live { continue }
   if sub.material<0 || sub.material>=len(scene.materials) || len(sub.outline.points)<3 || !core.valid_vec(sub.rest_center) { return fail_client(s,IO_ERROR,"invalid presented cell geometry or material") }
   if len(s.cells)>=100000 || len(s.vertices)+len(sub.outline.points)>1000000 { return fail_client(s,OVERFLOW,"presented geometry exceeds capacity") }
   m:=scene.materials[sub.material];kind:=core.Ent_Kind.Piece;if m.flexibility>0 { kind=.Rubber }
   color:=u32(m.color[0])|(u32(m.color[1])<<8)|(u32(m.color[2])<<16)|0xff000000
   pivot:=sub.rest_center
   if kind==.Piece { if row,found:=scene.piece_rows[sub.owner];found { pivot=scene.pieces[row].ref_rest } }
   append(&s.cells,BomCell{id=sub.id,piece_id=sub.owner,material=u32(sub.material),pose_kind=u32(kind),rest_x=sub.rest_center.x,rest_y=sub.rest_center.y,pivot_x=pivot.x,pivot_y=pivot.y,vertex_start=u32(len(s.vertices)),vertex_count=u32(len(sub.outline.points)),color_rgba=color})
   for p in sub.outline.points { if !core.valid_vec(p) { return fail_client(s,IO_ERROR,"nonfinite presented outline") };append(&s.vertices,BomVertex{p.x,p.y}) }
  }
  s.cached_epoch=s.client.epoch;s.cached_revision=scene.structure_revision;s.has_geometry=true
 }
 clear(&s.poses)
 for key,d in s.client.drawn { append(&s.poses,BomPose{id=core.key_id(key),kind=u32(core.key_kind(key)),flags=u32(d.landed),x=d.x,y=d.y,angle=d.angle,fuse=d.fuse}) }
 if s.client.rep.has_baseline {
  core.net_client_ensure_anchored(&s.client)
  for piece in scene.pieces {
   if piece.live && (piece.material<0 || piece.material>=len(scene.materials)) { return fail_client(s,IO_ERROR,"invalid presented piece material") }
   if !piece.live || !s.client.anchored[piece.id] || scene.materials[piece.material].flexibility>0 { continue }
   if _,exists:=s.client.drawn[core.ent_key(.Piece,piece.id)];!exists { append(&s.poses,BomPose{id=piece.id,kind=u32(core.Ent_Kind.Piece),x=piece.ref_rest.x,y=piece.ref_rest.y}) }
  }
  for sub in scene.subdivisions {
   pinned:=s.client.anchored[sub.owner];if sub.provenance.motion!=.Legacy {pinned=sub.provenance.pinned}
   if !sub.live || scene.materials[sub.material].flexibility<=0 || !pinned { continue }
   if _,exists:=s.client.drawn[core.ent_key(.Rubber,sub.id)];!exists { append(&s.poses,BomPose{id=sub.id,kind=u32(core.Ent_Kind.Rubber),x=sub.rest_center.x,y=sub.rest_center.y}) }
  }
 }
 flags:=u32(0);if s.client.real_hello_ok { flags|=1 };if s.client.rep.has_baseline { flags|=2 };if s.client.has_clock { flags|=4 }
 local_id:=u32(0xffffffff);if s.live && s.client.nc_client.client_index>=0 { local_id=u32(s.client.nc_client.client_index) }
 s.sample_sequence+=1;s.ack_event_id=0;if len(s.events)>0 { s.ack_event_id=s.events[len(s.events)-1].id }
 sample^=BomSample{struct_size=u32(size_of(BomSample)),version=1,connection_generation=s.connection_generation,epoch=s.client.epoch,connection_state=u32(s.client.nc_client.state),revision=scene.structure_revision,sample_sequence=s.sample_sequence,presentation_tick=s.presented_tick,canonical_hash=s.canonical_hash,input_count=u64(s.client.stats.input_count),stall_count=s.stall_count,local_player_id=local_id,flags=flags,cell_count=u32(len(s.cells)),vertex_count=u32(len(s.vertices)),pose_count=u32(len(s.poses)),event_count=u32(len(s.events)),cells=raw_data(s.cells),vertices=raw_data(s.vertices),poses=raw_data(s.poses),events=raw_data(s.events),error_text=raw_data(s.client.real_reason),error_length=u32(len(s.client.real_reason))}
 sample.received_epoch=s.client.received.scene.epoch;sample.received_revision=s.client.received.scene.structure_revision
 if scene.catalog!=nil {hash:=transmute([4]u64)core.level_sha256(transmute([]u8)scene.level_json);sample.catalog_revision=scene.epoch;sample.catalog_hash=hash[0]}
 if s.client.prediction!=nil { sample.owner_prediction_status=u32(s.client.prediction.mode) }
 if !s.live { sample.connection_state=s.last_connection_state }
 if s.client.received.has_baseline { sample.received_flags=1 }
 sample.transaction_id=s.topology_sequence;sample.effective_tick=s.client.rep.tick;sample.from_revision=s.topology_from;sample.to_revision=scene.structure_revision
 if s.topology_accepted!=s.topology_sequence && s.client.rep.has_baseline { sample.transaction_flags=1;if s.accepted_epoch!=s.client.epoch { sample.transaction_flags|=2 } }
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
 s.topology_accepted=s.topology_sequence;s.accepted_revision=s.cached_revision;s.accepted_epoch=s.cached_epoch
 return OK
}
@(export)
bom_client_host_command :: proc "c" (handle:u64,op,mode:u32,radius:f32) -> u32 {
 command:=BomHostCommand{struct_size=u32(size_of(BomHostCommand)),version=1,op=op,mode=mode,radius=radius}
 id:u64;return bom_client_request_host_command(handle,&command,&id)
}

// One reliable control request may be outstanding. The existing protocol orders
// responses, so this maps a local ID to a server result without changing bytes.
// op 1 reset, 2 mode, 3 radius, 4 native level upload (copied by reliable send).
@(export)
bom_client_request_host_command :: proc "c" (handle:u64,command:^BomHostCommand,command_id:^u64) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if s.acquired || s.command_pending { return BUSY }
 if !s.live || !s.client.real_hello_ok { return NOT_CONNECTED }
 if command==nil || command_id==nil || command.struct_size<u32(size_of(BomHostCommand)) || command.version!=1 || command.reserved!=0 || command.reserved1!=0 { return BAD_ARGUMENT }
 command_id^=0
 if command.op<1 || command.op>4 || command.mode>255 || !core.finite(command.radius) || s.command_counter==0xffffffffffffffff { return BAD_ARGUMENT }
 sent:=false
 if command.op==4 {
  if command.layout_length==0 || command.layout_length>u32(core.NET_APP_MAX_LAYOUT) || command.layout==nil { return BAD_ARGUMENT }
  sent=core.net_host_client_send_layout(&s.client,command.layout[:command.layout_length])
 } else {
  if command.layout_length!=0 { return BAD_ARGUMENT }
  sent=core.net_host_client_send_command(&s.client,u8(command.op),u8(command.mode),command.radius)
 }
 if !sent { return IO_ERROR }
 s.command_counter+=1;s.command_id=s.command_counter;s.command_serial=s.client.control_serial;s.command_pending=true;s.command_ok=false
 command_id^=s.command_id;return OK
}
@(export)
bom_client_get_command_result :: proc "c" (handle:u64,result:^BomCommandResult) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if result==nil || result.struct_size<u32(size_of(BomCommandResult)) || result.version!=1 { return BAD_ARGUMENT }
 state:=u32(0);reason:=""
 if s.command_id!=0 { state=1;if !s.command_pending { state=s.command_ok?2:3;reason=s.client.control_reason } }
 result^=BomCommandResult{struct_size=u32(size_of(BomCommandResult)),version=1,command_id=s.command_id,status=state,reason_length=u32(len(reason)),reason=raw_data(reason)}
 return OK
}

// Read-only diagnostics never reallocate or invalidate an acquired sample.
@(export)
bom_client_get_stats :: proc "c" (handle:u64,stats:^BomStats) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if stats==nil || stats.struct_size<u32(size_of(BomStats)) || stats.version!=1 { return BAD_ARGUMENT }
 flags:=u32(0);if s.live { flags|=1 };if s.acquired { flags|=2 };if s.client.real_is_host { flags|=4 };if s.client.stats.blast_rejections_seen>0 { flags|=8 }
 stats^=BomStats{struct_size=u32(size_of(BomStats)),version=1,connection_generation=s.connection_generation,input_count=u64(s.client.stats.input_count),stall_count=s.stall_count,presentation_tick=s.presented_tick,fixed_tick=s.client.clock,held_queued=u32(len(s.held)),jumps_queued=u32(len(s.jumps)),actions_queued=u32(len(s.actions)),events_queued=u32(len(s.events)),reliable_queued=u32(len(s.client.queue)),structure_errors=u32(s.client.stats.structure_errors),frames_complete=u32(s.client.stats.frames_complete),flags=flags,owned_bytes=u64(s.allocations.current_memory_allocated),peak_owned_bytes=u64(s.allocations.peak_memory_allocated),live_allocations=u64(len(s.allocations.allocation_map))}
 return OK
}
@(export)
bom_client_last_error :: proc "c" (handle:u64,error:^BomError) -> u32 {
 s,status:=get_slot(handle);if status!=OK { return status };context=s.ctx
 if error==nil || error.struct_size<u32(size_of(BomError)) || error.version!=1 { return BAD_ARGUMENT }
 reason:=s.last_error;if s.live && s.client.real_reason!="" { reason=s.client.real_reason }
 error^=BomError{struct_size=u32(size_of(BomError)),version=1,message=raw_data(reason),message_length=u32(len(reason))}
 return OK
}
