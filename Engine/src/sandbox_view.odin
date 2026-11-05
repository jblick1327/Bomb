package main

import rl "vendor:raylib"

YARD_INK :: rl.Color{229,239,241,255}
YARD_MUTED :: rl.Color{144,165,178,255}
YARD_ACCENT :: rl.Color{111,220,190,255}

// Fit a fixed rectangle with letterboxing. Fragments never affect the camera.
sandbox_view :: proc(width,height: f32) -> View {
	scale:=min((width-64)/16,(height-170)/8.4)
	return View{offset={width*0.5-0.5*scale,(height+30)*0.5+0.8*scale},scale=scale}
}
sandbox_settings_button :: proc(width: f32) -> rl.Rectangle { return {width-160,24,140,40} }
sandbox_reset_button :: proc(width: f32) -> rl.Rectangle { return {width-272,24,104,40} }
sandbox_over_hud :: proc(mouse: rl.Vector2,width,height: f32,inspection: bool) -> bool {
	if mouse.y<88 || mouse.y>height-80 { return true }
	return inspection && rl.CheckCollisionPointRec(mouse,{24,106,450,150})
}
sandbox_gui_style :: proc() {
	ui_font_init()
 rl.GuiLoadStyleDefault()
 rl.GuiSetFont(ui_fonts[.Body])
 texture_init()
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiDefaultProperty.TEXT_SIZE),17)
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_NORMAL),transmute(i32)u32(0x435969ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),transmute(i32)u32(0x233444ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),transmute(i32)u32(0xe5eff1ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_FOCUSED),transmute(i32)u32(0x6fdcbeff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_FOCUSED),transmute(i32)u32(0x304e58ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_FOCUSED),transmute(i32)u32(0xe5fff4ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_PRESSED),transmute(i32)u32(0x6fdcbeff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_PRESSED),transmute(i32)u32(0x416d68ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_PRESSED),transmute(i32)u32(0xffffffff))
 rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_DISABLED),transmute(i32)u32(0x2f4050ff))
 rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_DISABLED),transmute(i32)u32(0x1c2a38ff))
 rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_DISABLED),transmute(i32)rl.ColorToInt(YARD_MUTED))
}
sandbox_slider :: proc(x,y,width: f32,label: cstring,value: ^f32,low,high: f32,decimals: bool = false) {
	ui_text(.Body,label,i32(x),i32(y),YARD_INK)
	text:=rl.TextFormat("%.0f",value^)
	if decimals { text=rl.TextFormat("%.2f",value^) }
	ui_text(.Body,text,i32(x+width)-i32(ui_measure(.Body,text)),i32(y),YARD_ACCENT)
	_ = rl.GuiSliderBar({x,y+25,width,16},nil,nil,value,low,high)
}
Sandbox_UI_Action :: enum { None, Open, Resume, Reset, Toggle_Editor, Layouts, Materials }
sandbox_draw_panel :: proc(game: ^Sandbox,width,height: f32) -> Sandbox_UI_Action {
	rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,205})
	x,y:=(width-560)*0.5,(height-360)*0.5
	rl.DrawRectangleRounded({x,y,560,360},0.025,8,{23,35,49,255})
	x+=28; y+=24
	ui_panel_title("Settings",x,y)
	y+=54
	mode:=i32(sandbox_mode(game))
	_ = rl.GuiToggleGroup({x,y,248,32},"Manual blasts;Falling bombs",&mode)
	sandbox_set_blast_mode(game,Blast_Mode(mode))
	y+=48
	radius:=sandbox_radius(game)
	sandbox_slider(x,y,236,"Blast radius",&radius,0.5,6,true)
	sandbox_slider(x+268,y,236,"Outline width (px)",&game.outline_width,0,2,true)
	sandbox_set_radius(game,radius)
	y+=70
	ui_text(.Body,"Objects use their palette material. Ground stays Stone.",i32(x),i32(y),YARD_MUTED)
	y+=26
	y+=42
	if ui_button({x,y,504,36},"Resume") { return .Resume }
 if game.status_time>0 { ui_label(.Small,rl.TextFormat("%s",game.status),{x,y+43,504,22},YARD_ACCENT,true) }
	return .None
}
draw_burst :: proc(view: View,burst: Bomb_Burst) {
	progress:=burst.age/BOMB_BURST_TIME
	color:=rl.Color{255,200,112,u8(220*(1-progress))}
	rl.DrawCircleLinesV(screen_point(view,burst.position),burst.radius*view.scale*(0.2+0.8*progress),color)
}
draw_bomb_at :: proc(view: View,position: Vec2,landed: bool,fuse: f32) {
	center:=screen_point(view,position)
	radius:=BOMB_RADIUS*view.scale
	color:=rl.Color{245,206,133,255}
	if landed { color={255,132,112,255} }
	rl.DrawCircleV(center,radius,{39,42,50,255})
	rl.DrawCircleLinesV(center,radius,color)
	tip:=rl.Vector2{center.x+radius*0.5,center.y-radius*1.4}
	rl.DrawLineEx({center.x,center.y-radius*0.7},tip,2,color)
	rl.DrawCircleV(tip,2,color)
	if landed { rl.DrawRing(center,radius+3,radius+5,-90,-90+360*fuse/BOMB_FUSE,24,color) }
}
sandbox_draw_bombs :: proc(game: ^Sandbox,view: View) {
	for burst in game.bursts { draw_burst(view,burst) }
	for bomb in game.world.bombs {
		position:=bomb.pose.position
		if !game.panel_open && !game.editor.editing { position=vadd(game.previous_bombs[bomb.id],vmul(vsub(position,game.previous_bombs[bomb.id]),game.accumulator*60)) }
		draw_bomb_at(view,position,bomb.landed,bomb.fuse)
	}
}
// The yard's floor slab and hatching, behind the structure.
yard_draw_backdrop :: proc(view: View) {
	left,top:=screen_point(view,{-9.5,YARD_FLOOR_BOTTOM}),screen_point(view,{10.5,YARD_FLOOR_BOTTOM-YARD_BASE_DEPTH})
	rl.DrawRectangleRec({left.x,left.y,top.x-left.x,top.y-left.y},{42,58,68,255})
	rl.DrawLineEx(left,screen_point(view,{10.5,YARD_FLOOR_BOTTOM}),3,{116,151,151,255})
	for i in -15..=16 {
		x:=f32(i)*0.5
		rl.DrawLineEx(screen_point(view,{x,YARD_FLOOR_BOTTOM-0.04}),screen_point(view,{x+0.12,YARD_FLOOR_BOTTOM-0.20}),2,{66,86,91,255})
	}
}
yard_draw_spawn :: proc(view: View) {
	spawn:=screen_point(view,{PLAYER_SPAWN.x,0})
	rl.DrawLineEx({spawn.x-16,spawn.y+12},{spawn.x+16,spawn.y+12},3,YARD_ACCENT)
	ui_text(.Small,"SPAWN",i32(spawn.x)-24,i32(spawn.y)+27,YARD_MUTED)
}
draw_player_at :: proc(view: View,position: Vec2,index: int) {
	center:=screen_point(view,position)
	radius:=PLAYER_RADIUS*view.scale
	segment:=PLAYER_SEGMENT*view.scale
	body_color:=YARD_ACCENT
	// Players after the first (multiplayer) are tinted so they can be told apart.
	if index>0 { tints:=[MAX_PLAYERS]rl.Color{YARD_ACCENT,{244,182,92,255},{150,170,240,255},{226,132,190,255}}; body_color=tints[index] }
	rl.DrawRectangleRec({center.x-radius,center.y-segment,2*radius,2*segment},body_color)
	rl.DrawCircleV({center.x,center.y-segment},radius,body_color)
	rl.DrawCircleV({center.x,center.y+segment},radius,body_color)
	rl.DrawLineEx({center.x-radius*0.45,center.y-segment},{center.x+radius*0.45,center.y-segment},3,{21,51,53,255})
}
sandbox_draw_world :: proc(game: ^Sandbox,view: View,poses: map[u64]Pose,frames: map[u64]Pose = nil) {
	s:=&game.world.scene
	yard_draw_backdrop(view)
	draw_scene(s,&game.render_caches,view,poses,game.selected,game.surface,game.inspection && game.joints,game.inspection,true,game.outline_width,frames)
	sandbox_draw_editor(game,view)
	yard_draw_spawn(view)
	sandbox_draw_bombs(game,view)
	for player,index in game.world.players {
		if !player.active { continue }
		position:=player.pose.position
		if !game.panel_open && !game.editor.editing { position=vadd(game.previous_players[index],vmul(vsub(position,game.previous_players[index]),game.accumulator*60)) }
		draw_player_at(view,position,index)
	}
}
sandbox_aim_segments :: proc(radius_px: f32) -> i32 { return clamp(i32(radius_px/3),48,256) }
sandbox_aim_ring :: proc(center: rl.Vector2,radius_px: f32,color: rl.Color) {
	rl.DrawRing(center,max(f32(0),radius_px-0.75),radius_px+0.75,0,360,sandbox_aim_segments(radius_px),color)
}
sandbox_draw_aim :: proc(game: ^Sandbox,view: View,mouse: rl.Vector2) {
	if game.editor.editing || game.world.settings.blast_mode!=.Manual { return }
	point:=world_point(view,mouse)
	color:=rl.Color{245,206,133,210}
	valid:=sandbox_valid_aim(&game.world.scene,point)
	if !valid { color={244,132,131,230} }
	if valid {
  dim:=color; dim.a=80
  sandbox_aim_ring(mouse,sandbox_radius(game)*view.scale,dim)
  damage:=blast_damage_radius(&game.world.scene,sandbox_radius(game))
  if damage>0 { sandbox_aim_ring(mouse,damage*view.scale,color) }
 } else { sandbox_aim_ring(mouse,sandbox_radius(game)*view.scale,color) }
	rl.DrawCircleV(mouse,3,color)
	if !valid {
		rl.DrawLineEx({mouse.x-7,mouse.y-7},{mouse.x+7,mouse.y+7},2,color)
		rl.DrawLineEx({mouse.x+7,mouse.y-7},{mouse.x-7,mouse.y+7},2,color)
		label:=cstring("Aim outside the solid shape")
		x:=clamp(mouse.x+18,f32(12),f32(rl.GetScreenWidth()-i32(ui_measure(.Body,label))-12))
		y:=clamp(mouse.y+18,f32(94),f32(rl.GetScreenHeight()-80))
		rl.DrawRectangle(i32(x)-7,i32(y)-5,i32(ui_measure(.Body,label))+14,26,{19,28,42,240})
		ui_text(.Body,label,i32(x),i32(y),color)
	}
}
sandbox_draw_hud :: proc(game: ^Sandbox,width,height: f32) -> Sandbox_UI_Action {
	// raygui clears its private slider capture only when a slider sees mouse-up.
	// Keep that release path alive if Escape closed the panel during a drag.
	if !game.panel_open && !rl.IsMouseButtonDown(.LEFT) {
		dummy:=f32(0)
		_ = rl.GuiSliderBar({-100,-100,20,10},nil,nil,&dummy,0,1)
	}
	rl.DrawRectangle(0,0,i32(width),88,{19,28,42,250})
 ui_label(.Title,"BLAST YARD",{20,20,180,34},YARD_INK)
 pill_color:=YARD_ACCENT; mode:cstring="EDIT · paused"; if !game.editor.editing { pill_color={245,206,133,255}; mode="TEST" }
 pill_width:=ui_measure(.Small,mode)+24
 rl.DrawRectangleRoundedLinesEx({208,23,pill_width,31},0.6,8,1,pill_color); ui_label(.Small,mode,{220,23,pill_width-24,31},pill_color)
 help:cstring="Drag shapes above ground"; if !game.editor.editing { help="Move, jump and blast"; if game.world.settings.blast_mode==.Falling_Bombs { help="Move and jump / Falling bombs" } }
 ui_label(.Small,help,{22,62,500,20},YARD_MUTED)
 if !game.panel_open {
  label:cstring="Edit"; if game.editor.editing { label="Test" }
  if ui_button({width-536,24,134,40},label,"Enter") { return .Toggle_Editor }
  if !game.editor.editing && ui_button(sandbox_reset_button(width),"Reset","R") { return .Reset }
  if game.editor.editing && ui_button(sandbox_reset_button(width),"Layouts") { return .Layouts }
  if game.editor.editing && ui_button({width-394,24,114,40},"Materials") { return .Materials }
  if ui_button(sandbox_settings_button(width),"Settings","Tab") { return .Open }
 }
 rl.DrawRectangle(0,i32(height)-80,i32(width),80,{19,28,42,250})
 if game.editor.editing {
  if game.panel_open { rl.GuiDisable() }
  count:=palette_count(&game.layout); total:=count; if count<8 { total+=1 }
  button_width:=(width-260-f32(total-1)*5)/f32(total)
  for i in 0..<count {
   box:=rl.Rectangle{16+f32(i)*(button_width+5),height-66,button_width,36}
   clicked:=rl.GuiButton(box,nil); active:=game.editor.palette==Slot(i)
   color:=YARD_INK; if active { rl.DrawRectangleRec(box,YARD_ACCENT); color={19,28,42,255} }
   ui_keycap({box.x+5,box.y+7,22,22},rl.TextFormat("%d",i+1),color)
   m:=layout_material(&game.layout,Slot(i)); rl.DrawRectangle(i32(box.x+33),i32(box.y+12),12,12,material_color(m))
   ui_label(.Body,rl.TextFormat("%s",m.name),{box.x+51,box.y,box.width-56,box.height},color,true)
   if clicked { game.editor.palette=Slot(i) }
  }
  if count<8 && ui_button({16+f32(count)*(button_width+5),height-66,button_width,36},"+ New") { return .Materials }
  mortar:cstring="Mortar: off"; if game.editor.mortar { mortar="Mortar: on" }
  if ui_toggle({width-232,height-66,216,36},mortar,&game.editor.mortar,"M") {}
  if game.panel_open { rl.GuiEnable() }
  shape_name:cstring="Rect";if game.editor.shape==.Wedge { shape_name="Wedge" }
  ui_label(.Small,rl.TextFormat("Shape: %s [T]    Angle %.0f° [Q/E]    Glue [G]    ·    Drag: place / Right click: remove",shape_name,game.editor.angle),{18,height-25,width-36,22},YARD_MUTED,true)
 } else {
  controls:cstring="A/D  Move   ·   Space  Jump   ·   Click  Blast   ·   R  Reset"
  if game.world.settings.blast_mode==.Falling_Bombs { controls="A/D  Move   ·   Space  Jump   ·   Falling bombs   ·   R  Reset" }
  ui_label(.Body,controls,{22,height-62,width-270,30},YARD_INK,true)
  ui_label(.Body,rl.TextFormat("Radius %.1f  ·  Wheel",sandbox_radius(game)),{width-226,height-62,210,30},YARD_ACCENT,true)
 }
 if game.status_time>0 && !game.panel_open {
  text:=rl.TextFormat("%s",game.status); w:=min(width-48,ui_measure(.Body,text)+32); x:=(width-w)/2
  rl.DrawRectangle(i32(x),i32(height)-126,i32(w),32,{23,40,51,240}); ui_label(.Body,text,{x+16,height-126,w-32,32},YARD_ACCENT,true)
 }
	if game.inspection && !game.editor.editing {
		rl.DrawRectangleRounded({24,106,450,150},0.07,8,{22,36,51,240})
		ui_text(.Heading,"INSPECTION  /  F3",40,120,YARD_ACCENT)
		a,b,c:=counts_runtime(&game.world.scene)
		ui_text(.Body,rl.TextFormat("%d regions  /  %d links  /  %d pieces",a,b,c),40,150,YARD_INK)
		ui_text(.Body,"Right click: select   Delete / Ctrl+click: remove",40,180,YARD_MUTED)
		ui_text(.Body,"Shift+click / X: break link   J: links   V: surface",40,204,YARD_MUTED)
		ui_text(.Body,"S/L: save/load snapshot   D: move   Space: jump",40,228,YARD_MUTED)
	}
	if game.materials_open { return sandbox_draw_materials_panel(game,width,height) }
 if game.layouts_open { return sandbox_draw_layouts_panel(game,width,height) }
	if game.panel_open { return sandbox_draw_panel(game,width,height) }
	return .None
}
sandbox_inspect_input :: proc(game: ^Sandbox,point: Vec2,view: View,over_ui: bool) -> bool {
	if !game.inspection || game.panel_open { return false }
	if rl.IsKeyPressed(.J) { game.joints=!game.joints }
	if rl.IsKeyPressed(.V) { game.surface=!game.surface }
	if rl.IsKeyPressed(.S) {
		if save_world_snapshot(&game.world,"output/snapshot.json") { sandbox_notice(game,"Saved output/snapshot.json") }
	}
 if rl.IsKeyPressed(.L) {
  loaded,ok:=load_world_snapshot("output/snapshot.json")
  if ok {
   loaded.scene.epoch=game.world.scene.epoch+1
   scene_destroy(&game.world.scene); delete(game.world.bombs); release_render_caches(&game.render_caches); game.world=loaded
   clear(&game.bursts); clear(&game.previous_bombs)
   game.queued.players[0].radius=nil; game.queued.bomb_radius=nil; game.queued.mode=nil
   game.selected=0; sandbox_clear_input(game)
   sandbox_notice(game,"Loaded output/snapshot.json")
  } else { sandbox_notice(game,"Snapshot missing or invalid") }
 }
	if over_ui { return false }
	hover:=pick_subdivision(&game.world.scene,point)
	if rl.IsMouseButtonPressed(.RIGHT) { game.selected=hover }
	remove:=rl.IsKeyPressed(.DELETE)
	link:=rl.IsKeyPressed(.X)
	consumed:=false
	if rl.IsMouseButtonPressed(.LEFT) && !game.block_blast {
		if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) { game.selected=hover; remove=true; consumed=true }
		if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) { link=true; consumed=true }
	}
 if remove && game.selected!=0 { game.queued.remove_region=game.selected; game.selected=0 }
 if link { game.queued.break_connection=pick_connection(&game.world.scene,point,24/view.scale) }
	return consumed
}
sandbox_read_input :: proc(game:^Sandbox=nil) -> Sandbox_Input {
	move:=f32(0)
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { move-=1 }
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { move+=1 }
	return Sandbox_Input{move=move,jump_pressed=rl.IsKeyPressed(.SPACE),jump_down=rl.IsKeyDown(.SPACE),blast_pressed=rl.IsMouseButtonPressed(.LEFT),blast_down=rl.IsMouseButtonDown(.LEFT),menu_pressed=rl.IsKeyPressed(.TAB) || rl.IsKeyPressed(.ESCAPE) && (game==nil || !game.editor.glue_tool),reset_pressed=rl.IsKeyPressed(.R),inspection_pressed=rl.IsKeyPressed(.F3),edit_pressed=rl.IsKeyPressed(.ENTER),wheel=rl.GetMouseWheelMove()}
}
sandbox_handle_ui :: proc(game: ^Sandbox,action: Sandbox_UI_Action) {
	switch action {
	case .Open: sandbox_set_panel(game,true)
	case .Resume: sandbox_set_panel(game,false)
	case .Reset: sandbox_reset(game); sandbox_notice(game,"Yard reset")
	case .Toggle_Editor: sandbox_toggle_editor(game)
	case .Layouts: sandbox_set_layouts_panel(game,true)
 case .Materials: sandbox_set_materials_panel(game)
	case .None:
	}
	if action!=.None {
		game.block_jump=rl.IsKeyDown(.SPACE)
		game.block_blast=rl.IsMouseButtonDown(.LEFT)
	}
}
run_sandbox :: proc(smoke: bool = false,smoke_input: bool = false,smoke_msaa: bool = false,smoke_aim: bool = false,smoke_editor: bool = false) {
	rl.SetTraceLogLevel(.WARNING)
	flags:=rl.ConfigFlags{.MSAA_4X_HINT,.WINDOW_RESIZABLE,.WINDOW_HIGHDPI}
	if smoke { flags+={.WINDOW_HIDDEN} }
	rl.SetConfigFlags(flags)
	rl.InitWindow(1280,800,"Blast Yard | Odin + Box2D")
	defer { presentation_shutdown(); rl.CloseWindow() }
	// raygui also selects its font atlas; initialise it before the MSAA fix.
	sandbox_gui_style()
	// Avoid MSAA UV extrapolation into the font atlas: raylib issue #3247.
	rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{})
	rl.SetWindowMinSize(900,700)
	rl.SetExitKey(.KEY_NULL)
	rl.SetTargetFPS(60)
	game:=sandbox_editor_create()
	defer sandbox_destroy(&game)
	if smoke_msaa { sandbox_smoke_msaa(); return }
 if smoke_aim { sandbox_smoke_aim(); return }
	if smoke_input { sandbox_smoke_inputs(&game); return }
	if smoke_editor { sandbox_smoke_editor(); return }
	if !smoke { sandbox_start_layout_files(&game,"layouts") }
	poses:=make(map[u64]Pose); defer delete(poses)
	target:=rl.RenderTexture2D{}
	if smoke { target=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight()) }
	defer { if smoke { rl.UnloadRenderTexture(target) } }
	frames:=0
	for !rl.WindowShouldClose() {
		files_consumed:=sandbox_layout_file_input(&game)
		width,height:=f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())
		view:=sandbox_view(width,height)
		mouse:=rl.GetMousePosition()
		over_ui:=sandbox_over_hud(mouse,width,height,game.inspection && !game.editor.editing)
		raw:=sandbox_read_input(&game)
		input:=Sandbox_Input{}
		if !files_consumed { input=sandbox_route_input(&game,raw,over_ui) }
		point:=world_point(view,mouse)
		if !files_consumed && !raw.menu_pressed && !raw.reset_pressed {
			if game.editor.editing { sandbox_editor_input(&game,point,over_ui) }
			else if !sandbox_inspect_input(&game,point,view,over_ui) && input.blast_pressed { sandbox_blast(&game,point) }
		}
		sandbox_advance(&game,rl.GetFrameTime(),input)
		clear(&poses)
		for sub in game.world.scene.subdivisions {
			if !sub.live { continue }
			pose:=sub.pose
			if old,ok:=game.previous[sub.id]; ok && !game.panel_open { pose=interpolate_region_pose(&game.world.scene,sub,old,game.accumulator*60) }
			poses[sub.id]=pose
		}
		previous:=game.previous
		if game.panel_open { previous=nil }
		piece_frames:=render_piece_frames(&game.world.scene,poses,previous,game.accumulator*60)
		rl.BeginDrawing()
		if smoke { rl.BeginTextureMode(target) }
		rl.ClearBackground({19,28,42,255})
		sandbox_draw_world(&game,view,poses,piece_frames)
		if !game.panel_open && !over_ui { sandbox_draw_aim(&game,view,mouse) }
		action:=sandbox_draw_hud(&game,width,height)
		if smoke {
			rl.EndTextureMode()
			rl.DrawTextureRec(target.texture,{0,0,f32(target.texture.width),-f32(target.texture.height)},{0,0},rl.WHITE)
		}
		rl.EndDrawing()
		delete(piece_frames)
		sandbox_handle_ui(&game,action)
		sandbox_autosave_layout(&game)
		frames+=1
		if smoke && frames==2 {
			image:=rl.LoadImageFromTexture(target.texture)
			rl.ImageFlipVertical(&image)
			name:=cstring("output/sandbox-preview.png")
			_ = rl.ExportImage(image,name)
			rl.UnloadImage(image)
			break
		}
	}
}
