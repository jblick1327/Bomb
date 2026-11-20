package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:fmt"
import "core:os"
import "core:mem"
import b2 "vendor:box2d"

// Default-framebuffer capture, never a single-sample render texture.
run_rubber_band_capture :: proc(directory: string) {
 assert(os.make_directory_all(directory)==nil)
 rl.SetTraceLogLevel(.WARNING)
 rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"Rubber band verification"); defer { presentation_shutdown(); rl.CloseWindow() }
 sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{})
 when ODIN_OS==.Windows {
  samples,buffers:i32
  msaa_gl_integer(0x80a9,&samples); msaa_gl_integer(0x80a8,&buffers)
  fmt.printf("Band actual-MSAA: samples=%d buffers=%d framebuffer=%dx%d\n",samples,buffers,rl.GetRenderWidth(),rl.GetRenderHeight())
  assert(samples==4 && buffers==1)
 }
 track: mem.Tracking_Allocator
 mem.tracking_allocator_init(&track,context.allocator); defer mem.tracking_allocator_destroy(&track)
 context.allocator=mem.tracking_allocator(&track)
 box2d_before:=b2.GetByteCount()
 for fixture in 0..<4 {
  g:=sandbox_editor_create()
  view:=sandbox_view(1280,800)
  name:=string("materials")
  if fixture==0 || fixture==1 {
   scene_destroy(&g.world.scene)
   if fixture==0 { g.world.scene=rubber_bite_scene(); name="rubber-bite"; view={offset={250,650},scale=280} }
   else { g.world.scene=rubber_bend_scene(); name="rubber-bend"; view={offset={140,700},scale=150} }
  } else {
   assert(sandbox_load_preset(&g,0)); sandbox_toggle_editor(&g)
   if fixture==3 {
    sandbox_fixture_radius(&g,6); sandbox_explode(&g,{-0.6,1})
    for _ in 0..<30 { sandbox_tick(&g,0,false) }
    name="materials-blast"
   }
  }
  before,ok:=encode_snapshot(&g.world.scene)
  if fixture>=2 { delete(before); before,ok=encode_world_snapshot(&g.world) }
  assert(ok)
  poses:=make(map[u64]Pose)
  for sub in g.world.scene.subdivisions { if sub.live { poses[sub.id]=sub.pose } }
  widths:=[2]f32{0,2}
  for width in widths {
   rl.BeginDrawing(); rl.ClearBackground({19,28,42,255})
   draw_scene(&g.world.scene,&g.render_caches,view,poses,0,true,false,false,true,width)
   rlgl.DrawRenderBatchActive(); image:=rl.LoadImageFromScreen(); rl.EndDrawing()
   path:=fmt.caprintf("%s/%s-%.0f.png",directory,name,width)
   assert(rl.ExportImage(image,path)); delete(path); rl.UnloadImage(image)
  }
  after,encoded:=encode_snapshot(&g.world.scene)
  if fixture>=2 { delete(after); after,encoded=encode_world_snapshot(&g.world) }
  assert(encoded && string(before)==string(after),"Band capture changed World")
  path:=fmt.aprintf("%s/%s.json",directory,name)
  assert(os.write_entire_file(path,after)==nil); delete(path)
  if fixture==0 {
   cross_gap,checked,off_hull,spans:=rubber_bite_measure(&g.world.scene,&g.render_caches)
   fmt.printf("rubber-bite: cross-gap=%d checked=%d off-hull=%d top-spans=%d\n",cross_gap,checked,off_hull,spans)
  }
  delete(before); delete(after); delete(poses); sandbox_destroy(&g)
 }
 fmt.printf("Band capture teardown: Odin bytes=%d Box2D delta=%d\n",track.current_memory_allocated,b2.GetByteCount()-box2d_before)
 assert(track.current_memory_allocated==0 && b2.GetByteCount()==box2d_before)
}
