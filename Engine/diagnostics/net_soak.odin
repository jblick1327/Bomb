package main

import nc "netcode"
import b2 "vendor:box2d"
import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// End-to-end step 2b run: one Net_Server and four Net_Clients driven by seeded bots,
// connected through the netcode link simulator. Client 0 is local (no latency or loss);
// clients 1-3 are remote.

NET_LOCAL_LINK :: nc.Link_Config{}
NET_REMOTE_LINK :: nc.Link_Config{latency=0.040,jitter=0.010,loss=0.02,duplicate=0.01,reorder=0.02,reorder_delay=0.050}
NET_HISTORY :: 256

Err_Hist :: struct { bins: [dynamic]u32, step: f64, count: u64, max: f64 }
hist_init :: proc(h: ^Err_Hist,step: f64,bins: int) { h.step=step; h.bins=make([dynamic]u32,bins) }
hist_add :: proc(h: ^Err_Hist,v: f64) {
 index:=min(int(v/h.step),len(h.bins)-1)
 h.bins[index]+=1; h.count+=1; h.max=max(h.max,v)
}
hist_percentile :: proc(h: ^Err_Hist,p: f64) -> f64 {
 if h.count==0 { return 0 }
 target:=u64(math.ceil(p*f64(h.count)))
 total:=u64(0)
 for n,i in h.bins { total+=u64(n); if total>=target { return f64(i+1)*h.step } }
 return h.max
}
Error_Worst :: struct { key: u64, tick: int, clock: f64, lower,upper: u64, speed,angular_speed,error: f64 }
error_worst_json :: proc(report: ^strings.Builder,s: Error_Worst) {
 fmt.sbprintf(report,"{{\"kind\": \"%v\", \"id\": %d, \"tick\": %d, \"render_tick\": %.6f, \"lower\": %d, \"upper\": %d, \"speed_m_s\": %.6f, \"angular_speed_rad_s\": %.6f, \"error_m\": %.6f}}",key_kind(s.key),key_id(s.key),s.tick,s.clock,s.lower,s.upper,s.speed,s.angular_speed,s.error)
}
Err_Pair :: struct {
 pos,ang,vertex,origin,legacy_pos,legacy_vertex,legacy_origin: Err_Hist,
 worst_reference,worst_vertex: Error_Worst,
}
err_init :: proc(e: ^Err_Pair) {
 hist_init(&e.pos,1e-4,100000); hist_init(&e.ang,1e-4,32000)
 hist_init(&e.vertex,1e-4,100000); hist_init(&e.origin,1e-4,100000)
 hist_init(&e.legacy_pos,1e-4,100000); hist_init(&e.legacy_vertex,1e-4,100000); hist_init(&e.legacy_origin,1e-4,100000)
}
err_destroy :: proc(e: ^Err_Pair) {
 delete(e.pos.bins); delete(e.ang.bins); delete(e.vertex.bins); delete(e.origin.bins)
 delete(e.legacy_pos.bins); delete(e.legacy_vertex.bins); delete(e.legacy_origin.bins)
}
err_add :: proc(e: ^Err_Pair,reference,angle,vertex,origin,legacy_reference,legacy_vertex,legacy_origin: f64,sample: Error_Worst) {
 if reference>e.pos.max { e.worst_reference=sample; e.worst_reference.error=reference }
 if vertex>e.vertex.max { e.worst_vertex=sample; e.worst_vertex.error=vertex }
 hist_add(&e.pos,reference); hist_add(&e.ang,angle); hist_add(&e.vertex,vertex); hist_add(&e.origin,origin)
 hist_add(&e.legacy_pos,legacy_reference); hist_add(&e.legacy_vertex,legacy_vertex); hist_add(&e.legacy_origin,legacy_origin)
}

// Reconstruct the old origin representation on the SAME samples and received
// frame brackets. Its original 1/512 m, 16384-angle grid is independent of the
// newly selected grid. This diagnostic never affects the transmitted tables.
legacy_grid_frame :: proc(reference: Pose,ref_rest: Vec2) -> Pose {
 frame:=reference_to_frame(reference,ref_rest)
 frame.position={f32(math.round(f64(frame.position.x)*512)/512),f32(math.round(f64(frame.position.y)*512)/512)}
 frame.angle=f32(math.round(f64(frame.angle)*16384/(2*math.PI))*(2*math.PI)/16384)
 return frame
}
legacy_draw_reference :: proc(c: ^Net_Client,key: u64,ref_rest: Vec2,current: Pose) -> Pose {
 lo,hi:=c.dbg_lower,c.dbg_upper
 if lo==0 && hi==0 { return current }
 a,b:Pose; oka,okb:bool
 if lo>0 {
  if q,ok:=c.ring[lo%NET_CLIENT_RING].table[key]; ok { d:=net_drawn_single(q); a=legacy_grid_frame(Pose{position={d.x,d.y},angle=d.angle},ref_rest); oka=true }
 }
 if hi>0 {
  if q,ok:=c.ring[hi%NET_CLIENT_RING].table[key]; ok { d:=net_drawn_single(q); b=legacy_grid_frame(Pose{position={d.x,d.y},angle=d.angle},ref_rest); okb=true }
 }
 if !oka && !okb { return current }
 frame:=a
 if !oka { frame=b } else if okb && hi>lo { frame=interpolate_pose(a,b,f32((c.clock-f64(lo))/f64(hi-lo))) }
 return frame_to_reference(frame,ref_rest)
}
visible_vertex_error :: proc(s: ^Scene,key: u64,drawn,truth: Pose,ref_rest: Vec2) -> f64 {
 worst:=vlen(vsub(drawn.position,truth.position))
 switch key_kind(key) {
 case .Piece:
  if row,ok:=s.piece_rows[key_id(key)]; ok {
   for id in s.pieces[row].subdivisions {
    if cr,found:=s.sub_rows[id]; found { for pt in s.subdivisions[cr].outline.points {
     offset:=vsub(pt,ref_rest)
     worst=max(worst,vlen(vsub(vadd(drawn.position,vrotate(offset,drawn.angle)),vadd(truth.position,vrotate(offset,truth.angle)))))
    } }
   }
  }
 case .Rubber:
  if row,ok:=s.sub_rows[key_id(key)]; ok { sub:=s.subdivisions[row]; for pt in sub.outline.points {
   offset:=vsub(pt,sub.rest_center)
   worst=max(worst,vlen(vsub(vadd(drawn.position,vrotate(offset,drawn.angle)),vadd(truth.position,vrotate(offset,truth.angle)))))
  } }
 case .Player,.Bomb,.Item:
 }
 return f64(worst)
}

