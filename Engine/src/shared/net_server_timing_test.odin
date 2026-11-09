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
