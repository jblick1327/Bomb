package shared
import math "core:math"
import fmt "core:fmt"

Prediction_Mode :: enum u32 { Disabled, Predicting, Conservative, Warming }
Prediction_Record :: struct { valid:bool, identity:Input_Identity, tick:u64, position:Vec2 }
Prediction_Controller :: struct {
 world:Static_Prediction,
 mode:Prediction_Mode,
 reason:Prediction_Reason,
 identity:Input_Identity,
 last_owner_tick,last_teleport:u64,
 has_owner:bool,
 visual_offset:Vec2,
 records:[256]Prediction_Record,
 correction_histogram:[2001]u64,
 corrections,snaps,conservative_transitions,recoveries,reset_count:u64,
 correction_max:f32,
 conservative_seconds:f64,
 last_update:f64,
}
prediction_controller_destroy :: proc(p:^Prediction_Controller) { if p!=nil { prediction_static_destroy(&p.world);free(p) } }
prediction_controller_reset :: proc(c:^Net_Client) {
 p:=c.prediction;if p==nil { return }
 prediction_static_destroy(&p.world);p.visual_offset={};p.has_owner=false;p.last_owner_tick=0;p.records={};p.mode=.Warming;p.reset_count+=1
}
prediction_set_mode :: proc(p:^Prediction_Controller,mode:Prediction_Mode,reason:Prediction_Reason) {
 if p.mode==mode && p.reason==reason { return }
 if mode==.Conservative && p.mode!=.Conservative { p.conservative_transitions+=1 }
 if mode==.Predicting && p.mode==.Conservative { p.recoveries+=1 }
 if mode!=.Predicting { p.visual_offset={} }
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
 if !c.prediction_enabled { prediction_set_mode(p,.Disabled,.None);return }
 link:=&c.input_link
 if !link.active || !link.has_owner { prediction_set_mode(p,.Warming,.Uninitialized);return }
 owner:=link.owner;history:=&link.history;target:=history.next_tick-1
 if target<owner.state_tick { prediction_set_mode(p,.Conservative,.Missing_Command);return }
 if !p.has_owner || p.identity!=owner.identity || p.last_teleport!=owner.teleport_serial {
  // A schedule generation changes command identity, not collision geometry.
  // Keep the revision/epoch checked world; replay restores every player field
  // from the new owner before another step. Rebuilding here can turn a single
  // slow topology build into repeated stalls and schedule renegotiations.
  p.visual_offset={};p.last_owner_tick=0;p.records={};p.mode=.Warming;p.reset_count+=1
  p.world.identity={};p.world.state_tick=0;p.world.last_jump_edge=0
  p.identity=owner.identity;p.last_teleport=owner.teleport_serial;p.has_owner=true
 }
 topology:=collision_history_topology(&c.collision_history,owner.state_tick,owner.topology_revision)
 if topology==nil { prediction_set_mode(p,.Conservative,.Wrong_Revision);return }
 if prediction_bomb_uncertain(c,owner,target) { prediction_set_mode(p,.Conservative,.Bomb_Contact_Uncertain);return }
 if !p.world.active || p.world.revision!=owner.topology_revision || p.world.epoch!=owner.identity.epoch || p.world.has_region&&!prediction_region_contains(p.world.region,owner.position,3) {
  region:Level_Bounds;window:^Level_Bounds
  if len(topology.scene.subdivisions)>2048 {region={vsub(owner.position,{8,8}),vadd(owner.position,{8,8})};window=&region}
  if !prediction_static_build(&p.world,&topology.scene,true,window) { prediction_set_mode(p,.Conservative,p.world.reason);return }
 }
 old_position:Vec2;has_old:=false
 if p.mode==.Predicting && p.world.identity==owner.identity {
  if p.world.state_tick+1==target {
   slot:=history.slots[target%INPUT_HISTORY]
   if slot.occupied && slot.command.target_tick==target { _=prediction_world_step(&p.world,slot.command,&c.collision_history) }
  }
  if p.world.state_tick==target && p.world.reason==.None { old_position=p.world.player.pose.position;has_old=true }
 }
 if p.last_owner_tick!=owner.state_tick || !has_old {
  if !prediction_static_replay(&p.world,owner,history,&c.collision_history) { prediction_set_mode(p,.Conservative,p.world.reason);return }
  if p.last_owner_tick!=owner.state_tick {
   record:=p.records[owner.state_tick%256]
   if record.valid && record.identity==owner.identity && record.tick==owner.state_tick {
    correction:=vlen(vsub(record.position,owner.position));p.correction_max=max(p.correction_max,correction)
    p.corrections+=1;p.correction_histogram[int(math.ceil(f64(min(correction,2))*1000))]+=1
   }
  }
  if has_old {
   offset:=vsub(old_position,p.world.player.pose.position)
   if vlen(offset)<.25 { p.visual_offset=vadd(p.visual_offset,offset) }
   else { p.visual_offset={};p.snaps+=1;fmt.printf("PREDICTION SNAP reason=gross_correction distance=%.6f tick=%d\n",vlen(offset),target) }
  }
  p.last_owner_tick=owner.state_tick
 }
 p.records[target%256]={true,owner.identity,target,p.world.player.pose.position}
 prediction_set_mode(p,.Predicting,.None)
}
net_prediction_apply :: proc(c:^Net_Client) {
 p:=c.prediction
 if !c.prediction_enabled || p==nil || p.mode!=.Predicting || p.world.epoch!=c.epoch { return }
 position:=vadd(p.world.player.pose.position,p.visual_offset)
 c.drawn[ent_key(.Player,u64(c.nc_client.client_index))]={x=position.x,y=position.y}
}