Net_Soak_Config :: struct {
 ticks: int, flush_ticks: int, seed: u64,
 refill: bool, reset_tick: int,
 render_dir: string, // empty: no PNGs
 report_path: string,
 verbose: bool,
}
Net_Link :: struct { c2s,s2c: nc.Link, upload: [dynamic]i32 }
Net_Soak_Result :: struct {
 ticks: int,
 structure_applied,structure_mismatch,structure_unrecorded: [nc.MAX_CLIENTS]int,
 final_equal: [nc.MAX_CLIENTS]bool, final_revision_equal: [nc.MAX_CLIENTS]bool,
 final_pose_mismatch,final_pose_awake: [nc.MAX_CLIENTS]int,
 table_checked,table_mismatch,table_skipped: int,
 jumps_pressed,jumps_applied,blasts_issued,blasts_applied,blasts_rejected,blast_duplicates: [nc.MAX_CLIENTS]int,
 late_messages: [nc.MAX_CLIENTS]int,
 max_frame_bytes: int, max_part: int,
 structure_errors: int,
 delay_local_final: int,
 epochs_seen: int,
}

pct_f64 :: proc(sorted: []f64,p: f64) -> f64 {
 if len(sorted)==0 { return 0 }
 return sorted[clamp(int(math.ceil(p*f64(len(sorted))))-1,0,len(sorted)-1)]
}
frame_bytes_total :: proc(values: []i32) -> int { total:=0; for v in values { total+=int(v) }; return total }
pct_i32 :: proc(values: []i32,p: f64) -> i32 {
 if len(values)==0 { return 0 }
 sorted:=slice.clone(values); defer delete(sorted); slice.sort(sorted)
 return percentile(sorted,p)
}

Hist_Pose :: struct { x,y,a,speed,angular_speed: f32 }
Net_History :: struct { tick: u64, epoch: u32, valid: bool, poses: map[u64]Hist_Pose }

