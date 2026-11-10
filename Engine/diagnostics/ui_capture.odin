package main
import rl "vendor:raylib"
import "core:os"
import "core:fmt"

run_ui_captures :: proc(directory:string) {
 assert(os.make_directory_all(directory)==nil)
 rl.SetTraceLogLevel(.WARNING); rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"BOM UI capture"); defer { presentation_shutdown(); rl.CloseWindow() }
 sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{}); rl.SetTargetFPS(0)
 target:=rl.LoadRenderTexture(1280,800); defer rl.UnloadRenderTexture(target)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 assert(sandbox_load_preset(&g,0)); assert(materials_duplicate(&g,.Wood))
 g.layout_directory="output/ui-capture-layouts"; assert(os.make_directory_all(g.layout_directory)==nil)
 assert(sandbox_save_current_layout(&g)); sandbox_autosave_layout(&g)
 poses:=make(map[u64]Pose); defer delete(poses)
 for i in 0..<9 {
  if i==1 { sandbox_toggle_editor(&g) }
  if i==2 { sandbox_toggle_editor(&g); sandbox_set_materials_panel(&g); g.material_selected=0; materials_sync_name(&g) }
  if i==3 { g.material_selected=4; materials_sync_name(&g) }
  if i==4 { sandbox_set_layouts_panel(&g,true) }
  if i==5 { sandbox_set_panel(&g,true) }
  if i==6 { g.menu_page=.Gameplay }
  if i==7 { g.menu_page=.Appearance }
  if i==8 { g.menu_page=.Help }
  ui_overflows=0
  rl.BeginDrawing(); rl.BeginTextureMode(target); rl.ClearBackground({19,28,42,255})
  sandbox_draw_world(&g,sandbox_view(1280,800),poses); sandbox_draw_hud(&g,1280,800)
  rl.EndTextureMode(); rl.EndDrawing()
  names:=[9]string{"edit-hud","test-hud","materials-builtin","materials-custom","layouts","menu","gameplay","appearance","help"}
  fmt.printf("UI screen=%s overflow=%d\n",names[i],ui_overflows)
  path:=fmt.aprintf("%s/%s.png",directory,names[i]); sandbox_smoke_export(target,cstring_clone(path)); delete(path)
 }
}
cstring_clone :: proc(s:string)->cstring { return rl.TextFormat("%s",s) }

run_texture_captures :: proc() {
 assert(os.make_directory_all("evidence/textures-ui/after")==nil)
 rl.SetTraceLogLevel(.WARNING);rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI});rl.InitWindow(1280,800,"Texture closeups");defer { presentation_shutdown();rl.CloseWindow() }
 sandbox_gui_style();rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{});rl.SetTargetFPS(0)
 target:=rl.LoadRenderTexture(1280,800);defer rl.UnloadRenderTexture(target)
 rl.BeginDrawing();rl.BeginTextureMode(target);rl.ClearBackground({19,28,42,255})
 ui_label(.Title,"Procedural materials / 2x game scale",{24,20,1100,40},YARD_INK)
 scale:=2*sandbox_view(1280,800).scale
 texture_begin()
 for i in 0..<6 {
  m:=editor_material(.Wood);if i<4 { for recipe in Recipe { if int(recipe)==i { m=editor_material(recipe) } } }
  if i==4 { m.color={231,104,91} };if i==5 { m.color={236,215,119} }
  x,y:=f32(24+(i%3)*416),f32(300+(i/3)*340)
  texture_rectangle({offset={x,y},scale=scale},Authored_Shape{lo={0,0},hi={2.4,1.4}},m)
 }
 texture_end()
 names:=[6]cstring{"Wood","Glass","Rubber","Stone","Custom Wood / coral","Custom Wood / yellow"}
 for name,i in names { ui_label(.Heading,name,{f32(24+(i%3)*416),f32(314+(i/3)*340),380,30},YARD_INK) }
 ui_label(.Small,rl.TextFormat("Rest UVs / 4 m repeat / view scale %.1f px per metre",scale),{24,752,1200,24},YARD_MUTED)
 rl.EndTextureMode();rl.EndDrawing();sandbox_smoke_export(target,"evidence/textures-ui/after/texture-closeups.png")
 g:=sandbox_editor_create();defer sandbox_destroy(&g);assert(sandbox_load_preset(&g,0));sandbox_toggle_editor(&g);sandbox_fixture_radius(&g,4);sandbox_explode(&g,{-7.5,1})
 for _ in 0..<30 { sandbox_tick(&g,0,false) }
 poses:=make(map[u64]Pose);defer delete(poses)
 for i in 0..<2 {
  if i==1 { sandbox_toggle_editor(&g) };g.status_time=0
  before,ok:=encode_world_snapshot(&g.world);assert(ok)
  rl.BeginDrawing();rl.BeginTextureMode(target);rl.ClearBackground({19,28,42,255});sandbox_draw_world(&g,sandbox_view(1280,800),poses);sandbox_draw_hud(&g,1280,800);rl.EndTextureMode();rl.EndDrawing()
  if i==0 { sandbox_smoke_export(target,"evidence/textures-ui/after/materials-after-blast.png") } else { sandbox_smoke_export(target,"evidence/textures-ui/after/materials-edit.png") }
  after,aok:=encode_world_snapshot(&g.world);assert(aok && string(before)==string(after));delete(before);delete(after)
 }
 fmt.printf("Texture closeups: view scale=%.1f, Materials preset blast=(-7.5,1), radius=4, tick=30; render leaves World unchanged\n",scale)
}
