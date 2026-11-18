package shared

import math "core:math"
import b2 "vendor:box2d"

// Diagnostic data only: never enters a Scene, snapshot, manifest or wire packet.
Level_Settle_Seam :: struct {
 source_a,source_b,part_a,part_b:u64,
 members:[dynamic]u64,
 length,min_length,max_length:f32,
 first_tick,last_tick,peak_tick,break_tick:int,
 max_r,force_at_max_r,torque_at_max_r,max_force_part,max_torque_part,damage:f32,
 force_magnitude_at_max_r,torque_magnitude_at_max_r:f32,
 tick1_r,tick1_force_part,tick1_torque_part,tick1_damage:f32,
}
Level_Settle_Source :: struct {
 identity:u64,name:string,
 initial_cells,final_cells,min_cells,cells_lost:int,
 max_displacement,max_after_window:f32,
}
Level_Settle_Report :: struct {
 status:string,
 ticks,window_ticks,baseline_cells,min_cells_after_window,final_cells:int,
 max_piece_displacement:f32,
 max_piece_id:u64,
 max_piece_tick:int,
 sources:[dynamic]Level_Settle_Source,
 seams:[dynamic]Level_Settle_Seam,
}
Level_Settle_Observer :: struct {scene:^Scene,report:^Level_Settle_Report,tick:int}
@(thread_local) level_settle_observer:^Level_Settle_Observer

