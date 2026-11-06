package main

import nc "netcode"
import b2 "vendor:box2d"
import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// ------------------------------------------------------------------ pose bandwidth
// Sizes the step-2b pose stream. Per tick: awake bodies, and entities whose quantized
// pose (netcode quantize_pos / quantize_angle) differs from the previous tick.
Qpose :: struct { x,y: i32, a: u16 }
Pose_Tick :: struct {
 awake,changed: i32,
 awake_kind,changed_kind: [4]i32, // rigid piece frames, rubber cells, bombs, players
 explosions: i32,
 refill: bool,
}
Pose_Tracker :: struct {
 previous,current: map[u64]Qpose,
 ticks: [dynamic]Pose_Tick,
}
pose_tracker_destroy :: proc(t: ^Pose_Tracker) { delete(t.previous); delete(t.current); delete(t.ticks); t^={} }
pose_quantize :: proc(position: b2.Vec2,rotation: b2.Rot) -> Qpose {
 return {nc.quantize_pos(position.x),nc.quantize_pos(position.y),nc.quantize_angle(math.atan2(rotation.s,rotation.c))}
}
pose_tracker_sample :: proc(t: ^Pose_Tracker,w: ^World,explosions: int,refill: bool) {
 s:=&w.scene
 clear(&t.current)
 tick:Pose_Tick
 tick.explosions=i32(explosions); tick.refill=refill
 note :: proc(t: ^Pose_Tracker,tick: ^Pose_Tick,kind: int,key: u64,body: b2.BodyId) {
  q:=pose_quantize(b2.Body_GetPosition(body),b2.Body_GetRotation(body))
  t.current[key]=q
  if b2.Body_IsAwake(body) { tick.awake+=1; tick.awake_kind[kind]+=1 }
  old,present:=t.previous[key]
  if !present || old!=q { tick.changed+=1; tick.changed_kind[kind]+=1 }
 }
 for p in s.pieces {
  if !p.live || p.body==b2.nullBodyId || s.materials[p.material].flexibility>0 { continue }
  if b2.Body_GetType(p.body)!=.dynamicBody { continue }
  note(t,&tick,0,p.id,p.body)
 }
 for sub in s.subdivisions {
  if !sub.live || sub.body==b2.nullBodyId || s.materials[sub.material].flexibility<=0 { continue }
  if b2.Body_GetType(sub.body)!=.dynamicBody { continue }
  note(t,&tick,1,sub.id|(u64(1)<<62),sub.body)
 }
 for bomb in w.bombs { note(t,&tick,2,bomb.id|(u64(2)<<62),bomb.body) }
 for player,i in w.players { if player.active { note(t,&tick,3,u64(i)|(u64(3)<<62),player.body) } }
 t.previous,t.current=t.current,t.previous
 append(&t.ticks,tick)
}
percentile :: proc(sorted: []i32,p: f64) -> i32 {
 if len(sorted)==0 { return 0 }
 index:=int(math.ceil(p*f64(len(sorted))))-1
 return sorted[clamp(index,0,len(sorted)-1)]
}
pose_tracker_report :: proc(t: ^Pose_Tracker,label: string) {
 if len(t.ticks)==0 { return }
 awake:=make([]i32,len(t.ticks)); defer delete(awake)
 changed:=make([]i32,len(t.ticks)); defer delete(changed)
 awake_max,changed_max:=0,0
 for tick,i in t.ticks {
  awake[i]=tick.awake; changed[i]=tick.changed
  if tick.awake>t.ticks[awake_max].awake { awake_max=i }
  if tick.changed>t.ticks[changed_max].changed { changed_max=i }
 }
 slice.sort(awake); slice.sort(changed)
 fmt.printf("POSE %s ticks=%d awake_at_start=%d changed_at_start=%d\n",label,len(t.ticks),t.ticks[0].awake,t.ticks[0].changed)
 fmt.printf("POSE %s awake p50=%d p95=%d p99=%d max=%d\n",label,percentile(awake,0.5),percentile(awake,0.95),percentile(awake,0.99),awake[len(awake)-1])
 fmt.printf("POSE %s changed p50=%d p95=%d p99=%d max=%d\n",label,percentile(changed,0.5),percentile(changed,0.95),percentile(changed,0.99),changed[len(changed)-1])
 describe :: proc(label,what: string,t: ^Pose_Tracker,index: int) {
  tick:=t.ticks[index]
  last_blast,last_refill:=-1,-1
  for i in 0..=index { if t.ticks[i].explosions>0 { last_blast=i };if t.ticks[i].refill { last_refill=i } }
  fmt.printf("POSE context %s max_%s ticks_since_explosion=%d ticks_since_refill=%d\n",label,what,index-last_blast,index-last_refill)
  fmt.printf("POSE %s max_%s tick=%d (%.1fs) awake=%d [rigid %d, rubber %d, bombs %d, players %d] changed=%d [rigid %d, rubber %d, bombs %d, players %d] explosions_this_tick=%d refill=%v\n",label,what,index+1,f64(index+1)/60,tick.awake,tick.awake_kind[0],tick.awake_kind[1],tick.awake_kind[2],tick.awake_kind[3],tick.changed,tick.changed_kind[0],tick.changed_kind[1],tick.changed_kind[2],tick.changed_kind[3],tick.explosions,tick.refill)
 }
 describe(label,"awake",t,awake_max); describe(label,"changed",t,changed_max)
}