debug_large :: proc(history: ^[NET_HISTORY]Net_History,c: ^Net_Client,key: u64,client: int) {
 lo,hi:=c.dbg_lower,c.dbg_upper
 low,high:Pose_State; okl,okh:=false,false
 if lo!=0 && c.ring[lo%NET_CLIENT_RING].valid { low,okl=c.ring[lo%NET_CLIENT_RING].table[key] }
 if hi!=0 && c.ring[hi%NET_CLIENT_RING].valid { high,okh=c.ring[hi%NET_CLIENT_RING].table[key] }
 hl,hh:=history[lo%NET_HISTORY].poses[key],history[hi%NET_HISTORY].poses[key]
 fmt.printf("  bracket lower=%d upper=%d R=%.2f in_lower=%v (%.3f,%.3f) true=(%.3f,%.3f)  in_upper=%v (%.3f,%.3f) true=(%.3f,%.3f)\n",lo,hi,c.clock,okl,pose_dq_pos(low.x),pose_dq_pos(low.y),hl.x,hl.y,okh,pose_dq_pos(high.x),pose_dq_pos(high.y),hh.x,hh.y)
}
net_soak_run :: proc(cfg: Net_Soak_Config) -> Net_Soak_Result {
 result:Net_Soak_Result
 report:strings.Builder; strings.builder_init(&report); defer strings.builder_destroy(&report)
 g:=soak_yard()
 sandbox_fixture_mode(&g,.Falling_Bombs)
 ns:Net_Server; net_server_init(&ns,g,true)
 defer net_server_destroy(&ns)
 views:[nc.MAX_CLIENTS]Net_Client_View
 defer { for &view in views { net_client_view_destroy(&view) } }
 clients:[nc.MAX_CLIENTS]Net_Client
 bots:[nc.MAX_CLIENTS]Bot
 links:[nc.MAX_CLIENTS]Net_Link
 for i in 0..<nc.MAX_CLIENTS {
  net_client_init(&clients[i],u32(0x5a17+i*7919),0)
  bot_init(&bots[i],cfg.seed+u64(i)*0x9e3779b97f4a7c15,true)
  clients[i].verify=true
  config:=NET_REMOTE_LINK; if i==0 { config=NET_LOCAL_LINK }
  nc.link_init(&links[i].c2s,config,cfg.seed*31+u64(i)*2+1); nc.link_init(&links[i].s2c,config,cfg.seed*31+u64(i)*2+2)
 }
 defer { for i in 0..<nc.MAX_CLIENTS { net_client_destroy(&clients[i]); nc.link_destroy(&links[i].c2s); nc.link_destroy(&links[i].s2c); delete(links[i].upload) } }
 history:[NET_HISTORY]Net_History
 for i in 0..<NET_HISTORY { history[i].poses=make(map[u64]Hist_Pose) }
 defer { for i in 0..<NET_HISTORY { delete(history[i].poses) } }
 errors:[nc.MAX_CLIENTS][3]Err_Pair // all, players, bombs
 for i in 0..<nc.MAX_CLIENTS { for k in 0..<3 { err_init(&errors[i][k]) } }
 over:[nc.MAX_CLIENTS]map[u64]Error_Worst
 for i in 0..<nc.MAX_CLIENTS { over[i]=make(map[u64]Error_Worst) }
 defer { for i in 0..<nc.MAX_CLIENTS { delete(over[i]) } }
 defer { for i in 0..<nc.MAX_CLIENTS { for k in 0..<3 { err_destroy(&errors[i][k]) } } }
 total:=cfg.ticks+cfg.flush_ticks
 started_wall:=time.tick_now()
 epoch_seen:=ns.game.world.scene.epoch
 for n in 1..=total {
  now:=f64(n)/60
  if n==cfg.ticks+1 {
   // Flush: bots idle, no new bombs, so the structure settles.
   for i in 0..<nc.MAX_CLIENTS { clients[i].idle=true }
   headless_game_mode(&ns.game,.Manual)
  }
  for i in 0..<nc.MAX_CLIENTS {
   packets:=nc.link_receive(&links[i].c2s,now); defer nc.packets_free(&packets)
   for p in packets { nc.server_receive(&ns.srv,nc.Address(i+1),p,now) }
  }
  if cfg.refill && n>1 && (n-1)%3600==0 && ((n-1)/3600)%2==0 && n<=cfg.ticks { soak_rebuild_headless(&ns.game) }
  if cfg.reset_tick>0 && n==cfg.reset_tick { headless_game_reset(&ns.game) }
  net_server_tick(&ns,now)
  if ns.game.world.scene.epoch!=epoch_seen { epoch_seen=ns.game.world.scene.epoch; result.epochs_seen+=1 }
  outgoing:=nc.server_take_outgoing(&ns.srv)
  tick_bytes:[nc.MAX_CLIENTS]i32
  for o in outgoing { idx:=int(o.to)-1; if idx>=0 && idx<nc.MAX_CLIENTS { nc.link_send(&links[idx].s2c,o.data,now); tick_bytes[idx]+=i32(len(o.data)) } }
  nc.outgoing_free(&outgoing)
  for i in 0..<nc.MAX_CLIENTS { append(&links[i].upload,tick_bytes[i]) }
  // True poses of this tick, for the render-error comparison.
  slot:=&history[n%NET_HISTORY]
  clear(&slot.poses); slot.tick=u64(n); slot.valid=true; slot.epoch=ns.game.world.scene.epoch
  for key,e in ns.current { slot.poses[key]=Hist_Pose{e.fx,e.fy,e.fa,e.speed,e.angular_speed} }
  for i in 0..<nc.MAX_CLIENTS {
   c:=&clients[i]
   packets:=nc.link_receive(&links[i].s2c,now); defer nc.packets_free(&packets)
   for p in packets { nc.client_receive(&c.nc_client,p,now) }
   net_client_step(c,now,net_bot_client_input,&bots[i])
   net_client_view_step(c,&views[i])
   out:=nc.client_take_outgoing(&c.nc_client)
   for o in out { nc.link_send(&links[i].c2s,o.data,now) }
   nc.outgoing_free(&out)
   // (c) every acked frame must equal the server's record of it.
   for tick in c.acks_to_check {
    sc:=&ns.clients[i]; sslot:=tick%NET_SENT_RING; cslot:=&c.ring[tick%NET_CLIENT_RING]
    if sc.active && sc.ring_valid[sslot] && sc.ring_tick[sslot]==tick && cslot.valid && cslot.tick==tick {
     result.table_checked+=1
     if !tables_equal(&sc.ring[sslot],&cslot.table) { result.table_mismatch+=1 }
    } else { result.table_skipped+=1 }
   }
   clear(&c.acks_to_check)
   // Structure: the replica must equal the server's canonical structure at every revision.
   for a in c.applied {
    result.structure_applied[i]+=1
    if expected,ok:=ns.hashes[net_hash_key(a.epoch,a.revision)]; ok { if expected!=a.hash { result.structure_mismatch[i]+=1 } } else { result.structure_unrecorded[i]+=1 }
   }
   clear(&c.applied)
   // Render error against the true pose at the same fractional tick.
   if c.has_clock && c.has_complete {
    lo:=u64(max(math.floor(c.clock),0)); hi:=lo+1
    ha,hb:=&history[lo%NET_HISTORY],&history[hi%NET_HISTORY]
    if ha.valid && ha.tick==lo && hb.valid && hb.tick==hi && ha.epoch==c.epoch && hb.epoch==c.epoch {
     t:=f32(c.clock-f64(lo))
     for key,d in c.drawn {
      pa,oka:=ha.poses[key]; pb,okb:=hb.poses[key]
      if !oka || !okb { continue }
      tx,ty:=net_lerp(pa.x,pb.x,t),net_lerp(pa.y,pb.y,t)
      ta:=pa.a+radians_delta(pb.a,pa.a)*t
      truth:=Pose{position={tx,ty},angle=ta}
      drawn:=Pose{position={d.x,d.y},angle=d.angle}
      kind:=key_kind(key)
      ref_rest:Vec2
      if kind==.Piece { if row,ok:=c.rep.scene.piece_rows[key_id(key)]; ok { ref_rest=c.rep.scene.pieces[row].ref_rest } }
      pos_error:=f64(vlen(vsub(drawn.position,truth.position)))
      ang_error:=f64(math.abs(radians_delta(d.angle,ta)))
      vertex_error:=visible_vertex_error(&c.rep.scene,key,drawn,truth,ref_rest)
      // The historical origin metric interpolated true body origins, rather
      // than visible points. Keep it on precisely the same sample universe.
      oa:=reference_to_frame(Pose{position={pa.x,pa.y},angle=pa.a},ref_rest)
      ob:=reference_to_frame(Pose{position={pb.x,pb.y},angle=pb.a},ref_rest)
      old_truth:=interpolate_pose(oa,ob,t)
      origin:=reference_to_frame(drawn,ref_rest)
      origin_error:=f64(vlen(vsub(origin.position,old_truth.position)))
      legacy:=drawn
      if kind==.Piece { legacy=legacy_draw_reference(c,key,ref_rest,drawn) }
      legacy_pos:=f64(vlen(vsub(legacy.position,truth.position)))
      legacy_vertex:=visible_vertex_error(&c.rep.scene,key,legacy,truth,ref_rest)
      legacy_origin:=reference_to_frame(legacy,ref_rest)
      legacy_origin_error:=f64(vlen(vsub(legacy_origin.position,old_truth.position)))
      sample:=Error_Worst{key=key,tick=n,clock=c.clock,lower=c.dbg_lower,upper=c.dbg_upper,speed=f64(vlen(vsub(Vec2{pb.x,pb.y},Vec2{pa.x,pa.y})))*60,angular_speed=f64(math.abs(radians_delta(pb.a,pa.a)))*60,error=vertex_error}
      // Peak reference speed over the actual frame gap, including any bounce.
      for ht:=sample.lower; ht<=max(sample.lower,sample.upper) && ht+1<=u64(n); ht+=1 {
       a,b:=&history[ht%NET_HISTORY],&history[(ht+1)%NET_HISTORY]
       if a.tick!=ht || b.tick!=ht+1 || a.epoch!=c.epoch || b.epoch!=c.epoch { continue }
       va,oka:=a.poses[key]; vb,okb:=b.poses[key]; if !oka || !okb { continue }
       sample.speed=max(sample.speed,f64(vlen(vsub(Vec2{vb.x,vb.y},Vec2{va.x,va.y})))*60)
       sample.angular_speed=max(sample.angular_speed,f64(math.abs(radians_delta(vb.a,va.a)))*60)
       sample.speed=max(sample.speed,f64(va.speed),f64(vb.speed))
       sample.angular_speed=max(sample.angular_speed,f64(va.angular_speed),f64(vb.angular_speed))
      }
      if vertex_error>0.5 { if previous,present:=over[i][key]; !present || vertex_error>previous.error { over[i][key]=sample } }
      err_add(&errors[i][0],pos_error,ang_error,vertex_error,origin_error,legacy_pos,legacy_vertex,legacy_origin_error,sample)
      if kind==.Player { err_add(&errors[i][1],pos_error,ang_error,vertex_error,origin_error,legacy_pos,legacy_vertex,legacy_origin_error,sample) }
      if kind==.Bomb { err_add(&errors[i][2],pos_error,ang_error,vertex_error,origin_error,legacy_pos,legacy_vertex,legacy_origin_error,sample) }
     }
    }
   }
  }
  if cfg.verbose && n%3600==0 { fmt.printf("PROGRESS tick=%d/%d wall=%.0fs\n",n,total,f64(time.tick_diff(started_wall,time.tick_now()))/f64(time.Second)) }
 }
 result.ticks=total
 // ---- final state after the flush
 for i in 0..<nc.MAX_CLIENTS {
  c:=&clients[i]
  server_canonical:=canonical_encode(&ns.game.world.scene); defer delete(server_canonical)
  replica_canonical:=canonical_encode(&c.rep.scene); defer delete(replica_canonical)
  result.final_equal[i]=bytes_equal(server_canonical,replica_canonical)
  result.final_revision_equal[i]=c.rep.scene.structure_revision==ns.game.world.scene.structure_revision && c.rep.scene.epoch==ns.game.world.scene.epoch
  if c.has_complete {
   table:=&c.ring[c.newest_complete%NET_CLIENT_RING].table
   for key,e in ns.current {
    row,ok:=table[key]
    if !ok || row!=e.state {
     result.final_pose_mismatch[i]+=1
     switch key_kind(key) {
     case .Piece: if row,found:=ns.game.world.scene.piece_rows[key_id(key)]; found { if b2.Body_IsAwake(ns.game.world.scene.pieces[row].body) { result.final_pose_awake[i]+=1 } }
     case .Rubber: if row,found:=ns.game.world.scene.sub_rows[key_id(key)]; found { if b2.Body_IsAwake(ns.game.world.scene.subdivisions[row].body) { result.final_pose_awake[i]+=1 } }
     case .Player:
      player:=ns.game.world.players[key_id(key)]
      if b2.Body_IsAwake(player.body) { result.final_pose_awake[i]+=1 }
     case .Bomb:
      for bomb in ns.game.world.bombs { if bomb.id==key_id(key) {
       if b2.Body_IsAwake(bomb.body) { result.final_pose_awake[i]+=1 }; break
      } }
     case .Item: // items are positions, not bodies; there is no sleep state
     }
    }
   }
  }
  s:=&ns.clients[i].stats
  result.jumps_pressed[i]=c.stats.jumps_pressed; result.jumps_applied[i]=s.jumps_applied
  result.blasts_issued[i]=c.stats.blasts_issued; result.blasts_applied[i]=s.blasts_applied; result.blasts_rejected[i]=s.blasts_rejected; result.blast_duplicates[i]=s.blast_duplicates
  result.late_messages[i]=c.stats.late_messages
  result.structure_errors+=c.stats.structure_errors
  for b in s.frame_bytes { result.max_frame_bytes=max(result.max_frame_bytes,int(b)) }
 }
 result.max_part=FRAME_PART_MAX
 result.delay_local_final=clients[0].delay
 net_soak_report(&ns,&clients,&links,&errors,&over,&result,&report,total,cfg)
 if cfg.render_dir!="" { net_soak_render(&ns,&clients,&views,cfg.render_dir) }
 if cfg.report_path!="" { _ = os.write_entire_file(cfg.report_path,transmute([]byte)strings.to_string(report)) }
 return result
}

