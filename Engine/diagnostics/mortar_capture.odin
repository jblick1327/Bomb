package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import b2 "vendor:box2d"

mortar_smoke_controls :: proc() {
 target:=rl.LoadRenderTexture(1280,800); defer rl.UnloadRenderTexture(target)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 sandbox_smoke_frame(&g,target,smoke_key(.M,true)); sandbox_smoke_frame(&g,target,smoke_key(.M,false))
 assert(g.editor.mortar,"M key did not enable mortar")
 sandbox_smoke_click(&g,target,480,772); assert(!g.editor.mortar,"Mortar toggle did not disable mortar")
 sandbox_smoke_click(&g,target,480,772); assert(g.editor.mortar,"Mortar toggle did not enable mortar")
 sandbox_set_panel(&g,true)
 sandbox_smoke_frame(&g,target,smoke_key(.M,true)); sandbox_smoke_frame(&g,target,smoke_key(.M,false))
 sandbox_smoke_click(&g,target,480,772); assert(g.editor.mortar,"Paused panel allowed mortar input")
 sandbox_set_panel(&g,false)
 fmt.println("Mortar native controls: M key, toggle button, modal blocking passed")
}
run_mortar_captures :: proc(directory: string) {
 assert(os.make_directory_all(directory)==nil)
 rl.SetTraceLogLevel(.WARNING); rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"Mortar verification"); defer { presentation_shutdown(); rl.CloseWindow() }
 rl.SetTargetFPS(0); sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{})
 when ODIN_OS==.Windows {
  samples,buffers:i32; msaa_gl_integer(0x80a9,&samples); msaa_gl_integer(0x80a8,&buffers)
  fmt.printf("Mortar capture actual-MSAA samples=%d buffers=%d\n",samples,buffers); assert(samples==4 && buffers==1)
 }
 mortar_smoke_controls()
 for fixture in 0..<4 {
  g:=sandbox_editor_create(); name,title:=string("edit-mortar"),cstring("EDIT / Mortar objects")
  if fixture<2 {
   sandbox_destroy(&g); g=mortar_bridge_yard(); name="bridge-tick-0"; title="Bridge / tick 0"
   if fixture==1 { sandbox_fixture_radius(&g,5); sandbox_explode(&g,{-3,1}); for _ in 0..<90 { sandbox_tick(&g,0,false) }; name="bridge-blast-90"; title="Bridge / radius 5 at (-3, 1) / 90 ticks" }
  } else if fixture==2 {
   sandbox_destroy(&g); g=mortar_cantilever(4.4); for _ in 0..<120 { sandbox_tick(&g,0,false) }; name="f2-tick-120"; title="F2 / tick 120"
  } else {
   g.editor.mortar=true; g.editor.palette=recipe_slot(.Stone); assert(editor_place(&g,{0,0},{1,1}))
   g.editor.palette=recipe_slot(.Wood); assert(editor_place(&g,{1,0},{3.4,1})); g.status_time=0
  }
  g.outline_width=2
  poses:=make(map[u64]Pose)
  before,ok:=encode_world_snapshot(&g.world); assert(ok)
  rl.BeginDrawing(); rl.ClearBackground({19,28,42,255})
  sandbox_draw_world(&g,sandbox_view(1280,800),poses); sandbox_draw_hud(&g,1280,800)
  ui_text(.Heading,title,24,106,YARD_ACCENT)
  rlgl.DrawRenderBatchActive(); image:=rl.LoadImageFromScreen(); rl.EndDrawing()
  path:=fmt.caprintf("%s/%s.png",directory,name); assert(rl.ExportImage(image,path)); delete(path); rl.UnloadImage(image)
  after,encoded:=encode_world_snapshot(&g.world); assert(encoded && string(before)==string(after))
  snapshot_path:=fmt.aprintf("%s/%s.json",directory,name); assert(os.write_entire_file(snapshot_path,after)==nil); delete(snapshot_path)
  fmt.printf("Mortar capture %s tick=%d outline_width=2 World unchanged\n",name,g.world.tick)
  delete(before); delete(after); delete(poses); sandbox_destroy(&g)
 }
 fmt.printf("Mortar captures Box2D bytes after teardown=%d\n",b2.GetByteCount()); assert(b2.GetByteCount()==0)
}
