package main

import b2 "vendor:box2d"
import "core:math"
import "core:time"
import "core:strings"

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
World :: struct {
	scene: Scene,
	floor: b2.BodyId,
	player: Player,
	bombs: [dynamic]Bomb,
	rain: Bomb_Rain,
	settings: Sandbox_Settings,
	tick: u64,
}
Tick_Commands :: struct {
 move: f32,
 jump: bool,
 blasts: [dynamic]Vec2,
 radius: union { f32 },
 mode: union { Blast_Mode },
 remove_region,break_connection: u64,
}
Explosion_Event :: struct { position: Vec2, radius: f32, elapsed_ms: f64, regions: int }
Tick_Events :: struct {
 explosions: [dynamic]Explosion_Event,
 player_respawned,blast_rejected,structure_changed: bool,
}
Sandbox :: struct {
	world: World,
	render_caches: Render_Cache_State,
	layout: Layout,
	layout_revision,autosaved_layout_revision: u64,
	layout_directory: string,
	layout_files: [dynamic]Saved_Layout,
	layouts_open,last_session,materials_open: bool,
 material_selected: int,
 material_name_buffer: [81]u8,
 material_name_edit: bool,
	editor: Material_Editor,
	blast_timing: ^Soak_Timing,
	queued: Tick_Commands,
	bursts: [dynamic]Bomb_Burst,
	previous_bombs: map[b2.BodyId]Vec2,
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
	scene_destroy(&game.world.scene)
	release_render_caches(&game.render_caches)
	delete(game.world.bombs); delete(game.bursts); delete(game.queued.blasts)
	delete(game.previous); delete(game.previous_bombs); destroy_layout(&game.layout)
	delete(game.status); sandbox_release_layout_files(game)
	game^={}
}
sandbox_notice :: proc(game: ^Sandbox,text: string) {
	next:=strings.clone(text); delete(game.status); game.status=next; game.status_time=2.5
}
sandbox_clear_input :: proc(game: ^Sandbox) {
	game.accumulator=0
	game.jump_queued=false
	game.block_jump=true
	game.block_blast=true
	clear(&game.queued.blasts)
	game.queued.remove_region=0; game.queued.break_connection=0
	clear(&game.previous)
	game.previous_player=from_b2(b2.Body_GetPosition(game.world.player.body))
}
sandbox_reset :: proc(game: ^Sandbox) {
	release_render_caches(&game.render_caches)
	if radius,ok:=game.queued.radius.(f32); ok { game.world.settings.blast_radius=radius }
	if mode,ok:=game.queued.mode.(Blast_Mode); ok { game.world.settings.blast_mode=mode }
	game.queued.radius=nil; game.queued.mode=nil
	revision:=game.world.scene.revision+1
	scene_destroy(&game.world.scene)
	s:=&game.world.scene
	s^=new_scene(WOOD_MINIMUM_WIDTH)
	s.revision=revision
	material:=add_material(s,editor_material(.Stone))
	seed:=game.world.settings.seed
	objects: [dynamic]Built_Object; defer delete(objects)
 editor_build_objects(game,&objects)
 ground:=sandbox_add_ground(s,material,seed)
 build_mortar(s,objects[:],ground)
 build_glue(s,game.layout.glue[:],objects[:],ground)

	sandbox_start_physics(game)
	game.selected=0
	game.editor.dragging=false
	sandbox_clear_input(game)
	
}
// The floor uses the same creation refinement as authored objects.
sandbox_add_ground :: proc(s: ^Scene,material: int,seed: u8) -> Built_Object {
 first_id:=s.next_id+1
	ground:=add_piece(s,material,derive_seed(seed,13))
	points:=[4]Vec2{{YARD_LEFT,YARD_FLOOR_BOTTOM},{YARD_RIGHT,YARD_FLOOR_BOTTOM},{YARD_RIGHT,0},{YARD_LEFT,0}}
	outline:=Polygon{points=points[:]}
	_ = add_subdivision(s,ground,outline,Pose{position=centroid(outline)})
	presplit_piece(s,ground)
 return Built_Object{first_id=first_id,end_id=s.next_id+1,lo={YARD_LEFT,YARD_FLOOR_BOTTOM},hi={YARD_RIGHT,0}}
}
sandbox_set_panel :: proc(game: ^Sandbox,open: bool) {
	if game.materials_open { materials_commit_name(game) }
 game.panel_open=open
	game.layouts_open=false; game.materials_open=false; game.material_name_edit=false
	game.editor.dragging=false
	sandbox_clear_input(game)
}
sandbox_set_radius :: proc(game: ^Sandbox,radius: f32) {
	game.queued.radius=clamp(radius,f32(0.5),f32(6))
}
sandbox_radius :: proc(game: ^Sandbox) -> f32 {
 if radius,ok:=game.queued.radius.(f32); ok { return radius }; return game.world.settings.blast_radius
}
sandbox_mode :: proc(game: ^Sandbox) -> Blast_Mode {
 if mode,ok:=game.queued.mode.(Blast_Mode); ok { return mode }; return game.world.settings.blast_mode
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
	if game.editor.editing || game.panel_open || game.world.settings.blast_mode!=.Manual { return false }
	append(&game.queued.blasts,point)
	return true
}
// Fixtures may exercise internals without advancing physics.
sandbox_fixture_blast :: proc(game: ^Sandbox,point: Vec2) -> bool {
 if game.editor.editing || game.panel_open || game.world.settings.blast_mode!=.Manual { return false }
 if !sandbox_valid_aim(&game.world.scene,point) { return false }
 sandbox_explode(game,point); return true
}
sandbox_explode :: proc(game: ^Sandbox,point: Vec2) {
 if radius,ok:=game.queued.radius.(f32); ok { game.world.settings.blast_radius=radius; game.queued.radius=nil }
 events:=Tick_Events{}
 world_explode(&game.world,point,&events)
 sandbox_present_events(game,&events)
}
world_explode :: proc(w: ^World,point: Vec2,events: ^Tick_Events) {
 start:=time.tick_now()
 regions:=len(w.scene.subdivisions)
 blast_pass(&w.scene,Blast{position=point,radius=w.settings.blast_radius})
 append(&events.explosions,Explosion_Event{position=point,radius=w.settings.blast_radius,elapsed_ms=f64(time.tick_diff(start,time.tick_now()))/f64(time.Millisecond),regions=regions})
 events.structure_changed=true
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
		sandbox_reset(game); sandbox_notice(game,"Yard reset")
		game.block_jump=raw.jump_down
		game.block_blast=raw.blast_down
		return {}
	}
	result:=raw
	result.jump_pressed=raw.jump_pressed && !game.block_jump
	result.blast_pressed=raw.blast_pressed && !game.block_blast && !over_ui && game.world.settings.blast_mode==.Manual
	if over_ui { result.wheel=0 }
	if result.wheel!=0 { sandbox_set_radius(game,sandbox_radius(game)+result.wheel*0.2) }
	return result
}
sandbox_tick :: proc(game: ^Sandbox,move: f32,jump: bool,dt: f32 = 1.0/60.0) {
 count:=0
 for burst in game.bursts { next:=burst; next.age+=dt; if next.age<BOMB_BURST_TIME { game.bursts[count]=next; count+=1 } }
 resize(&game.bursts,count)
	clear(&game.previous)
	for sub in game.world.scene.subdivisions { if sub.live { game.previous[sub.id]=sub.pose } }
	game.previous_player=from_b2(b2.Body_GetPosition(game.world.player.body))
 clear(&game.previous_bombs)
 for bomb in game.world.bombs { game.previous_bombs[bomb.body]=from_b2(b2.Body_GetPosition(bomb.body)) }
 commands:=game.queued; commands.move=move; commands.jump=jump
 events:=world_tick(&game.world,commands,dt)
 for bomb in game.world.bombs {
  if _,ok:=game.previous_bombs[bomb.body]; !ok { p:=from_b2(b2.Body_GetPosition(bomb.body)); game.previous_bombs[bomb.body]={p.x,BOMB_SKY_HEIGHT} }
 }
 if mode,ok:=commands.mode.(Blast_Mode); ok { clear(&game.bursts) }
 clear(&game.queued.blasts); game.queued.radius=nil; game.queued.mode=nil
 game.queued.remove_region=0; game.queued.break_connection=0
 sandbox_present_events(game,&events)
}
sandbox_present_events :: proc(game: ^Sandbox,events: ^Tick_Events) {
 for event in events.explosions {
  append(&game.bursts,Bomb_Burst{position=event.position,radius=event.radius})
  if game.blast_timing!=nil { t:=game.blast_timing; t.total_ms+=event.elapsed_ms; t.max_ms=max(t.max_ms,event.elapsed_ms); t.count+=1 }
 }
 if events.structure_changed { clear(&game.previous) }
 if events.blast_rejected { sandbox_notice(game,"Aim outside the solid shape") }
 if !is_live_subdivision(&game.world.scene,game.selected) { game.selected=0 }
 if events.player_respawned {
		game.previous_player=PLAYER_SPAWN
		sandbox_notice(game,"Back at spawn")
	}
 delete(events.explosions)
}
world_tick :: proc(w: ^World,commands: Tick_Commands,dt: f32) -> Tick_Events {
 events:=Tick_Events{}
 if radius,ok:=commands.radius.(f32); ok { w.settings.blast_radius=clamp(radius,f32(0.5),f32(6)) }
 if mode,ok:=commands.mode.(Blast_Mode); ok && mode!=w.settings.blast_mode {
  w.settings.blast_mode=mode
  bomb_rain_clear(w)
  w.rain.until_drop=bomb_drop_delay(&w.rain)
 }
 failures:=Failures{}
 if commands.remove_region!=0 { append(&failures.discard_subdivisions,commands.remove_region) }
 if commands.break_connection!=0 { append(&failures.connections,commands.break_connection) }
 if len(failures.discard_subdivisions)+len(failures.connections)>0 {
  apply_failures(&w.scene,failures); physics_sync_structure(&w.scene); events.structure_changed=true
 }
 free_failures(&failures)
 for point in commands.blasts {
  if sandbox_valid_aim(&w.scene,point) { world_explode(w,point,&events) }
  else { events.blast_rejected=true }
 }
 bomb_rain_before_step(w,dt)
 player_before_step(&w.player,commands.move,commands.jump,dt)
 physics_tick(&w.scene,dt)
 bomb_rain_after_step(w,dt,&events)
 if world_remove_out_of_bounds(w) { events.structure_changed=true }
 events.player_respawned=player_after_step(&w.player)
 w.tick+=1
 return events
}
// This is yard cleanup, not an impact or another generation of damage.
world_remove_out_of_bounds :: proc(game: ^World) -> bool {
	f:=Failures{}
	defer delete(f.discard_subdivisions)
	for sub in game.scene.subdivisions {
		p:=sub.pose.position
		if sub.live && p.y<YARD_FLOOR_BOTTOM-2 { append(&f.discard_subdivisions,sub.id) }
	}
	if len(f.discard_subdivisions)==0 { return false }
	apply_failures(&game.scene,f)
	physics_sync_structure(&game.scene)
	return true
}
sandbox_advance :: proc(game: ^Sandbox,dt: f32,input: Sandbox_Input) {
	game.status_time=max(f32(0),game.status_time-dt)
	if game.panel_open || game.editor.editing { game.accumulator=0; game.jump_queued=false; return }
	if input.jump_pressed { game.jump_queued=true }
	game.accumulator+=clamp(dt,f32(0),f32(0.1))
	for game.accumulator>=1.0/60.0 {
		sandbox_tick(game,input.move,game.jump_queued)
		game.jump_queued=false
		game.accumulator-=1.0/60.0
	}
}

