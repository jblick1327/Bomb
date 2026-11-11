#+feature dynamic-literals
package shared

import b2 "vendor:box2d"
import math "core:math"
import time "core:time"

YARD_FLOOR_BOTTOM :: f32(-3)

YARD_BASE_DEPTH :: f32(0.25)

YARD_LEFT :: f32(-8)

YARD_RIGHT :: f32(9)

World :: struct {
 elimination_playing:bool,
 rebuild_error:string,
	scene: Scene,
	floor: b2.BodyId,
	players: [MAX_PLAYERS]Player,
	bombs: [dynamic]Bomb,
	next_bomb_id: u64,
	rain: Bomb_Rain,
	settings: Sandbox_Settings,
	tick: u64,
}

Player_Commands :: struct {
 move: f32,
 jump: bool,
 blasts: [dynamic]Vec2,
 radius: union { f32 },
}

Tick_Commands :: struct {
 players: [MAX_PLAYERS]Player_Commands,
 mode: union { Blast_Mode },
 bomb_radius: union { f32 }, // Sets settings.blast_radius, the falling-bomb radius.
 remove_region,break_connection: u64,
}

Explosion_Event :: struct { position: Vec2, radius: f32, elapsed_ms: f64, regions: int, event_id: u64 }

Tick_Events :: struct {
 deaths:[MAX_PLAYERS]Round_Death,
 bombs_spawned:u64,
 explosions: [dynamic]Explosion_Event,
 player_respawned,blast_rejected: [MAX_PLAYERS]bool,
 structure_changed: bool,
}

sandbox_add_ground :: proc(s: ^Scene,material: int,seed: u8) -> Built_Object {
 first_id:=s.next_id+1
	ground:=add_piece(s,material,derive_seed(seed,13))
	points:=[4]Vec2{{YARD_LEFT,YARD_FLOOR_BOTTOM},{YARD_RIGHT,YARD_FLOOR_BOTTOM},{YARD_RIGHT,0},{YARD_LEFT,0}}
	outline:=Polygon{points=points[:]}
	_ = add_subdivision(s,ground,outline,Pose{position=centroid(outline)})
	presplit_piece(s,ground)
 return Built_Object{first_id=first_id,end_id=s.next_id+1,lo={YARD_LEFT,YARD_FLOOR_BOTTOM},hi={YARD_RIGHT,0}}
}

point_in_subdivision :: proc(sub: Subdivision,point: Vec2) -> bool {
	local:=vadd(sub.rest_center,vrotate(vsub(point,sub.pose.position),-sub.pose.angle))
	inside:=false
	for a,i in sub.outline.points {
		b:=sub.outline.points[(i+1)%len(sub.outline.points)]
		edge:=vsub(b,a); relative:=vsub(local,a)
		if math.abs(vcross(edge,relative))<0.00001 && vdot(relative,edge)>=0 && vdot(relative,edge)<=vdot(edge,edge) { return true }
		if (a.y>local.y)!=(b.y>local.y) && local.x<(b.x-a.x)*(local.y-a.y)/(b.y-a.y)+a.x { inside=!inside }
	}
	return inside
}

sandbox_valid_aim :: proc(s: ^Scene,point: Vec2) -> bool {
	for sub in s.subdivisions { if sub.live && point_in_subdivision(sub,point) { return false } }
	return true
}

world_explode :: proc(w: ^World,point: Vec2,radius: f32,events: ^Tick_Events) {
 if w.elimination_playing {
  physics_read_motion(&w.scene)
  // This snapshot is read before this explosion can fracture any cover. It is
  // separate from destruction's resistance snapshot, so zero-resistance solids
  // still block players without altering material attenuation or damage.
  lethal_radius:=min(radius,scene_gameplay_config(&w.scene).lethal_radius)
  cover:=cover_begin(&w.scene,lethal_radius,true)
  for player,i in w.players {
   if player.active && blast_capsule_visible(&cover,from_b2(b2.Body_GetPosition(player.body)),Blast{point,lethal_radius}) {events.deaths[i]=.Blast}
  }
  cover_destroy(&cover)
 }
 start:=time.tick_now()
 regions:=len(w.scene.subdivisions)
 blast_pass(&w.scene,Blast{position=point,radius=radius})
 append(&events.explosions,Explosion_Event{position=point,radius=radius,elapsed_ms=f64(time.tick_diff(start,time.tick_now()))/f64(time.Millisecond),regions=regions})
 events.structure_changed=true
}

