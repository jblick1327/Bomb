package main

import b2 "vendor:box2d"
import "core:math"
import "core:time"
import "core:strings"

// Per-player input. Applied only to active players; a player's blasts use that player's blast_radius.
Sandbox :: struct {
	world: World,
	render_caches: Render_Cache_State,
	layout: Layout,
	layout_revision,autosaved_layout_revision: u64,
	layout_directory: string,
	layout_files: [dynamic]Saved_Layout,
	layouts_open,last_session,materials_open: bool,
 menu_page: Menu_Page,
 palette_open: bool,
 material_selected: int,
 material_name_buffer: [81]u8,
 material_name_edit: bool,
	editor: Material_Editor,
	blast_timing: ^Soak_Timing,
	queued: Tick_Commands,
	bursts: [dynamic]Bomb_Burst,
	previous_bombs: map[u64]Vec2,
	previous: map[u64]Pose,
	previous_players: [MAX_PLAYERS]Vec2,
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
	delete(game.world.bombs); delete(game.bursts); for &commands in game.queued.players { delete(commands.blasts) }
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
	for &commands in game.queued.players { clear(&commands.blasts) }
	game.queued.remove_region=0; game.queued.break_connection=0
	clear(&game.previous)
	for player,i in game.world.players { if player.active { game.previous_players[i]=player.pose.position } }
}
sandbox_reset :: proc(game: ^Sandbox) {
	release_render_caches(&game.render_caches)
	if radius,ok:=game.queued.bomb_radius.(f32); ok { game.world.settings.blast_radius=radius }
	if mode,ok:=game.queued.mode.(Blast_Mode); ok { game.world.settings.blast_mode=mode }
	if radius,ok:=game.queued.players[0].radius.(f32); ok && game.world.players[0].active { game.world.players[0].blast_radius=radius }
	game.queued.players[0].radius=nil; game.queued.bomb_radius=nil; game.queued.mode=nil
 world_rebuild_layout(&game.world,&game.layout,game.editor.editing)
 clear(&game.bursts); clear(&game.previous_bombs)
	game.selected=0
	game.editor.dragging=false
	sandbox_clear_input(game)
	
}
// The floor uses the same creation refinement as authored objects.
sandbox_set_panel :: proc(game: ^Sandbox,open: bool) {
	if game.materials_open { materials_commit_name(game) }
 game.panel_open=open
 game.palette_open=false
 if open { game.menu_page=.Main }
	game.layouts_open=false; game.materials_open=false; game.material_name_edit=false
	game.editor.dragging=false
	sandbox_clear_input(game)
}
sandbox_set_radius :: proc(game: ^Sandbox,radius: f32) {
	// The local Sandbox sends the same value as player 0's blast radius and the falling-bomb radius.
	game.queued.players[0].radius=clamp(radius,f32(0.5),f32(6))
	game.queued.bomb_radius=game.queued.players[0].radius
}
sandbox_radius :: proc(game: ^Sandbox) -> f32 {
 if radius,ok:=game.queued.players[0].radius.(f32); ok { return radius }; return game.world.players[0].blast_radius
}
sandbox_mode :: proc(game: ^Sandbox) -> Blast_Mode {
 if mode,ok:=game.queued.mode.(Blast_Mode); ok { return mode }; return game.world.settings.blast_mode
}
// Inclusive edges are solid too. Use the logical posed outline, not the cosmetic mesh.
sandbox_blast :: proc(game: ^Sandbox,point: Vec2) -> bool {
	if game.editor.editing || game.panel_open || game.world.settings.blast_mode!=.Manual { return false }
	append(&game.queued.players[0].blasts,point)
	return true
}
// Fixtures may exercise internals without advancing physics.
sandbox_fixture_blast :: proc(game: ^Sandbox,point: Vec2) -> bool {
 if game.editor.editing || game.panel_open || game.world.settings.blast_mode!=.Manual { return false }
 if !sandbox_valid_aim(&game.world.scene,point) { return false }
 sandbox_explode(game,point); return true
}
sandbox_explode :: proc(game: ^Sandbox,point: Vec2) {
 if radius,ok:=game.queued.bomb_radius.(f32); ok { game.world.settings.blast_radius=radius; game.world.players[0].blast_radius=radius; game.queued.bomb_radius=nil; game.queued.players[0].radius=nil }
 events:=Tick_Events{}
 world_explode(&game.world,point,game.world.settings.blast_radius,&events)
 sandbox_present_events(game,&events)
}

// Input routing is independent of raylib, so menu consumption has a direct regression check.
Sandbox_Input :: struct {
	move: f32,
	jump_pressed,jump_down,blast_pressed,blast_down: bool,
	menu_pressed,reset_pressed,inspection_pressed,edit_pressed: bool,
	wheel: f32,
}
sandbox_route_input :: proc(game: ^Sandbox,raw: Sandbox_Input,over_ui: bool) -> Sandbox_Input {
	if raw.menu_pressed && game.palette_open {
  game.palette_open=false; sandbox_clear_input(game); return {}
 }
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
	for player,i in game.world.players { if player.active { game.previous_players[i]=player.pose.position } }
 clear(&game.previous_bombs)
 for bomb in game.world.bombs { game.previous_bombs[bomb.id]=bomb.pose.position }
 commands:=game.queued; commands.players[0].move=move; commands.players[0].jump=jump
 events:=world_tick(&game.world,commands,dt)
 for bomb in game.world.bombs {
  if _,ok:=game.previous_bombs[bomb.id]; !ok { p:=bomb.pose.position; game.previous_bombs[bomb.id]={p.x,BOMB_SKY_HEIGHT} }
 }
 if mode,ok:=commands.mode.(Blast_Mode); ok { clear(&game.bursts) }
 for &player_commands in game.queued.players { clear(&player_commands.blasts); player_commands.radius=nil }
 game.queued.bomb_radius=nil; game.queued.mode=nil
 game.queued.remove_region=0; game.queued.break_connection=0
 sandbox_present_events(game,&events)
}
sandbox_present_events :: proc(game: ^Sandbox,events: ^Tick_Events) {
 for event in events.explosions {
  append(&game.bursts,Bomb_Burst{position=event.position,radius=event.radius})
  if game.blast_timing!=nil { t:=game.blast_timing; t.total_ms+=event.elapsed_ms; t.max_ms=max(t.max_ms,event.elapsed_ms); t.count+=1 }
 }
 if events.structure_changed { clear(&game.previous) }
 if events.blast_rejected[0] { sandbox_notice(game,"Aim outside the solid shape") }
 if !is_live_subdivision(&game.world.scene,game.selected) { game.selected=0 }
 for respawned,i in events.player_respawned { if respawned { game.previous_players[i]=PLAYER_SPAWN } }
 if events.player_respawned[0] { sandbox_notice(game,"Back at spawn") }
 delete(events.explosions)
}
// Presentation mirrors: refreshed from the bodies after every physics step and snapshot load.
// This is yard cleanup, not an impact or another generation of damage.
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
sandbox_fixture_radius :: proc(g: ^Sandbox,r: f32) { g.world.settings.blast_radius=clamp(r,f32(0.5),f32(6)); for &player in g.world.players { if player.active { player.blast_radius=g.world.settings.blast_radius } } }
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

// Players share PLAYER_SPAWN. A new player starts at the current manual blast radius.