// Split the actual native ratio rather than assuming a particular material law.
// This also lets the identical diagnostic source run on the pre-G-N1 native.
level_settle_parts :: proc(seam:Mortar_Seam,r:f32) -> (force,torque:f32) {
 f:=vlen(seam.force)/seam.length
 q:=math.abs(seam.torque)/(0.5*seam.length*seam.length)
 if f+q>0 {force=r*f/(f+q);torque=r*q/(f+q)}
 return
}
level_settle_force :: proc(s:^Scene,seam:Mortar_Seam,r:f32,broken:bool,damage:f32) {
 observer:=level_settle_observer
 if observer==nil || observer.scene!=s || len(seam.members)==0 {return}
 row:=-1
 for candidate,i in observer.report.seams {
  if len(candidate.members)!=len(seam.members) {continue}
  same:=true;for id,j in seam.members {if id!=candidate.members[j] {same=false;break}}
  if same {row=i;break}
 }
 if row<0 {
  c:=s.connections[s.conn_rows[seam.members[0]]]
  a,b:=s.subdivisions[s.sub_rows[c.a]].provenance,s.subdivisions[s.sub_rows[c.b]].provenance
  entry:=Level_Settle_Seam{source_a=a.source_identity,source_b=b.source_identity,part_a=a.source_part_id,part_b=b.source_part_id,length=seam.length,min_length=seam.length,max_length=seam.length,first_tick=observer.tick}
  append(&entry.members,..seam.members[:]);row=len(observer.report.seams);append(&observer.report.seams,entry)
 }
 entry:=&observer.report.seams[row]
 entry.last_tick=observer.tick;entry.min_length=min(entry.min_length,seam.length);entry.max_length=max(entry.max_length,seam.length)
 force,torque:=level_settle_parts(seam,r)
 if r>entry.max_r {entry.max_r=r;entry.force_at_max_r=force;entry.torque_at_max_r=torque;entry.peak_tick=observer.tick;entry.force_magnitude_at_max_r=vlen(seam.force);entry.torque_magnitude_at_max_r=math.abs(seam.torque)}
 if observer.tick==1 {entry.tick1_r=r;entry.tick1_force_part=force;entry.tick1_torque_part=torque;entry.tick1_damage=damage}
 entry.max_force_part=max(entry.max_force_part,force);entry.max_torque_part=max(entry.max_torque_part,torque)
 entry.damage=max(entry.damage,damage)
 if broken && entry.break_tick==0 {entry.break_tick=observer.tick}
}
level_settle_destroy :: proc(report:^Level_Settle_Report) {
 for seam in report.seams {delete(seam.members)}
 delete(report.seams);delete(report.sources);report^={}
}
level_settle_run :: proc(w:^World,level:^Level_Layout,ticks,window:int) -> Level_Settle_Report {
 assert(ticks>window && window>=0)
 report:=Level_Settle_Report{status="passed",ticks=ticks,window_ticks=window}
 for i in 0..<len(w.players) {_=world_remove_player(w,i)}
 // DEFAULT_SANDBOX_SETTINGS uses manual blasts; assert the diagnostic cannot spawn rain.
 assert(w.settings.blast_mode!=.Falling_Bombs && len(w.bombs)==0)
 for source in level.sources {
  row:=Level_Settle_Source{identity=source.identity,name=source.asset_key}
  for sub in w.scene.subdivisions {if sub.live&&sub.provenance.source_identity==source.identity {row.initial_cells+=1}}
  row.min_cells=row.initial_cells;append(&report.sources,row)
 }
 initial:=make(map[u64]Vec2);defer delete(initial)
 initial_sources:=make(map[u64]u64);defer delete(initial_sources)
 window_cells:=make(map[u64]Vec2);defer delete(window_cells)
 pieces:=make(map[u64]Vec2);defer delete(pieces)
 for sub in w.scene.subdivisions {if sub.live {initial[sub.id]=sub.pose.position;initial_sources[sub.id]=sub.provenance.source_identity}}
 observer:=Level_Settle_Observer{scene=&w.scene,report=&report}
 previous:=level_settle_observer;level_settle_observer=&observer;defer {level_settle_observer=previous}
 for tick in 0..=ticks {
  observer.tick=tick
  if tick>0 {events:=world_tick(w,{},f32(1.0/60.0));assert(len(events.explosions)==0 && events.bombs_spawned==0);delete(events.explosions)}
  if tick==0 {
   seams:=mortar_seams(&w.scene);for seam in seams {level_settle_force(&w.scene,seam,0,false,seam.damage)};mortar_free_seams(seams)
  }
  live:=0
  for &row in report.sources {
   count,lost:=0,0
   // Compaction can remove dead cells entirely; count missing original IDs too.
   for id,source in initial_sources {
    if source!=row.identity {continue}
    index,found:=w.scene.sub_rows[id]
    if !found || !w.scene.subdivisions[index].live {lost+=1}
   }
   for sub in w.scene.subdivisions {
    if sub.provenance.source_identity!=row.identity {continue}
    if !sub.live {continue}
    count+=1
    if position,found:=initial[sub.id];found {row.max_displacement=max(row.max_displacement,vlen(vsub(sub.pose.position,position)))}
    if tick==window {window_cells[sub.id]=sub.pose.position}
    if tick>=window {
     position,found:=window_cells[sub.id];if !found {position=sub.pose.position;window_cells[sub.id]=position}
     row.max_after_window=max(row.max_after_window,vlen(vsub(sub.pose.position,position)))
    }
   }
   row.final_cells=count;row.min_cells=min(row.min_cells,count);row.cells_lost=max(row.cells_lost,lost);live+=count
  }
  if tick==window {report.baseline_cells=live;report.min_cells_after_window=live}
  if tick>=window {
   report.min_cells_after_window=min(report.min_cells_after_window,live)
   for piece in w.scene.pieces {
    if !piece.live {continue}
    position:=piece.ref_rest
    if piece.body!=b2.nullBodyId && b2.Body_IsValid(piece.body) {position=from_b2(b2.Body_GetWorldPoint(piece.body,to_b2(piece.ref_rest)))}
    origin,found:=pieces[piece.id];if !found {origin=position;pieces[piece.id]=position}
    d:=vlen(vsub(position,origin))
    if d>report.max_piece_displacement {report.max_piece_displacement=d;report.max_piece_id=piece.id;report.max_piece_tick=tick}
   }
  }
  report.final_cells=live
 }
 if report.min_cells_after_window<report.baseline_cells || report.max_piece_displacement>0.1 {report.status="failed"}
 return report
}