// ------------------------------------------------------------------ scenario runner
Scenario :: struct {
 label: string,
 minutes: int, // Whole minutes of 3600 ticks each (refills follow run_soak's two-minute cycle).
 ticks: int, // Overrides minutes when positive.
 bots: int,
 blasting: bool,
 falling_bombs: bool,
 refill: bool,
 rubble: bool, // Materials preset after 6 spread radius-5 blasts, settled.
 lockstep: bool,
 join_tick: int, // Late-join replica starts here (0 = none).
 render_samples: int, // Needs a window.
 part_limit: int,
 seed: u64,
}
Scenario_Result :: struct {
 ticks, deltas, baselines: int,
 first_mismatch: int, // 0 = none
 join_mismatch: int, join_ticks_verified: int,
 delta_sizes: [dynamic]i32,
 largest_message, largest_part, max_parts: int,
 baseline_start, baseline_end: int,
 delta_ms: [dynamic]f64,
 render_checked, render_identical: int,
 blast_events: int,
}
scenario_result_destroy :: proc(r: ^Scenario_Result) { delete(r.delta_sizes); delete(r.delta_ms); r^={} }

repl_apply_output :: proc(rep: ^Replica,out: ^Repl_Output) -> string {
 for part in out.parts {
  _,err:=replica_receive(rep,part)
  if err!="" { return err }
 }
 return ""
}
bytes_equal :: proc(a,b: []u8) -> bool { return len(a)==len(b) && (len(a)==0 || mem.compare(a,b)==0) }

// Window-dependent: renders the scene with the given poses into the target texture.
replication_render :: proc(s: ^Scene,caches: ^Render_Cache_State,poses: map[u64]Pose,target: rl.RenderTexture2D) -> rl.Image {
 view:=sandbox_view(1280,800)
 frames:=render_piece_frames(s,poses); defer delete(frames)
 rl.BeginDrawing(); rl.BeginTextureMode(target); rl.ClearBackground({19,28,42,255})
 draw_scene(s,caches,view,poses,0,true,false,false,true,2,frames)
 rl.EndTextureMode(); rl.EndDrawing()
 image:=rl.LoadImageFromTexture(target.texture); rl.ImageFlipVertical(&image)
 return image
}
replication_images_identical :: proc(a,b: rl.Image) -> bool {
 if a.width!=b.width || a.height!=b.height || a.format!=b.format { return false }
 size:=int(a.width)*int(a.height)*4
 return mem.compare(slice.bytes_from_ptr(a.data,size),slice.bytes_from_ptr(b.data,size))==0
}

