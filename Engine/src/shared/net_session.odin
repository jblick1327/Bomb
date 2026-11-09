#+feature dynamic-literals
package shared

import nc "../netcode"
import fmt "core:fmt"
import strings "core:strings"

GAME_PROTOCOL_VERSION :: u32(6)

GAME_BUILD_ID :: "BOM-rounds-2026-11-09"

NET_APP_HELLO :: u8(0xC2)

NET_APP_WELCOME :: u8(0xC3)

NET_APP_REJECT :: u8(0xC4)

NET_APP_HOST_LEFT :: u8(0xC5)

NET_APP_MAX_REASON :: 256

net_app_write_hello :: proc(w: ^nc.Writer, version: u32, build, token: string,expected:[]u8=nil,spectator:bool=false,resume:Round_Credentials={}) {
 nc.write_u8(w, NET_APP_HELLO)
 nc.write_u32(w, version)
 nc.write_string(w, build)
 nc.write_string(w, token)
 if version==GAME_PROTOCOL_VERSION { nc.write_bool(w,len(expected)==32);if len(expected)==32 {nc.write_raw(w,expected)} }
 if version==GAME_PROTOCOL_VERSION {
  credential:=resume
  nc.write_bool(w,spectator);nc.write_raw(w,credential.server[:]);nc.write_u64(w,credential.session);nc.write_raw(w,credential.secret[:])
 }
}

net_app_client_send_hello :: proc(c: ^Net_Client) {
 if !c.real_gate || c.real_hello_sent || c.nc_client.state!=.Connected { return }
 w:nc.Writer;nc.writer_init(&w,64);defer nc.writer_destroy(&w)
 expected:[]u8;if c.has_expected_manifest {expected=c.expected_manifest[:]}
 net_app_write_hello(&w,c.real_protocol,c.real_build,c.real_host_token,expected,c.join_spectator,c.round_credentials)
 if nc.client_send_reliable(&c.nc_client,w.data[:]) { c.real_hello_sent=true }
}

net_app_client_control :: proc(c: ^Net_Client,data: []u8) -> bool {
 if !c.real_gate || len(data)==0 { return false }
 switch data[0] {
 case NET_APP_ROUND:
  round_client_accept(c,data);return true
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
  credential:Round_Credentials
  for &byte in credential.server {byte=nc.read_u8(&r)}
  credential.session=nc.read_u64(&r)
  for &byte in credential.secret {byte=nc.read_u8(&r)}
  if !r.ok || r.pos!=len(data) || index!=c.nc_client.client_index { return true }
  c.real_is_host=host;c.real_hello_ok=true;c.round_credentials=credential
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
  c.control_serial+=1;c.control_kind=kind;c.control_ok=ok
  delete(c.control_reason);c.control_reason=strings.clone(reason)
  fmt.printf("APP RESULT kind=%d status=%s reason=%s\n",kind,ok?"OK":"REJECT",reason)
  return true
 }
 return false
}
