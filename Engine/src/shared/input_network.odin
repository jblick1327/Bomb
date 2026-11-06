package shared
import nc "../netcode"

net_scheduled_send_control :: proc(ns:^Net_Server,index:int,control:Schedule_Control) {
 w:nc.Writer;nc.writer_init(&w,80);defer nc.writer_destroy(&w);schedule_control_encode(&w,control)
 _=nc.server_send_reliable(&ns.srv,index,w.data[:])
}
net_scheduled_server_offer :: proc(ns:^Net_Server,index:int) {
 c:=&ns.clients[index]
 generation:=max(u64(1),c.schedule.identity.generation+1)
 c.schedule.synchronized=false;c.schedule.held=0;c.schedule.slots={}
 request_cache_expire_epoch(c.requests,ns.tick)
 c.move=0;c.jump_pending=false;clear(&c.blast_queue)
 net_scheduled_send_control(ns,index,{kind=.Offer,proposal={{c.incarnation,ns.game.world.scene.epoch,generation},ns.tick+2,1},server={ns.tick,0}})
}
net_scheduled_server_owner :: proc(ns:^Net_Server,index:int) {
 c:=&ns.clients[index];p:=&ns.game.world.players[index]
 if !c.schedule.synchronized || !p.active { return }
 owner:=owner_state_capture(p,&c.schedule,ns.tick,ns.game.world.scene.structure_revision)
 w:nc.Writer;nc.writer_init(&w,160);defer nc.writer_destroy(&w);owner_state_encode(&w,owner)
 _=nc.server_send_unreliable(&ns.srv,index,w.data[:])
}
net_scheduled_server_message :: proc(ns:^Net_Server,index:int,channel:u8,data:[]u8) -> bool {
 if len(data)==0 { return false }
 c:=&ns.clients[index]
 switch data[0] {
 case SCHEDULED_MSG_REQUEST:
  if channel==nc.CHANNEL_RELIABLE { net_request_server_dispatch(ns,index,data) };return true
 case SCHEDULED_MSG_CONTROL:
  if channel!=nc.CHANNEL_RELIABLE { return true }
  control,ok:=schedule_control_decode(data);if !ok || control.kind!=.Request { return true }
  result:=input_schedule_reset(&c.schedule,c.incarnation,ns.game.world.scene.epoch,ns.tick,control.proposal)
  control.kind=result==.Accepted?Schedule_Control_Kind.Accepted:Schedule_Control_Kind.Rejected
  control.reason=result;control.server={ns.tick,0};net_scheduled_send_control(ns,index,control)
  return true
 case SCHEDULED_MSG_INPUT:
  if channel!=nc.CHANNEL_UNRELIABLE { return true }
  packet,ok:=scheduled_input_decode(data);if !ok { return true }
  if packet.identity.incarnation!=c.incarnation || packet.identity.epoch!=ns.game.world.scene.epoch { return true }
  if packet.has_ack { net_server_ack(ns,c,packet.ack) }
  for k in 0..<packet.count { _=input_schedule_insert(&c.schedule,packet.identity,ns.tick,packet.commands[k]) }
  return true
 case SCHEDULED_MSG_PROBE:
  if channel==nc.CHANNEL_UNRELIABLE && len(data)==9 { r:nc.Reader;nc.reader_init(&r,data);_=nc.read_u8(&r);c.echo_nonce=nc.read_u64(&r) }
  return true
 }
 return false
}
// Called after the real server's fixed-step loop, immediately before producing
// outgoing datagrams. Phase identifies send time, not receive/processing time.
net_scheduled_server_echoes :: proc(ns:^Net_Server,phase:f64,now:f64) {
 sent:=false
 for &c,i in ns.clients {
  if !c.active || c.echo_nonce==0 { continue }
  w:nc.Writer;nc.writer_init(&w,24)
  nc.write_u8(&w,SCHEDULED_MSG_ECHO);nc.write_u64(&w,c.echo_nonce);nc.write_u64(&w,ns.tick);nc.write_f32(&w,f32(clamp(phase,0,0.999999)))
  _=nc.server_send_unreliable(&ns.srv,i,w.data[:]);nc.writer_destroy(&w);c.echo_nonce=0;sent=true
 }
 if sent { nc.server_update(&ns.srv,now) }
}
net_scheduled_client_message :: proc(c:^Net_Client,channel:u8,data:[]u8,now:f64) -> bool {
 if len(data)==0 { return false }
 link:=&c.input_link
 switch data[0] {
 case SCHEDULED_MSG_RESULT:
  if channel==nc.CHANNEL_RELIABLE { net_request_client_result(c,data) };return true
 case SCHEDULED_MSG_ECHO:
  if channel!=nc.CHANNEL_UNRELIABLE || len(data)!=21 { return true }
  r:nc.Reader;nc.reader_init(&r,data);_=nc.read_u8(&r);nonce:=nc.read_u64(&r);tick:=nc.read_u64(&r);phase:=nc.read_f32(&r)
  if r.ok { _=input_clock_echo(&link.clock,nonce,{tick,f64(phase)},now) }
  return true
 case SCHEDULED_MSG_CONTROL:
  if channel!=nc.CHANNEL_RELIABLE { return true }
  control,ok:=schedule_control_decode(data);if !ok { return true }
  if control.kind==.Offer { _=input_link_offer(link,control);c.human_move=0;c.human_jump_pending=false;clear(&c.blasts) }
  else { _=input_link_control_result(link,control) }
  return true
 case SCHEDULED_MSG_OWNER:
  if channel!=nc.CHANNEL_UNRELIABLE { return true }
  owner,ok:=owner_state_decode(data);if ok { _=input_link_owner(link,owner) };return true
 }
 return false
}
net_scheduled_client_update :: proc(c:^Net_Client,now:f64) {
 link:=&c.input_link
 if now>=c.input_probe_at {
  nonce,ok:=input_clock_probe(&link.clock,now)
  if ok {
   w:nc.Writer;nc.writer_init(&w,16);nc.write_u8(&w,SCHEDULED_MSG_PROBE);nc.write_u64(&w,nonce)
   _=nc.client_send_unreliable(&c.nc_client,w.data[:]);nc.writer_destroy(&w)
  }
  c.input_probe_at=now+.25
 }
 if link.clock.valid { _,_=input_clock_now(&link.clock,now) }
 if link.clock.resync && link.active { input_link_clear_intent(link);c.human_move=0;c.human_jump_pending=false;clear(&c.blasts) }
 control,ready:=input_link_prepare_reset(link,now)
 if ready {
  w:nc.Writer;nc.writer_init(&w,80);schedule_control_encode(&w,control)
  if !nc.client_send_reliable(&c.nc_client,w.data[:]) { link.awaiting=false;link.history={} }
  nc.writer_destroy(&w)
 }
}
net_scheduled_client_input :: proc(c:^Net_Client) {
 net_request_client_blasts(c)
 _,created:=input_link_command(&c.input_link,move_quantize(c.human_move),c.human_jump_pending)
 if c.human_jump_pending { c.jump_counter+=1;c.stats.jumps_pressed+=1;c.human_jump_pending=false }
 if !created { return }
 packet,ready:=input_link_packet(&c.input_link,c.has_complete,c.newest_complete);if !ready { return }
 w:nc.Writer;nc.writer_init(&w,160);defer nc.writer_destroy(&w)
 if !scheduled_input_encode(&w,packet) { return }
 if c.stats.input_count==0 { c.stats.input_payload_hash=14695981039346656037 }
 for byte in w.data { c.stats.input_payload_hash=(c.stats.input_payload_hash~u64(byte))*1099511628211 }
 c.stats.input_count+=1;c.stats.input_bytes+=len(w.data);c.stats.input_max=max(c.stats.input_max,len(w.data))
 _=nc.client_send_unreliable(&c.nc_client,w.data[:])
}
