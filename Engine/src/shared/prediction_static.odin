package shared
import b2 "vendor:box2d"

// First prediction fixture: only validated static terrain. Dynamic topology
// history/proxies are a separate required M5 step; this is not the final gate.
Prediction_Reason :: enum { None, Uninitialized, Dynamic_History_Required, Capacity, Wrong_Epoch, Wrong_Revision, Invalid_Owner, Missing_Command, Unsafe_Position, Bomb_Contact_Uncertain }
Prediction_Proxy :: struct { key:u64, body:b2.BodyId, reference:Vec2, rigid:bool }
Static_Prediction :: struct {
 active: bool,
 scene: Scene,
 player: Player,
 epoch:u32,
 revision,state_tick,last_jump_edge:u64,
 identity:Input_Identity,
 reason:Prediction_Reason,
 proxies:[dynamic]Prediction_Proxy,
}
prediction_static_destroy :: proc(p:^Static_Prediction) {
 if p.active { scene_destroy(&p.scene) }
 delete(p.proxies)
 p^={}
}
prediction_static_build :: proc(p:^Static_Prediction,source:^Scene,allow_dynamic:bool=false) -> bool {
 prediction_static_destroy(p)
 live:=0
 for sub in source.subdivisions { if sub.live { live+=1 } }
 if live>4096 { p.reason=.Capacity;return false }
 for piece in source.pieces {
  if piece.live && !piece_anchored(source,piece.id,source.anchor_y) && !allow_dynamic { p.reason=.Dynamic_History_Required;return false }
 }
 p.scene=new_scene(0);p.epoch=source.epoch;p.revision=source.structure_revision
 p.scene.level_policy=source.level_policy
 def:=b2.DefaultWorldDef();def.gravity=to_b2(scene_gameplay_config(source).gravity)
 p.scene.physics={active=true,world=b2.CreateWorld(def)};p.active=true
 append(&p.scene.materials,..source.materials[:])
 for &material in p.scene.materials { material.name="" }
 bodies:=make(map[u64]b2.BodyId);defer delete(bodies)
 anchored:=make(map[u64]bool);defer delete(anchored)
 for piece in source.pieces { if piece.live { anchored[piece.id]=piece_anchored(source,piece.id,source.anchor_y) } }
 for original in source.subdivisions {
  if !original.live { continue }
  sub:=Subdivision{id=original.id,owner=original.owner,material=original.material,rest_center=original.rest_center,live=true,outline=make_polygon(original.outline.points),provenance=original.provenance}
  p.scene.sub_rows[sub.id]=len(p.scene.subdivisions);append(&p.scene.subdivisions,sub)
  rubber:=source.materials[sub.material].flexibility>0
  pinned:=anchored[sub.owner];if rubber&&sub.provenance.motion!=.Legacy { pinned=sub.provenance.pinned }
  body,exists:=bodies[sub.owner]
  if rubber || !exists {
   bd:=b2.DefaultBodyDef();if rubber { bd.position=to_b2(sub.rest_center) }
   if !pinned { bd.type=.kinematicBody }
   body=b2.CreateBody(p.scene.physics.world,bd)
   if !rubber { bodies[sub.owner]=body }
   if !pinned {
    key:=ent_key(.Rubber,sub.id);reference:=sub.rest_center
    if !rubber { key=ent_key(.Piece,sub.owner);reference=source.pieces[source.piece_rows[sub.owner]].ref_rest }
    append(&p.proxies,Prediction_Proxy{key,body,reference,!rubber})
   }
  }
  p.scene.subdivisions[p.scene.sub_rows[sub.id]].body=body
  // Exactly the authoritative decomposition, hull welding, fallback and filter.
  physics_create_region_shapes(&p.scene,sub.id,body)
 }
 if !source.level_policy.active {
 floor_def:=b2.DefaultBodyDef();floor_def.position={0.5,YARD_FLOOR_BOTTOM-YARD_BASE_DEPTH*0.5}
 floor:=b2.CreateBody(p.scene.physics.world,floor_def)
 shape:=b2.DefaultShapeDef();shape.material.friction=.65
 _=b2.CreatePolygonShape(floor,shape,b2.MakeBox(10,YARD_BASE_DEPTH*.5))
 }
 p.player=player_create(p.scene.physics.world)
 p.player.tuning=scene_gameplay_config(source).player
 return true
}
prediction_proxy_positions :: proc(p:^Static_Prediction,history:^Collision_History,tick:u64) -> bool {
 if len(p.proxies)==0 { return true }
 if history==nil { p.reason=.Dynamic_History_Required;return false }
 for proxy in p.proxies {
  a,_,valid_a:=collision_history_pose(history,tick,proxy.key)
  b,_,valid_b:=collision_history_pose(history,tick+1,proxy.key)
  if !valid_a || !valid_b { p.reason=.Dynamic_History_Required;return false }
  from,to:=Vec2{a.x,a.y},Vec2{b.x,b.y}
  if proxy.rigid { from=vsub(from,vrotate(proxy.reference,a.angle));to=vsub(to,vrotate(proxy.reference,b.angle)) }
  b2.Body_SetTransform(proxy.body,to_b2(from),b2.MakeRot(a.angle))
  b2.Body_SetLinearVelocity(proxy.body,to_b2(vmul(vsub(to,from),60)))
  b2.Body_SetAngularVelocity(proxy.body,radians_delta(b.angle,a.angle)*60)
 }
 return true
}
prediction_world_step :: proc(p:^Static_Prediction,command:Scheduled_Command,collision:^Collision_History=nil,seed_support:bool=false) -> bool {
 tick:=command.target_tick
 if tick!=p.state_tick+1 { p.reason=.Missing_Command;return false }
 if collision!=nil {
  topology:=collision_history_topology(collision,tick)
  if topology==nil || topology.scene.structure_revision!=p.revision { p.reason=.Wrong_Revision;return false }
 }
 if !prediction_proxy_positions(p,collision,tick-1) { return false }
 jump:=command.jump_edge!=0 && command.jump_edge>p.last_jump_edge
 if jump { p.last_jump_edge=command.jump_edge }
 if seed_support { player_movement_from_support(&p.player,move_dequantize(command.move),jump,f32(NET_STEP_DT)) }
 else { player_before_step(&p.player,move_dequantize(command.move),jump,f32(NET_STEP_DT)) }
 b2.World_Step(p.scene.physics.world,f32(NET_STEP_DT),PHYSICS_SUBSTEPS);player_after_movement_step(&p.player)
 outside:=player_out_of_bounds(&p.player);if p.scene.level_policy.active { outside=!level_bounds_contains(p.scene.level_policy.kill,p.player.pose.position) }
 if outside || !finite(p.player.pose.position.x) || !finite(p.player.pose.position.y) { p.reason=.Unsafe_Position;return false }
 p.state_tick=tick;p.reason=.None;return true
}
prediction_static_replay :: proc(p:^Static_Prediction,owner:Owner_State,history:^Command_History,collision:^Collision_History=nil) -> bool {
 if !p.active { p.reason=.Uninitialized;return false }
 if owner.identity.epoch!=p.epoch { p.reason=.Wrong_Epoch;return false }
 if owner.topology_revision!=p.revision { p.reason=.Wrong_Revision;return false }
 if owner.support_kind==1 && owner.support_cell not_in p.scene.sub_rows { p.reason=.Invalid_Owner;return false }
 if !history.accepted || owner.identity!=history.identity || !owner_state_restore(p.scene.physics.world,&p.player,owner) { p.reason=.Invalid_Owner;return false }
 p.identity=owner.identity;p.state_tick=owner.state_tick;p.last_jump_edge=owner.last_jump_edge
 if history.next_tick<=owner.state_tick { p.reason=.Missing_Command;return false }
 if history.next_tick-owner.state_tick>INPUT_HISTORY { p.reason=.Capacity;return false }
 first:=true
 for tick:=owner.state_tick+1;tick<history.next_tick;tick+=1 {
  slot:=history.slots[tick%INPUT_HISTORY]
  if !slot.occupied || slot.command.target_tick!=tick { p.reason=.Missing_Command;return false }
  if !prediction_world_step(p,slot.command,collision,first) { return false };first=false
 }
 p.reason=.None;return true
}
