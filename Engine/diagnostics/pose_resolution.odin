package main

import b2 "vendor:box2d"
import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"
import "core:strings"

// Step 2b part A: recount "changed entities per tick" for every position step x angle
// step pair, plus the worst on-screen error of each pair at a 2560x1440 window.
POSE_GRID_POS :: [3]f64{1.0/1024,1.0/512,1.0/256}
POSE_GRID_ANGLE :: [4]int{65536,16384,4096,1024}
POSE_GRID_COUNT :: 12

Grid_Q :: struct { x,y,a: i32 }
Pose_Grid :: struct {
 previous: map[u64][POSE_GRID_COUNT]Grid_Q,
 current: map[u64][POSE_GRID_COUNT]Grid_Q,
 changed: [POSE_GRID_COUNT][dynamic]i32,
 radius: map[u64]f32, // largest distance of any vertex from the entity's frame origin / centre
 rigid_radius,rubber_radius: f32,
 rigid_radius_piece: u64,
}
pose_grid_destroy :: proc(g: ^Pose_Grid) {
 delete(g.previous); delete(g.current); delete(g.radius)
 for &list in g.changed { delete(list) }
 g^={}
}
pose_grid_quantize :: proc(position: b2.Vec2,rotation: b2.Rot) -> (out: [POSE_GRID_COUNT]Grid_Q) {
 angle:=math.atan2(f64(rotation.s),f64(rotation.c))
 if angle<0 { angle+=2*math.PI }
 positions:=POSE_GRID_POS; angles:=POSE_GRID_ANGLE
 for pi in 0..<3 { for ai in 0..<4 {
  steps:=angles[ai]
  q:=int(math.round(angle/(2*math.PI)*f64(steps)))%steps
  out[pi*4+ai]={i32(math.round(f64(position.x)/positions[pi])),i32(math.round(f64(position.y)/positions[pi])),i32(q)}
 } }
 return
}
pose_grid_sample :: proc(g: ^Pose_Grid,w: ^World) {
 s:=&w.scene
 clear(&g.current)
 counts:[POSE_GRID_COUNT]i32
 note :: proc(g: ^Pose_Grid,counts: ^[POSE_GRID_COUNT]i32,key: u64,body: b2.BodyId,s: ^Scene) {
  pos:=b2.Body_GetPosition(body)
  if key>>62==0 { p:=s.pieces[s.piece_rows[key]]; pos=b2.Body_GetWorldPoint(body,to_b2(p.ref_rest)) }
  q:=pose_grid_quantize(pos,b2.Body_GetRotation(body))
  g.current[key]=q
  old,present:=g.previous[key]
  for i in 0..<POSE_GRID_COUNT { if !present || old[i]!=q[i] { counts[i]+=1 } }
 }
 for p in s.pieces {
  if !p.live || p.body==b2.nullBodyId || s.materials[p.material].flexibility>0 { continue }
  if b2.Body_GetType(p.body)!=.dynamicBody { continue }
  key:=p.id
  if _,seen:=g.radius[key]; !seen {
   r:=f32(0)
   for id in p.subdivisions { for pt in s.subdivisions[s.sub_rows[id]].outline.points { r=max(r,vlen(vsub(pt,p.ref_rest))) } }
   g.radius[key]=r
   if r>g.rigid_radius { g.rigid_radius=r; g.rigid_radius_piece=p.id }
  }
  note(g,&counts,key,p.body,s)
 }
 for sub in s.subdivisions {
  if !sub.live || sub.body==b2.nullBodyId || s.materials[sub.material].flexibility<=0 { continue }
  if b2.Body_GetType(sub.body)!=.dynamicBody { continue }
  key:=sub.id|(u64(1)<<62)
  if _,seen:=g.radius[key]; !seen {
   r:=f32(0)
   for pt in sub.outline.points { r=max(r,vlen(vsub(pt,sub.rest_center))) }
   g.radius[key]=r; g.rubber_radius=max(g.rubber_radius,r)
  }
  note(g,&counts,key,sub.body,s)
 }
 for bomb in w.bombs { note(g,&counts,bomb.id|(u64(2)<<62),bomb.body,s) }
 for player,i in w.players { if player.active { note(g,&counts,u64(i)|(u64(3)<<62),player.body,s) } }
 g.previous,g.current=g.current,g.previous
 for i in 0..<POSE_GRID_COUNT { append(&g.changed[i],counts[i]) }
}

