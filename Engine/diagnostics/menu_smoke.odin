package main

import rl "vendor:raylib"
import b2 "vendor:box2d"
import "core:os"
import "core:fmt"
import "core:time"
import "core:mem"

menu_smoke_click :: proc(game:^Sandbox,target:rl.RenderTexture2D,net:^Net_Game_UI,x,y:i32) {
 sandbox_smoke_ui_frame(game,target,net,smoke_mouse(x,y),smoke_button(true))
 sandbox_smoke_ui_frame(game,target,net,smoke_mouse(x,y),smoke_button(false))
}
menu_smoke_capture :: proc(game:^Sandbox,target:rl.RenderTexture2D,name:string,net:^Net_Game_UI=nil) {
 before,ok:=encode_world_snapshot(&game.world);assert(ok);defer delete(before)
 width,height:=f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight())
 poses:=make(map[u64]Pose);defer delete(poses)
 ui_overflows=0
 rl.BeginDrawing();rl.BeginTextureMode(target);rl.ClearBackground({19,28,42,255})
 if net!=nil && net.active && !game.editor.editing { net_client_draw(&net.client,&net.client_view,sandbox_view(width,height),game.outline_width) }
 else { sandbox_draw_world(game,sandbox_view(width,height),poses) }
 if net!=nil && net.open { _=net_gui_draw_panel(net,game,width,height) }
 else { _=sandbox_draw_hud(game,width,height,net) }
 rl.EndTextureMode();rl.EndDrawing()
 path:=fmt.aprintf("evidence/menu-simplification/%s.png",name);defer delete(path)
 sandbox_smoke_export(target,cstring_clone(path))
 after,encoded:=encode_world_snapshot(&game.world);defer delete(after)
 fmt.printf("MENU capture=%s size=%.0fx%.0f overflow=%d world_unchanged=%v\n",name,width,height,ui_overflows,encoded && string(before)==string(after))
 assert(encoded && string(before)==string(after),"Menu rendering changed the World")
 assert(ui_overflows==0,"Menu text overflowed")
}

