package shared
import "core:fmt"
import "core:math"
import "core:os"
import "core:testing"
import "core:time"
import b2 "vendor:box2d"

// NPT diagnosis probe (2026-11-24): replays the scripted host blast sequence (one blast per second at the yard
// points the owner clicked) on the server's world, with no network, and times each part of the server tick.
// Off unless built with -define:BOM_BLAST_PROBE=true; prints one line per second and every tick over 20 ms.
BOM_BLAST_PROBE :: #config(BOM_BLAST_PROBE,false)
BOM_BLAST_PROBE_RADIUS :: #config(BOM_BLAST_PROBE_RADIUS,5)
// -define:BOM_BLAST_PROBE_DEEP=true aims into the ground (below its top cell) instead of at the click points.
BOM_BLAST_PROBE_DEEP :: #config(BOM_BLAST_PROBE_DEEP,false)
BOM_BLAST_PROBE_TRACE :: #config(BOM_BLAST_PROBE_TRACE,false)
BOM_BLAST_PROBE_PLAYERS :: #config(BOM_BLAST_PROBE_PLAYERS,false)
BOM_BLAST_PROBE_FREEZE :: #config(BOM_BLAST_PROBE_FREEZE,false) // the server's settled-debris freeze

@(test)
blast_storm_probe :: proc(t:^testing.T) {
 when !BOM_BLAST_PROBE { return } else {
 data,err:=os.read_entire_file("integration/fixtures/network-yard/yard.json",context.allocator)
 if !testing.expect(t,err==nil,"run from the repo root") {return}
 defer delete(data)
 layout,seed,valid,reason:=decode_layout(data);if !testing.expect(t,valid,reason) {return};defer destroy_layout(&layout)
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false)
 w.debris_freeze=BOM_BLAST_PROBE_FREEZE
 defer scene_destroy(&w.scene);defer delete(w.bombs)
 repl:Repl_Server;defer repl_server_destroy(&repl)
 first:=repl_server_update(&repl,&w.scene,0);repl_output_destroy(&first)
 points:=[?]Vec2{{-3.6,11.0},{-1.4,7.5},{1.6,11.3},{4.3,10.8},{-5.5,8.2},{1.1,10.2},{-2.0,11.6},{7.7,9.1}}
 when BOM_BLAST_PROBE_DEEP {
  top:=f32(-1e9);ground:=layout.level.sources[0].identity
  for sub in w.scene.subdivisions {if sub.live && sub.provenance.source_identity==ground {top=max(top,sub.pose.position.y)}}
  xs:=[?]f32{-9,-6,-3,0,3,6,9,-4.5}
  for i in 0..<len(points) {points[i]={xs[i],top-0.5-f32(i%3)}}
  fmt.printf("PROBE deep ground_top=%.2f points=%v\n",top,points)
 }
 ms :: proc(start:time.Tick)->f64 {return time.duration_milliseconds(time.tick_since(start))}
 sec_world,sec_repl,sec_hash,sec_blast,sec_max:f64
 sec_step,sec_collide,sec_solve,sec_pairs:f64
 revisions:=0
 for tick in 1..=2400 {
  blast_ms,world_ms,repl_ms,hash_ms:f64
  when BOM_BLAST_PROBE { if tick>=200 && tick%15==0 {
   // Freeze trace: frozen pieces (largest by cells), live mortar seams, and the fastest dynamic piece.
   frozen,frozen_cells,largest,seams:=0,0,0,0;fast:f32;fast_cells:=0
   for p in w.scene.pieces {
    if !p.live {continue}
    if p.frozen {frozen+=1;frozen_cells+=len(p.subdivisions);largest=max(largest,len(p.subdivisions));continue}
    if p.body!=b2.nullBodyId && b2.Body_IsValid(p.body) && b2.Body_GetType(p.body)==.dynamicBody {
     v:=b2.Body_GetLinearVelocity(p.body);sp:=f32(math.sqrt(v.x*v.x+v.y*v.y));if sp>fast {fast=sp;fast_cells=len(p.subdivisions)}
    }
   }
   for c in w.scene.connections {if c.live && c.mortar {seams+=1}}
   fmt.printf("PROBE ftrace tick=%d frozen=%d frozen_cells=%d largest_frozen=%d seams=%d fastest=%.2f fastest_cells=%d contacts=%d\n",tick,frozen,frozen_cells,largest,seams,fast,fast_cells,b2.World_GetCounters(w.scene.physics.world).contactCount)
  }}
  if tick==60 || tick==170 || tick==200 || tick==239 || tick==250 || tick==260 {
   // Do the dynamic cells move? Awake bodies cost solver time even when still; sleeping ones are nearly free.
   dyn,awake,moving,displaced:int;max_speed,max_shift:f32
   frozen:=0;for p in w.scene.pieces {if p.live && p.frozen {frozen+=1}};fmt.printf("PROBE frozen tick=%d pieces=%d\n",tick,frozen)
   for sub in w.scene.subdivisions {
    if !sub.live || sub.body==b2.nullBodyId || !b2.Body_IsValid(sub.body) || b2.Body_GetType(sub.body)!=.dynamicBody {continue}
    dyn+=1
    if b2.Body_IsAwake(sub.body) {awake+=1}
    v:=b2.Body_GetLinearVelocity(sub.body);speed:=f32(math.sqrt(v.x*v.x+v.y*v.y))
    if speed>0.05 {moving+=1};max_speed=max(max_speed,speed)
    shift:=vlen(vsub(sub.pose.position,sub.rest_center));if shift>0.05 {displaced+=1};max_shift=max(max_shift,shift)
   }
   bodies:=make(map[u64][2]int);defer delete(bodies)
   for sub in w.scene.subdivisions {
    if !sub.live || sub.body==b2.nullBodyId || !b2.Body_IsValid(sub.body) || b2.Body_GetType(sub.body)!=.dynamicBody {continue}
    key:=transmute(u64)sub.body;row:=bodies[key];row[0]+=1;row[1]=int(b2.Body_GetShapeCount(sub.body));bodies[key]=row
   }
   largest,shapes:=0,0;for _,row in bodies {largest=max(largest,row[0]);shapes+=row[1]}
   fmt.printf("PROBE bodies tick=%d distinct_dynamic_bodies=%d cells_on_largest=%d dynamic_shapes=%d\n",tick,len(bodies),largest,shapes)
   fmt.printf("PROBE motion tick=%d dynamic=%d awake=%d moving_over_5cm_s=%d max_speed=%.3f displaced_over_5cm=%d max_shift=%.2f sleep_enabled=%v contacts=%v\n",tick,dyn,awake,moving,max_speed,displaced,max_shift,b2.World_IsSleepingEnabled(w.scene.physics.world),b2.World_GetCounters(w.scene.physics.world).contactCount)
  }
  if tick==239 || tick==260 {
   counts:=make(map[u64][2]int);defer delete(counts)
   for sub in w.scene.subdivisions {
    if !sub.live {continue}
    row:=counts[sub.provenance.source_identity];row[0]+=1
    if sub.body!=b2.nullBodyId && b2.Body_IsValid(sub.body) && b2.Body_GetType(sub.body)==.dynamicBody {row[1]+=1}
    counts[sub.provenance.source_identity]=row
   }
   for source,row in counts {if row[0]>200 || row[1]>50 {fmt.printf("PROBE cells tick=%d source=%d cells=%d dynamic=%d\n",tick,source,row[0],row[1])}}
  }
  if tick%60==0 && tick<=1800 {
   events:Tick_Events;s:=time.tick_now()
   world_explode(&w,points[(tick/60-1)%len(points)],f32(BOM_BLAST_PROBE_RADIUS),&events)
   blast_ms=ms(s);delete(events.explosions)
  }
  when BOM_BLAST_PROBE_TRACE {fmt.eprintf("TRACE tick=%d world\n",tick)}
  commands:Tick_Commands
  when BOM_BLAST_PROBE_PLAYERS {
   // Two players as --bom-debug-move drives them: right/left every 1.5 s, a jump every 3 s.
   if tick==1 {_=world_add_player(&w,0);_=world_add_player(&w,1)}
   for i in 0..<2 {commands.players[i].move=(tick/90)%2==0 ? 1 : -1;commands.players[i].jump=tick%180==0}
  }
  s:=time.tick_now();post:=world_tick(&w,commands,1.0/60.0);world_ms=ms(s);delete(post.explosions)
  prof:=b2.World_GetProfile(w.scene.physics.world);sec_step+=f64(prof.step);sec_collide+=f64(prof.collide);sec_solve+=f64(prof.solve);sec_pairs+=f64(prof.pairs)
  when BOM_BLAST_PROBE_TRACE {fmt.eprintf("TRACE tick=%d repl\n",tick)}
  s=time.tick_now();out:=repl_server_update(&repl,&w.scene,u64(tick));repl_ms=ms(s)
  when BOM_BLAST_PROBE_TRACE {fmt.eprintf("TRACE tick=%d hash\n",tick)}
  if out.kind!=.None {
   revisions+=1
   s=time.tick_now();bytes:=canonical_encode(&w.scene);_=repl_hash(bytes);delete(bytes);hash_ms=ms(s)
  }
  repl_output_destroy(&out)
  total:=blast_ms+world_ms+repl_ms+hash_ms
  sec_world+=world_ms;sec_repl+=repl_ms;sec_hash+=hash_ms;sec_blast+=blast_ms;sec_max=max(sec_max,total)
  live:=0;for sub in w.scene.subdivisions {if sub.live {live+=1}}
  if total>20 {fmt.printf("PROBE slow tick=%d total=%.1f blast=%.1f world=%.1f repl=%.1f hash=%.1f live_cells=%d\n",tick,total,blast_ms,world_ms,repl_ms,hash_ms,live)}
  if tick%60==0 {
   fmt.printf("PROBE second=%d world=%.0f repl=%.0f hash=%.0f blast=%.0f (ms per 1000 budget) max_tick=%.1f revisions=%d live_cells=%d\n",tick/60,sec_world,sec_repl,sec_hash,sec_blast,sec_max,revisions,live)
   fmt.printf("PROBE box2d second=%d step=%.0f pairs=%.0f collide=%.0f solve=%.0f odin_outside_step=%.0f\n",tick/60,sec_step,sec_pairs,sec_collide,sec_solve,sec_world-sec_step)
   fmt.printf("PROBE parts second=%d sync=%.0f step=%.0f read_motion=%.0f loads=%.0f (mortar=%.0f) failures=%.0f sync2=%.0f freeze=%.0f physics_tick=%.0f out_of_bounds=%.0f poses_bombs_items=%.0f\n",tick/60,physics_timing[0],physics_timing[1],physics_timing[2],physics_timing[3],physics_timing[6],physics_timing[4],physics_timing[5],physics_timing[7],physics_timing[8],physics_timing[9],physics_timing[10]);physics_timing={}
   sec_world,sec_repl,sec_hash,sec_blast,sec_max=0,0,0,0,0;revisions=0;sec_step,sec_collide,sec_solve,sec_pairs=0,0,0,0
  }
  if total>5000 {fmt.println("PROBE stopping: one tick over 5 s");break}
 }
 }
}