Grid_Stats :: struct { p50,p95,p99,max: i32 }
pose_grid_stats :: proc(g: ^Pose_Grid,index: int) -> Grid_Stats {
 sorted:=slice.clone(g.changed[index][:]); defer delete(sorted); slice.sort(sorted)
 if len(sorted)==0 { return {} }
 return {percentile(sorted,0.5),percentile(sorted,0.95),percentile(sorted,0.99),sorted[len(sorted)-1]}
}
// Worst on-screen error in physical pixels: half a position step plus half an angle
// step acting on the largest vertex distance, at the view scale of a 2560x1440 window.
pose_worst_error_px :: proc(pos_step: f64,angle_steps: int,radius: f32) -> f64 {
 scale:=f64(sandbox_view(2560,1440).scale)
 return (0.5*pos_step+0.5*(2*math.PI/f64(angle_steps))*f64(radius))*scale
}

run_pose_resolution :: proc(soak_minutes: int = 20) {
 fmt.println("== pose resolution: soak-4 and rubble-4, 12 position x angle step pairs")
 soak,rubble:Pose_Grid; defer { pose_grid_destroy(&soak); pose_grid_destroy(&rubble) }
 r1:=run_scenario(Scenario{label="soak-4",minutes=soak_minutes,bots=4,blasting=true,falling_bombs=true,refill=true,seed=1234},nil,nil,"",&soak)
 scenario_result_destroy(&r1)
 r2:=run_scenario(Scenario{label="rubble-4",minutes=5,bots=4,rubble=true,seed=99},nil,nil,"",&rubble)
 scenario_result_destroy(&r2)
 radius:=max(soak.rigid_radius,soak.rubber_radius,rubble.rigid_radius,rubble.rubber_radius)
 fmt.printf("RADIUS soak rigid=%.4f (piece %d) rubber=%.4f; rubble rigid=%.4f (piece %d) rubber=%.4f; used=%.4f m; 2560x1440 view scale=%.4f px/m\n",soak.rigid_radius,soak.rigid_radius_piece,soak.rubber_radius,rubble.rigid_radius,rubble.rigid_radius_piece,rubble.rubber_radius,radius,sandbox_view(2560,1440).scale)
 positions:=POSE_GRID_POS; angles:=POSE_GRID_ANGLE
 b:strings.Builder; strings.builder_init(&b); defer strings.builder_destroy(&b)
 strings.write_string(&b,"pos_step_m,angle_steps,worst_error_px,ok_0.5px,soak4_p50,soak4_p95,soak4_p99,soak4_max,rubble4_p50,rubble4_p95,rubble4_p99,rubble4_max\n")
 best:=-1; best_p99:=i32(1<<30); best_p95:=i32(1<<30)
 for pi in 0..<3 { for ai in 0..<4 {
  index:=pi*4+ai
  error_px:=pose_worst_error_px(positions[pi],angles[ai],radius)
  a,c:=pose_grid_stats(&soak,index),pose_grid_stats(&rubble,index)
  ok:=error_px<=0.5
  fmt.printf("GRID pos=1/%d angle=%d worst=%.4fpx ok=%v soak4 %d/%d/%d/%d rubble4 %d/%d/%d/%d\n",int(math.round(1/positions[pi])),angles[ai],error_px,ok,a.p50,a.p95,a.p99,a.max,c.p50,c.p95,c.p99,c.max)
  fmt.sbprintf(&b,"%.9f,%d,%.5f,%v,%d,%d,%d,%d,%d,%d,%d,%d\n",positions[pi],angles[ai],error_px,ok,a.p50,a.p95,a.p99,a.max,c.p50,c.p95,c.p99,c.max)
  // Coarsest = fewest changed entities at rubble-4 p99; ties go to the lower p95, then to the finer pair.
  if ok && (c.p99<best_p99 || c.p99==best_p99 && c.p95<best_p95) { best=index; best_p99=c.p99; best_p95=c.p95 }
 } }
 if best>=0 { fmt.printf("CHOICE pos=1/%d angle=%d rubble4_p99=%d\n",int(math.round(1/positions[best/4])),angles[best%4],best_p99) } else { fmt.println("CHOICE none within 0.5 px") }
 _ = os.make_directory_all("evidence/replication-2b-followup")
 _ = os.write_entire_file("evidence/replication-2b-followup/pose-resolution.csv",transmute([]byte)strings.to_string(b))
 _ = rl.IsWindowReady
}
