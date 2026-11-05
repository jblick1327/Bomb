package main
import rl "vendor:raylib"
import gl "vendor:raylib/rlgl"
import b2 "vendor:box2d"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"

cream_pixel :: proc(c:rl.Color)->bool {
 return math.abs(int(c.r)-236)<=12 && math.abs(int(c.g)-226)<=12 && math.abs(int(c.b)-198)<=12
}
cream_rectangle :: proc(image:rl.Image,x0,y0,x1,y1:i32)->int {
 count:=0;for y in y0..<y1 { for x in x0..<x1 { if cream_pixel(rl.GetImageColor(image,x,y)) { count+=1 } } };return count
}
seam_followup_captures :: proc() {
 target:=rl.LoadRenderTexture(1280,800);defer rl.UnloadRenderTexture(target)
 poses:=make(map[u64]Pose);defer delete(poses)
 for shot in 0..<3 {
  g:=seam_demo_game();ticks:=600
  if shot==1 { ticks=20;sandbox_fixture_radius(&g,4);sandbox_explode(&g,{-3.8,0.5}) }
  for _ in 0..<ticks { sandbox_tick(&g,0,false) };g.status_time=0
  view:=sandbox_view(1280,800);if shot==2 { view={offset={40,1580},scale=400} }
  before,ok:=encode_world_snapshot(&g.world);assert(ok)
  ui_overflows=0
  rl.BeginDrawing();rl.BeginTextureMode(target);rl.ClearBackground({19,28,42,255})
  if shot==2 {
   draw_scene(&g.world.scene,&g.render_caches,view,poses,0,true,false,false,true,2)
   rl.DrawRectangle(0,0,1280,88,{19,28,42,255});ui_text(.Title,"Roof ridge / continuous glue",24,20,YARD_INK);ui_text(.Small,"Test / 600 ticks",24,58,YARD_MUTED)
  } else { sandbox_draw_world(&g,view,poses);sandbox_draw_hud(&g,1280,800) }
  rl.EndTextureMode();rl.EndDrawing()
  path:=cstring("evidence/seam-toughness/demo-test-600.png");if shot==1 { path="evidence/seam-toughness/demo-test-blast-20.png" };if shot==2 { path="evidence/seam-toughness/ridge-closeup.png" }
  sandbox_smoke_export(target,path)
  image:=rl.LoadImageFromTexture(target.texture);rl.ImageFlipVertical(&image)
  if shot<2 {
   floor:=cream_rectangle(image,824,470,870,483);brace:=cream_rectangle(image,859,300,887,337);ridge:=cream_rectangle(image,710,197,723,290)
   fmt.printf("Cream shot=%d right_floor=%d right_brace=%d ridge=%d\n",shot,floor,brace,ridge);assert(floor>0 && brace>0 && ridge>0)
  } else {
   gaps:=0;for y in 120..<560 { if cream_rectangle(image,625,i32(y),657,i32(y+1))==0 { gaps+=1 } }
   fmt.printf("Ridge PNG interior rows=440 gaps=%d\n",gaps);assert(gaps==0)
  }
  rl.UnloadImage(image)
  after,aok:=encode_world_snapshot(&g.world);assert(aok && string(before)==string(after));delete(before);delete(after)
  fmt.printf("Follow-up capture %s overflow=%d render_world_identical=true\n",path,ui_overflows);assert(ui_overflows==0)
  if shot==2 {
   rl.BeginDrawing();rl.ClearBackground({19,28,42,255});draw_scene(&g.world.scene,&g.render_caches,view,poses,0,true,false,false,true,2);gl.DrawRenderBatchActive();image=rl.LoadImageFromScreen();rl.EndDrawing()
   dpi:=f32(image.width)/1280;gaps,rows:=0,0
   for y in i32(120*dpi)..<i32(560*dpi) { if cream_rectangle(image,i32(625*dpi),y,i32(657*dpi),y+1)==0 { gaps+=1 };rows+=1 }
   fmt.printf("Ridge actual4x interior rows=%d gaps=%d\n",rows,gaps);assert(gaps==0);rl.UnloadImage(image)
  }
  sandbox_destroy(&g)
 }
}
run_seam_followup_checks :: proc() {
 assert(os.make_directory_all("evidence/seam-toughness")==nil)
 track:mem.Tracking_Allocator;mem.tracking_allocator_init(&track,context.allocator);defer mem.tracking_allocator_destroy(&track);context.allocator=mem.tracking_allocator(&track)
 rl.SetTraceLogLevel(.WARNING);rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI});rl.InitWindow(1280,800,"Glue follow-up verification");defer rl.CloseWindow()
 rl.SetExitKey(.KEY_NULL);sandbox_gui_style();rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{});rl.SetTargetFPS(0)
 samples,buffers:i32;msaa_gl_integer(0x80a9,&samples);msaa_gl_integer(0x80a8,&buffers);assert(samples==4 && buffers==1);fmt.printf("Follow-up actual MSAA=%d fonts=%v\n",samples,ui_fonts_ready)
 shape_texture_checks();seam_followup_captures()
 presentation_shutdown();fmt.printf("Follow-up teardown Odin=%d Box2D=%d texture=%d shader=%d fonts=%v\n",track.current_memory_allocated,b2.GetByteCount(),material_texture.id,material_shader.id,ui_fonts_ready);assert(track.current_memory_allocated==0 && b2.GetByteCount()==0)
}
