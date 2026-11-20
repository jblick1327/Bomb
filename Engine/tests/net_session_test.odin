package main

import nc "netcode"
import "core:testing"

@(test)
test_step3_application_hello_validation :: proc(t: ^testing.T) {
 w:nc.Writer;nc.writer_init(&w,96);defer nc.writer_destroy(&w)
 net_app_write_hello(&w,GAME_PROTOCOL_VERSION,GAME_BUILD_ID,"")
 hello,ok:=net_app_read_hello(w.data[:])
 testing.expect(t,ok)
 testing.expect(t,net_app_hello_error(hello)=="")
 nc.writer_reset(&w)
 net_app_write_hello(&w,GAME_PROTOCOL_VERSION+1,GAME_BUILD_ID,"")
 hello,ok=net_app_read_hello(w.data[:])
 testing.expect(t,ok)
 testing.expect(t,net_app_hello_error(hello)!="")
 nc.writer_reset(&w)
 net_app_write_hello(&w,GAME_PROTOCOL_VERSION,"different build","")
 hello,ok=net_app_read_hello(w.data[:])
 testing.expect(t,ok)
 testing.expect(t,net_app_hello_error(hello)!="")
 nc.writer_reset(&w)
 net_app_write_hello(&w,GAME_PROTOCOL_VERSION,GAME_BUILD_ID,"host secret")
 hello,ok=net_app_read_hello(w.data[:])
 testing.expect(t,ok)
 testing.expect(t,hello.token=="host secret")
 for n in 0..<len(w.data) {
  _,valid:=net_app_read_hello(w.data[:n])
  testing.expect(t,!valid)
 }
 _,valid:=net_app_read_hello([]u8{NET_APP_HELLO,1,2})
 testing.expect(t,!valid)
}