run_scenario :: proc(sc: Scenario,tracker: ^Pose_Tracker = nil,render_target: ^rl.RenderTexture2D = nil,png_directory: string = "",grid: ^Pose_Grid = nil) -> Scenario_Result {
 result:Scenario_Result
 g:=soak_yard(); defer sandbox_destroy(&g)
 if sc.falling_bombs { sandbox_fixture_mode(&g,.Falling_Bombs) }
 if sc.rubble {
  blasts:=[6]Vec2{{-6.4,2.3},{-4.3,1},{-0.7,1},{2.5,1},{4.3,2.4},{6.2,1}}
  sandbox_fixture_radius(&g,5)
  for point in blasts { assert(sandbox_valid_aim(&g.world.scene,point)); sandbox_explode(&g,point) }
  for _ in 0..<1200 { sandbox_tick(&g,0,false) }
 }
 for i in 1..<max(sc.bots,1) { assert(world_add_player(&g.world,i)) }
 team:Bot_Team; bot_team_init(&team,sc.bots,sc.blasting,sc.seed)
 srv:Repl_Server; defer repl_server_destroy(&srv)
 rep,rep2:Replica; replica_init(&rep); replica_init(&rep2); defer { replica_destroy(&rep); replica_destroy(&rep2) }
 limit:=sc.part_limit; if limit==0 { limit=REPL_PART_LIMIT }
 total:=sc.ticks; if total==0 { total=sc.minutes*3600 }
 host_w,rep_w,rep2_w:nc.Writer
 nc.writer_init(&host_w); nc.writer_init(&rep_w); nc.writer_init(&rep2_w)
 defer { nc.writer_destroy(&host_w); nc.writer_destroy(&rep_w); nc.writer_destroy(&rep2_w) }
 host_x,rep_x,rep2_x:Repl_Scratch; defer { repl_scratch_destroy(&host_x); repl_scratch_destroy(&rep_x); repl_scratch_destroy(&rep2_x) }
 joined:=false
 // Every client starts with a Baseline at the initial revision.
 if sc.lockstep {
  out:=repl_server_update(&srv,&g.world.scene,0,limit)
  result.baselines+=1; result.baseline_start=out.message_bytes
  result.largest_message=max(result.largest_message,out.message_bytes); result.largest_part=max(result.largest_part,len(out.parts[0]))
  assert(repl_apply_output(&rep,&out)=="")
  repl_output_destroy(&out)
 }
 sample_ticks:[dynamic]int; defer delete(sample_ticks)
 if sc.render_samples>0 {
  random:=rand.create(0xC0FFEE); gen:=rand.default_random_generator(&random)
  for len(sample_ticks)<sc.render_samples {
   t:=int(rand.int_max(total-3000,gen))+3000
   if !slice.contains(sample_ticks[:],t) { append(&sample_ticks,t) }
  }
  slice.sort(sample_ticks[:])
 }
 host_caches,rep_caches:Render_Cache_State
 defer { release_render_caches(&host_caches); release_render_caches(&rep_caches) }
 for tick in 1..=total {
  if tick%3600==0 && sc.minutes>=5 { fmt.printf("PROGRESS %s tick=%d/%d deltas=%d mismatch=%d\n",sc.label,tick,total,result.deltas,result.first_mismatch) }
  refill:=false
  if sc.refill && (tick-1)%3600==0 && (tick-1)/3600>=1 && ((tick-1)/3600)%2==0 {
   // run_soak refills at the first tick of every odd minute after the first.
   soak_rebuild_layout(&g); refill=true
  }
  move,jump:=bot_team_step(&team,&g)
  for i in 0..<team.count { result.blast_events+=len(g.queued.players[i].blasts) }
  sandbox_tick(&g,move,jump)
  result.ticks+=1
  if tracker!=nil {
   fresh:=0; for burst in g.bursts { if burst.age==0 { fresh+=1 } } // Blasts and bomb explosions of this tick.
   pose_tracker_sample(tracker,&g.world,fresh,refill)
  }
  if grid!=nil { pose_grid_sample(grid,&g.world) }
  if !sc.lockstep { continue }
  started:=time.tick_now()
  out:=repl_server_update(&srv,&g.world.scene,u64(tick),limit)
  elapsed:=f64(time.tick_diff(started,time.tick_now()))/f64(time.Millisecond)
  if out.kind!=.None {
   if out.kind==.Delta {
    result.deltas+=1; append(&result.delta_sizes,i32(out.message_bytes)); append(&result.delta_ms,elapsed)
   } else { result.baselines+=1 }
   result.largest_message=max(result.largest_message,out.message_bytes); result.max_parts=max(result.max_parts,len(out.parts))
   for part in out.parts { result.largest_part=max(result.largest_part,len(part)) }
   if err:=repl_apply_output(&rep,&out); err!="" { fmt.printf("REPLICA ERROR tick=%d: %s\n",tick,err); result.first_mismatch=tick; repl_output_destroy(&out); return result }
   if joined { if err:=repl_apply_output(&rep2,&out); err!="" { fmt.printf("LATE JOINER ERROR tick=%d: %s\n",tick,err); result.join_mismatch=tick; repl_output_destroy(&out); return result } }
  }
  repl_output_destroy(&out)
  // The lockstep check runs on EVERY tick.
  clear(&host_w.data); clear(&rep_w.data)
  canonical_encode_into(&host_w,&g.world.scene,&host_x); canonical_encode_into(&rep_w,&rep.scene,&rep_x)
  if !bytes_equal(host_w.data[:],rep_w.data[:]) {
   fmt.printf("LOCKSTEP MISMATCH tick=%d host=%d bytes replica=%d bytes\n",tick,len(host_w.data),len(rep_w.data))
   result.first_mismatch=tick; return result
  }
  if joined {
   clear(&rep2_w.data); canonical_encode_into(&rep2_w,&rep2.scene,&rep2_x)
   if !bytes_equal(host_w.data[:],rep2_w.data[:]) { fmt.printf("LATE JOIN MISMATCH tick=%d\n",tick); result.join_mismatch=tick; return result }
   result.join_ticks_verified+=1
  }
  if sc.join_tick>0 && tick==sc.join_tick {
   // Join after this tick's delta: a Baseline at the current revision, then the following deltas.
   join:=repl_server_baseline(&srv,&g.world.scene,u64(tick),limit)
   result.baselines+=1; result.largest_message=max(result.largest_message,join.message_bytes)
   assert(repl_apply_output(&rep2,&join)=="")
   repl_output_destroy(&join); joined=true
  }
  if len(sample_ticks)>0 && slice.contains(sample_ticks[:],tick) && render_target!=nil {
   poses:=make(map[u64]Pose); defer delete(poses)
   for sub in g.world.scene.subdivisions { if sub.live { poses[sub.id]=sub.pose } }
   host_image:=replication_render(&g.world.scene,&host_caches,poses,render_target^)
   rep_image:=replication_render(&rep.scene,&rep_caches,poses,render_target^)
   same:=replication_images_identical(host_image,rep_image)
   result.render_checked+=1; if same { result.render_identical+=1 }
   fmt.printf("RENDER tick=%d cells=%d identical=%v\n",tick,len(poses),same)
   if png_directory!="" {
    path:=fmt.ctprintf("%s/render-%05d-host.png",png_directory,tick); _ = rl.ExportImage(host_image,path)
    path=fmt.ctprintf("%s/render-%05d-replica.png",png_directory,tick); _ = rl.ExportImage(rep_image,path)
   }
   rl.UnloadImage(host_image); rl.UnloadImage(rep_image)
  }
 }
 if sc.lockstep {
  end:=repl_server_baseline(&srv,&g.world.scene,u64(total),limit)
  result.baseline_end=end.message_bytes; repl_output_destroy(&end)
 }
 return result
}
print_size_stats :: proc(label: string,sizes: []i32) {
 if len(sizes)==0 { return }
 sorted:=slice.clone(sizes); defer delete(sorted); slice.sort(sorted)
 fmt.printf("%s count=%d p50=%d p99=%d max=%d bytes\n",label,len(sorted),percentile(sorted,0.5),percentile(sorted,0.99),sorted[len(sorted)-1])
}
print_ms_stats :: proc(label: string,values: []f64) {
 if len(values)==0 { return }
 sorted:=slice.clone(values); defer delete(sorted); slice.sort(sorted)
 fmt.printf("%s count=%d p50=%.4f p99=%.4f max=%.4f ms\n",label,len(sorted),sorted[int(0.5*f64(len(sorted)-1))],sorted[int(math.ceil(0.99*f64(len(sorted))))-1],sorted[len(sorted)-1])
}

