package shared
import t "core:testing"
import nc "../netcode"

@(test)
blast_deadline_includes_local_queue_age_instead_of_restarting_at_send :: proc(test:^t.T) {
 c:Net_Client;net_client_init(&c,1234,0);defer net_client_destroy(&c)
 c.nc_client.state=.Connected
 c.real_gate=true;c.real_hello_ok=true;c.has_epoch=true;c.epoch=1
 c.input_link.has_offer=true;c.input_link.offer.identity={1,1,1};c.input_link.active=true
 c.input_link.clock={valid=true,estimate={9007199254741000,.25}}
 append(&c.blasts,Net_Blast{});c.blast_ages[0]=.4
 net_request_client_blasts(&c)
 t.expect_value(test,c.last_request_created_tick,u64(9007199254740976))
 t.expect_value(test,c.last_request_deadline_tick,c.last_request_created_tick+30)
 t.expect(test,c.request_counter==1 && c.request_pending[1].active && c.blast_ages[0]==0)
 append(&c.blasts,Net_Blast{});c.blast_ages[0]=.6;net_request_client_blasts(&c)
 t.expect(test,c.request_counter==2 && c.completed_requests[2].local && c.completed_requests[2].result.status==.Expired && !c.request_pending[2].active)
}

test_request_envelope :: proc(w:^nc.Writer,incarnation:u64,epoch:u32,id:u64,kind:u8,payload:[]u8,created:u64=0,deadline:u64=0) {
 nc.writer_reset(w);nc.write_u8(w,SCHEDULED_MSG_REQUEST);nc.write_u64(w,incarnation);nc.write_u32(w,epoch)
 nc.write_u64(w,id);nc.write_u64(w,created);nc.write_u64(w,deadline);nc.write_u8(w,kind);nc.write_raw(w,payload)
}

@(test)
short_host_request_decodes_without_blast_sized_minimum :: proc(test:^t.T) {
 w:nc.Writer;nc.writer_init(&w,64);defer nc.writer_destroy(&w)
 payload:=[2]u8{NET_APP_HOST_COMMAND,NET_HOST_RESET}
 test_request_envelope(&w,9007199254740999,7,9007199254742001,NET_APP_HOST_COMMAND,payload[:])
 q,ok:=request_envelope_decode(w.data[:]);t.expect(test,ok && len(w.data)==40 && len(q.payload)==2 && q.id==9007199254742001)
 for size in 0..<38 { _,valid:=request_envelope_decode(w.data[:size]);t.expect(test,!valid) }
}

@(test)
real_request_dispatch_reset_dedup_and_old_epoch_precondition :: proc(test:^t.T) {
 ns,ok:=net_real_create_server("");t.expect(test,ok);if !ok { return };defer net_server_destroy(&ns)
 ns.real_logging=false;ns.real_gate=true;net_server_join(&ns,0);ns.clients[0].is_host=true
 epoch:=ns.game.world.scene.epoch;incarnation:=ns.clients[0].incarnation
 w:nc.Writer;nc.writer_init(&w,64);defer nc.writer_destroy(&w)
 payload:=[2]u8{NET_APP_HOST_COMMAND,NET_HOST_RESET}
 id:=u64(9007199254742001)
 test_request_envelope(&w,incarnation,epoch,id,NET_APP_HOST_COMMAND,payload[:])
 net_request_server_dispatch(&ns,0,w.data[:]);after:=ns.game.world.scene.epoch
 t.expect(test,after>epoch && ns.clients[0].requests.entries[id%1024].result.status==.Accepted)
 net_request_server_dispatch(&ns,0,w.data[:]);t.expect_value(test,ns.game.world.scene.epoch,after)
 test_request_envelope(&w,incarnation,epoch,id+1,NET_APP_HOST_COMMAND,payload[:])
 net_request_server_dispatch(&ns,0,w.data[:])
 t.expect(test,ns.game.world.scene.epoch==after && ns.clients[0].requests.entries[(id+1)%1024].result.status==.Wrong_Epoch)
 // A protocol-3 peer cannot enter this application session.
 t.expect(test,net_app_hello_error({version=3,build="BOM-menus-2026-11-05"})!="")
}

@(test)
real_request_dispatch_blast_executes_once_and_reports_effect_identity :: proc(test:^t.T) {
 ns,ok:=net_real_create_server("");t.expect(test,ok);if !ok { return };defer net_server_destroy(&ns)
 ns.real_logging=false;ns.real_gate=true;net_server_join(&ns,0)
 payload:nc.Writer;nc.writer_init(&payload,8);defer nc.writer_destroy(&payload)
 nc.write_f32(&payload,-6.4);nc.write_f32(&payload,2.3)
 w:nc.Writer;nc.writer_init(&w,64);defer nc.writer_destroy(&w)
 id:=u64(9007199254742001)
 test_request_envelope(&w,ns.clients[0].incarnation,ns.game.world.scene.epoch,id,REQUEST_BLAST,payload.data[:],0,30)
 net_request_server_dispatch(&ns,0,w.data[:]);result:=ns.clients[0].requests.entries[id%1024].result
 t.expect(test,result.status==.Accepted && result.event_id!=0 && result.effect_tick==1 && ns.clients[0].stats.blasts_applied==1)
 net_request_server_dispatch(&ns,0,w.data[:]);t.expect(test,ns.clients[0].stats.blasts_applied==1 && ns.clients[0].requests.entries[id%1024].result==result)
 w.data[len(w.data)-1]~=u8(1);net_request_server_dispatch(&ns,0,w.data[:])
 t.expect(test,ns.clients[0].stats.blasts_applied==1 && ns.clients[0].requests.entries[id%1024].result==result)
}
