package main

import b2 "vendor:box2d"
import "core:math"
import "core:encoding/json"
import "core:os"

Wire_Body :: struct { pose: Pose, rotation: b2.Rot }
Wire_Player :: struct { body: Wire_Body, coyote,buffered_jump: f32 }
// v4: every active player, by index.
Wire_Player_Entry :: struct { index: int, body: Wire_Body, coyote,buffered_jump: f32, blast_radius: f32 }
// id is written only when it differs from the sequential id a legacy loader assigns (index+1).
Wire_Bomb :: struct { body: Wire_Body, landed: bool, fuse: f32, id: union { u64 } `json:"id,omitempty"` }
World_Snapshot :: struct {
 version: int,
 scene: Snapshot,
 players: [dynamic]Wire_Player_Entry,
 bombs: [dynamic]Wire_Bomb,
 rain: Bomb_Rain,
 settings: Sandbox_Settings,
 tick: u64,
}
// v3 snapshots (single player) remain loadable; they are never written.
World_Snapshot_V3 :: struct {
 version: int,
 scene: Snapshot,
 player: Wire_Player,
 bombs: [dynamic]Wire_Bomb,
 rain: Bomb_Rain,
 settings: Sandbox_Settings,
 tick: u64,
}
read_body_state :: proc(body: b2.BodyId) -> Wire_Body {
 rotation:=b2.Body_GetRotation(body)
 return {pose={position=from_b2(b2.Body_GetPosition(body)),angle=math.atan2(rotation.s,rotation.c),velocity=from_b2(b2.Body_GetLinearVelocity(body)),angular_velocity=b2.Body_GetAngularVelocity(body)},rotation=rotation}
}
read_world_state :: proc(w: ^World) -> World_Snapshot {
 out:=World_Snapshot{version=4,scene=read_state(&w.scene),rain=w.rain,settings=w.settings,tick=w.tick}
 for player,i in w.players {
  if player.active { append(&out.players,Wire_Player_Entry{index=i,body=read_body_state(player.body),coyote=player.coyote,buffered_jump=player.buffered_jump,blast_radius=player.blast_radius}) }
 }
 for bomb,i in w.bombs {
  wire:=Wire_Bomb{body=read_body_state(bomb.body),landed=bomb.landed,fuse=bomb.fuse}
  if bomb.id!=u64(i+1) { wire.id=bomb.id }
  append(&out.bombs,wire)
 }
 return out
}
release_world_state :: proc(view: ^World_Snapshot) { release_state_view(&view.scene); delete(view.players); delete(view.bombs) }