// CLI: --replication-soak [minutes]. Lockstep soak with late join and render samples,
// then the pose-bandwidth scenarios.
run_replication_soak :: proc(minutes: int = 20) {
 track:mem.Tracking_Allocator;mem.tracking_allocator_init(&track,context.allocator);defer mem.tracking_allocator_destroy(&track)
 context.allocator=mem.tracking_allocator(&track)
 defer { fmt.printf("Replication teardown Odin=%d Box2D=%d texture=%d shader=%d fonts=%v\n",track.current_memory_allocated,b2.GetByteCount(),material_texture.id,material_shader.id,ui_fonts_ready);assert(track.current_memory_allocated==0 && b2.GetByteCount()==0 && material_texture.id==0 && material_shader.id==0 && !ui_fonts_ready) }
 rl.SetTraceLogLevel(.WARNING); rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"BOM replication soak"); defer { presentation_shutdown(); rl.CloseWindow() }
 sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{}); rl.SetTargetFPS(0)
 target:=rl.LoadRenderTexture(1280,800); defer rl.UnloadRenderTexture(target)
 assert(os.make_directory_all("evidence/replication-2a/render")==nil)
 fmt.println("== (a)(b)(c)(d1) lockstep soak: 4 bots blasting, falling bombs, two-minute refills, late join at minute 10, 10 render samples")
 tracker:Pose_Tracker; defer pose_tracker_destroy(&tracker)
 sc:=Scenario{label="soak-4-bots",minutes=minutes,bots=4,blasting=true,falling_bombs=true,refill=true,lockstep=true,join_tick=minutes/2*3600,render_samples=10,seed=1234}
 started:=time.tick_now()
 result:=run_scenario(sc,&tracker,&target,"evidence/replication-2a/render")
 defer scenario_result_destroy(&result)
 fmt.printf("LOCKSTEP ticks=%d deltas=%d baselines=%d first_mismatch=%d (0 = none) wall=%.1fs\n",result.ticks,result.deltas,result.baselines,result.first_mismatch,f64(time.tick_diff(started,time.tick_now()))/f64(time.Second))
 print_size_stats("DELTA size",result.delta_sizes[:])
 fmt.printf("BASELINE start=%d bytes end=%d bytes; largest message=%d bytes, largest part=%d bytes, most parts=%d\n",result.baseline_start,result.baseline_end,result.largest_message,result.largest_part,result.max_parts)
 fmt.printf("LATE JOIN join_tick=%d ticks_verified=%d mismatch=%d (0 = none)\n",sc.join_tick,result.join_ticks_verified,result.join_mismatch)
 fmt.printf("RENDER samples=%d identical=%d\n",result.render_checked,result.render_identical)
 print_ms_stats("DELTA generation",result.delta_ms[:])
 fmt.printf("BLASTS queued by bots=%d\n",result.blast_events)
 assert(result.ticks==minutes*3600 && result.first_mismatch==0 && result.join_mismatch==0 && result.join_ticks_verified==(minutes*3600-sc.join_tick) && result.render_checked==10 && result.render_identical==10 && result.baseline_end>0)
 pose_tracker_write(&tracker,"evidence/replication-2a/pose-soak-4.csv")
 replication_delta_write(&result)
 pose_tracker_report(&tracker,"(1) soak, 4 bots blasting + bombs")
 fmt.println("== (d2) rubble field: Materials preset, 6 spread radius-5 blasts, settled; 4 bots walking 5 minutes, no blasts or bombs")
 tracker2:Pose_Tracker; defer pose_tracker_destroy(&tracker2)
 r2:=run_scenario(Scenario{label="rubble",minutes=5,bots=4,rubble=true,seed=99},&tracker2)
 assert(r2.ticks==18000)
 scenario_result_destroy(&r2)
 pose_tracker_write(&tracker2,"evidence/replication-2a/pose-rubble-4.csv")
 pose_tracker_report(&tracker2,"(2) rubble field, 4 bots walking")
 fmt.println("== (d3) scenario (1) with 1 bot")
 tracker3:Pose_Tracker; defer pose_tracker_destroy(&tracker3)
 r3:=run_scenario(Scenario{label="soak-1-bot",minutes=minutes,bots=1,blasting=true,falling_bombs=true,refill=true,seed=1234},&tracker3)
 assert(r3.ticks==minutes*3600)
 scenario_result_destroy(&r3)
 pose_tracker_write(&tracker3,"evidence/replication-2a/pose-soak-1.csv")
 pose_tracker_report(&tracker3,"(3) soak, 1 bot blasting + bombs")
}

