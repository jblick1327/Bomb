package main

import "core:testing"
import "core:sync"
import "core:fmt"
import "core:strings"
import "core:slice"

// A mortared footing (x -1.6..2, y 0..0.4), post (x 0..0.4, y 0..2) and beam on top (y 2..2.4, x 0..end_x), all of
// one material: "wood" or "stone" (built-in) or "steel" (OD-2 custom). The footing's 3.6-long seam to the stone ground
// keeps that seam (capped at the ground's toughness 1) from failing before the material-to-material seams above it.
glue_material_cantilever :: proc(material: string,end_x: f32,seed: u8 = 42) -> Sandbox {
 g:=sandbox_editor_create()
 g.world.settings.seed=seed
 slot:=recipe_slot(.Wood); if material=="stone" { slot=recipe_slot(.Stone) }
 if material=="steel" { m:=steel_material(); m.name=strings.clone(m.name); append(&g.layout.materials,m); slot=Slot(4) }
 g.editor.mortar=true; g.editor.palette=slot
 assert(editor_place(&g,{-1.6,0},{2,0.4}))
 assert(editor_place(&g,{0,0.4},{0.4,2}))
 assert(editor_place(&g,{0,2},{end_x,2.4}))
 sandbox_toggle_editor(&g); return g
}

// Material of the live mortar cells, so the fixture is checked as well as built.
glue_material_live_glue_toughness :: proc(s: ^Scene) -> f32 {
 t:=f32(0)
 for c in s.connections { if c.live && c.mortar { a:=s.subdivisions[s.sub_rows[c.a]]; t=max(t,material_glue_toughness(s.materials[a.material])) } }
 return t
}

@(test)
glue_material_toughness_per_material :: proc(t: ^testing.T) {
 for recipe in Recipe { testing.expect(t,editor_material(recipe).glue_toughness==1) }
 steel:=steel_material()
 testing.expect(t,custom_problem(steel)=="")
 testing.expect(t,steel.base==.Stone && steel.toughness==1.25 && steel.blast_resistance==4)
 layout:Layout; append(&layout.materials,steel); defer delete(layout.materials)
 m:=layout_material(&layout,Slot(4))
 stone:=editor_material(.Stone)
 testing.expect(t,m.glue_toughness==1.25 && m.connection_strength==stone.connection_strength*1.25 && m.subdivision_strength==43.75)
 // Replicas do not carry the field; zero reads as 1.
 testing.expect(t,material_glue_toughness(Material{})==1)
}

// Over ticks 60..180 with breaking off: peak and lowest per-tick load ratio of the most loaded material-to-material seam
// (seams above y=0.2), its toughness, and the peak ratio of the footing-to-ground seam.
glue_material_beam_ratio :: proc(material: string,end_x: f32) -> (peak,low,toughness,ground: f32) {
 g:=glue_material_cantilever(material,end_x); defer sandbox_destroy(&g)
 s:=&g.world.scene; s.physics.mortar_breaking=false
 low=1e30
 for tick in 1..=180 {
  sandbox_tick(&g,0,false); if tick<60 { continue }
  seams:=mortar_seams(s)
  worst:=f32(0)
  for seam in seams {
   r:=mortar_seam_ratio(s,seam)
   if seam.center.y<=0.2 { ground=max(ground,r); continue }
   if r>worst { worst=r; toughness=mortar_seam_toughness(s,seam) }
  }
  peak=max(peak,worst); low=min(low,worst)
  mortar_free_seams(seams)
 }
 return
}

// Fixture, chosen by probing end_x 2.8..4.4 (seed 42): at 3.6 the most loaded stone seam sat steady at r 1.155 and
// the steel one at 0.924; the footing-to-ground seam stays near r 0.05. Wood seams are far over capacity at every length.
// G-N10b (OD-10, bearing not charged): re-probed 3.6..4.8 (evidence/G-N10b/README.md). At 3.6 stone dropped from r 1.091
// (5610dc2) to 0.985, below capacity; 3.9 puts it back over (stone 1.142 steady, steel 0.914). The checks are unchanged.
GLUE_MATERIAL_END_X :: f32(3.9)

// Same base and geometry, so the same forces: the steel seam's load ratio is the stone one divided by 1.25.
@(test)
glue_material_steel_capacity_is_stone_times_toughness :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 stone,stone_low,stone_t,_:=glue_material_beam_ratio("stone",GLUE_MATERIAL_END_X)
 steel,steel_low,steel_t,_:=glue_material_beam_ratio("steel",GLUE_MATERIAL_END_X)
 fmt.printf("G-N1 beam seam end_x=%.1f r stone=%.6f..%.6f steel=%.6f..%.6f\n",GLUE_MATERIAL_END_X,stone_low,stone,steel_low,steel)
 testing.expect(t,stone_t==1 && steel_t==1.25)
 testing.expect(t,stone_low>1 && steel<1,"fixture must overload stone steadily and keep steel under capacity")
 testing.expectf(t,abs(stone/steel-1.25)<1e-4 && abs(stone_low/steel_low-1.25)<1e-4,"stone/steel ratio %v %v",stone/steel,stone_low/steel_low)
}

