package main
import rl "vendor:raylib"
import "core:os"
import "core:fmt"

// Frame-bench style captures (Falling_Bombs soak yard) exported as PNG, used to
// prove presentation changes leave pixels identical. Uses only long-standing APIs.
run_frame_captures :: proc(directory:string) {
 assert(os.make_directory_all(directory)==nil)
 rl.SetTraceLogLevel(.WARNING); rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"BOM frame capture"); defer { presentation_shutdown(); rl.CloseWindow() }
 sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{}); rl.SetTargetFPS(0)
 target:=rl.LoadRenderTexture(1280,800); defer rl.UnloadRenderTexture(target)
 g:=soak_yard(); defer sandbox_destroy(&g)
 sandbox_fixture_mode(&g,.Falling_Bombs)
 blast:=Soak_Timing{}; g.blast_timing=&blast
 poses:=make(map[u64]Pose); defer delete(poses)
 shots:=0; previous_blast:=false
 for tick in 1..=2400 {
  blast={}
  sandbox_tick(&g,0,false)
  hit:=blast.count>0
  fixed:=tick==1 || tick==3 || tick==120 || tick==600 || tick==2400
  if !(fixed || ((hit || previous_blast) && shots<14)) { previous_blast=hit; continue }
  previous_blast=hit
  clear(&poses); g.accumulator=0; g.status_time=0
  for sub in g.world.scene.subdivisions {
   if !sub.live { continue }; pose:=sub.pose
   if old,ok:=g.previous[sub.id]; ok { pose=interpolate_region_pose(&g.world.scene,sub,old,0) }
   poses[sub.id]=pose
  }
  frames:=render_piece_frames(&g.world.scene,poses,g.previous,0)
  rl.BeginDrawing(); rl.BeginTextureMode(target); rl.ClearBackground({19,28,42,255})
  sandbox_draw_world(&g,sandbox_view(1280,800),poses,frames)
  sandbox_draw_hud(&g,1280,800)
  rl.EndTextureMode(); rl.EndDrawing(); delete(frames)
  path:=fmt.aprintf("%s/frame-%05d.png",directory,tick); sandbox_smoke_export(target,cstring_clone(path)); delete(path)
  if !fixed { shots+=1 }
 }
 fmt.printf("Frame captures written to %s\n",directory)
}
