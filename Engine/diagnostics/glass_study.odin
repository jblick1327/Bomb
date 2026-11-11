package main

import "core:fmt"
import "core:os"
import b2 "vendor:box2d"

Glass_Study :: struct { pieces,cells: int, surviving,largest_fraction: f32, medians,cell_medians: [3]f32, band_counts,cell_band_counts: [3]int }
glass_study_stats :: proc(s: ^Scene,origin: Vec2) -> Glass_Study {
 result:=Glass_Study{}; largest:=f32(0)
 areas,cell_areas:[3][dynamic]f32
 defer { for a in areas { delete(a) }; for a in cell_areas { delete(a) } }
 ids:[dynamic]u64; defer delete(ids)
 for p in s.pieces { if p.live && s.materials[p.material].name=="glass" { append(&ids,p.id) } }; sort_ids(ids[:])
 for id in ids {
  p:=s.pieces[s.piece_rows[id]]; mass:=f32(0); centre:=Vec2{}
  for cell in p.subdivisions {
   sub:=s.subdivisions[s.sub_rows[cell]]; area:=polygon_area(sub.outline); mass+=area
   centre=vadd(centre,vmul(sub.pose.position,area)); result.cells+=1
   d:=vlen(vsub(sub.pose.position,origin)); band:=0; if d>=2 { band=1 }; if d>=4 { band=2 }
   append(&cell_areas[band],area)
  }
  centre=vmul(centre,1/mass); result.pieces+=1; result.surviving+=mass; largest=max(largest,mass)
  d:=vlen(vsub(centre,origin)); band:=0; if d>=2 { band=1 }; if d>=4 { band=2 }
  append(&areas[band],mass)
 }
 if result.surviving>0 { result.largest_fraction=largest/result.surviving }
 for i in 0..<3 { result.band_counts[i]=len(areas[i]); result.medians[i]=wood_median(areas[i][:]); result.cell_band_counts[i]=len(cell_areas[i]); result.cell_medians[i]=wood_median(cell_areas[i][:]) }
 return result
}
glass_pane_yard :: proc(radius: f32,tuning:Player_Tuning=PLAYER_TUNING) -> Sandbox {
 g:=sandbox_editor_create(); g.editor.palette=recipe_slot(.Glass)
 assert(editor_place(&g,{0,0},{5,2.5})); sandbox_toggle_editor(&g)
 sandbox_fixture_player_tuning(&g,tuning)
 for _ in 0..<120 { sandbox_tick(&g,0,false) }
 sandbox_fixture_radius(&g,radius); sandbox_explode(&g,{-0.6,1.25}); return g
}
// Stop immediately after the first damaging impact batch, before later falls.
glass_impact_yard :: proc() -> (Sandbox,int) {
 g:=sandbox_editor_create(); g.editor.palette=recipe_slot(.Glass)
 assert(editor_place(&g,{0,0},{2,1})); sandbox_toggle_editor(&g)
 s:=&g.world.scene; moved:=make(map[b2.BodyId]bool); defer delete(moved)
 for sub in s.subdivisions {
  if s.materials[sub.material].name!="glass" || moved[sub.body] { continue }; moved[sub.body]=true
  p:=b2.Body_GetPosition(sub.body); p.y+=0.8; b2.Body_SetTransform(sub.body,p,b2.MakeRot(0))
 }
 physics_read_motion(s); revision:=s.revision
 for tick in 1..=180 { sandbox_tick(&g,0,false); if s.revision!=revision { return g,tick } }
 return g,0
}
glass_nonglass_yard :: proc() -> Sandbox {
 g:=sandbox_editor_create(); positions:=[4]f32{-7.2,-3,0,3.5}
 for choice in Recipe { if choice==.Glass { continue }; x:=positions[int(choice)]; g.editor.palette=recipe_slot(choice); assert(editor_place(&g,{x,0},{x+1.6,2})) }
 sandbox_toggle_editor(&g)
 // The fixture's material table contains only non-glass materials too.
 for m,i in g.world.scene.materials { if m.name=="glass" {
  ordered_remove(&g.world.scene.materials,i)
  for &sub in g.world.scene.subdivisions { if sub.material>i { sub.material-=1 } }
  for &piece in g.world.scene.pieces { if piece.material>i { piece.material-=1 } }
  break
 } }
 positions_blast:=[3]Vec2{{-6.6,1},{0,0.6},{5.8,1.2}}
 for p in positions_blast { sandbox_explode(&g,p) }
 return g
}
run_glass_study :: proc(directory: string) {
 assert(os.make_directory_all(directory)==nil)
 for radius in 3..=4 {
  g:=glass_pane_yard(f32(radius))
  stats:=glass_study_stats(&g.world.scene,{-0.6,1.25})
  fmt.printf("Pane r%d: %v\n",radius,stats)
  path:=fmt.aprintf("%s/pane-r%d.json",directory,radius); assert(save_world_snapshot(&g.world,path)); delete(path)
  sandbox_destroy(&g)
 }
 g,tick:=glass_impact_yard()
 fmt.printf("Impact tick=%d: %v\n",tick,glass_study_stats(&g.world.scene,{0,0}))
 path:=fmt.aprintf("%s/impact.json",directory); assert(save_world_snapshot(&g.world,path)); delete(path); sandbox_destroy(&g)
 control:=glass_nonglass_yard(); defer sandbox_destroy(&control)
 path=fmt.aprintf("%s/nonglass-v3.json",directory); assert(save_world_snapshot(&control.world,path)); delete(path)
}