run_menu_smoke :: proc() {
 assert(os.make_directory_all("evidence/menu-simplification")==nil)
 rl.SetTraceLogLevel(.WARNING);rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_RESIZABLE,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"BOM menu verification");defer { presentation_shutdown();rl.CloseWindow() }
 rl.SetExitKey(.KEY_NULL);sandbox_gui_style();rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{});rl.SetTargetFPS(0)
 track:mem.Tracking_Allocator;mem.tracking_allocator_init(&track,context.allocator);defer mem.tracking_allocator_destroy(&track)
 context.allocator=mem.tracking_allocator(&track)
 before:=b2.GetByteCount()
 defer { fmt.printf("MENU teardown Odin=%d Box2D=%d\n",track.current_memory_allocated,b2.GetByteCount()-before);assert(track.current_memory_allocated==0 && b2.GetByteCount()==before) }
 g:=sandbox_editor_create();defer sandbox_destroy(&g)
 target:=rl.LoadRenderTexture(1280,800);defer rl.UnloadRenderTexture(target)
 sandbox_smoke_frame(&g,target,smoke_mouse(30,90),smoke_button(false))
 menu_smoke_capture(&g,target,"edit")
 sandbox_smoke_click(&g,target,120,752);assert(g.palette_open)
 menu_smoke_capture(&g,target,"palette")
 sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,true));sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,false));assert(!g.palette_open && !g.panel_open)
 sandbox_smoke_manage_materials(&g,target);menu_smoke_capture(&g,target,"material-builtin")
 sandbox_smoke_click(&g,target,600,415);assert(len(g.layout.materials)==1)
 menu_smoke_capture(&g,target,"material-custom")
 sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,true));sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,false))
 sandbox_smoke_menu_page(&g,target,.Main);menu_smoke_capture(&g,target,"menu")
 sandbox_smoke_menu_page(&g,target,.Gameplay);menu_smoke_capture(&g,target,"gameplay")
 sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,true));sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,false))
 sandbox_smoke_menu_page(&g,target,.Appearance);menu_smoke_capture(&g,target,"appearance")
 sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,true));sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,false))
 sandbox_smoke_menu_page(&g,target,.Help);menu_smoke_capture(&g,target,"help")
 g.editor.glue_tool=true
 sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,true));sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,false))
 assert(!g.panel_open,"Escape must close Help even when the glue tool is active")
 g.editor.glue_tool=false
 sandbox_smoke_select_material(&g,target,0)
 editor_smoke_drag(&g,target,{0,0},{1,1});assert(len(g.layout.objects)==1)
 sandbox_smoke_click(&g,target,930,43);assert(!g.editor.editing);menu_smoke_capture(&g,target,"test")
 sandbox_smoke_click(&g,target,930,43);assert(g.editor.editing)
 // Check every page at the application's actual minimum window size.
 rl.SetWindowSize(900,700);sandbox_smoke_frame(&g,target);sandbox_smoke_frame(&g,target)
 small:=rl.LoadRenderTexture(900,700);defer rl.UnloadRenderTexture(small)
 for page in Menu_Page { sandbox_set_panel(&g,true);g.menu_page=page;menu_smoke_capture(&g,small,fmt.tprintf("small-menu-%d",int(page))) }
 sandbox_set_materials_panel(&g);g.material_selected=0;materials_sync_name(&g);menu_smoke_capture(&g,small,"small-material-builtin")
 g.material_selected=4;materials_sync_name(&g);menu_smoke_capture(&g,small,"small-material-custom")
 sandbox_set_panel(&g,false)
 rl.SetWindowSize(1280,800);sandbox_smoke_frame(&g,target);sandbox_smoke_frame(&g,target)
 net:Net_Game_UI;net_gui_init(&net);defer net_gui_destroy(&net)
 sandbox_smoke_click(&g,target,1180,43)
 box:=menu_box(1280,800,480,410);button:=menu_button(box,2)
 menu_smoke_click(&g,target,&net,i32(button.x+button.width/2),i32(button.y+button.height/2));assert(net.open)
 menu_smoke_capture(&g,target,"multiplayer",&net)
 menu_smoke_click(&g,target,&net,510,435);assert(net.active && net.hosting)
 rl.SetTargetFPS(60)
 for _ in 0..<240 { sandbox_smoke_ui_frame(&g,target,&net,smoke_mouse(30,90));if net.client.real_hello_ok && net.client.real_has_settings && net.client.has_complete { break } }
 assert(net.active && net.client.real_is_host && net.client.real_has_settings && net.client.has_complete,"Host menu did not establish a real session")
 menu_smoke_click(&g,target,&net,930,43);assert(g.editor.editing)
 // A real host must be able to place a new object after returning to Edit.
 view:=sandbox_view(1280,800);a,b:=screen_point(view,{2,0}),screen_point(view,{3,1})
 sandbox_smoke_ui_frame(&g,target,&net,smoke_mouse(i32(a.x),i32(a.y)),smoke_button(true))
 sandbox_smoke_ui_frame(&g,target,&net,smoke_mouse(i32(b.x),i32(b.y)))
 assert(g.editor.dragging,"Host Edit did not begin a drag")
 sandbox_smoke_ui_frame(&g,target,&net,smoke_button(false));assert(len(g.layout.objects)==2)
 epoch:=net.client.epoch
 menu_smoke_click(&g,target,&net,930,43);assert(!g.editor.editing)
 for _ in 0..<180 { sandbox_smoke_ui_frame(&g,target,&net,smoke_mouse(30,90));if net.client.epoch>epoch { break } }
 assert(net.client.epoch>epoch,"Test did not upload the edited layout")
 menu_smoke_click(&g,target,&net,1180,43)
 button=menu_button(box,0);menu_smoke_click(&g,target,&net,640,i32(button.y+button.height/2))
 menu_smoke_click(&g,target,&net,580,426)
 for _ in 0..<30 { sandbox_smoke_ui_frame(&g,target,&net,smoke_mouse(30,90)) }
 menu_smoke_capture(&g,target,"multiplayer-gameplay",&net)
 fmt.printf("MENU gameplay page=%v open=%v host=%v radius=%.3f\n",g.menu_page,g.panel_open,net.client.real_is_host,net.client.real_settings.blast_radius)
 assert(net.client.real_settings.blast_radius<3,"Host gameplay slider did not reach the server")
 sandbox_smoke_ui_frame(&g,target,&net,smoke_key(.ESCAPE,true));sandbox_smoke_ui_frame(&g,target,&net,smoke_key(.ESCAPE,false))
 menu_smoke_capture(&g,target,"multiplayer-test",&net)
 menu_smoke_click(&g,target,&net,1180,43);button=menu_button(box,2)
 menu_smoke_click(&g,target,&net,640,i32(button.y+button.height/2))
 menu_smoke_capture(&g,target,"multiplayer-connected",&net)
 menu_smoke_click(&g,target,&net,640,485);assert(!net.active && g.editor.editing && len(g.layout.objects)==2)
 // Let the specified host-left grace finish, then release its process handle.
 for _ in 0..<360 { _=net_gui_reap_server(&net);if !net.server_started { break };rl.BeginDrawing();rl.EndDrawing() }
 assert(!net.server_started,"Local server did not close after leaving")
 fmt.println("MENU PASS: picker, custom editor, all menu pages, minimum size, real Host, Edit placement, layout upload, radius synchronization and Leave")
}
