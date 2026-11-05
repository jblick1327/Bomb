package main

import rl "vendor:raylib"
import "core:fmt"
import "core:os"
import "core:time"
import "core:mem"
import b2 "vendor:box2d"

// Compare the actual HUD and aim pixels before the queued wheel setting reaches
// a tick with the same radius already applied. This does not advance physics.
editor_smoke_radius :: proc(target: rl.RenderTexture2D) {
	g:=sandbox_editor_create(); defer sandbox_destroy(&g)
	sandbox_toggle_editor(&g)
	view:=sandbox_view(1280,800)
	sandbox_set_radius(&g,2)
	images: [2]rl.Image
	defer { for image in images { rl.UnloadImage(image) } }
	for i in 0..<2 {
		if i==1 { g.world.settings.blast_radius=2; g.world.players[0].blast_radius=2; g.queued.players[0].radius=nil; g.queued.bomb_radius=nil }
		rl.BeginDrawing(); rl.BeginTextureMode(target)
		rl.ClearBackground({19,28,42,255})
		sandbox_draw_aim(&g,view,{640,300})
		sandbox_draw_hud(&g,1280,800)
		rl.EndTextureMode(); rl.EndDrawing()
		images[i]=rl.LoadImageFromTexture(target.texture)
		rl.ImageFlipVertical(&images[i])
	}
	hud,aim:=0,0
	for y in 0..<800 { for x in 0..<1280 {
		if rl.GetImageColor(images[0],i32(x),i32(y))!=rl.GetImageColor(images[1],i32(x),i32(y)) {
			if y>=744 { hud+=1 } else { aim+=1 }
		}
	} }
	fmt.printf("A1 pending radius: HUD mismatching pixels=%d, aim mismatching pixels=%d\n",hud,aim)
	segments:=0
	radii:=[3]f32{10,300,1000}
	for radius,i in radii {
		expected:=[3]i32{48,100,256}
		if sandbox_aim_segments(radius)!=expected[i] { segments+=1 }
	}
	fmt.printf("A2 adaptive aim segments: failing cases=%d/3\n",segments)
	assert(hud==0 && aim==0 && segments==0,"Queued radius and adaptive aim ring checks")
}
sandbox_smoke_editor :: proc() {
	assert(os.make_directory_all("evidence/editor-step2")==nil)
	box2d_before:=b2.GetByteCount()
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track,context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator=mem.tracking_allocator(&track)
	defer {
		box2d_delta:=b2.GetByteCount()-box2d_before
		fmt.printf("Editor smoke teardown: Odin bytes=%d Box2D delta bytes=%d\n",track.current_memory_allocated,box2d_delta)
		assert(track.current_memory_allocated==0 && box2d_delta==0,"Editor smoke leaked")
	}
	rl.SetTargetFPS(0)
	target:=rl.LoadRenderTexture(1280,800); defer rl.UnloadRenderTexture(target)
	editor_smoke_radius(target)
	g:=sandbox_editor_create(); defer sandbox_destroy(&g)
	before,encoded:=encode_world_snapshot(&g.world); assert(encoded); defer delete(before)
	poses:=make(map[u64]Pose); defer delete(poses)
	rl.BeginDrawing(); rl.BeginTextureMode(target)
	sandbox_draw_world(&g,sandbox_view(1280,800),poses)
	rl.EndTextureMode(); rl.EndDrawing()
	after,ok:=encode_world_snapshot(&g.world); assert(ok); defer delete(after)
	fmt.printf("A3 drawing changed World snapshot=%v; presentation cache entries=%d\n",string(before)!=string(after),len(g.render_caches.cells))
	assert(string(after)==string(before),"Drawing must leave the World unchanged")
	assert(len(g.render_caches.cells)==len(g.world.scene.subdivisions))
	keys:=[4]rl.KeyboardKey{.ONE,.TWO,.THREE,.FOUR}
	for key,i in keys {
		sandbox_smoke_frame(&g,target,smoke_key(key,true))
		assert(g.editor.palette==Slot(i),"Number key did not select material")
		sandbox_smoke_frame(&g,target,smoke_key(key,false))
	}
	sandbox_smoke_frame(&g,target,smoke_key(.TWO,true))
	sandbox_smoke_frame(&g,target,smoke_key(.TWO,false))
	assert(editor_place(&g,{0,0},{1.6,2}))
	a,b:=screen_point(sandbox_view(1280,800),{1.03,1.02}),screen_point(sandbox_view(1280,800),{2.62,3.01})
	sandbox_smoke_frame(&g,target,smoke_mouse(i32(a.x),i32(a.y)),smoke_button(true))
	sandbox_smoke_frame(&g,target,smoke_mouse(i32(b.x),i32(b.y)))
	assert(g.editor.dragging && g.editor.start==Vec2{1,1} && g.editor.cursor==Vec2{2.6,3})
	assert(editor_rectangle_problem(&g.layout,editor_rectangle(g.editor.start,g.editor.cursor,g.editor.palette))=="Overlaps an object")
	sandbox_smoke_export(target,"evidence/editor-step2/edit-invalid-drag.png")
	sandbox_smoke_frame(&g,target,smoke_button(false))
	assert(len(g.layout.objects)==1 && g.status=="Overlaps an object")
	fmt.println("B native smoke passed: number keys, snapped mouse preview, invalid reason and cancellation")
	editor_smoke_layout_files(target)
	editor_smoke_presets(target)
}

