package main

import b2 "vendor:box2d"
import "core:math"
import "core:time"

Sandbox_Settings :: struct {
	blast_radius: f32,
	blast_mode: Blast_Mode,
	seed: u8,
}
DEFAULT_SANDBOX_SETTINGS :: Sandbox_Settings{blast_radius=5.0,seed=42}
YARD_FLOOR_BOTTOM :: f32(-3)
YARD_BASE_DEPTH :: f32(0.25)
YARD_LEFT :: f32(-8)
YARD_RIGHT :: f32(9)
Sandbox :: struct {
	scene: Scene,
	blast_timing: ^Soak_Timing,
	editor: Material_Editor,
	floor: b2.BodyId,
	player: Player,
	bomb_rain: Bomb_Rain,
	applied: Sandbox_Settings,
	previous: map[u64]Pose,
	previous_player: Vec2,
	panel_open,inspection,surface,joints: bool,
	outline_width: f32,
	block_jump,block_blast,jump_queued: bool,
	selected: u64,
	accumulator: f32,
	status: string,
	status_time: f32,
}
sandbox_destroy :: proc(game: ^Sandbox) {
	scene_destroy(&game.scene)
	delete(game.bomb_rain.bombs); delete(game.bomb_rain.bursts)
	delete(game.previous); delete(game.editor.objects)
	game^={}
}
sandbox_notice :: proc(game: ^Sandbox,text: string) { game.status=text; game.status_time=2.5 }
sandbox_clear_input :: proc(game: ^Sandbox) {
	game.accumulator=0
	game.jump_queued=false
	game.block_jump=true
	game.block_blast=true
	player_clear_input(&game.player)
	clear(&game.previous)
	game.previous_player=from_b2(b2.Body_GetPosition(game.player.body))
}
sandbox_reset :: proc(game: ^Sandbox) {
	revision:=game.scene.revision+1
	scene_destroy(&game.scene)
	s:=&game.scene
	s^=new_scene(0.10)
	s.revision=revision
	material:=add_material(s,editor_material(.Stone))
	seed:=game.applied.seed
	editor_build_objects(game)
	sandbox_add_ground(s,material,seed)

	sandbox_start_physics(game)
	game.selected=0
	game.editor.dragging=false
	sandbox_clear_input(game)
	sandbox_notice(game,"Yard reset")
}
// The floor uses the same creation refinement as authored objects.
sandbox_add_ground :: proc(s: ^Scene,material: int,seed: u8) {
	ground:=add_piece(s,material,derive_seed(seed,13))
	points:=[4]Vec2{{YARD_LEFT,YARD_FLOOR_BOTTOM},{YARD_RIGHT,YARD_FLOOR_BOTTOM},{YARD_RIGHT,0},{YARD_LEFT,0}}
	outline:=Polygon{points=points[:]}
	_ = add_subdivision(s,ground,outline,Pose{position=centroid(outline)})
	presplit_piece(s,ground)
}
sandbox_set_panel :: proc(game: ^Sandbox,open: bool) {
	game.panel_open=open
	game.editor.dragging=false
	sandbox_clear_input(game)
}
sandbox_set_radius :: proc(game: ^Sandbox,radius: f32) {
	game.applied.blast_radius=clamp(radius,f32(0.5),f32(6))
}
// Inclusive edges are solid too. Use the logical posed outline, not the cosmetic mesh.
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
sandbox_blast :: proc(game: ^Sandbox,point: Vec2) -> bool {
	if game.editor.editing || game.panel_open || game.applied.blast_mode!=.Manual { return false }
	if !sandbox_valid_aim(&game.scene,point) { sandbox_notice(game,"Aim outside the solid shape"); return false }
	sandbox_explode(game,point)
	return true
}
sandbox_explode :: proc(game: ^Sandbox,point: Vec2) {
	start: time.Tick
	if game.blast_timing!=nil { start=time.tick_now() }
	defer { if game.blast_timing!=nil { soak_sample(game.blast_timing,start) } }
	blast:=Blast{position=point,radius=game.applied.blast_radius}
	blast_pass(&game.scene,blast)
	clear(&game.previous)
}

