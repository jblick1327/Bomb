package main

import rl "vendor:raylib"
import b2 "vendor:box2d"
import "core:fmt"

// raylib 5.x automation event IDs (rcore.c); the Odin binding exposes the raw event.
smoke_key :: proc(key: rl.KeyboardKey,down: bool) -> rl.AutomationEvent {
	type:=u32(1); if down { type=2 }
	return {type=type,params={i32(key),0,0,0}}
}
smoke_mouse :: proc(x,y: i32) -> rl.AutomationEvent {
	dpi:=rl.GetWindowScaleDPI()
	return {type=7,params={i32(f32(x)*dpi.x),i32(f32(y)*dpi.y),0,0}}
}
smoke_button :: proc(down: bool) -> rl.AutomationEvent {
	type:=u32(5); if down { type=6 }
	return {type=type,params={0,0,0,0}}
}
sandbox_smoke_frame :: proc(game: ^Sandbox,target: rl.RenderTexture2D,events: ..rl.AutomationEvent) {
 sandbox_smoke_ui_frame(game,target,nil,..events)
}
sandbox_smoke_ui_frame :: proc(game: ^Sandbox,target: rl.RenderTexture2D,net:^Net_Game_UI,events: ..rl.AutomationEvent) {
	for event in events { rl.PlayAutomationEvent(event) }
 if net!=nil { net_gui_step(net,game) }
 online:=net!=nil && net.active
 network_panel:=net!=nil && net.open
	files_consumed:=false
 if !network_panel && (!online || game.editor.editing) { files_consumed=sandbox_layout_file_input(game) }
	width,height:=f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())
	view:=sandbox_view(width,height)
	mouse:=rl.GetMousePosition()
	over_ui:=sandbox_over_hud(mouse,width,height,game.inspection && !game.editor.editing) || game.palette_open
	raw:=sandbox_read_input(game)
 if network_panel && rl.IsKeyPressed(.ESCAPE) { raw.menu_pressed=true }
	input:=Sandbox_Input{}
 if network_panel && raw.menu_pressed { net.open=false;sandbox_set_panel(game,true);files_consumed=true }
	if !files_consumed && !network_panel {
  if online { net_gui_route_input(net,game,raw,view,over_ui) }
  else { input=sandbox_route_input(game,raw,over_ui) }
 }
	if !network_panel && (!online || game.editor.editing) && !files_consumed && !raw.menu_pressed && !raw.reset_pressed {
		if game.editor.editing { sandbox_editor_input(game,world_point(view,mouse),over_ui) }
		else if !sandbox_inspect_input(game,world_point(view,mouse),view,over_ui) && input.blast_pressed { sandbox_blast(game,world_point(view,mouse)) }
	}
 if !online && !network_panel { sandbox_advance(game,1.0/60.0,input) }
	poses:=make(map[u64]Pose); defer delete(poses)
	rl.BeginDrawing()
	rl.BeginTextureMode(target)
	rl.ClearBackground({19,28,42,255})
 if online && !game.editor.editing { net_client_draw(&net.client,view,game.outline_width);net_gui_draw_local_outline(net,view) }
 else { sandbox_draw_world(game,view,poses) }
	if !network_panel && !game.panel_open && !over_ui { if online { net_gui_aim_draw(net,view,mouse) } else { sandbox_draw_aim(game,view,mouse) } }
 action:=Sandbox_UI_Action.None
 if network_panel { action=net_gui_draw_panel(net,game,width,height) }
 else { action=sandbox_draw_hud(game,width,height,net) }
	rl.EndTextureMode()
	rl.EndDrawing()
	sandbox_dispatch_ui(game,action,net)
	sandbox_autosave_layout(game)
}
sandbox_smoke_click :: proc(game: ^Sandbox,target: rl.RenderTexture2D,x,y: i32) {
	sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(true))
	sandbox_smoke_frame(game,target,smoke_mouse(x,y),smoke_button(false))
}
sandbox_smoke_export :: proc(target: rl.RenderTexture2D,name: cstring) {
	image:=rl.LoadImageFromTexture(target.texture); rl.ImageFlipVertical(&image)
	assert(rl.ExportImage(image,name)); rl.UnloadImage(image)
}
// Native render regressions use fixed cameras and never step between widths.
sandbox_smoke_outline_samples :: proc(s: ^Scene,target: rl.RenderTexture2D,name: string,view: View) {
 cache_state:=Render_Cache_State{}; defer release_render_caches(&cache_state)
 caches:=&cache_state
 render_cache_prepass(s,caches)
 before,ok:=encode_snapshot(s); assert(ok); defer delete(before)
 poses:=make(map[u64]Pose); defer delete(poses)
 widths:=[4]f32{0,0.3,0.7,2}
 for width in widths {
  rl.BeginDrawing(); rl.BeginTextureMode(target)
  rl.ClearBackground({19,28,42,255})
  draw_scene(s,caches,view,poses,0,true,false,false,true,width)
  rl.EndTextureMode(); rl.EndDrawing()
  image:=rl.LoadImageFromTexture(target.texture); rl.ImageFlipVertical(&image)
  // Check actual raster pixels inside each posed logical silhouette, including
  // its boundary. Real openings outside all silhouettes remain legitimate.
  for sub in s.subdivisions {
   rendered:=render_outline(s,caches,sub,poses,true)
   screen:=make([]rl.Vector2,len(rendered.points))
   for point,i in rendered.points { screen[i]=screen_point(view,point) }
   defer delete(rendered.points); defer delete(screen)
   lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
   for rest in sub.outline.points { p:=screen_point(view,posed_point(sub,rest)); lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)} }
   x0,x1:=max(0,int(lo.x)),min(int(image.width)-1,int(hi.x)+1)
   y0,y1:=max(0,int(lo.y)),min(int(image.height)-1,int(hi.y)+1)
   for y in y0..=y1 { for x in x0..=x1 {
    color:=rl.GetImageColor(image,i32(x),i32(y))
    background:=color==rl.Color{19,28,42,255}
    if background && rl.CheckCollisionPointPoly({f32(x)+0.5,f32(y)+0.5},raw_data(screen),i32(len(screen))) {
     fmt.printf("Render check background: %s width %.1f sub %d pixel %d,%d\n",name,width,sub.id,x,y)
     assert(rl.ExportImage(image,"output/background-check.png"))
     assert(false,"Background pixel inside a rendered silhouette")
    }
   } }
  }
  assert(rl.ExportImage(image,rl.TextFormat("output/%s-%.1f.png",name,width)))
  rl.UnloadImage(image)
 }
 after,encoded:=encode_snapshot(s); defer delete(after)
 assert(encoded && string(before)==string(after),"Render samples changed simulation")
}
sandbox_smoke_wood_fill :: proc(target: rl.RenderTexture2D) {
 for presplit in 0..<2 {
  s:=new_scene(0.1)
  m:=add_material(&s,editor_material(.Wood)); seed:=u8(13); if presplit==1 { seed=42 }
  p:=add_piece(&s,m,seed)
  points:=[4]Vec2{{0,0},{6,0},{6,4},{0,4}}
  add_subdivision(&s,p,Polygon{points=points[:]},Pose{position={3,2}})
  if presplit==1 { presplit_piece(&s,p) }
  physics_init(&s)
  blast_pass(&s,Blast{{-0.1,2},5}); if presplit==0 { blast_pass(&s,Blast{{3,4.1},4}) }
  name:=string("wood-fill"); if presplit==1 { name="wood-presplit-outlines" }
  sandbox_smoke_outline_samples(&s,target,name,{offset={140,700},scale=150})
  scene_destroy(&s)
 }
 g:=sandbox_editor_create(); defer sandbox_destroy(&g); g.editor.palette=recipe_slot(.Glass)
 assert(editor_place(&g,{0,0},{2.4,1.2})); sandbox_toggle_editor(&g)
 body:=g.world.scene.subdivisions[0].body; pos:=b2.Body_GetPosition(body); pos.y+=0.8; b2.Body_SetTransform(body,pos,b2.MakeRot(0))
 for _ in 0..<90 { sandbox_tick(&g,0,false) }
 sandbox_smoke_outline_samples(&g.world.scene,target,"glass-impact-outlines",{offset={220,650},scale=220})
 // Fractional strokes must have exactly the 1-pixel reference's coverage.
 vertices:=[4]Vec2{{0,0},{3,0.7},{3,2},{0,1.3}}
 flags:=[4]bool{true,true,true,true}; cache:=Render_Cache{draw_edge=flags[:]}
 reference: rl.Image
 defer rl.UnloadImage(reference)
 widths:=[3]f32{1,0.3,0.7}
 for width in widths {
  rl.BeginDrawing(); rl.BeginTextureMode(target); rl.ClearBackground(rl.BLACK)
  draw_cached_strokes({offset={100,400},scale=80},Polygon{points=vertices[:]},rl.WHITE,width,&cache,false)
  rl.EndTextureMode(); rl.EndDrawing()
  image:=rl.LoadImageFromTexture(target.texture)
  if width==1 { reference=image; continue }
  for y in 0..<image.height { for x in 0..<image.width {
   a,b:=rl.GetImageColor(reference,x,y),rl.GetImageColor(image,x,y)
   assert((a.r>0)==(b.r>0),"Fractional stroke coverage differs from a solid 1px stroke")
  } }
  rl.UnloadImage(image)
 }
}
editor_smoke_drag :: proc(game: ^Sandbox,target: rl.RenderTexture2D,a,b: Vec2) {
	view:=sandbox_view(1280,800)
	p,q:=screen_point(view,a),screen_point(view,b)
	sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),smoke_button(true))
	sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)))
	assert(game.editor.dragging,"Rectangle preview did not start")
	sandbox_smoke_frame(game,target,smoke_mouse(i32(q.x),i32(q.y)),smoke_button(false))
}
sandbox_smoke_inputs :: proc(game: ^Sandbox) {
 material_native_interactions()
	rl.SetTargetFPS(0)
	target:=rl.LoadRenderTexture(rl.GetScreenWidth(),rl.GetScreenHeight())
	defer rl.UnloadRenderTexture(target)
	sandbox_smoke_wood_fill(target)
	assert(game.editor.editing && len(game.layout.objects)==0)
	initial_ground:=counts_live_subdivisions(&game.world.scene)
	sandbox_smoke_menu_page(game,target,.Appearance)
	assert(game.outline_width==2)
	revision_before_slider:=game.world.scene.revision
	sandbox_smoke_frame(game,target,smoke_mouse(640,401),smoke_button(true))
	sandbox_smoke_frame(game,target,smoke_mouse(400,401))
	sandbox_smoke_frame(game,target,smoke_button(false))
	assert(game.outline_width==0,"Slider left endpoint must disable outlines")
	sandbox_smoke_click(game,target,440,401)
	assert(game.outline_width>0 && game.outline_width<0.1,"Slider must support subpixel outlines")
	sandbox_smoke_frame(game,target,smoke_mouse(640,401),smoke_button(true))
	sandbox_smoke_frame(game,target,smoke_mouse(880,401))
	sandbox_smoke_frame(game,target,smoke_button(false))
	assert(game.outline_width==2,"Slider right endpoint must restore thick outlines")
	sandbox_smoke_frame(game,target,smoke_mouse(640,401),smoke_button(true))
	sandbox_smoke_frame(game,target,smoke_mouse(650,401))
	sandbox_smoke_frame(game,target,smoke_button(false))
	preferred_outline_width:=game.outline_width
	assert(preferred_outline_width>0 && preferred_outline_width<2 && game.world.scene.revision==revision_before_slider,"Outline width must only change presentation")
	sandbox_smoke_click(game,target,357,752)
	assert(game.editor.palette==recipe_slot(.Wood) && game.panel_open,"Settings must consume clicks on the underlying palette")
	sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
	sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
	pose:=b2.Body_GetPosition(game.world.players[0].body)
	for _ in 0..<60 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
	assert(b2.Body_GetPosition(game.world.players[0].body)==pose,"Editing must pause simulation")
	// Use each actual palette widget and drag into the clear building area.
	for choice in 0..<4 {
		sandbox_smoke_select_material(game,target,int(choice))
		assert(int(game.editor.palette)==choice)
		x:=f32(choice)*2.0-2.0
		editor_smoke_drag(game,target,{x,0},{x+1.2,1.2})
		assert(len(game.layout.objects)==choice+1 && int(game.layout.objects[choice].material)==choice)
	}
	editor_smoke_drag(game,target,{-2,0},{-0.8,1.2})
	assert(len(game.layout.objects)==4,"Overlap was not rejected")
	editor_smoke_drag(game,target,{0,2},{0,3})
	assert(len(game.layout.objects)==4,"Degenerate rectangle was not rejected")
	// Right mouse deletes an authored object, not its damaged graph.
	p:=screen_point(sandbox_view(1280,800),{4.5,0.5})
	sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),rl.AutomationEvent{type=6,params={1,0,0,0}})
	sandbox_smoke_frame(game,target,rl.AutomationEvent{type=5,params={1,0,0,0}})
	assert(len(game.layout.objects)==3)
	editor_smoke_drag(game,target,{4,0},{5.2,1.2})
	assert(len(game.layout.objects)==4)
	// A drag ending over palette controls is cancelled.
	p=screen_point(sandbox_view(1280,800),{6,2})
	sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),smoke_button(true))
	sandbox_smoke_frame(game,target,smoke_mouse(60,752),smoke_button(false))
	assert(len(game.layout.objects)==4 && !game.editor.dragging)
	sandbox_smoke_export(target,"output/sandbox-editor.png")
	sandbox_smoke_click(game,target,930,43)
	assert(!game.editor.editing && len(game.world.scene.pieces)==5)
	revision:=game.world.scene.revision
	for _ in 0..<90 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
	assert(game.world.players[0].grounded)
	sandbox_smoke_frame(game,target,smoke_key(.D,true))
	for _ in 0..<15 { sandbox_smoke_frame(game,target) }
	sandbox_smoke_frame(game,target,smoke_key(.D,false),smoke_key(.SPACE,true))
	// Allow the existing 0.1-second buffer to catch a seam crossing.
	for _ in 0..<5 { if b2.Body_GetLinearVelocity(game.world.players[0].body).y>5 { break }; sandbox_smoke_frame(game,target) }
	assert(b2.Body_GetLinearVelocity(game.world.players[0].body).y>5,"Space must jump in Test")
	for _ in 0..<120 { sandbox_smoke_frame(game,target) }
	assert(game.world.players[0].grounded,"Held jump must not repeat")
	sandbox_smoke_frame(game,target,smoke_key(.SPACE,false))
	// Settings consume input and keep radius/mode live without material overrides.
	sandbox_smoke_menu_page(game,target,.Gameplay)
	assert(game.panel_open && len(game.layout.objects)==4)
	pose=b2.Body_GetPosition(game.world.players[0].body)
	for _ in 0..<15 { sandbox_smoke_frame(game,target,smoke_key(.D,true)) }
	assert(b2.Body_GetPosition(game.world.players[0].body)==pose)
	sandbox_smoke_frame(game,target,smoke_key(.D,false))
	sandbox_smoke_click(game,target,845,426)
	assert(sandbox_radius(game)>5.1)
	sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true));sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
	assert(!game.panel_open)
	sandbox_set_radius(game,5)
	sandbox_smoke_frame(game,target,smoke_key(.F3,true))
	assert(game.inspection)
	sandbox_smoke_frame(game,target,smoke_key(.F3,false))
	sandbox_smoke_frame(game,target,smoke_key(.F3,true))
	sandbox_smoke_frame(game,target,smoke_key(.F3,false))
	sandbox_smoke_frame(game,target,smoke_key(.R,true))
	assert(game.world.scene.revision>revision && len(game.layout.objects)==4 && game.outline_width==preferred_outline_width,"Reset must preserve the outline preference")
	sandbox_smoke_frame(game,target,smoke_key(.R,false))
	sandbox_smoke_click(game,target,930,43)
	assert(game.editor.editing && len(game.layout.objects)==4 && counts_live_subdivisions(&game.world.scene)==initial_ground)
	// One controlled breakup for each brittle/rigid material, through native clicks.
	choices:=[3]Recipe{.Wood,.Glass,.Stone}
	for choice in choices {
		clear(&game.layout.objects)
		sandbox_smoke_select_material(game,target,int(choice))
		editor_smoke_drag(game,target,{1.5,0},{3.1,1.6})
		sandbox_smoke_click(game,target,930,43)
		original_ids:=[dynamic]u64{}
		for sub in game.world.scene.subdivisions { if sub.material!=0 { append(&original_ids,sub.id) } }
		original_material:=game.world.scene.subdivisions[0].material
		sandbox_set_radius(game,editor_material(choice).subdivision_strength/BLAST_LOAD_MULTIPLIER+1.2)
		aim:=screen_point(sandbox_view(1280,800),{1.2,0.8})
		sandbox_smoke_click(game,target,i32(aim.x),i32(aim.y))
		removed:=false; for id in original_ids { if !is_live_subdivision(&game.world.scene,id) { removed=true } }; delete(original_ids)
		assert(removed,"Material example did not fracture")
		for _ in 0..<20 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
		valid,message:=validate_scene(&game.world.scene); assert(valid,message)
		survivors:=0
		for sub in game.world.scene.subdivisions { if sub.live && sub.material==original_material { survivors+=1 } }
		assert(survivors>0,"The breakup example must retain visible material fragments")
		fmt.printf("%s breakup: %d surviving fragments\n",editor_material(choice).name,survivors)
		sandbox_smoke_export(target,rl.TextFormat("output/sandbox-material-%s.png",editor_material(choice).name))

		sandbox_smoke_click(game,target,930,43)
		assert(game.editor.editing && len(game.layout.objects)==1)
	}
	sandbox_set_radius(game,5)
	// Rubber: record a localized nudge, then a missing cell, using the same mesh.
	clear(&game.layout.objects)
	sandbox_smoke_select_material(game,target,2)
	editor_smoke_drag(game,target,{1,0},{3.4,0.8})
	sandbox_smoke_click(game,target,930,43)
	for _ in 0..<60 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
	ids:=game.world.scene.pieces[0].subdivisions
	b2.Body_ApplyLinearImpulseToCenter(subdivision_body(&game.world.scene,ids[len(ids)-1]),{0,0.3},true)
	for _ in 0..<6 { sandbox_smoke_frame(game,target) }
	sandbox_smoke_export(target,"output/sandbox-material-rubber.png")
	sandbox_smoke_frame(game,target,smoke_key(.F3,true))
	sandbox_smoke_frame(game,target,smoke_key(.F3,false))
	cell:=game.world.scene.subdivisions[game.world.scene.sub_rows[ids[len(ids)/2+2]]]
	p=screen_point(sandbox_view(1280,800),cell.pose.position)
	sandbox_smoke_frame(game,target,smoke_mouse(i32(p.x),i32(p.y)),rl.AutomationEvent{type=6,params={1,0,0,0}})
	sandbox_smoke_frame(game,target,rl.AutomationEvent{type=5,params={1,0,0,0}})
	assert(game.selected==cell.id)
	sandbox_smoke_frame(game,target,smoke_key(.DELETE,true))
	sandbox_smoke_frame(game,target,smoke_key(.DELETE,false))
	assert(!is_live_subdivision(&game.world.scene,cell.id))
	for _ in 0..<60 { sandbox_smoke_frame(game,target) }
	valid,message:=validate_scene(&game.world.scene); assert(valid,message)
	sandbox_smoke_frame(game,target,smoke_key(.F3,true))
	sandbox_smoke_frame(game,target,smoke_key(.F3,false))
	sandbox_smoke_export(target,"output/sandbox-rubber-cell-removed.png")
	// Bomb controls still use their native settings widgets and real contacts.
	sandbox_smoke_menu_page(game,target,.Gameplay)
	sandbox_smoke_click(game,target,780,346)
	assert(sandbox_mode(game)==.Falling_Bombs)
	sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
	sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
	for _ in 0..<160 {
		sandbox_smoke_frame(game,target)
		if len(game.world.bombs)>0 { break }
	}
	assert(len(game.world.bombs)>0)
	first:=game.world.bombs[0].body
	for _ in 0..<300 {
		sandbox_smoke_frame(game,target)
		if !b2.Body_IsValid(first) { break }
	}
	assert(!b2.Body_IsValid(first),"Falling bomb did not land and explode")
	sandbox_smoke_menu_page(game,target,.Gameplay)
	sandbox_smoke_click(game,target,500,346)
	assert(sandbox_mode(game)==.Manual)
	sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,true))
	sandbox_smoke_frame(game,target,smoke_key(.ESCAPE,false))
	sandbox_smoke_frame(game,target,smoke_key(.ENTER,true))
	assert(game.editor.editing && len(game.layout.objects)==1)
	sandbox_smoke_frame(game,target,smoke_key(.ENTER,false))
	// Draw larger Wood/Stone roots through the actual palette and Test widget.
	// Ordinary support must not refine either the object or its floor collider.
	placements:=[2]Recipe{.Wood,.Stone}
	for choice in placements {
		clear(&game.layout.objects)
		sandbox_smoke_select_material(game,target,int(choice))
		editor_smoke_drag(game,target,{1.5,0},{5.3,3.8})
		sandbox_smoke_click(game,target,930,43)
		before_regions,before_links,before_pieces:=counts_runtime(&game.world.scene)
		before_id:=game.world.scene.next_id
		for _ in 0..<120 { sandbox_smoke_frame(game,target,smoke_mouse(30,40)) }
		regions,links,pieces:=counts_runtime(&game.world.scene)
		assert(regions==before_regions && links==before_links && pieces==before_pieces && game.world.scene.next_id==before_id,"Placed material and floor must survive support without refinement")
		sandbox_smoke_click(game,target,930,43)
		assert(game.editor.editing)
	}
 // Snapshot tools remain available after removing the separate lab/receiver.
 sandbox_smoke_frame(game,target,smoke_key(.ENTER,true)); sandbox_smoke_frame(game,target,smoke_key(.ENTER,false))
 if !game.inspection { sandbox_smoke_frame(game,target,smoke_key(.F3,true)); sandbox_smoke_frame(game,target,smoke_key(.F3,false)) }
 sandbox_smoke_frame(game,target,smoke_key(.S,true)); sandbox_smoke_frame(game,target,smoke_key(.S,false))
 saved_id:=game.world.scene.next_id; saved_regions,saved_links,saved_pieces:=counts_runtime(&game.world.scene)
 sandbox_explode(game,{1.45,0.6})
 assert(game.world.scene.next_id!=saved_id)
 sandbox_smoke_frame(game,target,smoke_key(.L,true)); sandbox_smoke_frame(game,target,smoke_key(.L,false))
 restored_regions,restored_links,restored_pieces:=counts_runtime(&game.world.scene)
 assert(game.world.scene.next_id==saved_id && restored_regions==saved_regions && restored_links==saved_links && restored_pieces==saved_pieces,"Native snapshot load failed")
 assert(b2.Body_IsValid(game.world.players[0].body) && b2.Body_IsValid(game.world.floor))
	fmt.println("Editor native smoke passed: palette, drag preview, overlap/degenerate rejection, deletion, UI consumption, paused edit, Test/Edit restoration, reset, movement/jump, inspection, radius, material breakups, rubber, falling bombs, and snapshot save/load.")
}

