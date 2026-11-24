package shared
import "core:crypto"
import "core:fmt"

Round_Credentials :: struct { server:[16]u8, session:u64, secret:[16]u8 }
Round_Admission :: struct { server:[16]u8, secrets:[ROUND_SESSION_CAPACITY][16]u8 }

round_server_identity :: proc(ns:^Net_Server) {
 if crypto.is_zero_constant_time(ns.round_admission.server[:])==1 {crypto.rand_bytes(ns.round_admission.server[:])}
}
round_server_admit :: proc(ns:^Net_Server,slot:int,credential:Round_Credentials,spectator:bool)->string {
 resume:=credential
 round_server_identity(ns)
 session:=u64(0)
 if credential.session!=0 && credential.server==ns.round_admission.server {
  found:=false
  for s,i in ns.rounds.sessions[:ns.rounds.session_count] {
   if s.id==credential.session {
    if crypto.compare_constant_time(ns.round_admission.secrets[i][:],resume.secret[:])!=1 {return "invalid session resume credentials"}
    session=s.id;found=true;break
   }
  }
  if !found {return "session resume identity not found"}
 }
 if session==0 {
  if ns.rounds.session_count==ROUND_SESSION_CAPACITY {return "session capacity reached; restart the local server"}
  // Monotonic server-local identity; the random per-session secret authorizes resume.
  session=u64(ns.rounds.session_count+1)
 }
 if !round_connect(&ns.rounds,slot,session,ns.clients[slot].incarnation,spectator) {return "session is already connected or capacity reached"}
 row:=ns.rounds.session_count-1
 for s,i in ns.rounds.sessions[:ns.rounds.session_count] {if s.id==session {row=i;break}}
 if crypto.is_zero_constant_time(ns.round_admission.secrets[row][:])==1 {crypto.rand_bytes(ns.round_admission.secrets[row][:])}
 ns.clients[slot].round_credentials={ns.round_admission.server,session,ns.round_admission.secrets[row]}
 return ""
}

round_server_can_play :: proc(ns:^Net_Server,slot:int)->bool {
 if ns.rounds.mode==.Sandbox {return ns.clients[slot].active && !ns.rounds.connections[slot].explicit_spectator}
 r:=&ns.rounds
 if r.state==.Waiting {
  c:=r.connections[slot]
  if !c.connected || c.explicit_spectator {return false}
  count:=0
  for other,i in r.connections {if other.connected && !other.explicit_spectator {if i==slot {return count<MAX_PLAYERS};count+=1}}
  return false
 }
 for p in r.players {if p.slot==slot && round_player_connected(r,p) {return r.state==.Countdown || p.alive}}
 return false
}

round_server_sync_bodies :: proc(ns:^Net_Server) {
 for i in 0..<MAX_PLAYERS {
  if round_server_can_play(ns,i) {
   if !ns.game.world.players[i].active {_=world_add_player(&ns.game.world,i)}
  }else{_=world_remove_player(&ns.game.world,i)}
 }
}

round_server_after_rebuild :: proc(ns:^Net_Server) {
 if ns.round_mode_pending {ns.rounds.mode=ns.round_next_mode;ns.round_mode_pending=false}
 if ns.rounds.mode==.Elimination {
  _=round_begin(&ns.rounds)
  ns.game.world.settings.blast_mode=.Falling_Bombs
  // Falling bomb physics, radius, fuse and deterministic stream stay native.
  bomb_rain_reset(&ns.game.world.rain,ns.game.world.settings.seed,scene_gameplay_config(&ns.game.world.scene),true)
  item_rain_reset(&ns.game.world.items,ns.game.world.settings.seed)
 }
 ns.game.world.elimination_playing=false
 round_server_sync_bodies(ns)
 ns.round_dirty=true
}

round_server_prepare :: proc(ns:^Net_Server) {
 if ns.rounds.mode!=.Elimination {return}
 old:=ns.rounds.state
 old_players:=ns.rounds.players
 round_prepare_tick(&ns.rounds,ns.tick+1)
 if old!=ns.rounds.state || old_players!=ns.rounds.players {ns.round_dirty=true}
 round_server_sync_bodies(ns)
 ns.game.world.elimination_playing=ns.rounds.state==.Playing
 // A new schedule fences all held pre-countdown input. It is accepted by the
 // same native input machinery; Unity does not retarget old movement/jumps.
 if old!=.Playing && ns.rounds.state==.Playing {
  for i in 0..<MAX_PLAYERS {if ns.clients[i].active {net_scheduled_server_offer(ns,i)}}
 }
}

round_server_finish :: proc(ns:^Net_Server,events:Tick_Events) {
 if ns.rounds.mode!=.Elimination {return}
 old:=ns.rounds.state
 if old==.Playing {
  for &p in ns.rounds.players {
   if !p.alive || !ns.game.world.players[p.slot].active {continue}
   count:=ns.game.world.players[p.slot].graze_count
   if count!=p.graze_count {p.graze_count=count;ns.round_dirty=true}
   if round_player_sync_items(&p,&ns.game.world.players[p.slot],ns.tick+1) {ns.round_dirty=true}
  }
 }
 round_finish_tick(&ns.rounds,ns.tick+1,events.deaths,events.bombs_spawned)
 // Effects are reported only for living players in a playing round; coins stay.
 for &p in ns.rounds.players {
  if (p.alive && ns.rounds.state==.Playing) || (p.effects==0 && p.invincible_end_tick==0 && p.speed_end_tick==0) {continue}
  p.effects=0;p.invincible_end_tick=0;p.speed_end_tick=0;ns.round_dirty=true
 }
 if old!=ns.rounds.state {
  ns.round_dirty=true
  round_server_sync_bodies(ns)
  if ns.real_logging {fmt.printf("ROUND id=%d state=%v tick=%d winner=%d draw=%t reason=%v\n",ns.rounds.id,ns.rounds.state,ns.tick+1,ns.rounds.winner,ns.rounds.draw,ns.rounds.reason)}
 }
}

// Copies N4 item state after a simulated tick. End ticks are the last affected
// tick (inclusive), so they stay constant while an effect counts down and the
// reliable snapshot changes only on pickup and expiry.
round_player_sync_items :: proc(p:^Round_Player,body:^Player,tick:u64)->bool {
 effects:=u8(0);invincible_end,speed_end:=u64(0),u64(0)
 if body.invincible_ticks>0 {effects|=ROUND_EFFECT_INVINCIBLE;invincible_end=round_add_sat(tick,u64(body.invincible_ticks))}
 if body.speed_ticks>0 && body.speed_effect!=.None {
  effects|=body.speed_effect==.Boost?ROUND_EFFECT_SPEED_BOOST:ROUND_EFFECT_SLOW;speed_end=round_add_sat(tick,u64(body.speed_ticks))
 }
 if p.coins==body.coins && p.effects==effects && p.invincible_end_tick==invincible_end && p.speed_end_tick==speed_end {return false}
 p.coins=body.coins;p.effects=effects;p.invincible_end_tick=invincible_end;p.speed_end_tick=speed_end
 return true
}