world_tick :: proc(w: ^World,commands: Tick_Commands,dt: f32) -> Tick_Events {
 events:=Tick_Events{}
 if radius,ok:=commands.bomb_radius.(f32); ok { w.settings.blast_radius=clamp(radius,f32(0.5),f32(6)) }
 for player_commands,i in commands.players {
  if radius,ok:=player_commands.radius.(f32); ok && w.players[i].active { w.players[i].blast_radius=clamp(radius,f32(0.5),f32(6)) }
 }
 if mode,ok:=commands.mode.(Blast_Mode); ok && mode!=w.settings.blast_mode {
  w.settings.blast_mode=mode
  bomb_rain_clear(w)
  w.rain.until_drop=bomb_drop_delay_config(&w.rain,scene_gameplay_config(&w.scene))
 }
 failures:=Failures{}
 if commands.remove_region!=0 { failures.administrative=true;append(&failures.discard_subdivisions,commands.remove_region) }
 if commands.break_connection!=0 { failures.administrative=true;append(&failures.connections,commands.break_connection) }
 if len(failures.discard_subdivisions)+len(failures.connections)>0 {
  apply_failures(&w.scene,failures); physics_sync_structure(&w.scene); events.structure_changed=true
 }
 free_failures(&failures)
 // Blasts apply in player-index order, each player's blasts in order.
 for player_commands,i in commands.players {
  if !w.players[i].active { continue }
  for point in player_commands.blasts {
   if w.elimination_playing {events.blast_rejected[i]=true;continue}
   if sandbox_valid_aim(&w.scene,point) { world_explode(w,point,w.players[i].blast_radius,&events) }
   else { events.blast_rejected[i]=true }
  }
 }
 previous_bomb_id:=w.next_bomb_id
 bomb_rain_before_step(w,dt)
 events.bombs_spawned=w.next_bomb_id-previous_bomb_id
 for &player,i in w.players {
  if player.active { player_before_step(&player,commands.players[i].move,commands.players[i].jump,dt) }
 }
 physics_tick(&w.scene,dt)
 world_refresh_poses(w)
 bomb_rain_after_step(w,dt,&events)
 if world_remove_out_of_bounds(w) { events.structure_changed=true }
 for &player,i in w.players {
  if player.active {
   if w.elimination_playing {
    player_after_movement_step(&player)
    outside:=player_out_of_bounds(&player)
    if w.scene.level_policy.active {outside=!level_bounds_contains(w.scene.level_policy.kill,player.pose.position)}
    if outside && events.deaths[i]==.None {events.deaths[i]=.Bounds}
    continue
   }
   if w.scene.level_policy.active {
    player_after_movement_step(&player)
    if !level_bounds_contains(w.scene.level_policy.kill,player.pose.position) { player_respawn_at(&player,w.scene.level_policy.spawns[i]);events.player_respawned[i]=true }
   }else{events.player_respawned[i]=player_after_step(&player)}
  }
 }
 world_refresh_poses(w)
 w.tick+=1
 return events
}

world_refresh_poses :: proc(w: ^World) {
 for &player in w.players { player_refresh_pose(&player) }
 for &bomb in w.bombs { bomb.pose=read_body_state(bomb.body).pose }
}

world_remove_out_of_bounds :: proc(game: ^World) -> bool {
 f:=Failures{administrative=true}
	defer delete(f.discard_subdivisions)
	for sub in game.scene.subdivisions {
  if !sub.live {continue}
  if sub.provenance.motion==.Fixed||sub.provenance.motion==.Anchored {continue}
  if sub.provenance.motion==.Legacy {
   if game.scene.physics.active&&sub.body!=b2.nullBodyId {
    if b2.Body_GetType(sub.body)!=.dynamicBody {continue}
   }else if piece_anchored(&game.scene,sub.owner,game.scene.anchor_y) {continue}
  }
		p:=sub.pose.position
  outside:=p.y<YARD_FLOOR_BOTTOM-2;if game.scene.level_policy.active { outside=!level_bounds_contains(game.scene.level_policy.fragment_cull,p) }
  if outside { append(&f.discard_subdivisions,sub.id) }
	}
	if len(f.discard_subdivisions)==0 { return false }
	apply_failures(&game.scene,f)
	physics_sync_structure(&game.scene)
	return true
}

world_start_physics :: proc(game: ^World) {
 s:=&game.scene
 anchor:=YARD_FLOOR_BOTTOM;if s.level_policy.active { anchor=-1e30 }
	physics_init(s,scene_gameplay_config(s).gravity,anchor)
 game.floor={}
 if !s.level_policy.active {
	def:=b2.DefaultBodyDef()
	def.position={0.5,YARD_FLOOR_BOTTOM-YARD_BASE_DEPTH*0.5}
	game.floor=b2.CreateBody(s.physics.world,def)
	shape:=b2.DefaultShapeDef(); shape.material.friction=0.65
	// Extend beyond the playable edges so excavation never opens the screen bottom.
	_ = b2.CreatePolygonShape(game.floor,shape,b2.MakeBox(10,YARD_BASE_DEPTH*0.5))
 }
	// A rebuild keeps the active player set (and their radii); a fresh world starts with player 0.
	was:=game.players
	game.players={}
	any_active:=false
	for player in was { if player.active { any_active=true } }
	if !any_active { world_add_player(game,0) }
	else { for i in 0..<MAX_PLAYERS { if was[i].active { world_add_player(game,i); game.players[i].blast_radius=was[i].blast_radius } } }
	bomb_rain_reset(&game.rain,game.settings.seed,scene_gameplay_config(s))
	clear(&game.bombs)
	game.tick=0
}

world_add_player :: proc(w: ^World,index: int) -> bool {
 if index<0 || index>=MAX_PLAYERS || w.players[index].active || !w.scene.physics.active { return false }
 w.players[index]=player_create(w.scene.physics.world,w.settings.blast_radius,scene_gameplay_config(&w.scene).player)
 if w.scene.level_policy.active { b2.Body_SetTransform(w.players[index].body,to_b2(w.scene.level_policy.spawns[index]),b2.MakeRot(0));player_refresh_pose(&w.players[index]) }
 return true
}

world_remove_player :: proc(w: ^World,index: int) -> bool {
 if index<0 || index>=MAX_PLAYERS || !w.players[index].active { return false }
 if b2.Body_IsValid(w.players[index].body) { b2.DestroyBody(w.players[index].body) }
 w.players[index]={}
 return true
}