pose_tracker_write :: proc(t:^Pose_Tracker,path:string) {
 b:strings.Builder;strings.builder_init(&b,context.allocator);defer strings.builder_destroy(&b)
 strings.write_string(&b,"tick,awake,changed,awake_rigid,awake_rubber,awake_bombs,awake_players,changed_rigid,changed_rubber,changed_bombs,changed_players,explosions,refill\n")
 for row,i in t.ticks { fmt.sbprintf(&b,"%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%v\n",i+1,row.awake,row.changed,row.awake_kind[0],row.awake_kind[1],row.awake_kind[2],row.awake_kind[3],row.changed_kind[0],row.changed_kind[1],row.changed_kind[2],row.changed_kind[3],row.explosions,row.refill) }
 assert(os.write_entire_file(path,transmute([]byte)strings.to_string(b))==nil)
}
replication_delta_write :: proc(r:^Scenario_Result) {
 b:strings.Builder;strings.builder_init(&b,context.allocator);defer strings.builder_destroy(&b)
 strings.write_string(&b,"index,bytes,generation_ms\n")
 for size,i in r.delta_sizes { fmt.sbprintf(&b,"%d,%d,%.9f\n",i+1,size,r.delta_ms[i]) }
 assert(os.write_entire_file("evidence/replication-2a/deltas-full.csv",transmute([]byte)strings.to_string(b))==nil)
}
