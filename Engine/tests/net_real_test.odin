package main

import nc "netcode"
import "core:testing"

@(test)
test_step3_staging_target_parser :: proc(t: ^testing.T) {
 target,ok:=net_real_parse_target("127.0.0.1:47380")
 testing.expect(t,ok)
 testing.expect(t,target==nc.address_loopback(47380))
 target,ok=net_real_parse_target("192.168.0.42")
 testing.expect(t,ok)
 testing.expect(t,nc.address_port(target)==47380)
 testing.expect(t,nc.address_ip(target)==[4]u8{192,168,0,42})
 for text in ([]string{
  "", "127.0.0.1:", "1.2.3", "1.2.3.4.5", "1.2.3.256",
  "127.0.0.1:0", "127.0.0.1:65536", "host:47380",
  "127.0.0.1:-1", "127.0.0.1:01junk",
 }) {
  _,valid:=net_real_parse_target(text)
  testing.expect(t,!valid)
 }
}

@(test)
test_step3_staging_port_parser :: proc(t: ^testing.T) {
 _,ok:=net_real_cli_port("0");testing.expect(t,!ok)
 _,ok=net_real_cli_port("65536");testing.expect(t,!ok)
 port,port_ok:=net_real_cli_port("47380")
 testing.expect(t,port_ok)
 testing.expect(t,port==47380)
}
