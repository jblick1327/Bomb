package shared
import nc "../netcode"
import "core:fmt"

NET_APP_ROUND :: u8(0xCA)
NET_APP_READY :: u8(0xCB)
ROUND_RULES_VERSION :: u32(2)

Round_Connection_View :: struct {
 session_id,generation,total_xp,wins:u64,
 connected,ready,spectator,restart_allowed:bool,
 progress:Round_Progress,
}
Round_Snapshot :: struct {
 epoch:u32,
 rules_version:u32,
 tick,id,countdown_tick,start_tick,end_tick,bombs_spawned,winner:u64,
 mode:Game_Mode,
 state:Round_State,
 draw:bool,
 reason:Round_End,
 lethal_radius:f32,
 players:[MAX_PLAYERS]Round_Player,
 connections:[MAX_PLAYERS]Round_Connection_View,
}

round_snapshot :: proc(ns:^Net_Server)->Round_Snapshot {
 r:=&ns.rounds
 result:=Round_Snapshot{epoch=ns.game.world.scene.epoch,rules_version=ROUND_RULES_VERSION,
  tick=ns.tick,id=r.id,countdown_tick=r.countdown_tick,start_tick=r.start_tick,end_tick=r.end_tick,
  bombs_spawned=r.bombs_spawned,winner=r.winner,mode=r.mode,state=r.state,draw=r.draw,reason=r.reason,
  lethal_radius=ns.game.world.settings.blast_radius,players=r.players}
 for c,i in r.connections {
  v:=&result.connections[i]
  v.session_id=c.session_id;v.generation=c.generation;v.connected=c.connected;v.ready=c.ready
  v.spectator=!round_server_can_play(ns,i)
  v.restart_allowed=ns.clients[i].active && ns.clients[i].is_host && !net_rebuild_pending(ns) && (r.mode==.Sandbox || r.state==.Finished)
  if s:=round_find_session(r,c.session_id);s!=nil {v.total_xp=s.total_xp;v.wins=s.wins;v.progress=round_progress(s.total_xp)}
 }
 return result
}

round_encode :: proc(w:^nc.Writer,s:Round_Snapshot) {
 nc.write_u8(w,NET_APP_ROUND);nc.write_u32(w,s.epoch);nc.write_u32(w,s.rules_version)
 nc.write_u64(w,s.tick);nc.write_u64(w,s.id);nc.write_u64(w,s.countdown_tick);nc.write_u64(w,s.start_tick);nc.write_u64(w,s.end_tick)
 nc.write_u64(w,s.bombs_spawned);nc.write_u64(w,s.winner)
 nc.write_u8(w,u8(s.mode));nc.write_u8(w,u8(s.state));nc.write_bool(w,s.draw);nc.write_u8(w,u8(s.reason));nc.write_f32(w,s.lethal_radius)
 for p in s.players {
  nc.write_u64(w,p.session_id);nc.write_u64(w,p.generation);nc.write_u8(w,u8(p.slot));nc.write_bool(w,p.alive);nc.write_u8(w,u8(p.death))
  nc.write_u64(w,p.death_tick);nc.write_u64(w,p.alive_ticks);nc.write_u64(w,p.bombs_faced);nc.write_u64(w,p.xp_gained)
 }
 for c in s.connections {
  nc.write_u64(w,c.session_id);nc.write_u64(w,c.generation);nc.write_u64(w,c.total_xp);nc.write_u64(w,c.wins)
  nc.write_bool(w,c.connected);nc.write_bool(w,c.ready);nc.write_bool(w,c.spectator);nc.write_bool(w,c.restart_allowed)
  nc.write_u64(w,c.progress.level);nc.write_u64(w,c.progress.xp_in_level);nc.write_u64(w,c.progress.xp_to_next)
 }
}

