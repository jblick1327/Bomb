package shared

// Pure server rules. Connection generations are distinct from session identities:
// resuming a session may recover its totals, but cannot revive its round body.
Game_Mode :: enum u8 { Sandbox, Elimination }
Round_State :: enum u8 { Waiting, Countdown, Playing, Finished }
Round_Death :: enum u8 { None, Blast, Bounds, Disconnect }
Round_End :: enum u8 { None, Elimination, Forfeit, Mixed }
ROUND_COUNTDOWN_TICKS :: u64(180)
ROUND_SESSION_CAPACITY :: 128

Round_Progress :: struct { level, xp_in_level, xp_to_next:u64 }
Round_Session :: struct {
 id, total_xp, wins, awarded_round:u64,
}
Round_Connection :: struct {
 session_id, generation:u64,
 connected, ready, explicit_spectator:bool,
}
Round_Player :: struct {
 session_id, generation:u64,
 slot:int,
 alive:bool,
 death:Round_Death,
 death_tick, alive_ticks, bombs_faced, xp_gained:u64,
}
Round_Controller :: struct {
 mode:Game_Mode,
 state:Round_State,
 id, countdown_tick, start_tick, end_tick, bombs_spawned:u64,
 winner:u64, // Zero means no winner, including a draw. Session IDs are nonzero.
 draw:bool,
 reason:Round_End,
 connections:[MAX_PLAYERS]Round_Connection,
 countdown_candidates:[MAX_PLAYERS]Round_Connection,
 players:[MAX_PLAYERS]Round_Player,
 sessions:[ROUND_SESSION_CAPACITY]Round_Session,
 session_count:int,
}

round_add_sat :: proc(a,b:u64)->u64 {return max(u64)-a<b?max(u64):a+b}
round_mul_sat :: proc(a,b:u64)->u64 {return a!=0 && b>max(u64)/a?max(u64):a*b}

// Cost to advance m levels is 25*m*(m+3). Compare by division to avoid
// overflowing even for the largest possible session XP value.
round_progress :: proc(xp:u64)->Round_Progress {
 lo,hi:=u64(0),u64(1)<<30
 for lo<hi {
  mid:=(lo+hi+1)/2
  if mid<=xp/25/(mid+3) {lo=mid}else{hi=mid-1}
 }
 spent:=25*lo*(lo+3)
 return {lo+1,xp-spent,100+50*lo}
}

round_find_session :: proc(r:^Round_Controller,id:u64)->^Round_Session {
 if id==0 {return nil}
 for i in 0..<r.session_count {if r.sessions[i].id==id {return &r.sessions[i]}}
 return nil
}

round_connect :: proc(r:^Round_Controller,slot:int,id,generation:u64,spectator:bool=false)->bool {
 if slot<0 || slot>=MAX_PLAYERS || id==0 || generation==0 {return false}
 // Server admission validates resume credentials before calling this method.
 // One session cannot control two simultaneous connections.
 for c,i in r.connections {if c.connected && c.session_id==id && i!=slot {return false}}
 if round_find_session(r,id)==nil {
  if r.session_count==len(r.sessions) {return false}
  r.sessions[r.session_count]=Round_Session{id=id};r.session_count+=1
 }
 r.connections[slot]={session_id=id,generation=generation,connected=true,explicit_spectator=spectator}
 return true
}

round_disconnect :: proc(r:^Round_Controller,slot:int) {
 if slot>=0 && slot<MAX_PLAYERS {r.connections[slot].connected=false;r.connections[slot].ready=false}
}

round_ready :: proc(r:^Round_Controller,slot:int,generation:u64,ready:bool) {
 if slot>=0 && slot<MAX_PLAYERS && r.connections[slot].connected && r.connections[slot].generation==generation {r.connections[slot].ready=ready}
}

// Called only after a successful world rebuild, never directly on restart intent.
round_begin :: proc(r:^Round_Controller)->bool {
 if r.id==max(u64) {return false}
 r.id+=1;r.state=.Waiting;r.players={};r.countdown_candidates={};r.countdown_tick=0;r.start_tick=0;r.end_tick=0
 r.winner=0;r.draw=false;r.reason=.None;r.bombs_spawned=0
 for &c in r.connections {c.ready=false}
 return true
}

round_player_connected :: proc(r:^Round_Controller,p:Round_Player)->bool {
 if p.slot<0 || p.slot>=MAX_PLAYERS || p.session_id==0 {return false}
 c:=r.connections[p.slot]
 return c.connected && c.session_id==p.session_id && c.generation==p.generation && !c.explicit_spectator
}

