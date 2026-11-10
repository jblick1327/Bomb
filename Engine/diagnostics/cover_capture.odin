package main
import "core:fmt"
import "core:os"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
@(thread_local) cover_wood_failures:int
run_cover_capture :: proc() {
 assert(os.make_directory_all("evidence/blast-cover")==nil)
 rl.SetTraceLogLevel(.WARNING); rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI}); rl.InitWindow(1000,700,"Blast cover"); defer { presentation_shutdown(); rl.CloseWindow() }
 sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{})
 for variant in 0..<2 {
  g:=sandbox_editor_create(); g.editor.palette=recipe_slot(.Stone); assert(editor_place(&g,{2,0},{2.4,2.4})); g.editor.palette=recipe_slot(.Wood); assert(editor_place(&g,{2.6,0},{3.6,1.6})); sandbox_toggle_editor(&g)
  if variant==0 { for &m in g.world.scene.materials { m.blast_resistance=0 } }
  cover_wood_failures=0; blast_pass(&g.world.scene,Blast{{1,1},5})
  area:f32; for sub in g.world.scene.subdivisions { if sub.live && g.world.scene.materials[sub.material].name=="wood" { area+=polygon_area(sub.outline) } }
  fmt.printf("WALL variant=%d lost_area=%.9f failed_cells=%d\n",variant,1.6-area,cover_wood_failures)
  for _ in 0..<30 { sandbox_tick(&g,0,false) }
  poses:=make(map[u64]Pose); for sub in g.world.scene.subdivisions { if sub.live { poses[sub.id]=sub.pose } }
  rl.BeginDrawing(); rl.ClearBackground({19,28,42,255}); draw_scene(&g.world.scene,&g.render_caches,View{offset={100,580},scale=80},poses,0,true,false,false,true,2)
  rlgl.DrawRenderBatchActive(); img:=rl.LoadImageFromScreen(); rl.EndDrawing()
  names:=[2]string{"before","after"}; path:=fmt.caprintf("evidence/blast-cover/wall-%s.png",names[variant]); assert(rl.ExportImage(img,path)); delete(path); rl.UnloadImage(img)
  delete(poses); sandbox_destroy(&g)
 }
}