round_decode :: proc(data:[]u8)->(s:Round_Snapshot,ok:bool) {
 if len(data)>1000 {return}
 r:nc.Reader;nc.reader_init(&r,data)
 if nc.read_u8(&r)!=NET_APP_ROUND {return}
 s.epoch=nc.read_u32(&r);s.rules_version=nc.read_u32(&r)
 s.tick=nc.read_u64(&r);s.id=nc.read_u64(&r);s.countdown_tick=nc.read_u64(&r);s.start_tick=nc.read_u64(&r);s.end_tick=nc.read_u64(&r)
 s.bombs_spawned=nc.read_u64(&r);s.winner=nc.read_u64(&r)
 mode:=nc.read_u8(&r);state:=nc.read_u8(&r);s.draw=nc.read_bool(&r);reason:=nc.read_u8(&r);s.lethal_radius=nc.read_f32(&r)
 if mode>u8(Game_Mode.Elimination) || state>u8(Round_State.Finished) || reason>u8(Round_End.Mixed) {return {},false}
 s.mode=Game_Mode(mode);s.state=Round_State(state);s.reason=Round_End(reason)
 for &p in s.players {
  p.session_id=nc.read_u64(&r);p.generation=nc.read_u64(&r);p.slot=int(nc.read_u8(&r));p.alive=nc.read_bool(&r);death:=nc.read_u8(&r)
  if death>u8(Round_Death.Disconnect) || p.slot>=MAX_PLAYERS {return {},false}
  p.death=Round_Death(death)
  p.death_tick=nc.read_u64(&r);p.alive_ticks=nc.read_u64(&r);p.bombs_faced=nc.read_u64(&r);p.xp_gained=nc.read_u64(&r)
 }
 for &c in s.connections {
  c.session_id=nc.read_u64(&r);c.generation=nc.read_u64(&r);c.total_xp=nc.read_u64(&r);c.wins=nc.read_u64(&r)
  c.connected=nc.read_bool(&r);c.ready=nc.read_bool(&r);c.spectator=nc.read_bool(&r);c.restart_allowed=nc.read_bool(&r)
  c.progress.level=nc.read_u64(&r);c.progress.xp_in_level=nc.read_u64(&r);c.progress.xp_to_next=nc.read_u64(&r)
  if c.session_id!=0 && c.progress!=round_progress(c.total_xp) {return {},false}
 }
 ok=r.ok && r.pos==len(data) && s.rules_version==ROUND_RULES_VERSION && finite(s.lethal_radius) && s.lethal_radius>=0 && s.lethal_radius<=100
 return
}

round_server_broadcast :: proc(ns:^Net_Server) {
 if !ns.real_gate || (!ns.round_dirty && ns.tick%60!=0) {return}
 ns.round_dirty=false
 w:nc.Writer;nc.writer_init(&w,768);defer nc.writer_destroy(&w)
 round_encode(&w,round_snapshot(ns))
 for c,i in ns.clients {if c.active {_=nc.server_send_reliable(&ns.srv,i,w.data[:])}}
}

round_client_accept :: proc(c:^Net_Client,data:[]u8) {
 s,ok:=round_decode(data);if !ok {return}
 if c.has_round && (s.id<c.round_snapshot.id || s.epoch<c.round_snapshot.epoch || s.tick<c.round_snapshot.tick) {return}
 if !c.has_round || s.id!=c.round_snapshot.id || s.state!=c.round_snapshot.state || s.epoch!=c.round_snapshot.epoch {
  fmt.printf("ROUND SNAPSHOT id=%d epoch=%d state=%v tick=%d winner=%d draw=%t\n",s.id,s.epoch,s.state,s.tick,s.winner,s.draw)
 }
 c.round_snapshot=s;c.has_round=true
}

round_client_ready :: proc(c:^Net_Client) {
 if !c.real_gate || !c.real_hello_ok || !c.has_epoch || c.real_reason!="" || !c.input_link.has_offer || c.ready_epoch==c.epoch {return}
 // Shared native code confirms the fully validated baseline/catalog, independent
 // of whether the frontend requests optional diagnostic hash reports.
 data:=canonical_encode(&c.received.scene);defer delete(data)
 w:nc.Writer;nc.writer_init(&w,64);defer nc.writer_destroy(&w)
 nc.write_u8(&w,NET_APP_READY);nc.write_u64(&w,c.input_link.offer.identity.incarnation)
 nc.write_u32(&w,c.received.scene.epoch);nc.write_u64(&w,c.received.scene.structure_revision);nc.write_u64(&w,repl_hash(data))
 if nc.client_send_reliable(&c.nc_client,w.data[:]) {c.ready_epoch=c.epoch}
}

round_server_ready :: proc(ns:^Net_Server,index:int,data:[]u8) {
 r:nc.Reader;nc.reader_init(&r,data);_=nc.read_u8(&r)
 generation:=nc.read_u64(&r);epoch:=nc.read_u32(&r);revision:=nc.read_u64(&r);hash:=nc.read_u64(&r)
 if !r.ok || r.pos!=len(data) || generation!=ns.clients[index].incarnation || epoch!=ns.game.world.scene.epoch {return}
 expected,found:=ns.hashes[net_hash_key(epoch,revision)]
 if !found && revision==ns.game.world.scene.structure_revision {bytes:=canonical_encode(&ns.game.world.scene);expected=repl_hash(bytes);delete(bytes);found=true}
 if found && hash==expected {round_ready(&ns.rounds,index,generation,true);ns.round_dirty=true}
}