// Run once before simulation. Winner selection is deliberately separate so a
// disconnect and an explosion on this tick can produce a simultaneous draw.
round_prepare_tick :: proc(r:^Round_Controller,tick:u64) {
 if r.mode!=.Elimination || r.state==.Finished || r.state==.Playing {return}
 if r.state==.Countdown {
  valid:=true
  for p in r.players {if p.session_id!=0&&(!round_player_connected(r,p) || !r.connections[p.slot].ready) {valid=false}}
  if !valid {r.state=.Waiting;r.players={};r.countdown_candidates={};r.countdown_tick=0;r.start_tick=0;return}
  // Baselines for clients already present at countdown selection can arrive on
  // adjacent ticks. Admit them before Playing without extending the countdown.
  // A new connection or resumed generation after selection remains a spectator.
  for candidate,slot in r.countdown_candidates {
   current:=r.connections[slot]
   if !candidate.connected || candidate.explicit_spectator || !current.connected || !current.ready || current.explicit_spectator || current.session_id!=candidate.session_id || current.generation!=candidate.generation {continue}
   found:=false
   for p in r.players {if p.session_id==candidate.session_id {found=true;break}}
   if found {continue}
   for &p in r.players {if p.session_id==0 {p={session_id=current.session_id,generation=current.generation,slot=slot};break}}
  }
  if tick>=r.start_tick {r.state=.Playing;for &p in r.players {p.alive=p.session_id!=0}}
  return
 }
 candidates:[MAX_PLAYERS]Round_Player;count:=0
 for c,i in r.connections {
  if c.connected && c.ready && !c.explicit_spectator && count<MAX_PLAYERS {
   candidates[count]={session_id=c.session_id,generation=c.generation,slot=i};count+=1
  }
 }
 // Capture connection generations once. Existing loading clients may finish
 // validation during countdown; later joins spectate until the next round.
 if count>=2 {
  r.players=candidates;r.countdown_candidates=r.connections;r.state=.Countdown;r.countdown_tick=tick
  r.start_tick=round_add_sat(tick,ROUND_COUNTDOWN_TICKS)
 }
}

round_award :: proc(r:^Round_Controller) {
 for &p in r.players {
  s:=round_find_session(r,p.session_id)
  if s==nil || s.awarded_round==r.id {continue}
  p.xp_gained=round_add_sat(round_mul_sat(p.bombs_faced,10),p.alive_ticks/60)
  s.total_xp=round_add_sat(s.total_xp,p.xp_gained)
  if p.session_id==r.winner {s.wins=round_add_sat(s.wins,1)}
  s.awarded_round=r.id
 }
}

// Deaths are accumulated by World at each actual detonation pose, then combined
// here with forfeits. The caller removes dead bodies only after this method.
round_finish_tick :: proc(r:^Round_Controller,tick:u64,deaths:[MAX_PLAYERS]Round_Death,bombs_spawned:u64) {
 if r.mode!=.Elimination || r.state!=.Playing {return}
 r.bombs_spawned=round_add_sat(r.bombs_spawned,bombs_spawned)
 alive:=0;winner:=u64(0)
 for &p in r.players {
  if !p.alive {continue}
  death:=deaths[p.slot]
  if !round_player_connected(r,p) {death=.Disconnect}else{
   p.alive_ticks=round_add_sat(p.alive_ticks,1)
   p.bombs_faced=round_add_sat(p.bombs_faced,bombs_spawned)
  }
  if death!=.None {p.alive=false;p.death=death;p.death_tick=tick}else{alive+=1;winner=p.session_id}
 }
 if alive>1 {return}
 r.state=.Finished;r.end_tick=tick;r.winner=winner;r.draw=alive==0;r.reason=.Elimination
 disconnected,other:=false,false
 for p in r.players {if p.death==.Disconnect {disconnected=true}else if p.death!=.None {other=true}}
 if disconnected {r.reason=other?.Mixed:.Forfeit}
 round_award(r)
}

// Upright native player capsule: segment +/- PLAYER_SEGMENT plus PLAYER_RADIUS.
// The expanded-radius distance test includes the boundary and avoids sqrt.
round_capsule_hit :: proc(center,blast:Vec2,lethal_radius:f32)->bool {
 if !finite(center.x) || !finite(center.y) || !finite(blast.x) || !finite(blast.y) || !finite(lethal_radius) || lethal_radius<0 {return false}
 nearest:=Vec2{center.x,clamp(blast.y,center.y-PLAYER_SEGMENT,center.y+PLAYER_SEGMENT)}
 delta:=vsub(blast,nearest);radius:=lethal_radius+PLAYER_RADIUS
 return f64(delta.x)*f64(delta.x)+f64(delta.y)*f64(delta.y)<=f64(radius)*f64(radius)
}
