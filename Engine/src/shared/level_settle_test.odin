package shared

import t "core:testing"
import math "core:math"
import strings "core:strings"

@(test)
settle_records_actual_force_torque_damage_and_break_tick :: proc(test:^t.T) {
 s:Scene;s.sub_rows=make(map[u64]int);s.conn_rows=make(map[u64]int)
 defer delete(s.sub_rows);defer delete(s.conn_rows);defer delete(s.subdivisions);defer delete(s.connections)
 append(&s.subdivisions,Subdivision{id=10,provenance={source_identity=101,source_part_id=1}})
 append(&s.subdivisions,Subdivision{id=20,provenance={source_identity=202,source_part_id=2}})
 s.sub_rows[10]=0;s.sub_rows[20]=1
 append(&s.connections,Connection{id=30,a=10,b=20});s.conn_rows[30]=0
 report:Level_Settle_Report;defer level_settle_destroy(&report)
 observer:=Level_Settle_Observer{scene=&s,report=&report,tick=7}
 previous:=level_settle_observer;level_settle_observer=&observer;defer {level_settle_observer=previous}
 // OD-10: the force part of r comes from the charged force (the weld force less any bearing); here all of it is charged.
 seam:=Mortar_Seam{length=0.25,force={70,0},charged={70,0},torque=8.75};append(&seam.members,u64(30));defer delete(seam.members)
 level_settle_force(&s,seam,5,true,.43)
 t.expect_value(test,len(report.seams),1)
 row:=report.seams[0]
 t.expect(test,row.source_a==101 && row.source_b==202 && row.part_a==1 && row.part_b==2)
 t.expect(test,math.abs(row.force_at_max_r-2.5)<1e-6 && math.abs(row.torque_at_max_r-2.5)<1e-6)
 t.expect(test,row.max_r==5 && row.damage==.43 && row.break_tick==7 && row.peak_tick==7)
 observer.tick=8;level_settle_force(&s,seam,1,false,0)
 t.expect(test,len(report.seams)==1 && report.seams[0].damage==.43 && report.seams[0].last_tick==8)
 // A seam carrying 70 N of bearing besides the same charged force splits r the same way; the weld force magnitude is still recorded.
 bearing:=seam;bearing.force={70,70};bearing.bearing=70
 observer.tick=9;level_settle_force(&s,bearing,6,false,0)
 row=report.seams[0]
 t.expect(test,math.abs(row.force_at_max_r-3)<1e-6 && math.abs(row.torque_at_max_r-3)<1e-6 && row.peak_tick==9)
 t.expect(test,math.abs(row.force_magnitude_at_max_r-70*math.sqrt(f32(2)))<1e-3)
}

@(test)
settle_observation_is_deterministic_and_does_not_change_world_bytes :: proc(test:^t.T) {
 layout,seed,ok,reason:=decode_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_layout(&layout)
 // An unsupported dynamic source exercises movement; the original anchored
 // source exercises a stable control below. 600 ticks lets every cell cross
 // its y=-10 cull bound and exercises removal from the compacted cell table.
 delete(layout.level.sources[0].motion);layout.level.sources[0].motion=strings.clone("dynamic")
 clear(&layout.level.sources[0].parts[0].anchors)
 reports:[2]Level_Settle_Report;defer {for &report in reports {level_settle_destroy(&report)}}
 states:[3][]u8;defer {for state in states {delete(state)}}
 for run in 0..<3 {
  w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false)
  if run<2 {reports[run]=level_settle_run(&w,layout.level,600,10)}
  else {for i in 0..<len(w.players) {_=world_remove_player(&w,i)};for _ in 0..<600 {events:=world_tick(&w,{},f32(1.0/60.0));delete(events.explosions)}}
  states[run]=canonical_encode(&w.scene);scene_destroy(&w.scene);delete(w.bombs)
 }
 a,a_ok:=exact_json_encode(reports[0],true);b,b_ok:=exact_json_encode(reports[1],true);defer delete(a);defer delete(b)
 t.expect(test,a_ok && b_ok && string(a)==string(b),"settle report must repeat byte for byte")
 t.expect(test,string(states[0])==string(states[1]) && string(states[0])==string(states[2]),"observed and unobserved native state must match")
 t.expect(test,reports[0].sources[0].cells_lost==reports[0].sources[0].initial_cells && reports[0].sources[0].final_cells==0)
 t.expect(test,reports[0].status=="failed" && reports[0].sources[0].max_displacement>0.1 && reports[0].max_piece_displacement>0.1)
 delete(layout.level.sources[0].motion);layout.level.sources[0].motion=strings.clone("fixed")
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false);defer scene_destroy(&w.scene);defer delete(w.bombs)
 report:=level_settle_run(&w,layout.level,40,10);defer level_settle_destroy(&report)
 t.expect(test,report.status=="passed" && report.sources[0].cells_lost==0 && report.max_piece_displacement==0)
}