net_soak_report :: proc(ns: ^Net_Server,clients: ^[nc.MAX_CLIENTS]Net_Client,links: ^[nc.MAX_CLIENTS]Net_Link,errors: ^[nc.MAX_CLIENTS][3]Err_Pair,over: ^[nc.MAX_CLIENTS]map[u64]Error_Worst,result: ^Net_Soak_Result,report: ^strings.Builder,total: int,cfg: Net_Soak_Config) {
 fmt.sbprintf(report,"{{\n \"ticks\": %d, \"flush_ticks\": %d, \"table_checked\": %d, \"table_mismatch\": %d, \"table_skipped\": %d, \"epochs_seen\": %d,\n",total,cfg.flush_ticks,result.table_checked,result.table_mismatch,result.table_skipped,result.epochs_seen)
 fmt.printf("NETSOAK ticks=%d (flush %d) table_agreement checked=%d mismatches=%d skipped=%d; epoch changes=%d\n",total,cfg.flush_ticks,result.table_checked,result.table_mismatch,result.table_skipped,result.epochs_seen)
 fmt.sbprintf(report," \"clients\": [\n")
 for i in 0..<nc.MAX_CLIENTS {
  c:=&clients[i]; s:=&ns.clients[i].stats; label:="remote"; if i==0 { label="local" }
  fmt.printf("== client %d (%s)\n",i,label)
  fmt.printf("STRUCTURE applied=%d hash_mismatches=%d unrecorded=%d final_equal=%v final_revision_equal=%v errors=%d\n",result.structure_applied[i],result.structure_mismatch[i],result.structure_unrecorded[i],result.final_equal[i],result.final_revision_equal[i],c.stats.structure_errors)
  fmt.printf("FINAL POSES entities differing from the server's quantized state=%d (awake bodies among them=%d)\n",result.final_pose_mismatch[i],result.final_pose_awake[i])
  names:=[3]string{"all","players","bombs"}
  fmt.sbprintf(report,"  {{\"client\": %d, \"link\": \"%s\", \"structure_applied\": %d, \"structure_hash_mismatches\": %d, \"structure_unrecorded\": %d, \"final_equal\": %v, \"final_revision_equal\": %v, \"final_pose_mismatch\": %d, \"final_pose_awake\": %d,\n",i,label,result.structure_applied[i],result.structure_mismatch[i],result.structure_unrecorded[i],result.final_equal[i],result.final_revision_equal[i],result.final_pose_mismatch[i],result.final_pose_awake[i])
  fmt.sbprintf(report,"   \"render_error\": {{")
  for k in 0..<3 {
   e:=&errors[i][k]
   fmt.printf("RENDER ERROR %-7s samples=%d position p50=%.5f p99=%.5f max=%.5f m; angle p50=%.5f p99=%.5f max=%.5f rad\n",names[k],e.pos.count,hist_percentile(&e.pos,0.5),hist_percentile(&e.pos,0.99),e.pos.max,hist_percentile(&e.ang,0.5),hist_percentile(&e.ang,0.99),e.ang.max)
   fmt.sbprintf(report,"%s\"%s\": {{\"samples\": %d, \"pos_p50\": %.6f, \"pos_p99\": %.6f, \"pos_max\": %.6f, \"ang_p50\": %.6f, \"ang_p99\": %.6f, \"ang_max\": %.6f}}",k>0?", ":"",names[k],e.pos.count,hist_percentile(&e.pos,0.5),hist_percentile(&e.pos,0.99),e.pos.max,hist_percentile(&e.ang,0.5),hist_percentile(&e.ang,0.99),e.ang.max)
   fmt.sbprintf(report,",\"%s_visible\": {{",names[k])
   labels:=[6]string{"reference","vertex","origin_metric","legacy_reference","legacy_vertex","legacy_origin_metric"}
   histograms:=[6]^Err_Hist{&e.pos,&e.vertex,&e.origin,&e.legacy_pos,&e.legacy_vertex,&e.legacy_origin}
   for h,j in histograms {
    fmt.sbprintf(report,"%s\"%s\": {{\"p50\": %.6f, \"p99\": %.6f, \"max\": %.6f, \"samples\": %d}}",j>0?",":"",labels[j],hist_percentile(h,0.5),hist_percentile(h,0.99),h.max,h.count)
   }
   fmt.sbprintf(report,",\"worst_reference\": ")
   error_worst_json(report,e.worst_reference)
   fmt.sbprintf(report,",\"worst_vertex\": ")
   error_worst_json(report,e.worst_vertex)
   fmt.sbprintf(report,"}}")
  }
  fmt.sbprintf(report,"}},\n")
  fmt.sbprintf(report,"   \"over_half_meter\": [")
  over_keys:[dynamic]u64
  for key in over[i] { append(&over_keys,key) }; slice.sort(over_keys[:])
  for key,j in over_keys {
   if j>0 { fmt.sbprintf(report,",") }; sample:=over[i][key]; error_worst_json(report,sample)
   fmt.printf("VISIBLE OVER 0.5m client=%d kind=%v id=%d tick=%d R=%.3f error=%.6f speed=%.3fm/s angular=%.3frad/s bracket=%d..%d gap=%dticks\n",i,key_kind(key),key_id(key),sample.tick,sample.clock,sample.error,sample.speed,sample.angular_speed,sample.lower,sample.upper,sample.upper>sample.lower?sample.upper-sample.lower:0)
  }
  delete(over_keys); fmt.sbprintf(report,"],\n")
  // delay over time and clock
  counts:[NET_DELAY_MAX+1]int
  changes:=0; previous:=u8(0)
  for d,k in c.stats.delay_history { counts[d]+=1; if k>0 && d!=previous { changes+=1 }; previous=d }
  fmt.printf("DELAY final=%d changes=%d histogram(ticks:count)",c.delay,changes)
  for count,d in counts { if count>0 { fmt.printf(" %d:%d",d,count) } }
  fmt.println()
  mean_adjust:=0.0; if c.stats.clock_ticks>0 { mean_adjust=c.stats.adjust_sum/f64(c.stats.clock_ticks) }
  fmt.printf("CLOCK snaps=%d adjusted_ticks=%d saturated_at_5pct=%d mean_adjust=%.5f max_abs_adjust=%.4f\n",c.stats.snaps,c.stats.clock_ticks,c.stats.clock_saturated,mean_adjust,c.stats.adjust_abs_max)
  fmt.printf("LATE structure/events arriving after the clock passed their tick: structure=%d events=%d max_lateness=%.2f ticks; explosions played=%d rejected events=%d resets=%d\n",c.stats.late_structure,c.stats.late_events,c.stats.late_max_ticks,c.stats.events_played,c.stats.blast_rejections_seen,c.stats.resets)
  fmt.printf("FRAMES complete=%d parts=%d duplicate_parts=%d wrong_epoch=%d undecodable=%d malformed=%d lost(declared)=%d\n",c.stats.frames_complete,c.stats.frame_parts,c.stats.frame_parts_duplicate,c.stats.frames_wrong_epoch,c.stats.frames_undecodable,c.stats.frames_malformed,c.stats.frames_lost)
  fb:=s.frame_bytes[:]
  fmt.printf("ENTRIES sent=%d (players/bombs %d) gone ids sent=%d parts=%d; mean %.2f bytes per entry incl. headers; input messages mean %.1f max %d bytes\n",s.entries_sent,s.forced_sent,s.gone_sent,s.parts_sent,f64(frame_bytes_total(s.frame_bytes[:]))/max(f64(s.entries_sent),1),f64(c.stats.input_bytes)/max(f64(c.stats.input_count),1),c.stats.input_max)
  fmt.printf("FRAME BYTES per tick p50=%d p99=%d max=%d; parts per frame max=%d\n",pct_i32(fb,0.5),pct_i32(fb,0.99),slice.max(fb),slice.max(s.frame_parts[:]))
  // upload per second (all packets handed to the link) and frame payload only
  upload_total,upload_peak:=u64(0),u64(0)
  window:=u64(0)
  for b,k in links[i].upload { window+=u64(b); upload_total+=u64(b); if k>=60 { window-=u64(links[i].upload[k-60]) }; upload_peak=max(upload_peak,window) }
  frame_total,frame_peak,fwindow:=u64(0),u64(0),u64(0)
  for b,k in fb { fwindow+=u64(b); frame_total+=u64(b); if k>=60 { fwindow-=u64(fb[k-60]) }; frame_peak=max(frame_peak,fwindow) }
  seconds:=f64(total)/60
  fmt.printf("UPLOAD (server->client, all packets incl. headers and structure) avg=%.1f kbit/s peak 1s=%.1f kbit/s; frame payload only avg=%.1f peak=%.1f kbit/s\n",f64(upload_total)*8/seconds/1000,f64(upload_peak)*8/1000,f64(frame_total)*8/seconds/1000,f64(frame_peak)*8/1000)
  stale:=slice.clone(s.staleness_samples[:]); defer delete(stale)
  slice.sort(stale[:])
  p99:=u16(0); if len(stale)>0 { p99=stale[clamp(int(math.ceil(0.99*f64(len(stale))))-1,0,len(stale)-1)] }
  saturation:=f64(s.saturated_ticks)/max(f64(s.ticks),1)
  fmt.printf("BUDGET saturated_ticks=%d/%d (%.4f) max_staleness=%d ticks p99_staleness=%d\n",s.saturated_ticks,s.ticks,saturation,s.staleness_max,p99)
  build:=slice.clone(s.build_ms[:]); defer delete(build); slice.sort(build)
  fmt.printf("FRAME BUILD ms p50=%.4f p99=%.4f max=%.4f\n",pct_f64(build,0.5),pct_f64(build,0.99),pct_f64(build,1))
  fmt.printf("INPUTS jumps pressed=%d applied=%d; blasts issued=%d applied=%d rejected=%d (outside=%d rate=%d solid=%d) duplicates=%d dropped_by_client=%d inputs=%d stale=%d\n",c.stats.jumps_pressed,s.jumps_applied,c.stats.blasts_issued,s.blasts_applied,s.blasts_rejected,s.rejected_outside,s.rejected_rate,s.rejected_solid,s.blast_duplicates,c.stats.blasts_dropped,s.inputs,s.inputs_stale)
  fmt.printf("LINK s2c sent=%d dropped=%d duplicated=%d reordered=%d; c2s sent=%d dropped=%d\n",links[i].s2c.stats.sent,links[i].s2c.stats.dropped,links[i].s2c.stats.duplicated,links[i].s2c.stats.reordered,links[i].c2s.stats.sent,links[i].c2s.stats.dropped)
  fmt.sbprintf(report,"   \"delay\": {{\"final\": %d, \"changes\": %d, \"every_10s\": [",c.delay,changes)
  for k:=0; k<len(c.stats.delay_history); k+=600 { fmt.sbprintf(report,"%s%d",k>0?",":"",c.stats.delay_history[k]) }
  fmt.sbprintf(report,"], \"histogram\": {{")
  first:=true
  for count,d in counts { if count>0 { fmt.sbprintf(report,"%s\"%d\": %d",first?"":", ",d,count); first=false } }
  fmt.sbprintf(report,"}}}},\n   \"clock\": {{\"snaps\": %d, \"adjusted_ticks\": %d, \"saturated\": %d, \"mean_adjust\": %.6f, \"max_abs_adjust\": %.4f}},\n",c.stats.snaps,c.stats.clock_ticks,c.stats.clock_saturated,mean_adjust,c.stats.adjust_abs_max)
  fmt.sbprintf(report,"   \"late\": {{\"structure\": %d, \"events\": %d, \"max_ticks\": %.3f}},\n",c.stats.late_structure,c.stats.late_events,c.stats.late_max_ticks)
  fmt.sbprintf(report,"   \"frame_bytes\": {{\"p50\": %d, \"p99\": %d, \"max\": %d, \"max_parts\": %d, \"entries_sent\": %d, \"gone_sent\": %d, \"bytes_per_entry\": %.3f, \"input_mean\": %.2f, \"input_max\": %d}},\n",pct_i32(fb,0.5),pct_i32(fb,0.99),slice.max(fb),slice.max(s.frame_parts[:]),s.entries_sent,s.gone_sent,f64(frame_bytes_total(s.frame_bytes[:]))/max(f64(s.entries_sent),1),f64(c.stats.input_bytes)/max(f64(c.stats.input_count),1),c.stats.input_max)
  fmt.sbprintf(report,"   \"upload_kbit_s\": {{\"avg_all\": %.2f, \"peak_all\": %.2f, \"avg_frames\": %.2f, \"peak_frames\": %.2f}},\n",f64(upload_total)*8/seconds/1000,f64(upload_peak)*8/1000,f64(frame_total)*8/seconds/1000,f64(frame_peak)*8/1000)
  fmt.sbprintf(report,"   \"budget\": {{\"saturated_fraction\": %.5f, \"max_staleness_ticks\": %d, \"p99_staleness_ticks\": %d}},\n",saturation,s.staleness_max,p99)
  fmt.sbprintf(report,"   \"frame_build_ms\": {{\"p50\": %.5f, \"p99\": %.5f, \"max\": %.5f}},\n",pct_f64(build,0.5),pct_f64(build,0.99),pct_f64(build,1))
  fmt.sbprintf(report,"   \"inputs\": {{\"jumps_pressed\": %d, \"jumps_applied\": %d, \"blasts_issued\": %d, \"blasts_applied\": %d, \"blasts_rejected\": %d, \"duplicates\": %d}}}}%s\n",c.stats.jumps_pressed,s.jumps_applied,c.stats.blasts_issued,s.blasts_applied,s.blasts_rejected,s.blast_duplicates,i<nc.MAX_CLIENTS-1?",":"")
 }
 ticks:=slice.clone(ns.tick_ms[:]); defer delete(ticks); slice.sort(ticks)
 world:=slice.clone(ns.world_ms[:]); defer delete(world); slice.sort(world)
 fmt.printf("WORLD TICK ms (world_tick alone) p50=%.4f p99=%.4f max=%.4f\n",pct_f64(world,0.5),pct_f64(world,0.99),pct_f64(world,1))
 fmt.printf("SERVER TICK ms (receive, inputs, world_tick, structure, 4 frame builds, packets) p50=%.4f p99=%.4f max=%.4f; reliable structure bytes sent=%d; explosions emitted=%d\n",pct_f64(ticks,0.5),pct_f64(ticks,0.99),pct_f64(ticks,1),ns.reliable_bytes,ns.explosions_emitted)
 fmt.sbprintf(report," ],\n \"world_tick_ms\": {{\"p50\": %.5f, \"p99\": %.5f, \"max\": %.5f}}, \"server_tick_ms\": {{\"p50\": %.5f, \"p99\": %.5f, \"max\": %.5f}}, \"reliable_structure_bytes\": %d, \"explosions_emitted\": %d\n}}\n",pct_f64(world,0.5),pct_f64(world,0.99),pct_f64(world,1),pct_f64(ticks,0.5),pct_f64(ticks,0.99),pct_f64(ticks,1),ns.reliable_bytes,ns.explosions_emitted)
}

