package main

import "core:testing"
import "core:slice"
import nc "netcode"
import shared "shared"

@(test)
test_client_due_event_not_blocked_by_future_event :: proc(t:^testing.T) {
 c:Net_Client;net_client_init(&c,42,0);defer net_client_destroy(&c)
 future:nc.Writer;nc.writer_init(&future);defer nc.writer_destroy(&future)
 earlier:nc.Writer;nc.writer_init(&earlier);defer nc.writer_destroy(&earlier)
 event_encode_explosion(&future,400,{1,2},2)
 event_encode_explosion(&earlier,50,{2,3},2)
 testing.expect(t,shared.net_client_queue_owned(&c,shared.Net_Queued{tick=400,event=true,data=slice.clone(future.data[:])}))
 testing.expect(t,shared.net_client_queue_owned(&c,shared.Net_Queued{tick=50,event=true,data=slice.clone(earlier.data[:])}))
 c.has_clock=true;c.clock=100
 net_client_apply_queue(&c)
 testing.expect(t,len(c.events)==1 && c.events[0].tick==50,"future event cannot block an earlier due event")
 testing.expect(t,len(c.queue)==1 && c.queue[0].tick==400,"future state remains queued")
}

@(test)
test_client_presentation_overflow_is_explicit_and_owned :: proc(t:^testing.T) {
 c:Net_Client;net_client_init(&c,43,0);defer net_client_destroy(&c)
 for _ in 0..<shared.NET_MAX_QUEUED_MESSAGES {
  testing.expect(t,shared.net_client_queue_owned(&c,shared.Net_Queued{tick=1000,data=make([]u8,1)}))
 }
 testing.expect(t,!shared.net_client_queue_owned(&c,shared.Net_Queued{tick=1001,data=make([]u8,1)}))
 testing.expect(t,len(c.queue)==shared.NET_MAX_QUEUED_MESSAGES)
 testing.expect(t,c.stats.structure_errors==1 && c.real_reason!="","overflow is a visible reconnect error, not a silently missing transaction")
}