@(test)
settle_startup_gravity_options_schedule_trace_and_zero_gravity :: proc(test:^t.T) {
 // Defaults keep full gravity from the first step.
 t.expect(test,level_settle_gravity_scale({},1)==1 && level_settle_gravity_scale({},500)==1)
 hold:=Level_Settle_Options{gravity_hold_ticks=3}
 t.expect(test,level_settle_gravity_scale(hold,1)==0 && level_settle_gravity_scale(hold,3)==0 && level_settle_gravity_scale(hold,4)==1)
 ramp:=Level_Settle_Options{gravity_ramp_ticks=4}
 t.expect(test,level_settle_gravity_scale(ramp,1)==.25 && level_settle_gravity_scale(ramp,3)==.75 && level_settle_gravity_scale(ramp,4)==1)
 both:=Level_Settle_Options{gravity_hold_ticks=2,gravity_ramp_ticks=2}
 t.expect(test,level_settle_gravity_scale(both,2)==0 && level_settle_gravity_scale(both,3)==.5 && level_settle_gravity_scale(both,4)==1)
 // An unsupported dynamic source stays exactly still with gravity held at zero, and the trace has one row per tick.
 layout,seed,ok,reason:=decode_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_layout(&layout)
 delete(layout.level.sources[0].motion);layout.level.sources[0].motion=strings.clone("dynamic")
 clear(&layout.level.sources[0].parts[0].anchors)
 reports:[2]Level_Settle_Report;defer {for &report in reports {level_settle_destroy(&report)}}
 for run in 0..<2 {
  w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false)
  reports[run]=level_settle_run(&w,layout.level,40,10,{gravity_hold_ticks=40,trace_ticks=5})
  scene_destroy(&w.scene);delete(w.bombs)
 }
 report:=reports[0]
 t.expect(test,report.status=="passed" && report.max_piece_displacement==0 && report.sources[0].max_displacement==0)
 t.expect_value(test,len(report.trace),6)
 t.expect(test,report.trace[0].tick==0 && report.trace[5].tick==5 && report.trace[5].gravity_scale==0)
 a,a_ok:=exact_json_encode(reports[0],true);b,b_ok:=exact_json_encode(reports[1],true);defer delete(a);defer delete(b)
 t.expect(test,a_ok && b_ok && string(a)==string(b),"traced settle report must repeat byte for byte")
}

@(test)
settle_scripted_blast_option_parses_records_and_matches_unobserved_world :: proc(test:^t.T) {
 // G-N9 diagnostic blast: parsing, report contents, byte identity, and no effect on native state beyond the blast itself.
 parsed,parsed_ok:=level_settle_parse_blast("7,-1.5,2.25,3");t.expect(test,parsed_ok)
 t.expect(test,parsed.blast_tick==7 && parsed.blast_point==Vec2{-1.5,2.25} && parsed.blast_radius==3)
 for bad in ([]string{"0,1,1,1","1,1,1,0","1,1,1","1,1,1,1,1","x,1,1,1","1,nan,1,1","1,1,1,-2"}) {_,bad_ok:=level_settle_parse_blast(bad);t.expect(test,!bad_ok,bad)}
 layout,seed,ok,reason:=decode_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_layout(&layout)
 delete(layout.level.sources[0].damage);layout.level.sources[0].damage=strings.clone("destructible")
 // Wood, not the fixture's stone: the stone L shrugs off this blast (11 -> 11 cells), so it would not exercise the blast record.
 delete(layout.level.sources[0].parts[0].material);layout.level.sources[0].parts[0].material=strings.clone("wood")
 TICKS,BLAST_TICK::40,12
 reports:[2]Level_Settle_Report;defer {for &report in reports {level_settle_destroy(&report)}}
 states:[3][]u8;defer {for state in states {delete(state)}}
 point:Vec2
 for run in 0..<3 {
  w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false)
  if run==0 {
   // Just left of the structure's leftmost vertex, at its vertical middle: outside every cell.
   lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
   for sub in w.scene.subdivisions {for q in sub.outline.points {p:=vadd(sub.pose.position,vrotate(vsub(q,sub.rest_center),sub.pose.angle));lo={min(lo.x,p.x),min(lo.y,p.y)};hi={max(hi.x,p.x),max(hi.y,p.y)}}}
   point={lo.x-0.05,(lo.y+hi.y)*0.5}
  }
  options:=Level_Settle_Options{blast_tick=BLAST_TICK,blast_point=point,blast_radius=3}
  if run<2 {reports[run]=level_settle_run(&w,layout.level,TICKS,10,options)}
  else {
   for i in 0..<len(w.players) {_=world_remove_player(&w,i)}
   for tick in 1..=TICKS {
    if tick==BLAST_TICK {blast_events:Tick_Events;world_explode(&w,point,3,&blast_events);delete(blast_events.explosions)}
    events:=world_tick(&w,{},f32(1.0/60.0));delete(events.explosions)
   }
  }
  states[run]=canonical_encode(&w.scene);scene_destroy(&w.scene);delete(w.bombs)
 }
 blast:=reports[0].blast
 t.expect(test,blast.tick==BLAST_TICK && blast.aim_valid && blast.radius==3 && blast.point==point)
 t.expectf(test,blast.cells_before>0 && blast.cells_after_blast!=blast.cells_before,"the scripted blast must change a destructible source's cells: %d -> %d",blast.cells_before,blast.cells_after_blast)
 t.expect(test,len(blast.pieces_before)>=1 && len(blast.pieces_final)>=1)
 t.expect_value(test,len(blast.trace),TICKS-BLAST_TICK+1)
 t.expect(test,blast.trace[0].tick==BLAST_TICK && blast.trace[len(blast.trace)-1].tick==TICKS)
 a,a_ok:=exact_json_encode(reports[0],true);b,b_ok:=exact_json_encode(reports[1],true);defer delete(a);defer delete(b)
 t.expect(test,a_ok && b_ok && string(a)==string(b),"blast settle report must repeat byte for byte")
 t.expect(test,string(states[0])==string(states[1]) && string(states[0])==string(states[2]),"observed blast run must match an unobserved world_explode + world_tick run")
}
