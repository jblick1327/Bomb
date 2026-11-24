package main


import shared "shared"
import "core:fmt"
import "core:math"

mortar_cantilever :: proc(end_x: f32,seed: u8 = 42) -> Sandbox {
 g:=sandbox_editor_create()
 g.world.settings.seed=seed
 g.editor.mortar=true; g.editor.palette=recipe_slot(.Stone)
 assert(editor_place(&g,{0,0},{0.4,2}))
 g.editor.palette=recipe_slot(.Wood); assert(editor_place(&g,{0,2},{end_x,2.4}))
 sandbox_toggle_editor(&g); return g
}
mortar_calibrate :: proc(end_x: f32,seed: u8 = 42) -> f32 {
 g:=mortar_cantilever(end_x,seed); defer sandbox_destroy(&g)
 g.world.scene.physics.mortar_breaking=false
 need:=f32(0)
 peaks:=make(map[u64]f32); defer delete(peaks)
 lengths:=make(map[u64]f32); defer delete(lengths)
 for tick in 1..=120 {
  sandbox_tick(&g,0,false)
  if tick<60 { continue }
  seams:=mortar_seams(&g.world.scene)
  for seam in seams {
   id:=seam.members[0]; n:=mortar_seam_need(seam)
   peaks[id]=max(peaks[id],n); lengths[id]=seam.length; need=max(need,n)
  }
  mortar_free_seams(seams)
 }
 ids:[dynamic]u64; defer delete(ids); for id in peaks { append(&ids,id) }; sort_ids(ids[:])
 for id in ids { fmt.printf("Mortar calibration beam_end=%.1f seam_first_id=%d need=%.9f length=%.9f\n",end_x,id,peaks[id],lengths[id]) }
 return need
}
run_mortar_calibration :: proc() {
 n1,n2:=mortar_calibrate(2.4),mortar_calibrate(4.4)
 fmt.printf("Mortar calibration N1=%.9f N2=%.9f ratio=%.9f geometric_mean=%.9f\n",n1,n2,n2/n1,math.sqrt(n1*n2))
 assert(n2>2*n1,"Calibration requires N(F2)>2*N(F1)")
}

mortar_bridge_yard :: proc() -> Sandbox {
 g:=sandbox_editor_create(); assert(sandbox_load_preset(&g,4)); sandbox_toggle_editor(&g); return g
}
mortar_live_count :: proc(s: ^Scene) -> int {
 count:=0; for c in s.connections { if c.live && c.mortar { count+=1 } }; return count
}
mortar_deck_lowest :: proc(s: ^Scene) -> f32 {
 lowest:=f32(1e30)
 for sub in s.subdivisions { if !sub.live || s.materials[sub.material].name!="wood" { continue }
  for point in sub.outline.points { lowest=min(lowest,posed_point(sub,point).y) }
 }; return lowest
}
run_mortar_bridge_measurements :: proc() {
 when !BOM_MORTAR_MEASURE { panic("--measure-mortar requires -define:BOM_MORTAR_MEASURE=true") }
 when BOM_MORTAR_MEASURE {
  idle:=mortar_bridge_yard()
  regions,links,pieces:=counts_runtime(&idle.world.scene); mortar:=mortar_live_count(&idle.world.scene)
  shared.mortar_measured_force_breaks=0; changed_ticks:=0; first_change:=0
  for tick in 1..=600 {
   sandbox_tick(&idle,0,false)
   r,l,_:=counts_runtime(&idle.world.scene)
   if r!=regions || l!=links { changed_ticks+=1; if first_change==0 { first_change=tick } }
  }
  fmt.printf("Mortar C1 regions=%d->%d links=%d->%d pieces=%d->%d mortar=%d->%d force_breaks=%d changed_ticks=%d first_change=%d\n",regions,len(idle.world.scene.subdivisions),links,len(idle.world.scene.connections),pieces,len(idle.world.scene.pieces),mortar,mortar_live_count(&idle.world.scene),shared.mortar_measured_force_breaks,changed_ticks,first_change)
  sandbox_destroy(&idle)
  hit:=mortar_bridge_yard(); before:=mortar_live_count(&hit.world.scene)
  original:=make(map[u64]bool); defer delete(original)
  for c in hit.world.scene.connections { if c.live && c.mortar { original[c.id]=true } }
  sandbox_fixture_radius(&hit,5); sandbox_explode(&hit,{-3,1})
  after_blast:=mortar_live_count(&hit.world.scene)
  retired,inherited:=0,0
  for id in original { if _,ok:=hit.world.scene.conn_rows[id]; !ok { retired+=1 } }
  for c in hit.world.scene.connections { if c.live && c.mortar && !original[c.id] { inherited+=1 } }
  fmt.printf("Mortar C2 direct blast retired_original_ids=%d new_inherited_ids=%d\n",retired,inherited)
  shared.mortar_measured_force_breaks=0; below_tick:=0; lowest:=mortar_deck_lowest(&hit.world.scene)
  for tick in 1..=180 {
   sandbox_tick(&hit,0,false); lowest=min(lowest,mortar_deck_lowest(&hit.world.scene))
   if below_tick==0 && mortar_deck_lowest(&hit.world.scene)<1 { below_tick=tick }
  }
  fmt.printf("Mortar C2 before_blast=%d after_blast=%d after_180=%d force_breaks=%d deck_below_y1_tick=%d min_deck_y=%.9f\n",before,after_blast,mortar_live_count(&hit.world.scene),shared.mortar_measured_force_breaks,below_tick,lowest)
  sandbox_destroy(&hit)
 }
}

run_mortar_seed_study :: proc() {
 low,high:=f32(1e30),f32(0)
 for seed in u8(1)..=8 {
  n:=mortar_calibrate(2.4,seed); low=min(low,n); high=max(high,n)
  fmt.printf("Mortar seed study seed=%d N1=%.9f\n",seed,n)
 }
 fmt.printf("Mortar seed study max_min=%.9f min=%.9f max=%.9f\n",high/low,low,high)
}