net_soak_render :: proc(ns: ^Net_Server,clients: ^[nc.MAX_CLIENTS]Net_Client,views: ^[nc.MAX_CLIENTS]Net_Client_View,directory: string) {
 _ = os.make_directory_all(directory)
 target:=rl.LoadRenderTexture(1280,800); defer rl.UnloadRenderTexture(target)
 view:=sandbox_view(1280,800)
 // Host picture: true poses through the same draw path.
 poses:=make(map[u64]Pose); defer delete(poses)
 for sub in ns.game.world.scene.subdivisions { if sub.live { poses[sub.id]=sub.pose } }
 caches:Render_Cache_State; defer release_render_caches(&caches)
 image:=replication_render(&ns.game.world.scene,&caches,poses,target)
 _ = rl.ExportImage(image,fmt.ctprintf("%s/host.png",directory)); rl.UnloadImage(image)
 for i in 0..<nc.MAX_CLIENTS {
  rl.BeginDrawing(); rl.BeginTextureMode(target); rl.ClearBackground({19,28,42,255})
  net_client_draw(&clients[i],&views[i],view)
  rl.EndTextureMode(); rl.EndDrawing()
  shot:=rl.LoadImageFromTexture(target.texture); rl.ImageFlipVertical(&shot)
  _ = rl.ExportImage(shot,fmt.ctprintf("%s/client-%d.png",directory,i)); rl.UnloadImage(shot)
 }
}

