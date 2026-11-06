package shared
import nc "../netcode"
import sha2 "core:crypto/sha2"
import strings "core:strings"

REQUEST_BLAST :: u8(1)
Pending_Request :: struct { active:bool, id:u64, kind:u8 }
Request_Envelope :: struct { incarnation:u64, epoch:u32, id,created,deadline:u64, kind:u8, payload:[]u8 }

request_envelope_decode :: proc(data:[]u8) -> (q:Request_Envelope,ok:bool) {
 if len(data)<38 || len(data)>NET_APP_MAX_LAYOUT+64 { return }
 r:nc.Reader;nc.reader_init(&r,data)
 if nc.read_u8(&r)!=SCHEDULED_MSG_REQUEST { return }
 q.incarnation=nc.read_u64(&r);q.epoch=nc.read_u32(&r);q.id=nc.read_u64(&r);q.created=nc.read_u64(&r);q.deadline=nc.read_u64(&r);q.kind=nc.read_u8(&r)
 q.payload=data[r.pos:]
 return q,r.ok && q.id!=0 && (q.kind==REQUEST_BLAST || q.kind==NET_APP_HOST_COMMAND || q.kind==NET_APP_LAYOUT_UPLOAD)
}
request_reason_text :: proc(result:Request_Result) -> string {
 switch result.status {
 case .Accepted:return ""
 case .Expired:return "blast intent expired"
 case .Wrong_Epoch:return "epoch changed"
 case .Wrong_Connection:return "connection changed"
 case .Too_Old:return "request ID is terminal or too old"
 case .Conflict:return "conflicting request contents"
 case .Capacity:return "request result window is full"
 case .Rejected:
  switch result.reason { case 1:return "host only";case 3:return "outside world";case 4:return "blast rate exceeded";case 5:return "solid aim";case:return "invalid request" }
 case .Pending:return "request pending"
 }
 return "invalid request result"
}
net_request_send_result :: proc(ns:^Net_Server,index:int,kind:u8,result:Request_Result) {
 w:nc.Writer;nc.writer_init(&w,40);defer nc.writer_destroy(&w)
 nc.write_u8(&w,SCHEDULED_MSG_RESULT);nc.write_u8(&w,kind);nc.write_u64(&w,result.request_id);nc.write_u8(&w,u8(result.status))
 nc.write_u64(&w,result.effect_tick);nc.write_u64(&w,result.event_id);nc.write_u16(&w,result.reason)
 _=nc.server_send_reliable(&ns.srv,index,w.data[:])
}
net_request_server_dispatch :: proc(ns:^Net_Server,index:int,data:[]u8) {
 q,ok:=request_envelope_decode(data);if !ok { return }
 c:=&ns.clients[index]
 hash:[32]u8;ctx:sha2.Context_256;sha2.init_256(&ctx);sha2.update(&ctx,data);sha2.final(&ctx,hash[:])
 begin,previous:=request_cache_begin(c.requests,q.incarnation,q.id,hash)
 if begin!=.New { net_request_send_result(ns,index,q.kind,previous);return }
 result:=Request_Result{request_id=q.id,effect_tick=ns.tick+1,status=.Accepted}
 if q.epoch!=ns.game.world.scene.epoch { result.status=.Wrong_Epoch }
 else if q.kind==REQUEST_BLAST {
  result.status=blast_intent_status(c.incarnation,q.incarnation,ns.game.world.scene.epoch,q.epoch,ns.tick+1,q.created,q.deadline)
  if result.status==.Accepted {
   r:nc.Reader;nc.reader_init(&r,q.payload);point:=Vec2{nc.read_f32(&r),nc.read_f32(&r)}
   if !r.ok || r.pos!=len(q.payload) || !finite(point.x) || !finite(point.y) { result.status=.Rejected;result.reason=2 }
   else {
    recent:=0;for tick in c.blast_ticks { if ns.tick+1-tick<NET_BLAST_RATE_TICKS { recent+=1 } }
    if point.x<YARD_LEFT || point.x>YARD_RIGHT || point.y<=YARD_FLOOR_BOTTOM || point.y>NET_YARD_CEILING { result.status=.Rejected;result.reason=3;c.stats.rejected_outside+=1 }
    else if recent>=NET_BLAST_RATE_COUNT { result.status=.Rejected;result.reason=4;c.stats.rejected_rate+=1 }
    else if !sandbox_valid_aim(&ns.game.world.scene,point) { result.status=.Rejected;result.reason=5;c.stats.rejected_solid+=1 }
    else {
     world_explode(&ns.game.world,point,c.radius,&ns.pre_events)
     ns.next_event_id+=1;result.event_id=ns.next_event_id
     ns.pre_events.explosions[len(ns.pre_events.explosions)-1].event_id=result.event_id
     c.stats.blasts_applied+=1;append(&c.blast_ticks,ns.tick+1)
    }
   }
  }
  if result.status!=.Accepted {
   c.stats.blasts_rejected+=1;ns.next_event_id+=1;result.event_id=ns.next_event_id
   w:nc.Writer;nc.writer_init(&w,32);event_encode_rejected(&w,ns.tick+1,0,result.event_id)
   _=nc.server_send_reliable(&ns.srv,index,w.data[:]);nc.writer_destroy(&w)
  }
 } else {
  reason:="invalid request"
  if len(q.payload)>0 && q.payload[0]==q.kind {
   if q.kind==NET_APP_HOST_COMMAND { reason=net_host_apply_command(ns,index,q.payload) }
   else { reason=net_host_apply_layout(ns,index,q.payload) }
  }
  if reason!="" { result.status=.Rejected;result.reason=ns.clients[index].is_host?u16(2):u16(1) }
 }
 _=request_cache_finish(c.requests,result);net_request_send_result(ns,index,q.kind,result)
}

