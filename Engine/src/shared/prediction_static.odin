package shared
import b2 "vendor:box2d"

// First prediction fixture: only validated static terrain. Dynamic topology
// history/proxies are a separate required M5 step; this is not the final gate.
Prediction_Reason :: enum { None, Uninitialized, Dynamic_History_Required, Capacity, Wrong_Epoch, Wrong_Revision, Invalid_Owner, Missing_Command, Unsafe_Position }
Static_Prediction :: struct {
 active: bool,
 scene: Scene,
 player: Player,
 epoch:u32,
 revision,state_tick,last_jump_edge:u64,
 identity:Input_Identity,
 reason:Prediction_Reason,
}
prediction_static_destroy :: proc(p:^Static_Prediction) {
 if p.active { scene_destroy(&p.scene) }
 p^={}
}
prediction_static_build :: proc(p:^Static_Prediction,source:^Scene) -> bool {
 prediction_static_destroy(p)
 live:=0
 for sub in source.subdivisions { if sub.live { live+=1 } }
 if live>4096 { p.reason=.Capacity;return false }
 for piece in source.pieces {
  if piece.live && !piece_anchored(source,piece.id,source.anchor_y) { p.reason=.Dynamic_History_Required;return false }
 }
 p.scene=new_scene(0);p.epoch=source.epoch;p.revision=source.structure_revision
 def:=b2.DefaultWorldDef();def.gravity={0,-9.8}
 p.scene.physics={active=true,world=b2.CreateWorld(def)};p.active=true
 append(&p.scene.materials,..source.materials[:])
 bodies:=make(map[u64]b2.BodyId);defer delete(bodies)
 for original in source.subdivisions {
  if !original.live { continue }
  sub:=Subdivision{id=original.id,owner=original.owner,material=original.material,rest_center=original.rest_center,live=true,outline=make_polygon(original.outline.points)}
  p.scene.sub_rows[sub.id]=len(p.scene.subdivisions);append(&p.scene.subdivisions,sub)
  rubber:=source.materials[sub.material].flexibility>0
  body,exists:=bodies[sub.owner]
  if rubber || !exists {
   bd:=b2.DefaultBodyDef();if rubber { bd.position=to_b2(sub.rest_center) }
   body=b2.CreateBody(p.scene.physics.world,bd)
   if !rubber { bodies[sub.owner]=body }
  }
  p.scene.subdivisions[p.scene.sub_rows[sub.id]].body=body
  // Exactly the authoritative decomposition, hull welding, fallback and filter.
  physics_create_region_shapes(&p.scene,sub.id,body)
 }
 floor_def:=b2.DefaultBodyDef();floor_def.position={0.5,YARD_FLOOR_BOTTOM-YARD_BASE_DEPTH*0.5}
 floor:=b2.CreateBody(p.scene.physics.world,floor_def)
 shape:=b2.DefaultShapeDef();shape.material.friction=.65
 _=b2.CreatePolygonShape(floor,shape,b2.MakeBox(10,YARD_BASE_DEPTH*.5))
 p.player=player_create(p.scene.physics.world)
 return true
}
prediction_static_replay :: proc(p:^Static_Prediction,owner:Owner_State,history:^Command_History) -> bool {
 if !p.active { p.reason=.Uninitialized;return false }
 if owner.identity.epoch!=p.epoch { p.reason=.Wrong_Epoch;return false }
 if owner.topology_revision!=p.revision { p.reason=.Wrong_Revision;return false }
 if !history.accepted || owner.identity!=history.identity || !owner_state_restore(p.scene.physics.world,&p.player,owner) { p.reason=.Invalid_Owner;return false }
 p.identity=owner.identity;p.state_tick=owner.state_tick;p.last_jump_edge=owner.last_jump_edge
 if history.next_tick<=owner.state_tick { p.reason=.Missing_Command;return false }
 if history.next_tick-owner.state_tick>INPUT_HISTORY { p.reason=.Capacity;return false }
 first:=true
 for tick:=owner.state_tick+1;tick<history.next_tick;tick+=1 {
  slot:=history.slots[tick%INPUT_HISTORY]
  if !slot.occupied || slot.command.target_tick!=tick { p.reason=.Missing_Command;return false }
  c:=slot.command;jump:=c.jump_edge!=0 && c.jump_edge>p.last_jump_edge
  if jump { p.last_jump_edge=c.jump_edge }
  if first { player_movement_from_support(&p.player,move_dequantize(c.move),jump,f32(NET_STEP_DT));first=false }
  else { player_before_step(&p.player,move_dequantize(c.move),jump,f32(NET_STEP_DT)) }
  b2.World_Step(p.scene.physics.world,f32(NET_STEP_DT),PHYSICS_SUBSTEPS)
  player_after_movement_step(&p.player)
  if player_out_of_bounds(&p.player) || !finite(p.player.pose.position.x) || !finite(p.player.pose.position.y) { p.reason=.Unsafe_Position;return false }
  p.state_tick=tick
 }
 p.reason=.None;return true
}
