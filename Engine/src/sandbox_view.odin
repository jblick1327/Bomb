package main

import rl "vendor:raylib"
import b2 "vendor:box2d"

YARD_INK :: rl.Color{229,239,241,255}
YARD_MUTED :: rl.Color{144,165,178,255}
YARD_ACCENT :: rl.Color{111,220,190,255}

// Fit a fixed rectangle with letterboxing. Fragments never affect the camera.
sandbox_view :: proc(width,height: f32) -> View {
	scale:=min((width-64)/16,(height-170)/8.4)
	return View{offset={width*0.5-0.5*scale,(height+30)*0.5+0.8*scale},scale=scale}
}
sandbox_settings_button :: proc(width: f32) -> rl.Rectangle { return {width-174,24,150,38} }
sandbox_reset_button :: proc(width: f32) -> rl.Rectangle { return {width-284,24,98,38} }
sandbox_over_hud :: proc(mouse: rl.Vector2,width,height: f32,inspection: bool) -> bool {
	if mouse.y<88 || mouse.y>height-56 { return true }
	return inspection && rl.CheckCollisionPointRec(mouse,{24,106,450,150})
}
sandbox_gui_style :: proc() {
	rl.GuiLoadStyleDefault()
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiDefaultProperty.TEXT_SIZE),18)
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_NORMAL),transmute(i32)u32(0x435969ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_NORMAL),transmute(i32)u32(0x233444ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_NORMAL),transmute(i32)u32(0xe5eff1ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_FOCUSED),transmute(i32)u32(0x6fdcbeff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_FOCUSED),transmute(i32)u32(0x304e58ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_FOCUSED),transmute(i32)u32(0xe5fff4ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BORDER_COLOR_PRESSED),transmute(i32)u32(0x6fdcbeff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.BASE_COLOR_PRESSED),transmute(i32)u32(0x416d68ff))
	rl.GuiSetStyle(.DEFAULT,i32(rl.GuiControlProperty.TEXT_COLOR_PRESSED),transmute(i32)u32(0xffffffff))
}
sandbox_slider :: proc(x,y,width: f32,label: cstring,value: ^f32,low,high: f32,decimals: bool = false) {
	rl.DrawText(label,i32(x),i32(y),17,YARD_INK)
	text:=rl.TextFormat("%.0f",value^)
	if decimals { text=rl.TextFormat("%.2f",value^) }
	rl.DrawText(text,i32(x+width)-rl.MeasureText(text,17),i32(y),17,YARD_ACCENT)
	_ = rl.GuiSliderBar({x,y+25,width,16},nil,nil,value,low,high)
}
Sandbox_UI_Action :: enum { None, Open, Resume, Reset, Toggle_Editor }
sandbox_draw_panel :: proc(game: ^Sandbox,width,height: f32) -> Sandbox_UI_Action {
	rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,205})
	x,y:=(width-560)*0.5,(height-360)*0.5
	rl.DrawRectangleRounded({x,y,560,360},0.025,8,{23,35,49,255})
	x+=28; y+=24
	rl.DrawText("SETTINGS / PAUSED",i32(x),i32(y),24,YARD_INK)
	y+=54
	mode:=i32(game.applied.blast_mode)
	_ = rl.GuiToggleGroup({x,y,248,32},"Manual blasts;Falling bombs",&mode)
	sandbox_set_blast_mode(game,Blast_Mode(mode))
	y+=48
	radius:=game.applied.blast_radius
	sandbox_slider(x,y,236,"Blast radius",&radius,0.5,6,true)
	sandbox_slider(x+268,y,236,"Outline width (px)",&game.outline_width,0,2,true)
	sandbox_set_radius(game,radius)
	y+=70
	rl.DrawText("Objects use their palette material. Ground stays Stone.",i32(x),i32(y),16,YARD_MUTED)
	y+=26
	y+=42
	if rl.GuiButton({x,y,504,36},"Resume") { return .Resume }
	return .None
}
sandbox_draw_bombs :: proc(game: ^Sandbox,view: View) {
	for burst in game.bomb_rain.bursts {
		progress:=burst.age/BOMB_BURST_TIME
		color:=rl.Color{255,200,112,u8(220*(1-progress))}
		rl.DrawCircleLinesV(screen_point(view,burst.position),burst.radius*view.scale*(0.2+0.8*progress),color)
	}
	for bomb in game.bomb_rain.bombs {
		position:=from_b2(b2.Body_GetPosition(bomb.body))
		if !game.panel_open && !game.editor.editing { position=vadd(bomb.previous,vmul(vsub(position,bomb.previous),game.accumulator*60)) }
		center:=screen_point(view,position)
		radius:=BOMB_RADIUS*view.scale
		color:=rl.Color{245,206,133,255}
		if bomb.landed { color={255,132,112,255} }
		rl.DrawCircleV(center,radius,{39,42,50,255})
		rl.DrawCircleLinesV(center,radius,color)
		tip:=rl.Vector2{center.x+radius*0.5,center.y-radius*1.4}
		rl.DrawLineEx({center.x,center.y-radius*0.7},tip,2,color)
		rl.DrawCircleV(tip,2,color)
		if bomb.landed { rl.DrawRing(center,radius+3,radius+5,-90,-90+360*bomb.fuse/BOMB_FUSE,24,color) }
	}
}
sandbox_draw_world :: proc(game: ^Sandbox,view: View,poses: map[u64]Pose,frames: map[u64]Pose = nil) {
	s:=&game.scene
	left,top:=screen_point(view,{-9.5,YARD_FLOOR_BOTTOM}),screen_point(view,{10.5,YARD_FLOOR_BOTTOM-YARD_BASE_DEPTH})
	rl.DrawRectangleRec({left.x,left.y,top.x-left.x,top.y-left.y},{42,58,68,255})
	rl.DrawLineEx(left,screen_point(view,{10.5,YARD_FLOOR_BOTTOM}),3,{116,151,151,255})
	for i in -15..=16 {
		x:=f32(i)*0.5
		rl.DrawLineEx(screen_point(view,{x,YARD_FLOOR_BOTTOM-0.04}),screen_point(view,{x+0.12,YARD_FLOOR_BOTTOM-0.20}),2,{66,86,91,255})
	}
	draw_scene(s,view,poses,game.selected,game.surface,game.inspection && game.joints,game.inspection,true,game.outline_width,frames)
	sandbox_draw_editor(game,view)
	spawn:=screen_point(view,{PLAYER_SPAWN.x,0})
	rl.DrawLineEx({spawn.x-16,spawn.y+12},{spawn.x+16,spawn.y+12},3,YARD_ACCENT)
	rl.DrawText("SPAWN",i32(spawn.x)-24,i32(spawn.y)+27,12,YARD_MUTED)
	sandbox_draw_bombs(game,view)
	position:=from_b2(b2.Body_GetPosition(game.player.body))
	if !game.panel_open && !game.editor.editing { position=vadd(game.previous_player,vmul(vsub(position,game.previous_player),game.accumulator*60)) }
	center:=screen_point(view,position)
	radius:=PLAYER_RADIUS*view.scale
	segment:=PLAYER_SEGMENT*view.scale
	rl.DrawRectangleRec({center.x-radius,center.y-segment,2*radius,2*segment},YARD_ACCENT)
	rl.DrawCircleV({center.x,center.y-segment},radius,YARD_ACCENT)
	rl.DrawCircleV({center.x,center.y+segment},radius,YARD_ACCENT)
	rl.DrawLineEx({center.x-radius*0.45,center.y-segment},{center.x+radius*0.45,center.y-segment},3,{21,51,53,255})
}
sandbox_draw_aim :: proc(game: ^Sandbox,view: View,mouse: rl.Vector2) {
	if game.editor.editing || game.applied.blast_mode!=.Manual { return }
	point:=world_point(view,mouse)
	color:=rl.Color{245,206,133,210}
	valid:=sandbox_valid_aim(&game.scene,point)
	if !valid { color={244,132,131,230} }
	rl.DrawCircleLinesV(mouse,game.applied.blast_radius*view.scale,color)
	rl.DrawCircleV(mouse,3,color)
	if !valid {
		rl.DrawLineEx({mouse.x-7,mouse.y-7},{mouse.x+7,mouse.y+7},2,color)
		rl.DrawLineEx({mouse.x+7,mouse.y-7},{mouse.x-7,mouse.y+7},2,color)
		label:=cstring("Aim outside the solid shape")
		x:=clamp(mouse.x+18,f32(12),f32(rl.GetScreenWidth()-rl.MeasureText(label,16)-12))
		y:=clamp(mouse.y+18,f32(94),f32(rl.GetScreenHeight()-80))
		rl.DrawRectangle(i32(x)-7,i32(y)-5,rl.MeasureText(label,16)+14,26,{19,28,42,240})
		rl.DrawText(label,i32(x),i32(y),16,color)
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
	rl.DrawText("BLAST YARD",24,24,26,YARD_INK)
	mode_label:=cstring("Manual blasts / Click to place")
	if game.applied.blast_mode==.Falling_Bombs { mode_label="Falling bombs / 1 sec fuse on landing" }
	if game.editor.editing { mode_label="EDIT / Paused / Drag rectangles above ground" }
	rl.DrawText(mode_label,25,56,15,YARD_MUTED)
	if !game.panel_open {
		{
			label:=cstring("Enter  Edit"); if game.editor.editing { label="Enter  Test" }
			if rl.GuiButton({width-406,24,112,38},label) { return .Toggle_Editor }
		}
		if !game.editor.editing && rl.GuiButton(sandbox_reset_button(width),"R  Reset") { return .Reset }
		if rl.GuiButton(sandbox_settings_button(width),"Tab  Settings") { return .Open }
	}
	rl.DrawRectangle(0,i32(height)-56,i32(width),56,{19,28,42,250})
	controls:=cstring("A/D Move   /   Space Jump   /   Click Blast   /   R Reset")
	if game.applied.blast_mode==.Falling_Bombs { controls="A/D Move   /   Space Jump   /   Falling Bombs   /   R Reset" }
	if game.editor.editing {
		if game.panel_open { rl.GuiDisable() }
		active:=i32(game.editor.palette)
		_ = rl.GuiToggleGroup({24,height-44,90,32},"Wood;Glass;Rubber;Stone",&active)
		game.editor.palette=Palette(active)
		if game.panel_open { rl.GuiEnable() }
		rl.DrawText("Drag: place / Right click: remove",420,i32(height)-35,17,YARD_INK)
	} else {
		rl.DrawText(controls,24,i32(height)-35,17,YARD_INK)
		rl.DrawText(rl.TextFormat("Radius %.1f  /  Wheel",game.applied.blast_radius),i32(width)-222,i32(height)-35,17,YARD_ACCENT)
	}
	if game.status_time>0 {
		text:=rl.TextFormat("%s",game.status)
		x:=i32(width)/2-rl.MeasureText(text,17)/2
		rl.DrawRectangle(x-16,i32(height)-102,rl.MeasureText(text,17)+32,32,{23,40,51,240})
		rl.DrawText(text,x,i32(height)-94,17,YARD_ACCENT)
	}
	if game.inspection && !game.editor.editing {
		rl.DrawRectangleRounded({24,106,450,150},0.07,8,{22,36,51,240})
		rl.DrawText("INSPECTION  /  F3",40,120,18,YARD_ACCENT)
		a,b,c:=counts_runtime(&game.scene)
		rl.DrawText(rl.TextFormat("%d regions  /  %d links  /  %d pieces",a,b,c),40,150,17,YARD_INK)
		rl.DrawText("Right click: select   Delete / Ctrl+click: remove",40,180,16,YARD_MUTED)
		rl.DrawText("Shift+click / X: break link   J: links   V: surface",40,204,16,YARD_MUTED)
		rl.DrawText("S/L: save/load snapshot   D: move   Space: jump",40,228,16,YARD_MUTED)
	}
	if game.panel_open { return sandbox_draw_panel(game,width,height) }
	return .None
}
sandbox_inspect_input :: proc(game: ^Sandbox,point: Vec2,view: View,over_ui: bool) -> bool {
	if !game.inspection || game.panel_open { return false }
	if rl.IsKeyPressed(.J) { game.joints=!game.joints }
	if rl.IsKeyPressed(.V) { game.surface=!game.surface }
	if rl.IsKeyPressed(.S) {
		if save_snapshot(&game.scene,"output/snapshot.json") { sandbox_notice(game,"Saved output/snapshot.json") }
	}
 if rl.IsKeyPressed(.L) {
  loaded,ok:=load_snapshot("output/snapshot.json")
  if ok {
   scene_destroy(&game.scene); game.scene=loaded
   sandbox_start_physics(game)
   game.selected=0; sandbox_clear_input(game)
   sandbox_notice(game,"Loaded output/snapshot.json")
  } else { sandbox_notice(game,"Snapshot missing or invalid") }
 }
	if over_ui { return false }
	hover:=pick_subdivision(&game.scene,point)
	if rl.IsMouseButtonPressed(.RIGHT) { game.selected=hover }
	remove:=rl.IsKeyPressed(.DELETE)
	link:=rl.IsKeyPressed(.X)
	consumed:=false
	if rl.IsMouseButtonPressed(.LEFT) && !game.block_blast {
		if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) { game.selected=hover; remove=true; consumed=true }
		if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) { link=true; consumed=true }
	}
	failures:=Failures{}
	if remove && game.selected!=0 { append(&failures.discard_subdivisions,game.selected); game.selected=0 }
	if link {
		id:=pick_connection(&game.scene,point,24/view.scale)
		if id!=0 { append(&failures.connections,id) }
	}
	if len(failures.discard_subdivisions)+len(failures.connections)>0 {
		apply_failures(&game.scene,failures)
		physics_sync_structure(&game.scene)
		clear(&game.previous)
	}
	delete(failures.discard_subdivisions); delete(failures.connections)
	return consumed
}
sandbox_read_input :: proc() -> Sandbox_Input {
	move:=f32(0)
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { move-=1 }
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { move+=1 }
	return Sandbox_Input{move=move,jump_pressed=rl.IsKeyPressed(.SPACE),jump_down=rl.IsKeyDown(.SPACE),blast_pressed=rl.IsMouseButtonPressed(.LEFT),blast_down=rl.IsMouseButtonDown(.LEFT),menu_pressed=rl.IsKeyPressed(.TAB) || rl.IsKeyPressed(.ESCAPE),reset_pressed=rl.IsKeyPressed(.R),inspection_pressed=rl.IsKeyPressed(.F3),edit_pressed=rl.IsKeyPressed(.ENTER),wheel=rl.GetMouseWheelMove()}
}
sandbox_handle_ui :: proc(game: ^Sandbox,action: Sandbox_UI_Action) {
	switch action {
	case .Open: sandbox_set_panel(game,true)
	case .Resume: sandbox_set_panel(game,false)
	case .Reset: sandbox_reset(game)
	case .Toggle_Editor: sandbox_toggle_editor(game)
	case .None:
	}
	if action!=.None {
		game.block_jump=rl.IsKeyDown(.SPACE)
		game.block_blast=rl.IsMouseButtonDown(.LEFT)
	}
}
run_sandbox :: proc(smoke: bool = false,smoke_input: bool = false,smoke_msaa: bool = false) {
	rl.SetTraceLogLevel(.WARNING)
	flags:=rl.ConfigFlags{.MSAA_4X_HINT,.WINDOW_RESIZABLE,.WINDOW_HIGHDPI}
	if smoke { flags+={.WINDOW_HIDDEN} }
	rl.SetConfigFlags(flags)
	rl.InitWindow(1280,800,"Blast Yard | Odin + Box2D")
	defer rl.CloseWindow()
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
	if smoke_input { sandbox_smoke_inputs(&game); return }
	poses:=make(map[u64]Pose); defer delete(poses)
	target:=rl.RenderTexture2D{}
	if smoke { target=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight()) }
	defer { if smoke { rl.UnloadRenderTexture(target) } }
	frames:=0
	for !rl.WindowShouldClose() {
		width,height:=f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())
		view:=sandbox_view(width,height)
		mouse:=rl.GetMousePosition()
		over_ui:=sandbox_over_hud(mouse,width,height,game.inspection && !game.editor.editing)
		raw:=sandbox_read_input()
		input:=sandbox_route_input(&game,raw,over_ui)
		point:=world_point(view,mouse)
		if !raw.menu_pressed && !raw.reset_pressed {
			if game.editor.editing { sandbox_editor_input(&game,point,over_ui) }
			else if !sandbox_inspect_input(&game,point,view,over_ui) && input.blast_pressed { sandbox_blast(&game,point) }
		}
		sandbox_advance(&game,rl.GetFrameTime(),input)
		clear(&poses)
		for sub in game.scene.subdivisions {
			if !sub.live { continue }
			pose:=sub.pose
			if old,ok:=game.previous[sub.id]; ok && !game.panel_open { pose=interpolate_region_pose(&game.scene,sub,old,game.accumulator*60) }
			poses[sub.id]=pose
		}
		previous:=game.previous
		if game.panel_open { previous=nil }
		piece_frames:=render_piece_frames(&game.scene,poses,previous,game.accumulator*60)
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