net_request_client_send :: proc(c:^Net_Client,kind:u8,payload:[]u8,created:u64=0,deadline:u64=0) -> bool {
 if !c.real_hello_ok || !c.input_link.has_offer || !c.has_epoch || c.request_counter==max(u64) { return false }
 id:=c.request_counter+1;slot:=&c.request_pending[id%u64(len(c.request_pending))]
 if slot.active { return false }
 w:nc.Writer;nc.writer_init(&w,len(payload)+48);defer nc.writer_destroy(&w)
 nc.write_u8(&w,SCHEDULED_MSG_REQUEST);nc.write_u64(&w,c.input_link.offer.identity.incarnation);nc.write_u32(&w,c.epoch)
 nc.write_u64(&w,id);nc.write_u64(&w,created);nc.write_u64(&w,deadline);nc.write_u8(&w,kind);nc.write_raw(&w,payload)
 if !nc.client_send_reliable(&c.nc_client,w.data[:]) { return false }
 if c.request_counter==0 { c.stats.request_payload_hash=14695981039346656037 }
 for byte in w.data { c.stats.request_payload_hash=(c.stats.request_payload_hash~u64(byte))*1099511628211 }
 c.request_counter=id;slot^={true,id,kind}
 if kind!=REQUEST_BLAST { c.host_request_id=id }
 return true
}
net_request_client_result :: proc(c:^Net_Client,data:[]u8) {
 r:nc.Reader;nc.reader_init(&r,data);_=nc.read_u8(&r);kind:=nc.read_u8(&r)
 result:Request_Result;result.request_id=nc.read_u64(&r);status:=nc.read_u8(&r)
 result.effect_tick=nc.read_u64(&r);result.event_id=nc.read_u64(&r);result.reason=nc.read_u16(&r)
 if !r.ok || r.pos!=len(data) || status==0 || status>u8(Request_Status.Capacity) { return }
 pending:=&c.request_pending[result.request_id%u64(len(c.request_pending))]
 if !pending.active || pending.id!=result.request_id || pending.kind!=kind { return }
 result.status=Request_Status(status);pending^={};c.last_request_result=result
 if kind!=REQUEST_BLAST && result.request_id==c.host_request_id {
  c.control_serial+=1;c.control_kind=kind;c.control_ok=result.status==.Accepted
  delete(c.control_reason);c.control_reason=strings.clone(request_reason_text(result))
 }
}
net_request_client_blasts :: proc(c:^Net_Client) {
 if !c.input_link.active || !c.input_link.clock.valid { clear(&c.blasts);return }
 created:=c.input_link.clock.estimate.tick
 if created>max(u64)-30 { clear(&c.blasts);return }
 // The timestamped FFI queue already enforces the local 500ms bound. The
 // reliable application deadline also prevents intent delayed in transport.
 for blast in c.blasts {
  w:nc.Writer;nc.writer_init(&w,8)
  nc.write_f32(&w,nc.dequantize_pos(blast.x));nc.write_f32(&w,nc.dequantize_pos(blast.y))
  if !net_request_client_send(c,REQUEST_BLAST,w.data[:],created,created+30) {
   c.stats.blasts_dropped+=1
   if c.real_reason=="" { c.real_reason=strings.clone("reliable action queue full; reconnect required") }
  }
  nc.writer_destroy(&w)
 }
 clear(&c.blasts)
}
