package main

import nc "netcode"
import "core:fmt"
import "core:strings"

// Step 3 application handshake. The transport's low-level Connect/Accept is
// deliberately unchanged: an accepted socket gets no World/player/replica
// privileges until the reliable Hello has passed validation.
GAME_PROTOCOL_VERSION :: u32(3)
GAME_BUILD_ID :: "BOM-menus-2026-11-05"
NET_APP_HELLO :: u8(0xC2)
NET_APP_WELCOME :: u8(0xC3)
NET_APP_REJECT :: u8(0xC4)
NET_APP_HOST_LEFT :: u8(0xC5)
NET_APP_MAX_BUILD :: 80
NET_APP_MAX_TOKEN :: 128
NET_APP_MAX_REASON :: 256
NET_APP_REJECT_GRACE :: 2.0

Net_App_Hello :: struct {
 version: u32,
 build: string, // views into the packet; do not persist without cloning
 token: string,
}

net_app_write_hello :: proc(w: ^nc.Writer, version: u32, build, token: string) {
 nc.write_u8(w, NET_APP_HELLO)
 nc.write_u32(w, version)
 nc.write_string(w, build)
 nc.write_string(w, token)
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

// Returns empty for a compatible client; caller additionally validates HOST
// ownership. No string from an untrusted packet is used as a format string.
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

net_app_client_send_hello :: proc(c: ^Net_Client) {
 if !c.real_gate || c.real_hello_sent || c.nc_client.state!=.Connected { return }
 w:nc.Writer;nc.writer_init(&w,64);defer nc.writer_destroy(&w)
 net_app_write_hello(&w,c.real_protocol,c.real_build,c.real_host_token)
 if nc.client_send_reliable(&c.nc_client,w.data[:]) { c.real_hello_sent=true }
}

// Returns true when consumed as an application-level control message.
net_app_client_control :: proc(c: ^Net_Client,data: []u8) -> bool {
 if !c.real_gate || len(data)==0 { return false }
 switch data[0] {
 case NET_APP_SETTINGS:
  r:nc.Reader;nc.reader_init(&r,data)
  _=nc.read_u8(&r);mode:=nc.read_u8(&r);radius:=nc.read_f32(&r)
  if !r.ok || r.pos!=len(data) || mode>1 || !finite(radius) || radius<0.5 || radius>6 { return true }
  c.real_settings.blast_mode=Blast_Mode(mode);c.real_settings.blast_radius=radius
  c.radius_q=radius_quantize(radius);c.real_has_settings=true
  return true
 case NET_APP_WELCOME:
  r:nc.Reader;nc.reader_init(&r,data)
  _=nc.read_u8(&r);index:=int(nc.read_u8(&r));host:=nc.read_bool(&r)
  if !r.ok || r.pos!=len(data) || index!=c.nc_client.client_index { return true }
  c.real_is_host=host;c.real_hello_ok=true
  return true
 case NET_APP_REJECT:
  r:nc.Reader;nc.reader_init(&r,data)
  _=nc.read_u8(&r); reason:=nc.read_string(&r)
  if !r.ok || r.pos!=len(data) || len(reason)==0 || len(reason)>NET_APP_MAX_REASON { return true }
  delete(c.real_reason);c.real_reason=strings.clone(reason)
  return true
 case NET_APP_HOST_LEFT:
  if len(data)==1 {
   delete(c.real_reason);c.real_reason=strings.clone("host left")
   c.real_host_left=true
  }
  return true
 case NET_APP_COMMAND_RESULT:
  r:nc.Reader;nc.reader_init(&r,data)
  _=nc.read_u8(&r);kind:=nc.read_u8(&r);ok:=nc.read_bool(&r);reason:=nc.read_string(&r)
  if !r.ok || r.pos!=len(data) || len(reason)>NET_APP_MAX_REASON { return true }
  fmt.printf("APP RESULT kind=%d status=%s reason=%s\n",kind,ok?"OK":"REJECT",reason)
  return true
 }
 return false
}
