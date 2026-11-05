package main

import b2 "vendor:box2d"
import "core:math"
import "core:encoding/json"
import "core:os"

Wire_Body :: struct { pose: Pose, rotation: b2.Rot }
Wire_Player :: struct { body: Wire_Body, coyote,buffered_jump: f32 }
Wire_Bomb :: struct { body: Wire_Body, landed: bool, fuse: f32 }
World_Snapshot :: struct {
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
 out:=World_Snapshot{version=3,scene=read_state(&w.scene),player={body=read_body_state(w.player.body),coyote=w.player.coyote,buffered_jump=w.player.buffered_jump},rain=w.rain,settings=w.settings,tick=w.tick}
 for bomb in w.bombs { append(&out.bombs,Wire_Bomb{body=read_body_state(bomb.body),landed=bomb.landed,fuse=bomb.fuse}) }
 return out
}
release_world_state :: proc(view: ^World_Snapshot) { release_state_view(&view.scene); delete(view.bombs) }

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
decode_world_snapshot :: proc(data: []byte) -> (World,bool) {
 header: struct { version: int }
 if json.unmarshal(data,&header)!=nil { return {},false }
 if header.version==1 || header.version==2 {
  scene,ok:=decode_snapshot(data); if !ok { return {},false }
  w:=World{scene=scene,settings=DEFAULT_SANDBOX_SETTINGS}
  world_start_physics(&w); return w,true
 }
 if header.version!=3 { return {},false }
 wire:=World_Snapshot{}
 defer { destroy_decoded_snapshot(&wire.scene); delete(wire.bombs) }
 if json.unmarshal(data,&wire)!=nil { return {},false }
 if !finite(wire.settings.blast_radius) || wire.settings.blast_radius<0.5 || wire.settings.blast_radius>6 || (wire.settings.blast_mode!=.Manual && wire.settings.blast_mode!=.Falling_Bombs) { return {},false }
 if !finite(wire.rain.until_drop) || !valid_wire_body(wire.player.body) || !finite(wire.player.coyote) || !finite(wire.player.buffered_jump) { return {},false }
 for bomb in wire.bombs { if !valid_wire_body(bomb.body) || !finite(bomb.fuse) || bomb.fuse<0 { return {},false } }
 scene,ok:=decode_scene_state(&wire.scene); if !ok { return {},false }
 w:=World{scene=scene,settings=wire.settings}
 world_start_physics(&w)
 // Construction reads motion back through rigid body transforms. Keep the saved
 // cell record exact; the next real tick will read the rebuilt engine's motion.
 for sub in wire.scene.subdivisions { w.scene.subdivisions[w.scene.sub_rows[sub.id]].pose=sub.pose }
 restore_body_state(w.player.body,wire.player.body)
 w.player.coyote=wire.player.coyote; w.player.buffered_jump=wire.player.buffered_jump
 for bomb in wire.bombs {
  world_bomb_spawn(&w,bomb.body.pose.position)
  target:=&w.bombs[len(w.bombs)-1]
  restore_body_state(target.body,bomb.body); target.landed=bomb.landed; target.fuse=bomb.fuse
 }
 w.rain=wire.rain; w.tick=wire.tick
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