// Input routing is independent of raylib, so menu consumption has a direct regression check.
Sandbox_Input :: struct {
	move: f32,
	jump_pressed,jump_down,blast_pressed,blast_down: bool,
	menu_pressed,reset_pressed,inspection_pressed,edit_pressed: bool,
	wheel: f32,
}
sandbox_route_input :: proc(game: ^Sandbox,raw: Sandbox_Input,over_ui: bool) -> Sandbox_Input {
	if raw.inspection_pressed && !game.editor.editing { game.inspection=!game.inspection }
	if raw.edit_pressed && !game.panel_open {
		sandbox_toggle_editor(game)
		game.block_jump=raw.jump_down; game.block_blast=raw.blast_down
		return {}
	}
	if raw.menu_pressed {
		sandbox_set_panel(game,!game.panel_open)
		game.block_jump=raw.jump_down
		game.block_blast=raw.blast_down
		return {}
	}
	if !raw.jump_down { game.block_jump=false }
	if !raw.blast_down { game.block_blast=false }
	if game.panel_open { return {} }
	if game.editor.editing { return {} }
	if raw.reset_pressed {
		sandbox_reset(game)
		game.block_jump=raw.jump_down
		game.block_blast=raw.blast_down
		return {}
	}
	result:=raw
	result.jump_pressed=raw.jump_pressed && !game.block_jump
	result.blast_pressed=raw.blast_pressed && !game.block_blast && !over_ui && game.applied.blast_mode==.Manual
	if over_ui { result.wheel=0 }
	if result.wheel!=0 { sandbox_set_radius(game,game.applied.blast_radius+result.wheel*0.2) }
	return result
}
sandbox_tick :: proc(game: ^Sandbox,move: f32,jump: bool,dt: f32 = 1.0/60.0) {
	clear(&game.previous)
	for sub in game.scene.subdivisions { if sub.live { game.previous[sub.id]=sub.pose } }
	game.previous_player=from_b2(b2.Body_GetPosition(game.player.body))
	bomb_rain_before_step(game,dt)
	player_before_step(&game.player,move,jump,dt)
	physics_tick(&game.scene,dt)
	bomb_rain_after_step(game,dt)
	sandbox_remove_out_of_bounds(game)
	if player_after_step(&game.player) {
		game.previous_player=PLAYER_SPAWN
		sandbox_notice(game,"Back at spawn")
	}
}
// This is yard cleanup, not an impact or another generation of damage.
sandbox_remove_out_of_bounds :: proc(game: ^Sandbox) {
	f:=Failures{}
	defer delete(f.discard_subdivisions)
	for sub in game.scene.subdivisions {
		p:=sub.pose.position
		if sub.live && p.y<YARD_FLOOR_BOTTOM-2 { append(&f.discard_subdivisions,sub.id) }
	}
	if len(f.discard_subdivisions)==0 { return }
	apply_failures(&game.scene,f)
	physics_sync_structure(&game.scene)
	if !is_live_subdivision(&game.scene,game.selected) { game.selected=0 }
}
sandbox_advance :: proc(game: ^Sandbox,dt: f32,input: Sandbox_Input) {
	if game.panel_open || game.editor.editing { game.accumulator=0; game.jump_queued=false; return }
	if input.jump_pressed { game.jump_queued=true }
	game.status_time=max(f32(0),game.status_time-dt)
	game.accumulator+=clamp(dt,f32(0),f32(0.1))
	for game.accumulator>=1.0/60.0 {
		sandbox_tick(game,input.move,game.jump_queued)
		game.jump_queued=false
		game.accumulator-=1.0/60.0
	}
}

sandbox_start_physics :: proc(game: ^Sandbox) {
 s:=&game.scene
	physics_init(s,{0,-9.8},YARD_FLOOR_BOTTOM)
	def:=b2.DefaultBodyDef()
	def.position={0.5,YARD_FLOOR_BOTTOM-YARD_BASE_DEPTH*0.5}
	game.floor=b2.CreateBody(s.physics.world,def)
	shape:=b2.DefaultShapeDef(); shape.material.friction=0.65
	// Extend beyond the playable edges so excavation never opens the screen bottom.
	_ = b2.CreatePolygonShape(game.floor,shape,b2.MakeBox(10,YARD_BASE_DEPTH*0.5))
	game.player=player_create(s.physics.world)
	bomb_rain_reset(&game.bomb_rain,game.applied.seed)
}
