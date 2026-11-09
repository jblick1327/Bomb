package shared
import t "core:testing"
import nc "../netcode"
import b2 "vendor:box2d"

round_test_server :: proc()->Net_Server {
 game:=Headless_Game{world=round_test_world(),layout=Layout{next_identity=1}}
 ns:Net_Server;net_server_init_world(&ns,game)
 ns.real_gate=true
 for i in 0..<2 {
  net_server_join(&ns,i);_=round_server_admit(&ns,i,{},false)
 }
 ns.clients[0].is_host=true
 return ns
}

@(test)
round_server_requires_host_and_stages_mode_until_rebuilt :: proc(test:^t.T) {
 ns:=round_test_server();defer net_server_destroy(&ns)
 command:=[3]u8{NET_APP_HOST_COMMAND,NET_HOST_GAME_MODE,u8(Game_Mode.Elimination)}
 epoch:=ns.game.world.scene.epoch
 t.expect(test,net_host_apply_command(&ns,1,command[:])=="host only" && ns.rounds.mode==.Sandbox)
 t.expect(test,net_host_apply_command(&ns,0,command[:])=="" && ns.rounds.mode==.Elimination)
 t.expect(test,ns.game.world.scene.epoch==epoch+1 && ns.rounds.id==1 && ns.rounds.state==.Waiting)
 t.expect(test,ns.game.world.settings.blast_mode==.Falling_Bombs)
 restart:=[2]u8{NET_APP_HOST_COMMAND,NET_HOST_RESET}
 t.expect(test,net_host_apply_command(&ns,0,restart[:])=="round restart requires a finished round")
}

@(test)
round_server_ready_packet_checks_generation_epoch_and_real_canonical_baseline :: proc(test:^t.T) {
 ns:=round_test_server();defer net_server_destroy(&ns)
 w:nc.Writer;nc.writer_init(&w,64);defer nc.writer_destroy(&w)
 bytes:=canonical_encode(&ns.game.world.scene);defer delete(bytes)
 hash:=repl_hash(bytes)
 for hash_case in 0..<4 {
  nc.writer_reset(&w);nc.write_u8(&w,NET_APP_READY)
  nc.write_u64(&w,ns.clients[0].incarnation+(hash_case==0?u64(1):0))
  nc.write_u32(&w,ns.game.world.scene.epoch+(hash_case==1?u32(1):0))
  nc.write_u64(&w,ns.game.world.scene.structure_revision);nc.write_u64(&w,hash+(hash_case==2?u64(1):0))
  round_server_ready(&ns,0,w.data[:]);t.expect(test,ns.rounds.connections[0].ready==(hash_case==3))
 }
}

@(test)
round_snapshot_is_complete_bounded_exact_and_rejects_every_truncation :: proc(test:^t.T) {
 ns:=round_test_server();defer net_server_destroy(&ns)
 ns.rounds=round_test_playing();ns.rounds.connections[0].session_id=100
 deaths:[MAX_PLAYERS]Round_Death;deaths[1]=.Blast;round_finish_tick(&ns.rounds,240,deaths,7)
 snapshot:=round_snapshot(&ns)
 w:nc.Writer;nc.writer_init(&w,768);defer nc.writer_destroy(&w);round_encode(&w,snapshot)
 t.expect(test,len(w.data)<1000)
 copy,ok:=round_decode(w.data[:]);t.expect(test,ok && copy==snapshot)
 for length in 0..<len(w.data) {_,valid:=round_decode(w.data[:length]);t.expect(test,!valid)}
 nc.write_u8(&w,0);_,valid:=round_decode(w.data[:]);t.expect(test,!valid)
 c:Net_Client;c.has_round=true;c.round_snapshot=snapshot;c.round_snapshot.tick=999
 round_client_accept(&c,w.data[:len(w.data)-1]);t.expect(test,c.round_snapshot.tick==999)
}

@(test)
round_live_server_tick_freezes_countdown_and_finished_world_but_advances_network_time :: proc(test:^t.T) {
 ns:=round_test_server();defer net_server_destroy(&ns)
 mode:=[3]u8{NET_APP_HOST_COMMAND,NET_HOST_GAME_MODE,u8(Game_Mode.Elimination)}
 t.expect(test,net_host_apply_command(&ns,0,mode[:])=="")
 for i in 0..<2 {round_ready(&ns.rounds,i,ns.clients[i].incarnation,true)}
 for i in 0..<180 {net_server_tick(&ns,f64(i)/60)}
 t.expect(test,ns.tick==180 && ns.game.world.tick==0 && ns.rounds.state==.Countdown)
 net_server_tick(&ns,3)
 t.expect(test,ns.rounds.state==.Playing && ns.game.world.tick==1)
 // A real bounds death passes through World, not a direct rule injection.
 b2.Body_SetTransform(ns.game.world.players[1].body,{30,1},b2.MakeRot(0))
 net_server_tick(&ns,3.1)
 t.expect(test,ns.rounds.state==.Finished && ns.rounds.winner==1 && !ns.game.world.players[1].active)
 world_tick_before:=ns.game.world.tick;body_pos:=b2.Body_GetPosition(ns.game.world.players[0].body)
 for i in 0..<30 {net_server_tick(&ns,3.2+f64(i)/60)}
 t.expect(test,ns.tick==212 && ns.game.world.tick==world_tick_before && b2.Body_GetPosition(ns.game.world.players[0].body)==body_pos)
 restart:=[2]u8{NET_APP_HOST_COMMAND,NET_HOST_RESET};epoch:=ns.game.world.scene.epoch
 t.expect(test,net_host_apply_command(&ns,0,restart[:])=="" && ns.rounds.id==2 && ns.game.world.scene.epoch==epoch+1 && ns.rounds.state==.Waiting)
}

@(test)
round_resume_requires_server_secret_recovers_totals_but_cannot_resurrect :: proc(test:^t.T) {
 ns:=round_test_server();defer net_server_destroy(&ns)
 credentials:=ns.clients[1].round_credentials
 ns.rounds.sessions[1].total_xp=250;ns.rounds.mode=.Elimination
 _=round_begin(&ns.rounds)
 for i in 0..<2 {round_ready(&ns.rounds,i,ns.clients[i].incarnation,true)}
 round_prepare_tick(&ns.rounds,1);round_prepare_tick(&ns.rounds,181)
 net_server_leave(&ns,1);net_server_join(&ns,1)
 invalid:=credentials;invalid.secret[0]~=1
 t.expect(test,round_server_admit(&ns,1,invalid,false)=="invalid session resume credentials")
 t.expect(test,round_server_admit(&ns,1,credentials,false)=="")
 t.expect(test,!round_server_can_play(&ns,1) && ns.rounds.sessions[1].total_xp==250 && ns.rounds.session_count==2)
 round_finish_tick(&ns.rounds,182,{},0)
 t.expect(test,ns.rounds.players[1].death==.Disconnect && ns.rounds.winner==1)
}