editor_smoke_presets :: proc(target: rl.RenderTexture2D) {
	directory:=fmt.aprintf("output/editor-preset-smoke-%d",time.to_unix_nanoseconds(time.now())); defer delete(directory)
	assert(os.make_directory_all(directory)==nil)
	for name,i in PRESET_NAMES {
		g:=sandbox_editor_create(); defer sandbox_destroy(&g)
		g.layout_directory=directory
		sandbox_smoke_frame(&g,target,smoke_mouse(30,40),smoke_button(false))
		sandbox_smoke_click(&g,target,1040,43)
		sandbox_smoke_click(&g,target,i32(348+(f32(i)+0.5)*(584-8*(f32(len(PRESET_NAMES))-1))/f32(len(PRESET_NAMES))+f32(i)*8),193)
		assert(g.editor.editing && !g.panel_open && len(g.layout.objects)>0,"Preset button did not load")
		path:=fmt.aprintf("%s/autosave.json",directory)
		saved,err:=os.read_entire_file(path,context.allocator); delete(path)
		layout,ok:=encode_layout(&g.layout,g.world.settings.seed)
		assert(err==nil && ok && string(saved)==string(layout),"Preset did not autosave")
		delete(saved); delete(layout)
		sandbox_smoke_click(&g,target,810,43)
		assert(!g.editor.editing && g.world.tick==0,"Preset capture must be Test at tick 0")
		before,encoded:=encode_world_snapshot(&g.world); assert(encoded); defer delete(before)
		poses:=make(map[u64]Pose); defer delete(poses)
		g.status_time=0
		rl.BeginDrawing(); rl.BeginTextureMode(target)
		rl.ClearBackground({19,28,42,255})
		sandbox_draw_world(&g,sandbox_view(1280,800),poses)
		sandbox_draw_hud(&g,1280,800)
		ui_text(.Heading,rl.TextFormat("%s / tick 0",name),24,105,YARD_ACCENT)
		rl.EndTextureMode(); rl.EndDrawing()
		sandbox_smoke_export(target,rl.TextFormat("evidence/editor-step2/preset-%d.png",i+1))
		after,ok2:=encode_world_snapshot(&g.world); defer delete(after)
		assert(ok2 && string(before)==string(after),"Capture changed the World")
	}
	fmt.println("D native smoke passed: all preset buttons, exact autosaves, unchanged Test/tick-0 captures")
}