// Test and measurement fixtures may build/mutate worlds directly.
sandbox_fixture_radius :: proc(g: ^Sandbox,r: f32) { g.world.settings.blast_radius=clamp(r,f32(0.5),f32(6)) }
sandbox_fixture_mode :: proc(g: ^Sandbox,mode: Blast_Mode) {
 if mode==g.world.settings.blast_mode { return }
 g.world.settings.blast_mode=mode; bomb_rain_clear(&g.world); clear(&g.bursts)
 g.world.rain.until_drop=bomb_drop_delay(&g.world.rain)
}
sandbox_remove_out_of_bounds :: proc(g: ^Sandbox) {
 world_remove_out_of_bounds(&g.world)
 if !is_live_subdivision(&g.world.scene,g.selected) { g.selected=0 }
}

sandbox_start_physics :: proc(game: ^Sandbox) {
 world_start_physics(&game.world)
 clear(&game.bursts); clear(&game.previous_bombs)
}
world_start_physics :: proc(game: ^World) {
 s:=&game.scene
	physics_init(s,{0,-9.8},YARD_FLOOR_BOTTOM)
	def:=b2.DefaultBodyDef()
	def.position={0.5,YARD_FLOOR_BOTTOM-YARD_BASE_DEPTH*0.5}
	game.floor=b2.CreateBody(s.physics.world,def)
	shape:=b2.DefaultShapeDef(); shape.material.friction=0.65
	// Extend beyond the playable edges so excavation never opens the screen bottom.
	_ = b2.CreatePolygonShape(game.floor,shape,b2.MakeBox(10,YARD_BASE_DEPTH*0.5))
	game.player=player_create(s.physics.world)
	bomb_rain_reset(&game.rain,game.settings.seed)
	clear(&game.bombs)
	game.tick=0
}
