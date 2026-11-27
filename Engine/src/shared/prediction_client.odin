package shared
import math "core:math"
import fmt "core:fmt"

Prediction_Mode :: enum u32 { Disabled, Predicting, Conservative, Warming }
// Conservative (Dynamic_History_Required) -> Predicting needs this many
// consecutive successful updates, so a transient history gap cannot flip the
// mode every few ticks. Other reasons clear deterministically and recover at once.
PREDICTION_RECOVER_UPDATES :: u64(12)
// Mode changes and corrections blend through visual_offset's 100 ms decay. Only a
// jump larger than this (respawn-sized) is presented as a snap.
PREDICTION_BLEND_LIMIT :: f32(3)
// A moving loose piece or rubber cell near the player makes a replay uncertain
// (Dynamic_History_Required). Switching the drawn player to the interpolated authority
// then moves it back by lead+delay ticks of motion (about 1.5 m at full speed) and
// forward again on recovery. While an unbroken prediction is younger than
// PREDICTION_ESTIMATE_SECONDS past its last certain update, the replay instead uses
// proxy estimates within PREDICTION_ESTIMATE_TOLERANCE and stays on screen; the status
// still reports Conservative, and any error is blended like other corrections.
PREDICTION_ESTIMATE_SECONDS :: f64(.5)
PREDICTION_ESTIMATE_TOLERANCE :: f32(.75)
// A schedule reset (round start, respawn, lead correction) leaves no owner state for the
// commands being issued until the server accepts the new schedule and reports on it, about
// one and a half round trips. For up to this long past the last certain update, the
// presented prediction keeps stepping with those commands (prediction_bridge) instead of
// dropping to the interpolated authority; the first new owner state blends any difference.
PREDICTION_BRIDGE_SECONDS :: f64(.75)
PREDICTION_BRIDGE_GAP :: u64(8) // most ticks a bridge update may step
Prediction_Record :: struct { valid:bool, identity:Input_Identity, tick:u64, position:Vec2 }
Prediction_Controller :: struct {
 world:Static_Prediction,
 hulls:Prediction_Hull_Cache,
 mode:Prediction_Mode,
 reason:Prediction_Reason,
 identity:Input_Identity,
 last_owner_tick,last_teleport:u64,
 has_owner:bool,
 visual_offset:Vec2,
 // The own-player position last presented, and what it was presented over: the
 // predicted world or the interpolated authority. A change of source re-bases
 // visual_offset so the drawn position stays continuous.
 presented,presented_base:Vec2,
 presented_serial:u64,
 has_presented,presented_predicted:bool,
 // Sub-tick presentation: the own player is drawn between step_from (where it was one
 // tick before step_tick, on the current trajectory) and the world's position at
 // step_tick, so it moves as smoothly as the interpolated world instead of in 60 Hz steps.
 step_from:Vec2,
 step_tick:u64,
 has_step:bool,
 // The last update ended with a valid predicted world at the target tick.
 world_ok:bool,
 // The presented world was replayed with estimated proxies (see PREDICTION_ESTIMATE_SECONDS),
 // or is certain again but still in the recovery dwell of an estimated episode.
 estimated:bool,
 certain_at:f64,
 estimated_updates:u64,
 recover_streak:u64,
 records:[256]Prediction_Record,
 correction_histogram:[2001]u64,
 corrections,snaps,conservative_transitions,recoveries,reset_count:u64,
 correction_max:f32,
 conservative_seconds:f64,
 last_update:f64,
}
prediction_controller_destroy :: proc(p:^Prediction_Controller) { if p!=nil { prediction_static_destroy(&p.world);prediction_hull_cache_destroy(&p.hulls);free(p) } }
prediction_controller_reset :: proc(c:^Net_Client) {
 p:=c.prediction;if p==nil { return }
 prediction_static_destroy(&p.world);p.visual_offset={};p.has_owner=false;p.last_owner_tick=0;p.records={};p.mode=.Warming;p.reset_count+=1
 p.has_presented=false;p.world_ok=false;p.recover_streak=0;p.has_step=false;p.estimated=false
}
prediction_set_mode :: proc(p:^Prediction_Controller,mode:Prediction_Mode,reason:Prediction_Reason) {
 if mode!=.Predicting { p.world_ok=false;p.recover_streak=0 }
 // visual_offset is re-based by net_prediction_apply, never zeroed here.
 if p.mode==mode && p.reason==reason { return }
 if mode==.Conservative && p.mode!=.Conservative { p.conservative_transitions+=1 }
 if mode==.Predicting && p.mode==.Conservative { p.recoveries+=1 }
 fmt.printf("PREDICTION mode=%v reason=%v tick=%d\n",mode,reason,p.world.state_tick)
 p.mode=mode;p.reason=reason
}
prediction_quantile :: proc(p:^Prediction_Controller,percent:u64) -> f32 {
 if p==nil || p.corrections==0 { return 0 }
 needed:=(p.corrections*percent+99)/100;count:=u64(0)
 for n,i in p.correction_histogram { count+=n;if count>=needed { if i==2000 { return p.correction_max };return f32(i)/1000 } }
 return p.correction_max
}
// Bombs are authoritative dynamic bodies. Until their proxy contacts are
// validated, a bomb in the swept prediction neighborhood selects conservative
// mode rather than silently omitting an imminent capsule/bomb collision.
prediction_bomb_uncertain :: proc(c:^Net_Client,owner:Owner_State,target:u64) -> bool {
 h:=&c.collision_history;if !h.has_frame { return false }
 frame:=&h.frames[h.newest%PREDICTION_HISTORY_TICKS];if !frame.valid { return true }
 horizon:=f32(target-owner.state_tick)/60
 tuning:=PLAYER_TUNING;gravity:=f32(9.8);topology:=collision_history_topology(h,owner.state_tick,owner.topology_revision)
 if topology!=nil {config:=scene_gameplay_config(&topology.scene);tuning=config.player;gravity=math.abs(config.gravity.y)}
 gravity*=tuning.gravity_scale
 if owner.speed_ticks>0 && owner.speed_effect==.Boost {tuning.speed*=ITEM_TUNING.boost_scale}
 margin_x:=PLAYER_RADIUS+BOMB_RADIUS+.5+max(tuning.speed,math.abs(owner.velocity.x))*horizon
 margin_y:=PLAYER_HALF_HEIGHT+BOMB_RADIUS+.5+max(f32(20),tuning.jump_speed,math.abs(owner.velocity.y)+gravity*horizon)*horizon
 for key,pose in frame.poses {
  if key_kind(key)!=.Bomb { continue }
  if math.abs(pose_dq_pos(pose.x)-owner.position.x)<margin_x && math.abs(pose_dq_pos(pose.y)-owner.position.y)<margin_y { return true }
  future,_,valid:=collision_history_pose(h,target,key)
  if !valid { return true }
  if math.abs(future.x-owner.position.x)<margin_x && math.abs(future.y-owner.position.y)<margin_y { return true }
 }
 return false
}
net_prediction_update :: proc(c:^Net_Client,now:f64) {
 if !c.real_gate { return }
 if c.prediction==nil { c.prediction=new(Prediction_Controller) }
 p:=c.prediction
 elapsed:=clamp(now-p.last_update,0,.25);p.last_update=now
 if p.mode==.Conservative { p.conservative_seconds+=elapsed }
 p.visual_offset=vmul(p.visual_offset,f32(math.exp(-elapsed/.1)))
 // Every path that does not set it again falls back to the interpolated authority.
 was_estimated:=p.estimated;p.estimated=false
 presenting:=p.mode==.Predicting || was_estimated
 allow_estimate:=presenting && now-p.certain_at<=PREDICTION_ESTIMATE_SECONDS
 uncertain:=false
 if !c.prediction_enabled { prediction_set_mode(p,.Disabled,.None);return }
 link:=&c.input_link
 if c.has_round && c.round_snapshot.mode==.Elimination {
  index:=c.nc_client.client_index
  if c.round_snapshot.state!=.Playing || index<0 || index>=MAX_PLAYERS || c.round_snapshot.connections[index].spectator {
   prediction_set_mode(p,.Conservative,.Round_Inactive);return
  }
  if !link.has_owner || link.owner.state_tick<c.round_snapshot.start_tick {
   if prediction_bridge(c,p,now,presenting) { return }
   prediction_set_mode(p,.Conservative,.Round_Inactive);return
  }
 }
 if !link.active || !link.has_owner {
  if prediction_bridge(c,p,now,presenting) { return }
  prediction_set_mode(p,.Warming,.Uninitialized);return
 }
 owner:=link.owner;history:=&link.history;target:=history.next_tick-1
 // The client's newest command is older than the server's owner state (this client stalled, or its schedule is
 // catching up): hold the presented prediction through the bridge instead of dropping back to the authority, which
 // drew the player several ticks behind and then forward again (movement stutter, 2026-11-27).
 if target<owner.state_tick {
  if prediction_bridge(c,p,now,presenting) { return }
  prediction_set_mode(p,.Conservative,.Missing_Command);return
 }
 bridged:=false;bridge_pos,bridge_from:Vec2;bridge_has_from:=false
 if !p.has_owner || p.identity!=owner.identity || p.last_teleport!=owner.teleport_serial {
  // The first owner state after a bridged reset: continue from the bridged world, one tick
  // ahead if needed, so the replay below blends the difference instead of snapping.
  if was_estimated && p.world_ok && p.has_owner && p.last_teleport==owner.teleport_serial && p.world.active && p.world.epoch==owner.identity.epoch {
   if p.world.state_tick+1==target { bridge_from,bridge_has_from=prediction_bridge_step(c,p,target) }
   else if p.world.state_tick==target { bridge_from=p.step_from;bridge_has_from=p.has_step && p.step_tick==target }
   bridged=p.world.state_tick==target && p.world.reason==.None
   bridge_pos=p.world.player.pose.position
  }
  // A schedule generation changes command identity, not collision geometry.
  // Keep the revision/epoch checked world; replay restores every player field
  // from the new owner before another step. Rebuilding here can turn a single
  // slow topology build into repeated stalls and schedule renegotiations.
  // A teleport is a real discontinuity; a new schedule generation is not.
  if p.last_teleport!=owner.teleport_serial { p.visual_offset={};p.has_presented=false }
  p.last_owner_tick=0;p.records={};p.mode=.Warming;p.reset_count+=1;p.world_ok=false;p.recover_streak=0
  p.world.identity={};p.world.state_tick=0;p.world.last_jump_edge=0
  p.identity=owner.identity;p.last_teleport=owner.teleport_serial;p.has_owner=true
 }
 topology:=collision_history_topology(&c.collision_history,owner.state_tick,owner.topology_revision)
 if topology==nil { prediction_set_mode(p,.Conservative,.Wrong_Revision);return }
 if prediction_bomb_uncertain(c,owner,target) { prediction_set_mode(p,.Conservative,.Bomb_Contact_Uncertain);return }
 if !p.world.active || p.world.revision!=owner.topology_revision || p.world.epoch!=owner.identity.epoch || p.world.has_region&&!prediction_region_contains(p.world.region,owner.position,3) {
  region:Level_Bounds;window:^Level_Bounds
  if len(topology.scene.subdivisions)>2048 {region={vsub(owner.position,{8,8}),vadd(owner.position,{8,8})};window=&region}
  if !prediction_static_build(&p.world,&topology.scene,true,window,&p.hulls) { prediction_set_mode(p,.Conservative,p.world.reason);return }
 }
 old_position:Vec2;has_old:=false
 // Where the player was one tick before target on the presented trajectory.
 from:Vec2;has_from:=false
 if bridged { old_position=bridge_pos;has_old=true;from=bridge_from;has_from=bridge_has_from }
 if p.world_ok && p.world.identity==owner.identity {
  if p.world.state_tick+1==target {
   slot:=history.slots[target%INPUT_HISTORY]
   if slot.occupied && slot.command.target_tick==target {
    from=p.world.player.pose.position
    has_from=prediction_world_step(&p.world,slot.command,&c.collision_history)
    if !has_from && allow_estimate && p.world.reason==.Dynamic_History_Required {
     has_from=prediction_world_step(&p.world,slot.command,&c.collision_history,tolerance=PREDICTION_ESTIMATE_TOLERANCE);uncertain=has_from
    }
   }
  } else if p.world.state_tick==target && p.has_step && p.step_tick==target { from=p.step_from;has_from=true }
  if p.world.state_tick==target && p.world.reason==.None { old_position=p.world.player.pose.position;has_old=true }
 }
 if p.last_owner_tick!=owner.state_tick || !has_old {
  if !has_old || !presenting { has_from=false }
  // The replay starts again from the owner: only its own result decides certainty.
  uncertain=false
  replayed:=prediction_static_replay(&p.world,owner,history,&c.collision_history)
  if !replayed && allow_estimate && p.world.reason==.Dynamic_History_Required {
   replayed=prediction_static_replay(&p.world,owner,history,&c.collision_history,PREDICTION_ESTIMATE_TOLERANCE);uncertain=replayed
  }
  // A gap in this client's own command history: the server ran those ticks neutral, so replay them neutral as an
  // estimate rather than dropping back to the authority (2026-11-27).
  if !replayed && allow_estimate && p.world.reason==.Missing_Command {
   replayed=prediction_static_replay(&p.world,owner,history,&c.collision_history,PREDICTION_ESTIMATE_TOLERANCE,fill_missing=true);uncertain=replayed
  }
  if !replayed { prediction_set_mode(p,.Conservative,p.world.reason);return }
  if p.last_owner_tick!=owner.state_tick {
   record:=p.records[owner.state_tick%256]
   if record.valid && record.identity==owner.identity && record.tick==owner.state_tick {
    correction:=vlen(vsub(record.position,owner.position));p.correction_max=max(p.correction_max,correction)
    p.corrections+=1;p.correction_histogram[int(math.ceil(f64(min(correction,2))*1000))]+=1
   }
  }
  if has_old && presenting {
   offset:=vsub(old_position,p.world.player.pose.position)
   p.visual_offset=vadd(p.visual_offset,offset)
   // The corrected trajectory starts where the old one was drawn: shift step_from with the offset.
   from=vsub(from,offset)
   if vlen(p.visual_offset)>PREDICTION_BLEND_LIMIT { p.visual_offset={};has_from=false }
   if vlen(offset)>=.25 { p.snaps+=1;fmt.printf("PREDICTION SNAP reason=gross_correction distance=%.6f tick=%d\n",vlen(offset),target) }
  }
  p.last_owner_tick=owner.state_tick
 }
 p.records[target%256]={true,owner.identity,target,p.world.player.pose.position}
 p.step_tick=target;p.step_from=has_from ? from : p.world.player.pose.position;p.has_step=true
 p.world_ok=true
 if uncertain {
  prediction_set_mode(p,.Conservative,.Dynamic_History_Required)
  p.world_ok=true;p.estimated=true;p.estimated_updates+=1;return
 }
 p.certain_at=now
 if p.mode==.Conservative && p.reason==.Dynamic_History_Required {
  p.recover_streak+=1
  // An estimated episode keeps presenting the (now certain) world through the dwell.
  if p.recover_streak<PREDICTION_RECOVER_UPDATES { p.estimated=was_estimated;return }
 }
 p.recover_streak=0
 prediction_set_mode(p,.Predicting,.None)
}
// Steps the presented world one tick with the link's command for that tick, or neutral
// when there is none (the server runs a fenced tick neutral too).
prediction_bridge_step :: proc(c:^Net_Client,p:^Prediction_Controller,tick:u64) -> (from:Vec2,ok:bool) {
 command:=Scheduled_Command{target_tick=tick}
 slot:=c.input_link.history.slots[tick%INPUT_HISTORY]
 if c.input_link.history.accepted && slot.occupied && slot.command.target_tick==tick { command=slot.command }
 from=p.world.player.pose.position
 ok=prediction_world_step(&p.world,command,&c.collision_history,tolerance=PREDICTION_ESTIMATE_TOLERANCE)
 return
}
// A schedule reset is pending (see PREDICTION_BRIDGE_SECONDS). Returns false when the
// caller should fall back to the interpolated authority as before.
prediction_bridge :: proc(c:^Net_Client,p:^Prediction_Controller,now:f64,presenting:bool) -> bool {
 link:=&c.input_link
 if !presenting || !p.world_ok || !p.world.active || p.world.epoch!=c.epoch || now-p.certain_at>PREDICTION_BRIDGE_SECONDS { return false }
 // Until the next proposal's history begins, hold the presented position.
 target:=p.world.state_tick
 if link.history.accepted && link.history.next_tick>link.history.first_tick { target=max(target,link.history.next_tick-1) }
 if target-p.world.state_tick>PREDICTION_BRIDGE_GAP { return false }
 from:=p.world.player.pose.position;has_from:=p.has_step && p.step_tick==target
 if has_from { from=p.step_from }
 for p.world.state_tick<target {
  ok:bool
  from,ok=prediction_bridge_step(c,p,p.world.state_tick+1)
  if !ok { return false }
 }
 p.step_tick=target;p.step_from=from;p.has_step=true
 prediction_set_mode(p,.Warming,.Uninitialized)
 p.world_ok=true;p.estimated=true;p.estimated_updates+=1
 return true
}
// The own player is drawn from the predicted world while Predicting and from the
// interpolated authority otherwise, plus visual_offset either way. When the
// source changes, the offset is re-based to the last presented position and then
// decays (100 ms), so a mode change blends instead of snapping.
net_prediction_apply :: proc(c:^Net_Client) {
 p:=c.prediction
 if p==nil { return }
 if !c.prediction_enabled { p.has_presented=false;return }
 key:=ent_key(.Player,u64(c.nc_client.client_index))
 predicted:=(p.mode==.Predicting || p.estimated) && p.world.epoch==c.epoch
 drawn,exists:=c.drawn[key]
 base:Vec2
 if predicted {
  base=p.world.player.pose.position;drawn={}
  // present_lag is 1 - the frame's fraction of the current tick (0 outside fractional presentation).
  if p.has_step && p.step_tick==p.world.state_tick && c.present_lag>0 { base=vadd(base,vmul(vsub(p.step_from,base),f32(min(c.present_lag,1)))) }
 }
 else {
  if !exists { p.has_presented=false;return }
  base={drawn.x,drawn.y}
  // Apply can run twice on one interpolation; drawn then already has the offset.
  if p.has_presented && !p.presented_predicted && p.presented_serial==c.drawn_serial { base=p.presented_base }
 }
 if p.has_presented && p.presented_predicted!=predicted {
  p.visual_offset=vsub(p.presented,base)
  if vlen(p.visual_offset)>PREDICTION_BLEND_LIMIT { p.visual_offset={} }
 }
 position:=vadd(base,p.visual_offset)
 drawn.x=position.x;drawn.y=position.y;c.drawn[key]=drawn
 p.presented=position;p.presented_base=base;p.presented_serial=c.drawn_serial
 p.has_presented=true;p.presented_predicted=predicted
}
