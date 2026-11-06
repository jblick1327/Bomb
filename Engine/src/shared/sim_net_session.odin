#+feature dynamic-literals
package shared

import nc "../netcode"
import fmt "core:fmt"

NET_APP_MAX_BUILD :: 80

NET_APP_MAX_TOKEN :: 128

NET_APP_REJECT_GRACE :: 2.0

Net_App_Hello :: struct {
 version: u32,
 build: string, // views into the packet; do not persist without cloning
 token: string,
}

net_app_read_hello :: proc(data: []u8) -> (hello: Net_App_Hello, valid: bool) {
 if len(data)<1 || data[0]!=NET_APP_HELLO || len(data)>256 { return {},false }
 r:nc.Reader; nc.reader_init(&r,data)
 _=nc.read_u8(&r)
 hello.version=nc.read_u32(&r)
 hello.build=nc.read_string(&r)
 hello.token=nc.read_string(&r)
 valid=r.ok && r.pos==len(data) && len(hello.build)>0 && len(hello.build)<=NET_APP_MAX_BUILD && len(hello.token)<=NET_APP_MAX_TOKEN
 return
}

net_app_hello_error :: proc(h: Net_App_Hello) -> string {
 if h.version!=GAME_PROTOCOL_VERSION || h.build!=GAME_BUILD_ID {
  return fmt.tprintf("version mismatch (server %d/%s, you %d/%s)", GAME_PROTOCOL_VERSION, GAME_BUILD_ID, h.version, h.build)
 }
 return ""
}

net_app_send_reject :: proc(ns: ^Net_Server, index: int, reason: string, now: f64) {
 if index<0 || index>=nc.MAX_CLIENTS || ns.real_reject_at[index]>0 { return }
 w:nc.Writer;nc.writer_init(&w,64);defer nc.writer_destroy(&w)
 nc.write_u8(&w,NET_APP_REJECT);nc.write_string(&w,reason)
 _=nc.server_send_reliable(&ns.srv,index,w.data[:])
 ns.real_reject_at[index]=now+NET_APP_REJECT_GRACE
 if ns.real_logging { fmt.printf("HELLO REJECT client=%d reason=%s\n",index,reason) }
}

net_app_server_hello :: proc(ns: ^Net_Server,index: int,data: []u8,now: f64) {
 if ns.clients[index].active || ns.real_reject_at[index]>0 { return }
 hello,ok:=net_app_read_hello(data)
 if !ok { net_app_send_reject(ns,index,"invalid hello",now);return }
 if reason:=net_app_hello_error(hello);reason!="" { net_app_send_reject(ns,index,reason,now);return }
 is_host:=false
 if ns.real_host_token!="" && hello.token==ns.real_host_token {
  if ns.real_host_index>=0 && ns.real_host_index!=index { net_app_send_reject(ns,index,"host already connected",now);return }
  is_host=true
 }
 // No player is ever added before version/build validation.
 net_server_join(ns,index)
 ns.clients[index].is_host=is_host
 if is_host {
  ns.real_host_index=index
  ns.real_host_seen=true
  ns.real_host_left_at=-1
 }
 w:nc.Writer;nc.writer_init(&w,16);defer nc.writer_destroy(&w)
 nc.write_u8(&w,NET_APP_WELCOME)
 nc.write_u8(&w,u8(index))
 nc.write_bool(&w,is_host)
 _=nc.server_send_reliable(&ns.srv,index,w.data[:])
 net_host_send_settings(ns,index)
 if ns.real_logging { fmt.printf("HELLO OK client=%d role=%s\n",index,is_host?"HOST":"player") }
}

net_app_server_disconnect :: proc(ns: ^Net_Server,index: int,now: f64) {
 if !ns.real_gate || ns.real_host_index!=index { return }
 ns.real_host_index=-1
 ns.real_host_left_at=now
 for i in 0..<nc.MAX_CLIENTS {
  if i==index || !ns.clients[i].active { continue }
  _=nc.server_send_reliable(&ns.srv,i,[]u8{NET_APP_HOST_LEFT})
 }
 if ns.real_logging { fmt.println("HOST left; server will exit in 5s") }
}
