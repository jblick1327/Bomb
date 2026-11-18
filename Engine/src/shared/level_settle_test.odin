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
 seam:=Mortar_Seam{length=0.25,force={70,0},torque=8.75};append(&seam.members,u64(30));defer delete(seam.members)
 level_settle_force(&s,seam,5,true,.43)
 t.expect_value(test,len(report.seams),1)
 row:=report.seams[0]
 t.expect(test,row.source_a==101 && row.source_b==202 && row.part_a==1 && row.part_b==2)
 t.expect(test,math.abs(row.force_at_max_r-2.5)<1e-6 && math.abs(row.torque_at_max_r-2.5)<1e-6)
 t.expect(test,row.max_r==5 && row.damage==.43 && row.break_tick==7 && row.peak_tick==7)
 observer.tick=8;level_settle_force(&s,seam,1,false,0)
 t.expect(test,len(report.seams)==1 && report.seams[0].damage==.43 && report.seams[0].last_tick==8)
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
