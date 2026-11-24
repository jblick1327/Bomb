package main

import "core:slice"

// Frontend-owned graphics resources. The native client never allocates these.
Net_Client_View :: struct {
 caches: Render_Cache_State,
 reset_serial: u64,
 has_serial: bool,
 bursts: [dynamic]Bomb_Burst,
 reset_count: int,
}
net_client_view_destroy :: proc(state: ^Net_Client_View) {
 release_render_caches(&state.caches)
 delete(state.bursts)
 state^={}
}
// Called once after each fixed client step, including steps without a rendered frame.
net_client_view_step :: proc(c: ^Net_Client,state: ^Net_Client_View) {
 if state.reset_count!=c.stats.resets { clear(&state.bursts); state.reset_count=c.stats.resets }
 for e in c.events { if e.kind==NET_EVENT_EXPLOSION { append(&state.bursts,Bomb_Burst{position=e.position,radius=e.radius}) } }
 for &burst in state.bursts { burst.age+=f32(NET_STEP_DT) }
 count:=0
 for burst in state.bursts { if burst.age<BOMB_BURST_TIME { state.bursts[count]=burst; count+=1 } }
 resize(&state.bursts,count)
}
// Reference frontend rendering; no renderer types are owned by Net_Client.
// Piece frames map to rigid cell poses; rubber cells and anchored pieces keep their own rule.
// Dynamic pieces and cells without a drawn row are moved far off screen.
net_client_draw_inputs :: proc(c: ^Net_Client) -> (poses: map[u64]Pose,frames: map[u64]Pose) {
 net_client_ensure_anchored(c)
 s:=&c.rep.scene
 poses=make(map[u64]Pose); frames=make(map[u64]Pose)
 for p in s.pieces {
  if !p.live || s.materials[p.material].flexibility>0 || len(p.subdivisions)==0 { continue }
  frame:Pose
  if d,ok:=c.drawn[ent_key(.Piece,p.id)]; ok { frame=reference_to_frame(Pose{position={d.x,d.y},angle=d.angle},p.ref_rest) }
  else if !c.anchored[p.id] { frame=Pose{position={NET_HIDDEN,NET_HIDDEN}} }
  frames[p.id]=frame
  for id in p.subdivisions {
   row,ok:=s.sub_rows[id]; if !ok || !s.subdivisions[row].live { continue }
   sub:=s.subdivisions[row]
   poses[id]=Pose{position=rigid_render_point(frame,sub.rest_center),angle=frame.angle}
  }
 }
 for sub in s.subdivisions {
  if !sub.live || s.materials[sub.material].flexibility<=0 { continue }
  if d,ok:=c.drawn[ent_key(.Rubber,sub.id)]; ok { poses[sub.id]=Pose{position={d.x,d.y},angle=d.angle} }
  else if c.anchored[sub.owner] { poses[sub.id]=Pose{position=sub.rest_center} }
  else { poses[sub.id]=Pose{position={NET_HIDDEN,NET_HIDDEN}} }
 }
 return
}
// Draws the replica through the existing draw path.
net_client_draw :: proc(c: ^Net_Client,state: ^Net_Client_View,view: View,outline_width:f32=2) {
 if !state.has_serial || state.reset_serial!=c.presentation_reset_serial {
  release_render_caches(&state.caches)
  state.reset_serial=c.presentation_reset_serial; state.has_serial=true
 }
 poses,frames:=net_client_draw_inputs(c); defer { delete(poses); delete(frames) }
 yard_draw_backdrop(view)
 draw_scene(&c.rep.scene,&state.caches,view,poses,0,true,false,false,true,outline_width,frames)
 yard_draw_spawn(view)
 for burst in state.bursts { draw_burst(view,burst) }
 keys:[dynamic]u64; defer delete(keys)
 for key in c.drawn { if kind:=key_kind(key); kind==.Bomb || kind==.Player { append(&keys,key) } }
 slice.sort(keys[:])
 for key in keys { if key_kind(key)==.Bomb { d:=c.drawn[key]; draw_bomb_at(view,{d.x,d.y},d.landed,d.fuse) } }
 for key in keys { if key_kind(key)==.Player { d:=c.drawn[key]; draw_player_at(view,{d.x,d.y},int(key_id(key))) } }
}