encode_world_snapshot :: proc(w: ^World,pretty: bool = true) -> ([]byte,bool) {
 view:=read_world_state(w); defer release_world_state(&view)
 return exact_json_encode(view,pretty)
}
valid_wire_body :: proc(body: Wire_Body) -> bool {
 p:=body.pose
 return valid_vec(p.position) && valid_vec(p.velocity) && finite(p.angle) && finite(p.angular_velocity) && finite(body.rotation.c) && finite(body.rotation.s) && math.abs(body.rotation.c*body.rotation.c+body.rotation.s*body.rotation.s-1)<0.001
}
restore_body_state :: proc(body: b2.BodyId,state: Wire_Body) {
 b2.Body_SetTransform(body,to_b2(state.pose.position),state.rotation)
 b2.Body_SetLinearVelocity(body,to_b2(state.pose.velocity))
 b2.Body_SetAngularVelocity(body,state.pose.angular_velocity)
}
// epoch is the replication epoch the loaded world starts in; callers pass the
// previous world's epoch plus one so replicas know to take a new Baseline.
decode_world_snapshot :: proc(data: []byte,epoch: u32 = 0) -> (World,bool) {
 header: struct { version: int }
 if json.unmarshal(data,&header)!=nil { return {},false }
 if header.version==1 || header.version==2 {
  scene,ok:=decode_snapshot(data); if !ok { return {},false }
  scene.epoch=epoch
  w:=World{scene=scene,settings=DEFAULT_SANDBOX_SETTINGS}
  world_start_physics(&w); return w,true
 }
 if header.version!=3 && header.version!=4 { return {},false }
 wire:=World_Snapshot{}
 defer { destroy_decoded_snapshot(&wire.scene); delete(wire.players); delete(wire.bombs) }
 if header.version==3 {
  old:=World_Snapshot_V3{}
  defer { destroy_decoded_snapshot(&old.scene); delete(old.bombs) }
  if json.unmarshal(data,&old)!=nil { return {},false }
  // Move the decoded scene and bombs; the single player becomes player 0.
  wire.version=3; wire.scene=old.scene; old.scene={}
  wire.bombs=old.bombs; old.bombs={}
  wire.rain=old.rain; wire.settings=old.settings; wire.tick=old.tick
  append(&wire.players,Wire_Player_Entry{index=0,body=old.player.body,coyote=old.player.coyote,buffered_jump=old.player.buffered_jump,blast_radius=old.settings.blast_radius})
 } else {
  if json.unmarshal(data,&wire)!=nil { return {},false }
 }
 if !finite(wire.settings.blast_radius) || wire.settings.blast_radius<0.5 || wire.settings.blast_radius>6 || (wire.settings.blast_mode!=.Manual && wire.settings.blast_mode!=.Falling_Bombs) { return {},false }
 if !finite(wire.rain.until_drop) { return {},false }
 seen:=[MAX_PLAYERS]bool{}
 for entry in wire.players {
  if entry.index<0 || entry.index>=MAX_PLAYERS || seen[entry.index] { return {},false }
  seen[entry.index]=true
  if !valid_wire_body(entry.body) || !finite(entry.coyote) || !finite(entry.buffered_jump) || !finite(entry.blast_radius) || entry.blast_radius<0.5 || entry.blast_radius>6 { return {},false }
 }
 ids_seen:=make(map[u64]bool); defer delete(ids_seen)
 for bomb,i in wire.bombs {
  if !valid_wire_body(bomb.body) || !finite(bomb.fuse) || bomb.fuse<0 { return {},false }
  id:=u64(i+1); if explicit,present:=bomb.id.(u64); present { id=explicit }
  if id==0 || ids_seen[id] { return {},false }
  ids_seen[id]=true
 }
 scene,ok:=decode_scene_state(&wire.scene); if !ok { return {},false }
 scene.epoch=epoch
 w:=World{scene=scene,settings=wire.settings}
 world_start_physics(&w)
 // Construction reads motion back through rigid body transforms. Keep the saved
 // cell record exact; the next real tick will read the rebuilt engine's motion.
 for sub in wire.scene.subdivisions { w.scene.subdivisions[w.scene.sub_rows[sub.id]].pose=sub.pose }
 // world_start_physics created player 0; make the active set match the snapshot.
 for index in 0..<MAX_PLAYERS {
  if !seen[index] && w.players[index].active { world_remove_player(&w,index) }
 }
 for entry in wire.players {
  if !w.players[entry.index].active { world_add_player(&w,entry.index) }
  target:=&w.players[entry.index]
  restore_body_state(target.body,entry.body)
  target.coyote=entry.coyote; target.buffered_jump=entry.buffered_jump; target.blast_radius=entry.blast_radius
 }
 for bomb in wire.bombs {
  world_bomb_spawn(&w,bomb.body.pose.position)
  target:=&w.bombs[len(w.bombs)-1]
  restore_body_state(target.body,bomb.body); target.landed=bomb.landed; target.fuse=bomb.fuse
  if explicit,present:=bomb.id.(u64); present { target.id=explicit; w.next_bomb_id=max(w.next_bomb_id,explicit) }
 }
 w.rain=wire.rain; w.tick=wire.tick
 world_refresh_poses(&w)
 return w,true
}
save_world_snapshot :: proc(w: ^World,path: string) -> bool {
 data,ok:=encode_world_snapshot(w); defer delete(data)
 return ok && os.write_entire_file(path,data)==nil
}
load_world_snapshot :: proc(path: string) -> (World,bool) {
 data,err:=os.read_entire_file(path,context.allocator); defer delete(data)
 if err!=nil { return {},false }; return decode_world_snapshot(data)
}