// Under the same self-weight the wood and stone post-to-beam seams fail and the steel one holds.
// Only the material-to-material links (above y=0.2) are tracked: the footing-to-ground seam is capped by the stone ground for all three.
@(test)
glue_material_steel_seam_outlasts_wood_under_load :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 survive :: proc(material: string) -> (first_break: int,live_after: int,initial: int) {
  g:=glue_material_cantilever(material,GLUE_MATERIAL_END_X); defer sandbox_destroy(&g)
  s:=&g.world.scene
  beam:[dynamic]u64; defer delete(beam)
  for c in s.connections { if c.live && c.mortar && connection_sample(s,c).y>0.2 { append(&beam,c.id) } }
  live :: proc(s: ^Scene,ids: []u64) -> int { n:=0; for id in ids { row,ok:=s.conn_rows[id]; if ok && s.connections[row].live { n+=1 } }; return n }
  initial=len(beam)
  for tick in 1..=600 {
   sandbox_tick(&g,0,false)
   if first_break==0 && live(s,beam[:])<initial { first_break=tick }
  }
  return first_break,live(s,beam[:]),initial
 }
 wood_break,wood_live,wood_initial:=survive("wood")
 stone_break,stone_live,stone_initial:=survive("stone")
 steel_break,steel_live,steel_initial:=survive("steel")
 fmt.printf("G-N1 cantilever end_x=%.1f 600 ticks, material-to-material links: wood %d->%d first break tick %d; stone %d->%d tick %d; steel %d->%d tick %d\n",GLUE_MATERIAL_END_X,wood_initial,wood_live,wood_break,stone_initial,stone_live,stone_break,steel_initial,steel_live,steel_break)
 testing.expect(t,wood_initial>0 && stone_initial>0 && steel_initial>0)
 testing.expect(t,wood_break>0 && wood_live<wood_initial,"wood seam must fail under load")
 testing.expect(t,stone_break>0 && stone_live<stone_initial,"stone seam must fail under load")
 testing.expect(t,steel_break==0 && steel_live==steel_initial,"steel seam must hold under the same load")
}

// Blast failure still uses min(connection_strength) and never the glue toughness.
@(test)
glue_material_blast_unchanged :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 run :: proc(force_one: bool) -> (subs,links,discards: [dynamic]u64,live_cells,live_links: int) {
  g:=glue_material_cantilever("steel",2.4); defer sandbox_destroy(&g)
  s:=&g.world.scene; s.physics.mortar_breaking=false
  if force_one { for &m in s.materials { m.glue_toughness=1 } }
  for radius in ([]f32{0.8,1.5,2.5,5}) {
   f:=evaluate_blast(s,Blast{position={0.2,2.6},radius=radius})
   append(&subs,..f.subdivisions[:]); append(&links,..f.connections[:]); append(&discards,..f.discard_subdivisions[:])
   free_failures(&f)
  }
  blast_pass(s,Blast{position={0.2,2.6},radius=2.5})
  for c in s.subdivisions { if c.live { live_cells+=1 } }
  for c in s.connections { if c.live { live_links+=1 } }
  return
 }
 a_subs,a_links,a_disc,a_cells,a_live:=run(false); defer { delete(a_subs); delete(a_links); delete(a_disc) }
 b_subs,b_links,b_disc,b_cells,b_live:=run(true); defer { delete(b_subs); delete(b_links); delete(b_disc) }
 fmt.printf("G-N1 blast on steel: failed cells %d links %d; after blast_pass live cells %d links %d\n",len(a_subs),len(a_links),a_cells,a_live)
 testing.expect(t,len(a_links)>0,"fixture must break some glue by blast")
 testing.expect(t,slice.equal(a_subs[:],b_subs[:]) && slice.equal(a_links[:],b_links[:]) && slice.equal(a_disc[:],b_disc[:]))
 testing.expect(t,a_cells==b_cells && a_live==b_live)
}

// World snapshots keep the steel glue toughness; built-in materials write nothing new.
@(test)
glue_material_snapshot_keeps_toughness :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=glue_material_cantilever("steel",2.4); defer sandbox_destroy(&g)
 bytes,ok:=encode_world_snapshot(&g.world); defer delete(bytes); testing.expect(t,ok)
 testing.expect(t,strings.count(string(bytes),"\"glue_toughness\": 1.25")==1)
 restored,loaded:=decode_world_snapshot(bytes); testing.expect(t,loaded)
 if loaded {
  defer { scene_destroy(&restored.scene); delete(restored.bombs) }
  testing.expect(t,glue_material_live_glue_toughness(&restored.scene)==1.25)
  again,encoded:=encode_world_snapshot(&restored); defer delete(again)
  testing.expect(t,encoded && string(again)==string(bytes))
 }
 bad,_:=strings.replace(string(bytes),"\"glue_toughness\": 1.25","\"glue_toughness\": 0",1); defer delete(bad)
 _,accepted:=decode_world_snapshot(transmute([]byte)bad); testing.expect(t,!accepted)
 w:=glue_material_cantilever("wood",2.4); defer sandbox_destroy(&w)
 plain,pok:=encode_world_snapshot(&w.world); defer delete(plain)
 testing.expect(t,pok && !strings.contains(string(plain),"glue_toughness"))
}