// Native fixtures choose real picker rows and menu entries.
sandbox_smoke_select_material :: proc(game:^Sandbox,target:rl.RenderTexture2D,choice:int) {
 sandbox_smoke_click(game,target,120,rl.GetScreenHeight()-48)
 assert(game.palette_open)
 popup:=palette_popup(game,f32(rl.GetScreenHeight()))
 sandbox_smoke_click(game,target,130,i32(popup.y+25+f32(choice)*40))
 assert(!game.palette_open && game.editor.palette==Slot(choice))
}
sandbox_smoke_menu_page :: proc(game:^Sandbox,target:rl.RenderTexture2D,page:Menu_Page) {
 if !game.panel_open { sandbox_smoke_click(game,target,rl.GetScreenWidth()-90,43) }
 assert(game.panel_open)
 if game.menu_page!=.Main { sandbox_smoke_click(game,target,rl.GetScreenWidth()/2+185,rl.GetScreenHeight()/2-130) }
 box:=menu_box(f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight()),480,410)
 row:=0;switch page { case .Gameplay:row=0;case .Appearance:row=1;case .Help:row=3;case .Main:return }
 button:=menu_button(box,row)
 sandbox_smoke_click(game,target,i32(button.x+button.width/2),i32(button.y+button.height/2))
 assert(game.menu_page==page)
}
