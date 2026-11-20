package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:fmt"
import "core:os"

run_glass_captures :: proc(directory: string) {
 assert(os.make_directory_all(directory)==nil)
 rl.SetTraceLogLevel(.WARNING); rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"Glass shock verification"); defer { presentation_shutdown(); rl.CloseWindow() }
 sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{})
 when ODIN_OS==.Windows {
  samples,buffers:i32; msaa_gl_integer(0x80a9,&samples); msaa_gl_integer(0x80a8,&buffers)
  fmt.printf("Glass capture actual-MSAA: samples=%d buffers=%d\n",samples,buffers); assert(samples==4 && buffers==1)
 }
 for fixture in 0..<3 {
  g:Sandbox; name:=string("glass-house"); view:=View{offset={400,650},scale=95}
  if fixture<2 {
   g=glass_pane_yard(f32(3+fixture)); name="pane-r3"; if fixture==1 { name="pane-r4" }
   for _ in 0..<30 { sandbox_tick(&g,0,false) }; view={offset={150,700},scale=110}
  } else {
   g=preset_test_yard(2); sandbox_fixture_radius(&g,4); sandbox_explode(&g,{-2,1})
   for _ in 0..<60 { sandbox_tick(&g,0,false) }
  }
  before,ok:=encode_world_snapshot(&g.world); assert(ok)
  poses:=make(map[u64]Pose); for sub in g.world.scene.subdivisions { if sub.live { poses[sub.id]=sub.pose } }
  rl.BeginDrawing(); rl.ClearBackground({19,28,42,255})
  draw_scene(&g.world.scene,&g.render_caches,view,poses,0,true,false,false,true,2)
  rlgl.DrawRenderBatchActive(); image:=rl.LoadImageFromScreen(); rl.EndDrawing()
  path:=fmt.caprintf("%s/%s-2.png",directory,name); assert(rl.ExportImage(image,path)); delete(path); rl.UnloadImage(image)
  after,encoded:=encode_world_snapshot(&g.world); assert(encoded && string(before)==string(after))
  json_path:=fmt.aprintf("%s/%s.json",directory,name); assert(os.write_entire_file(json_path,after)==nil); delete(json_path)
  delete(before); delete(after); delete(poses); sandbox_destroy(&g)
 }
}
