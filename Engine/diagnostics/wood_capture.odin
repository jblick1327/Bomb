package main
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:fmt"
import "core:os"

run_wood_captures :: proc(directory: string) {
 assert(os.make_directory_all(directory)==nil)
 rl.SetTraceLogLevel(.WARNING); rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"Wood splinter verification"); defer { presentation_shutdown(); rl.CloseWindow() }
 sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{})
 when ODIN_OS==.Windows {
  samples,buffers:i32; msaa_gl_integer(0x80a9,&samples); msaa_gl_integer(0x80a8,&buffers)
  fmt.printf("Wood capture actual-MSAA: samples=%d buffers=%d\n",samples,buffers); assert(samples==4 && buffers==1)
 }
 for fixture in 0..<3 {
  g:=sandbox_editor_create(); view:=View{offset={140,700},scale=150}; name:=string("plank")
  if fixture==0 { scene_destroy(&g.world.scene); g.world.scene=wood_plank_scene(); view={offset={180,550},scale=150} }
  if fixture==1 {
   assert(editor_place(&g,{0,0},{6,4})); sandbox_toggle_editor(&g)
   for _ in 0..<120 { sandbox_tick(&g,0,false) }; sandbox_explode(&g,{-0.1,2}); name="wood-blast"
  }
  if fixture==2 {
   assert(sandbox_load_preset(&g,1)); sandbox_toggle_editor(&g); sandbox_explode(&g,{0.2,1.6})
   for _ in 0..<60 { sandbox_tick(&g,0,false) }; name="tower"; view={offset={240,700},scale=120}
  }
  before,ok:=encode_snapshot(&g.world.scene); assert(ok)
  poses:=make(map[u64]Pose); for sub in g.world.scene.subdivisions { if sub.live { poses[sub.id]=sub.pose } }
  rl.BeginDrawing(); rl.ClearBackground({19,28,42,255})
  draw_scene(&g.world.scene,&g.render_caches,view,poses,0,true,false,fixture==0,true,2)
  rlgl.DrawRenderBatchActive(); image:=rl.LoadImageFromScreen(); rl.EndDrawing()
  path:=fmt.caprintf("%s/%s-2.png",directory,name); assert(rl.ExportImage(image,path)); delete(path); rl.UnloadImage(image)
  after,encoded:=encode_snapshot(&g.world.scene); assert(encoded && string(before)==string(after))
  json_path:=fmt.aprintf("%s/%s.json",directory,name); assert(os.write_entire_file(json_path,after)==nil); delete(json_path)
  delete(before); delete(after); delete(poses); sandbox_destroy(&g)
 }
}
