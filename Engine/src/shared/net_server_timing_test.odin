package shared
import t "core:testing"

@(test)
net_server_timing_is_bounded :: proc(test:^t.T) {
 samples:[dynamic]f64;defer delete(samples)
 for tick in 0..<u64(NET_SERVER_TIMING_CAPACITY+7) {net_server_record_timing(&samples,tick,f64(tick))}
 t.expect(test,len(samples)==NET_SERVER_TIMING_CAPACITY)
 for i in 0..<NET_SERVER_TIMING_CAPACITY {expected:=u64(i);if i<7 {expected+=NET_SERVER_TIMING_CAPACITY};t.expect(test,samples[i]==f64(expected))}
}

@(test)
net_entity_and_delay_diagnostic_samples_are_bounded :: proc(test:^t.T) {
 staleness:[dynamic]u16;delays:[dynamic]u8;defer delete(staleness);defer delete(delays)
 for i in 0..<u64(NET_SERVER_TIMING_CAPACITY*3+7) {
  net_record_bounded_sample(&staleness,i,u16(i%65536));net_record_bounded_sample(&delays,i,u8(i%251))
 }
 t.expect(test,len(staleness)==NET_SERVER_TIMING_CAPACITY&&len(delays)==NET_SERVER_TIMING_CAPACITY)
 last:=u64(NET_SERVER_TIMING_CAPACITY*3+6)
 t.expect(test,staleness[last%NET_SERVER_TIMING_CAPACITY]==u16(last%65536)&&delays[last%NET_SERVER_TIMING_CAPACITY]==u8(last%251))
}

@(test)
explicit_server_bind_keeps_numeric_ipv4_and_requires_nonlocal_host_authorization :: proc(test:^t.T) {
 valid:=[3]string{"127.0.0.2","0.0.0.0","192.168.1.4"}
 for text in valid {_,ok:=net_real_cli_bind(text);t.expect(test,ok)}
 invalid:=[6]string{"","localhost","127.0.0.1:47380","256.0.0.1","127.0.0","127.0.0.1/24"}
 for text in invalid {_,ok:=net_real_cli_bind(text);t.expect(test,!ok)}
 ip,ok:=net_real_cli_bind("127.0.0.2");t.expect(test,ok&&ip==[4]u8{127,0,0,2})
 args:=[4]string{"--bind","0.0.0.0","--seconds","1"};t.expect(test,!net_real_cli_server(args[:]))
}
