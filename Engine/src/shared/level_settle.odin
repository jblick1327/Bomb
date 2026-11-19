package shared

import math "core:math"
import b2 "vendor:box2d"
import time "core:time"
import strings "core:strings"
import strconv "core:strconv"

// Diagnostic data only: never enters a Scene, snapshot, manifest or wire packet.
Level_Settle_Seam :: struct {
 source_a,source_b,part_a,part_b:u64,
 members:[dynamic]u64,
 length,min_length,max_length:f32,
 first_tick,last_tick,peak_tick,break_tick:int,
 max_r,force_at_max_r,torque_at_max_r,max_force_part,max_torque_part,damage:f32,
 force_magnitude_at_max_r,torque_magnitude_at_max_r:f32,
 tick1_r,tick1_force_part,tick1_torque_part,tick1_damage:f32,
 trace_r:[dynamic]f32, // G-N8: r per tick for ticks 0..trace_ticks; -1 where the seam was not evaluated.
}
// G-N8 diagnostic options. Gravity scale at step t: 0 while t<=hold, then (t-hold)/ramp until it reaches 1.
// The defaults (all zero) leave the run exactly as before.
Level_Settle_Options :: struct {
 gravity_hold_ticks,gravity_ramp_ticks,trace_ticks:int,
 // G-N9 diagnostic: one scripted blast applied just before step blast_tick (0 = none).
 blast_tick:int,blast_point:Vec2,blast_radius:f32,
}
// G-N9: rows of Level_Settle_Report.blast.trace cover ticks blast_tick..blast_tick+LEVEL_SETTLE_BLAST_TRACE_TICKS.
LEVEL_SETTLE_BLAST_TRACE_TICKS :: 600
// Per-tick summary for ticks 0..trace_ticks. Contact figures come from Box2D's manifolds after the step.
Level_Settle_Tick :: struct {
 tick:int,gravity_scale:f32,
 max_r,max_r_length:f32,max_r_source_a,max_r_source_b:u64,
 seams,seams_over_one,breaks:int,
 contact_points,penetrating_points:int,
 max_penetration,max_contact_force:f32,
 max_contact_source_a,max_contact_source_b:u64,
 world_contacts:int, // G-N9: Box2D's live contact pair count after the step (touching or not).
}
// G-N9: one live piece; position is the area-weighted centre of its live cells.
Level_Settle_Piece :: struct {id,source:u64,cells:int,area:f32,position:Vec2,dynamic_body:bool}
Level_Settle_Blast :: struct {
 tick:int,point:Vec2,radius:f32,aim_valid:bool,
 cells_before,cells_after_blast:int,
 pieces_before,pieces_final:[dynamic]Level_Settle_Piece,
 trace:[dynamic]Level_Settle_Tick,
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
 options:Level_Settle_Options,
 trace:[dynamic]Level_Settle_Tick,
 blast:Level_Settle_Blast,
 sources:[dynamic]Level_Settle_Source,
 seams:[dynamic]Level_Settle_Seam,
}
Level_Settle_Observer :: struct {scene:^Scene,report:^Level_Settle_Report,tick:int}
// G-N9: wall-clock step timing for the CLI's stdout only; never written to the report, so reports stay byte-identical.
Level_Settle_Timing :: struct {step_ms,blast_ms,blast_window_step_ms:f64}
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
 if observer.tick<=observer.report.options.trace_ticks {
  for len(entry.trace_r)<observer.tick {append(&entry.trace_r,-1)}
  if len(entry.trace_r)==observer.tick {append(&entry.trace_r,r)}
  if n:=len(observer.report.trace);n>0 && observer.report.trace[n-1].tick==observer.tick {
   row:=&observer.report.trace[n-1];row.seams+=1
   if r>=1 {row.seams_over_one+=1}
   if broken {row.breaks+=1}
   if r>row.max_r {row.max_r=r;row.max_r_length=seam.length;row.max_r_source_a=entry.source_a;row.max_r_source_b=entry.source_b}
  }
 }
}
level_settle_gravity_scale :: proc(options:Level_Settle_Options,tick:int) -> f32 {
 if tick<=options.gravity_hold_ticks {return options.gravity_hold_ticks>0 ? 0 : 1}
 if options.gravity_ramp_ticks>0 && tick-options.gravity_hold_ticks<options.gravity_ramp_ticks {return f32(tick-options.gravity_hold_ticks)/f32(options.gravity_ramp_ticks)}
 return 1
}
level_settle_bodies :: proc(s:^Scene) -> [dynamic]b2.BodyId {
 bodies:[dynamic]b2.BodyId;seen:=make(map[b2.BodyId]bool);defer delete(seen)
 for sub in s.subdivisions {
  if !sub.live || sub.body==b2.nullBodyId || !b2.Body_IsValid(sub.body) || seen[sub.body] {continue}
  seen[sub.body]=true;append(&bodies,sub.body)
 }
 return bodies
}
level_settle_shape_source :: proc(s:^Scene,shape:b2.ShapeId) -> u64 {
 id:=u64(uintptr(b2.Shape_GetUserData(shape)))
 if row,ok:=s.sub_rows[id];ok {return s.subdivisions[row].provenance.source_identity}
 return 0
}
// Each manifold is counted once: from its A body, or from the dynamic side when the other body is not dynamic.
level_settle_contacts :: proc(s:^Scene,row:^Level_Settle_Tick,dt:f32) {
 bodies:=level_settle_bodies(s);defer delete(bodies)
 buffer:[dynamic]b2.ContactData;defer delete(buffer)
 for body in bodies {
  if b2.Body_GetType(body)!=.dynamicBody {continue}
  resize(&buffer,int(b2.Body_GetContactCapacity(body)))
  for contact in b2.Body_GetContactData(body,buffer[:]) {
   a,b:=b2.Shape_GetBody(contact.shapeIdA),b2.Shape_GetBody(contact.shapeIdB)
   other:=a==body ? b : a
   if a!=body && b2.Body_GetType(other)==.dynamicBody {continue}
   m:=contact.manifold
   for i in 0..<int(m.pointCount) {
    point:=m.points[i]
    if point.totalNormalImpulse<=0 && point.separation>=0 {continue}
    row.contact_points+=1
    if point.separation<0 {row.penetrating_points+=1;row.max_penetration=max(row.max_penetration,-point.separation)}
    force:=point.totalNormalImpulse/dt
    if force>row.max_contact_force {row.max_contact_force=force;row.max_contact_source_a=level_settle_shape_source(s,contact.shapeIdA);row.max_contact_source_b=level_settle_shape_source(s,contact.shapeIdB)}
   }
  }
 }
}
// "TICK,X,Y,RADIUS" -> options with only the blast fields set.
level_settle_parse_blast :: proc(text:string) -> (options:Level_Settle_Options,ok:bool) {
 parts:=strings.split(text,",");defer delete(parts)
 if len(parts)!=4 {return}
 tick,tick_ok:=strconv.parse_int(parts[0]);x,x_ok:=strconv.parse_f32(parts[1]);y,y_ok:=strconv.parse_f32(parts[2]);r,r_ok:=strconv.parse_f32(parts[3])
 if !tick_ok || !x_ok || !y_ok || !r_ok || tick<1 || !(r>0) || math.is_nan(x) || math.is_nan(y) || math.is_inf(x) || math.is_inf(y) || math.is_inf(r) {return}
 return Level_Settle_Options{blast_tick=tick,blast_point={x,y},blast_radius=r},true
}
level_settle_pieces :: proc(s:^Scene) -> [dynamic]Level_Settle_Piece {
 rows:[dynamic]Level_Settle_Piece
 ids:[dynamic]u64;defer delete(ids)
 for p in s.pieces {if p.live {append(&ids,p.id)}};sort_ids(ids[:])
 for id in ids {
  p:=s.pieces[s.piece_rows[id]];row:=Level_Settle_Piece{id=id}
  weighted:Vec2
  for sub_id in p.subdivisions {
   index,found:=s.sub_rows[sub_id];if !found {continue}
   sub:=s.subdivisions[index];if !sub.live {continue}
   area:=polygon_area(sub.outline);row.cells+=1;row.area+=area;weighted=vadd(weighted,vmul(sub.pose.position,area))
   if row.source==0 {row.source=sub.provenance.source_identity}
   if sub.body!=b2.nullBodyId && b2.Body_IsValid(sub.body) && b2.Body_GetType(sub.body)==.dynamicBody {row.dynamic_body=true}
  }
  if row.cells==0 {continue}
  if row.area>0 {row.position=vmul(weighted,1/row.area)}
  append(&rows,row)
 }
 return rows
}
level_settle_destroy :: proc(report:^Level_Settle_Report) {
 delete(report.blast.pieces_before);delete(report.blast.pieces_final);delete(report.blast.trace)
 for seam in report.seams {delete(seam.members)}
 for seam in report.seams {delete(seam.trace_r)}
 delete(report.seams);delete(report.sources);delete(report.trace);report^={}
}
level_settle_run :: proc(w:^World,level:^Level_Layout,ticks,window:int,options:=Level_Settle_Options{},timing:^Level_Settle_Timing=nil) -> Level_Settle_Report {
 assert(ticks>window && window>=0 && options.gravity_hold_ticks>=0 && options.gravity_ramp_ticks>=0 && options.trace_ticks>=0)
 assert(options.blast_tick>=0 && options.blast_tick<=ticks && (options.blast_tick==0 || options.blast_radius>0))
 report:=Level_Settle_Report{status="passed",ticks=ticks,window_ticks=window,options=options}
 gravity:=scene_gameplay_config(&w.scene).gravity;gravity_scale:=f32(1)
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
  if tick<=options.trace_ticks {append(&report.trace,Level_Settle_Tick{tick=tick,gravity_scale=tick>0 ? level_settle_gravity_scale(options,tick) : 0})}
  if tick>0 {
   // Diagnostic start-up gravity (G-N8). Bodies are woken on every change so none sleeps through it.
   if scale:=level_settle_gravity_scale(options,tick);scale!=gravity_scale {
    gravity_scale=scale;b2.World_SetGravity(w.scene.physics.world,to_b2(vmul(gravity,scale)))
    bodies:=level_settle_bodies(&w.scene);for body in bodies {if b2.Body_GetType(body)==.dynamicBody {b2.Body_SetAwake(body,true)}};delete(bodies)
   }
   blasted:=options.blast_tick>0 && tick==options.blast_tick
   if blasted {
    // G-N9: the same entry a host blast uses, minus the player aim/permission checks (there are no players).
    blast:=&report.blast;blast^=Level_Settle_Blast{tick=tick,point=options.blast_point,radius=options.blast_radius,aim_valid=sandbox_valid_aim(&w.scene,options.blast_point)}
    for sub in w.scene.subdivisions {if sub.live {blast.cells_before+=1}}
    blast.pieces_before=level_settle_pieces(&w.scene)
    blast_events:Tick_Events;start:=time.tick_now()
    world_explode(w,options.blast_point,options.blast_radius,&blast_events)
    if timing!=nil {timing.blast_ms=f64(time.tick_diff(start,time.tick_now()))/f64(time.Millisecond)}
    delete(blast_events.explosions)
    for sub in w.scene.subdivisions {if sub.live {blast.cells_after_blast+=1}}
   }
   start:=time.tick_now()
   events:=world_tick(w,{},f32(1.0/60.0));assert(len(events.explosions)==0 && events.bombs_spawned==0);delete(events.explosions)
   if timing!=nil {
    elapsed:=f64(time.tick_diff(start,time.tick_now()))/f64(time.Millisecond);timing.step_ms+=elapsed
    if options.blast_tick>0 && tick>=options.blast_tick && tick<=options.blast_tick+LEVEL_SETTLE_BLAST_TRACE_TICKS {timing.blast_window_step_ms+=elapsed}
   }
   if tick<=options.trace_ticks {row:=&report.trace[len(report.trace)-1];level_settle_contacts(&w.scene,row,f32(1.0/60.0));row.world_contacts=int(b2.World_GetCounters(w.scene.physics.world).contactCount)}
   if options.blast_tick>0 && tick>=options.blast_tick && tick<=options.blast_tick+LEVEL_SETTLE_BLAST_TRACE_TICKS {
    row:=Level_Settle_Tick{tick=tick,gravity_scale=gravity_scale};level_settle_contacts(&w.scene,&row,f32(1.0/60.0))
    row.world_contacts=int(b2.World_GetCounters(w.scene.physics.world).contactCount)
    append(&report.blast.trace,row)
   }
  }
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
 if options.blast_tick>0 {report.blast.pieces_final=level_settle_pieces(&w.scene)}
 if report.min_cells_after_window<report.baseline_cells || report.max_piece_displacement>0.1 {report.status="failed"}
 return report
}
