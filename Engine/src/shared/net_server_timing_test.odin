package shared
import t "core:testing"

@(test)
net_server_timing_is_bounded :: proc(test:^t.T) {
 samples:[dynamic]f64;defer delete(samples)
 for tick in 0..<u64(NET_SERVER_TIMING_CAPACITY+7) {net_server_record_timing(&samples,tick,f64(tick))}
 t.expect(test,len(samples)==NET_SERVER_TIMING_CAPACITY)
 for i in 0..<NET_SERVER_TIMING_CAPACITY {expected:=u64(i);if i<7 {expected+=NET_SERVER_TIMING_CAPACITY};t.expect(test,samples[i]==f64(expected))}
}
