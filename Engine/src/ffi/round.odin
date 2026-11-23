package ffi
import core "../shared"

// Borrowed arrays follow the same acquired-sample lifetime as poses/topology.
// The managed frontend must copy them before release; no protocol bytes escape.
@(export)
bom_client_get_round :: proc "c" (handle,sample_sequence:u64,info:^BomRoundInfo)->u32 {
 s,status,held:=enter(handle);if status!=OK {return status};defer leave(s,held);context=s.ctx
 if !s.acquired || sample_sequence!=s.sample_sequence {return BAD_ARGUMENT}
 if info==nil || info.struct_size<u32(size_of(BomRoundInfo)) || info.version!=1 {return BAD_ARGUMENT}
 if !s.client.has_round {info^=BomRoundInfo{struct_size=u32(size_of(BomRoundInfo)),version=1};return OK}
 r:=s.client.round_snapshot
 player_count:=0
 for p in r.players {
  if p.session_id==0 {continue}
  s.round_players[player_count]={session_id=p.session_id,generation=p.generation,slot=u32(p.slot),alive=p.alive?1:0,death=u32(p.death),graze_count=p.graze_count,death_tick=p.death_tick,alive_ticks=p.alive_ticks,bombs_faced=p.bombs_faced,xp_gained=p.xp_gained,coins=p.coins,effects=u32(p.effects),invincible_end_tick=p.invincible_end_tick,speed_end_tick=p.speed_end_tick}
  player_count+=1
 }
 for c,i in r.connections {
  flags:=u32(0);if c.connected {flags|=1};if c.ready {flags|=2};if c.spectator {flags|=4};if c.restart_allowed {flags|=8}
  s.round_connections[i]={session_id=c.session_id,generation=c.generation,total_xp=c.total_xp,wins=c.wins,level=c.progress.level,xp_in_level=c.progress.xp_in_level,xp_to_next=c.progress.xp_to_next,flags=flags}
 }
 flags:=u32(1);local:=u64(0);index:=s.client.nc_client.client_index
 if index>=0 && index<core.MAX_PLAYERS {
  c:=r.connections[index];local=c.session_id
  if c.restart_allowed {flags|=2};if c.spectator {flags|=4}
 }
 info^=BomRoundInfo{struct_size=u32(size_of(BomRoundInfo)),version=1,epoch=r.epoch,rules_version=r.rules_version,tick=r.tick,round_id=r.id,countdown_tick=r.countdown_tick,start_tick=r.start_tick,end_tick=r.end_tick,bombs_spawned=r.bombs_spawned,winner=r.winner,local_session_id=local,mode=u32(r.mode),state=u32(r.state),draw=r.draw?1:0,reason=u32(r.reason),lethal_radius=r.lethal_radius,flags=flags,players=raw_data(s.round_players[:]),player_count=u32(player_count),connections=raw_data(s.round_connections[:]),connection_count=core.MAX_PLAYERS,graze_radius=r.graze_radius,grazes_to_die=r.grazes_to_die}
 return OK
}

@(export)
bom_client_set_join_options :: proc "c" (handle:u64,flags:u32)->u32 {
 s,status,held:=enter(handle);if status!=OK {return status};defer leave(s,held);context=s.ctx
 if s.acquired || s.live {return BUSY}
 if flags>1 {return BAD_ARGUMENT}
 s.join_spectator=flags==1
 return OK
}