editor_smoke_layout_files :: proc(target: rl.RenderTexture2D) {
	directory:=fmt.aprintf("output/editor-layout-smoke-%d",time.to_unix_nanoseconds(time.now())); defer delete(directory)
	assert(os.make_directory_all(directory)==nil)
	g:=sandbox_editor_create(); defer sandbox_destroy(&g)
	sandbox_start_layout_files(&g,directory)
	sandbox_smoke_frame(&g,target,smoke_mouse(30,40),smoke_button(false))
	editor_smoke_drag(&g,target,{0,0},{1.6,2})
	assert(g.last_session && g.autosaved_layout_revision==g.layout_revision,"Placement did not autosave")
	original,ok:=encode_layout(&g.layout,g.world.settings.seed); assert(ok); defer delete(original)
	sandbox_smoke_click(&g,target,1040,43)
	assert(g.layouts_open && g.panel_open,"Layouts button did not open")
	// A material shortcut and a drag over the underlying world are consumed.
	sandbox_smoke_frame(&g,target,smoke_key(.FOUR,true))
	sandbox_smoke_frame(&g,target,smoke_key(.FOUR,false))
	assert(g.editor.palette==recipe_slot(.Wood))
	sandbox_smoke_frame(&g,target,smoke_mouse(1100,400),smoke_button(true))
	assert(!g.editor.dragging)
	sandbox_smoke_frame(&g,target,smoke_button(false))
	sandbox_smoke_frame(&g,target,smoke_key(.TAB,true)); sandbox_smoke_frame(&g,target,smoke_key(.TAB,false))
	assert(!g.panel_open && !g.layouts_open,"Tab did not close Layouts")
	sandbox_smoke_click(&g,target,1040,43)
	sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,true)); sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,false))
	assert(!g.panel_open && !g.layouts_open,"Escape did not close Layouts")
	sandbox_smoke_click(&g,target,1040,43)
	sandbox_smoke_click(&g,target,640,238)
	assert(len(g.layout_files)==1 && os.is_file(g.layout_files[0].path),"Save button did not write a file")
	path:=fmt.aprintf("%s/layout-001.json",directory); defer delete(path)
	data,err:=os.read_entire_file(path,context.allocator); defer delete(data)
	assert(err==nil && string(data)==string(original),"Saved layout differs")
	sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,true)); sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,false))
	assert(editor_remove(&g,{0.8,1}))
	sandbox_smoke_frame(&g,target)
	assert(len(g.layout.objects)==0 && g.autosaved_layout_revision==g.layout_revision)
	sandbox_smoke_click(&g,target,1040,43)
	sandbox_smoke_click(&g,target,640,353)
	assert(g.editor.editing && !g.panel_open && len(g.layout.objects)==1,"Saved button did not load")
	restored,ok2:=encode_layout(&g.layout,g.world.settings.seed); defer delete(restored)
	assert(ok2 && string(restored)==string(original),"Loaded layout differs")
	sandbox_smoke_frame(&g,target,smoke_key(.LEFT_CONTROL,true),smoke_key(.S,true))
	sandbox_smoke_frame(&g,target,smoke_key(.LEFT_CONTROL,false),smoke_key(.S,false))
	assert(len(g.layout_files)==2,"Ctrl+S did not save")
	for _ in 0..<8 { assert(sandbox_save_current_layout(&g)) }
	assert(len(g.layout_files)==8)
	assert(g.layout_files[0].path==fmt.tprintf("%s/layout-010.json",directory),"Saved files are not newest first")
	sandbox_smoke_click(&g,target,1040,43)
	sandbox_smoke_click(&g,target,640,319)
	assert(!g.panel_open && len(g.layout.objects)==1,"Last session button did not load")
	// A fresh application restores the autosaved layout; no Test state is saved.
	fresh:=sandbox_editor_create(); defer sandbox_destroy(&fresh)
	sandbox_start_layout_files(&fresh,directory)
	restarted,ok3:=encode_layout(&fresh.layout,fresh.world.settings.seed); defer delete(restarted)
	assert(ok3 && string(restarted)==string(original) && fresh.editor.editing)
	sandbox_toggle_editor(&g)
	assert(sandbox_load_layout_file(&g,path) && g.editor.editing,"Loading from Test did not switch to Edit")
	fmt.println("C native smoke passed: modal open/Tab/Escape/blocks input, Save button, saved-file load, Ctrl+S, autosave placement/removal/load/startup, Test-to-Edit load")
}