// CLI: --net-soak [minutes]
run_net_soak :: proc(minutes: int = 10) {
 track:mem.Tracking_Allocator;mem.tracking_allocator_init(&track,context.allocator);defer mem.tracking_allocator_destroy(&track)
 context.allocator=mem.tracking_allocator(&track)
 defer { fmt.printf("Net soak teardown Odin=%d Box2D=%d texture=%d shader=%d fonts=%v\n",track.current_memory_allocated,b2.GetByteCount(),material_texture.id,material_shader.id,ui_fonts_ready);assert(track.current_memory_allocated==0 && b2.GetByteCount()==0 && material_texture.id==0 && material_shader.id==0 && !ui_fonts_ready) }
 rl.SetTraceLogLevel(.WARNING); rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"BOM net soak"); defer { presentation_shutdown(); rl.CloseWindow() }
 sandbox_gui_style(); rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{}); rl.SetTargetFPS(0)
 _ = os.make_directory_all("evidence/replication-2b-followup")
 cfg:=Net_Soak_Config{ticks=minutes*3600,flush_ticks=120,seed=1234,refill=true,reset_tick=minutes*1800,render_dir="evidence/replication-2b-followup/render",report_path="evidence/replication-2b-followup/net-soak.json",verbose=true}
 fmt.printf("== net soak: %d minutes, falling bombs, 4 bots, client 0 local, clients 1-3 remote (40+-10 ms, 2%% loss, 1%% dup, 2%% reorder); refills every 2 min, sandbox reset at tick %d\n",minutes,cfg.reset_tick)
 result:=net_soak_run(cfg)
 ok:=result.table_mismatch==0 && result.structure_errors==0
 for i in 0..<nc.MAX_CLIENTS { ok = ok && result.structure_mismatch[i]==0 && result.final_equal[i] && result.jumps_pressed[i]==result.jumps_applied[i] && result.blasts_applied[i]+result.blasts_rejected[i]==result.blasts_issued[i] && result.blast_duplicates[i]==0 }
 fmt.printf("NETSOAK RESULT %s\n","PASS" if ok else "FAIL")
 assert(ok)
}
