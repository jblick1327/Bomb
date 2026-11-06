package main

import "core:fmt"
import "core:os"
import "core:mem"
import b2 "vendor:box2d"

pose_bits_equal :: proc(a,b: Pose) -> bool { return transmute([6]u32)a==transmute([6]u32)b }
world_motion_difference :: proc(a,b: ^World) -> (bool,f32,int) {
 equal:=true; maximum:=f32(0); missing:=0
 for sub in a.scene.subdivisions {
  row,ok:=b.scene.sub_rows[sub.id]
  if !ok { equal=false; missing+=1; continue }
  other:=b.scene.subdivisions[row]
  if !pose_bits_equal(sub.pose,other.pose) { equal=false }
  maximum=max(maximum,vlen(vsub(sub.pose.position,other.pose.position)))
 }
 for sub in b.scene.subdivisions { if _,ok:=a.scene.sub_rows[sub.id]; !ok { missing+=1; equal=false } }
 p,q:=read_body_state(a.players[0].body).pose,read_body_state(b.players[0].body).pose
 if !pose_bits_equal(p,q) { equal=false }
 maximum=max(maximum,vlen(vsub(p.position,q.position)))
 if len(a.bombs)!=len(b.bombs) { equal=false; missing+=abs(len(a.bombs)-len(b.bombs)) }
 for i in 0..<min(len(a.bombs),len(b.bombs)) {
  p,q=read_body_state(a.bombs[i].body).pose,read_body_state(b.bombs[i].body).pose
  if !pose_bits_equal(p,q) { equal=false }
  maximum=max(maximum,vlen(vsub(p.position,q.position)))
 }
 return equal,maximum,missing
}
measure_restore :: proc(falling: bool) {
 g:=soak_yard(); defer sandbox_destroy(&g)
 label:=string("manual")
 if falling {
  label="falling"; sandbox_fixture_mode(&g,.Falling_Bombs)
  for _ in 0..<600 { sandbox_tick(&g,0,false) }
 } else {
  for _ in 0..<120 { sandbox_tick(&g,0,false) }; sandbox_explode(&g,{-6.6,1})
  for _ in 0..<120 { sandbox_tick(&g,0,false) }; sandbox_explode(&g,{0,0.6})
  for _ in 0..<60 { sandbox_tick(&g,0,false) }
 }
 data,ok:=encode_world_snapshot(&g.world); assert(ok); defer delete(data)
 path:=fmt.aprintf("evidence/world-v3/continuity-%s-S.json",label); defer delete(path)
 assert(os.write_entire_file(path,data)==nil)
 restored,decoded:=decode_world_snapshot(data); assert(decoded)
 defer { scene_destroy(&restored.scene); delete(restored.bombs) }
 first:=-1
 for tick in 1..=600 {
  ea:=world_tick(&g.world,{},1.0/60.0); delete(ea.explosions)
  eb:=world_tick(&restored,{},1.0/60.0); delete(eb.explosions)
  equal,_,_:=world_motion_difference(&g.world,&restored)
  if !equal && first<0 { first=tick }
 }
 _,maximum,missing:=world_motion_difference(&g.world,&restored)
 a,b,c:=counts_runtime(&g.world.scene); x,y,z:=counts_runtime(&restored.scene)
 fmt.printf("C continuity %s: first_tick=%d max_position=%.9f missing_entities=%d counts_A=%v counts_B=%v next_A=%d next_B=%d counts_match=%v next_match=%v\n",label,first,maximum,missing,[3]int{a,b,c},[3]int{x,y,z},g.world.scene.next_id,restored.scene.next_id,a==x && b==y && c==z,g.world.scene.next_id==restored.scene.next_id)
}
measure_snapshot_sizes :: proc(w: ^World,label: string) {
 pretty,ok:=encode_world_snapshot(w); assert(ok); defer delete(pretty)
 compact,ok2:=encode_world_snapshot(w,false); assert(ok2); defer delete(compact)
 path:=fmt.aprintf("evidence/world-v3/%s.json",label); defer delete(path)
 assert(os.write_entire_file(path,pretty)==nil)
 fmt.printf("C size %s: pretty=%d compact=%d regions=%d tick=%d\n",label,len(pretty),len(compact),len(w.scene.subdivisions),w.tick)
}
run_world_measurements :: proc() {
 track: mem.Tracking_Allocator
 mem.tracking_allocator_init(&track,context.allocator)
 defer mem.tracking_allocator_destroy(&track)
 context.allocator=mem.tracking_allocator(&track)
 measure_restore(false); measure_restore(true)
 {
  bytes,_,_:=soak_replay_snapshot(); defer delete(bytes)
  w,ok:=decode_world_snapshot(bytes); assert(ok)
  defer { scene_destroy(&w.scene); delete(w.bombs) }
  measure_snapshot_sizes(&w,"fixture-600")
 }
 {
  g:=soak_yard(); defer sandbox_destroy(&g)
  sandbox_fixture_mode(&g,.Falling_Bombs)
  peak,peak_tick:=len(g.world.scene.subdivisions),0
  peak_bytes,ok:=encode_world_snapshot(&g.world); assert(ok); defer delete(peak_bytes)
  worst:=f64(0); worst_regions,worst_tick,blast_count:=0,0,0
  for tick in 1..=18000 {
   events:=world_tick(&g.world,{},1.0/60.0)
   for e in events.explosions {
    blast_count+=1
    if e.elapsed_ms>worst { worst=e.elapsed_ms; worst_regions=e.regions; worst_tick=tick }
   }
   delete(events.explosions)
   if len(g.world.scene.subdivisions)>peak {
    peak=len(g.world.scene.subdivisions); peak_tick=tick
    delete(peak_bytes); peak_bytes,ok=encode_world_snapshot(&g.world); assert(ok)
   }
  }
  w,decoded:=decode_world_snapshot(peak_bytes); assert(decoded)
  defer { scene_destroy(&w.scene); delete(w.bombs) }
  measure_snapshot_sizes(&w,"falling-5min-peak")
  fmt.printf("C falling 5min (no refill): peak_regions=%d peak_tick=%d worst_blast_ms=%.6f regions_before_worst=%d worst_tick=%d blasts=%d\n",peak,peak_tick,worst,worst_regions,worst_tick,blast_count)
 }
 fmt.printf("C teardown Odin=%d Box2D=%d\n",track.current_memory_allocated,b2.GetByteCount())
 assert(track.current_memory_allocated==0 && b2.GetByteCount()==0)
}
