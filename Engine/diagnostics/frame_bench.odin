package main

import shared "shared"
import rl "vendor:raylib"
import "core:time"
import "core:fmt"
when BOM_FRAME_BENCH {
 foreign import frame_gl "system:opengl32.lib"
 foreign frame_gl { @(link_name="glFinish") frame_gl_finish :: proc "system" () --- }

 run_frame_bench :: proc() {
  rl.SetTraceLogLevel(.WARNING)
  rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIGHDPI,.WINDOW_RESIZABLE,.WINDOW_HIDDEN})
  rl.InitWindow(1280,800,"BOM native full-frame timings"); defer { presentation_shutdown(); rl.CloseWindow() }
  sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{}); rl.SetTargetFPS(0)
  samples,buffers:i32; msaa_gl_integer(0x80a9,&samples); msaa_gl_integer(0x80a8,&buffers)
  fmt.printf("Native: logical=%dx%d framebuffer=%dx%d samples=%d buffers=%d profile=%v; GPU completion included; FPS sleep disabled\n",rl.GetScreenWidth(),rl.GetScreenHeight(),rl.GetRenderWidth(),rl.GetRenderHeight(),samples,buffers,BOM_PROFILE)
  fmt.println("run,tick,kind,full_frame_ms,tick_ms,blast_ms,physics_pipeline_ms,draw_submit_swap_ms,cache_ms,gpu_finish_ms,regions,links,pieces")
  for run in 1..=3 {
   g:=soak_yard(); sandbox_fixture_mode(&g,.Falling_Bombs)
   poses:=make(map[u64]Pose); blast:=Soak_Timing{}; g.blast_timing=&blast
   hits:=0; previous_blast:=false
   for tick in 1..=10000 {
    if tick>1 && (tick-1)%7200==0 { soak_rebuild_layout(&g) }
    shared.frame_measuring=true; shared.frame_cache_ms=0; shared.frame_physics_ms=0; blast={}
    start:=time.tick_now(); sandbox_tick(&g,0,false); tick_ms:=frame_ms(start)
    hit:=blast.count>0
    measure:=tick>600 && (hit || previous_blast)
    draw:=tick<=3 || hit || previous_blast
    if !draw { previous_blast=hit; continue }
    draw_start:=time.tick_now()
    clear(&poses); g.accumulator=0
    for sub in g.world.scene.subdivisions {
     if !sub.live { continue }; pose:=sub.pose
     if old,ok:=g.previous[sub.id]; ok { pose=interpolate_region_pose(&g.world.scene,sub,old,0) }
     poses[sub.id]=pose
    }
    frames:=render_piece_frames(&g.world.scene,poses,g.previous,0)
    view:=sandbox_view(f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight()))
    rl.BeginDrawing(); rl.ClearBackground({19,28,42,255})
    sandbox_draw_world(&g,view,poses,frames)
    _=sandbox_draw_hud(&g,f32(rl.GetScreenWidth()),f32(rl.GetScreenHeight()))
    rl.EndDrawing(); delete(frames)
    draw_ms:=frame_ms(draw_start); gpu_start:=time.tick_now(); frame_gl_finish(); gpu_ms:=frame_ms(gpu_start)
    total:=frame_ms(start); shared.frame_measuring=false
    if measure {
     r,l,p:=counts_runtime(&g.world.scene); kind:=string("next"); if hit { kind="blast" }
     fmt.printf("%d,%d,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%d,%d\n",run,tick,kind,total,tick_ms,blast.total_ms,shared.frame_physics_ms,draw_ms,shared.frame_cache_ms,gpu_ms,r,l,p)
    }
    if measure && hit { hits+=1 }
    if hits>=8 && previous_blast && !hit { break }
    previous_blast=hit
   }
   path:=fmt.aprintf("output/frame-bench-%d.json",run); assert(save_world_snapshot(&g.world,path)); delete(path)
   delete(poses); sandbox_destroy(&g)
  }
 }
}
