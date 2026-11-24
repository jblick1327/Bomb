package shared
import "core:fmt"
import "core:os"
import "core:testing"
import "core:time"
import b2 "vendor:box2d"

// NPT diagnosis probe (2026-11-24): replays the scripted host blast sequence (one blast per second at the yard
// points the owner clicked) on the server's world, with no network, and times each part of the server tick.
// Off unless built with -define:BOM_BLAST_PROBE=true; prints one line per second and every tick over 20 ms.
BOM_BLAST_PROBE :: #config(BOM_BLAST_PROBE,false)
BOM_BLAST_PROBE_RADIUS :: #config(BOM_BLAST_PROBE_RADIUS,5)

@(test)
blast_storm_probe :: proc(t:^testing.T) {
 when !BOM_BLAST_PROBE { return } else {
 data,err:=os.read_entire_file("integration/fixtures/network-yard/yard.json",context.allocator)
 if !testing.expect(t,err==nil,"run from the repo root") {return}
 defer delete(data)
 layout,seed,valid,reason:=decode_layout(data);if !testing.expect(t,valid,reason) {return};defer destroy_layout(&layout)
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false)
 defer scene_destroy(&w.scene);defer delete(w.bombs)
 repl:Repl_Server;defer repl_server_destroy(&repl)
 first:=repl_server_update(&repl,&w.scene,0);repl_output_destroy(&first)
 points:=[?]Vec2{{-3.6,11.0},{-1.4,7.5},{1.6,11.3},{4.3,10.8},{-5.5,8.2},{1.1,10.2},{-2.0,11.6},{7.7,9.1}}
 ms :: proc(start:time.Tick)->f64 {return time.duration_milliseconds(time.tick_since(start))}
 sec_world,sec_repl,sec_hash,sec_blast,sec_max:f64
 revisions:=0
 for tick in 1..=2400 {
  blast_ms,world_ms,repl_ms,hash_ms:f64
  if tick==239 || tick==260 {
   counts:=make(map[u64][2]int);defer delete(counts)
   for sub in w.scene.subdivisions {
    if !sub.live {continue}
    row:=counts[sub.provenance.source_identity];row[0]+=1
    if sub.body!=b2.nullBodyId && b2.Body_IsValid(sub.body) && b2.Body_GetType(sub.body)==.dynamicBody {row[1]+=1}
    counts[sub.provenance.source_identity]=row
   }
   for source,row in counts {if row[0]>200 || row[1]>50 {fmt.printf("PROBE cells tick=%d source=%d cells=%d dynamic=%d\n",tick,source,row[0],row[1])}}
   if tick==260 {
    for source in layout.level.sources {if counts[source.identity][0]>1000 {fmt.printf("PROBE source=%d asset=%s parts=%d\n",source.identity,source.asset_key,len(source.parts))}}
    return
   }
  }
  if tick%60==0 && tick<=1800 {
   events:Tick_Events;s:=time.tick_now()
   world_explode(&w,points[(tick/60-1)%len(points)],f32(BOM_BLAST_PROBE_RADIUS),&events)
   blast_ms=ms(s);delete(events.explosions)
  }
  s:=time.tick_now();post:=world_tick(&w,Tick_Commands{},1.0/60.0);world_ms=ms(s);delete(post.explosions)
  s=time.tick_now();out:=repl_server_update(&repl,&w.scene,u64(tick));repl_ms=ms(s)
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
   sec_world,sec_repl,sec_hash,sec_blast,sec_max=0,0,0,0,0;revisions=0
  }
  if total>5000 {fmt.println("PROBE stopping: one tick over 5 s");break}
 }
 }
}
