package main

import "core:testing"
import "core:sync"
import "core:fmt"
import b2 "vendor:box2d"
import "core:math"
import "core:strings"

@(test)
glass_pane_blast_shock_crosses_width :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 // Prototype ranges are measurements to report, not tuning budgets. Require
 // an actual reduction from the recorded radius-3 baseline and the predicted
 // near-total radius-4 separation.
 limits:=[2]f32{0.91167849,0.05}
 radii:=[2]int{3,4}
 for radius,i in radii {
  g:=glass_pane_yard(f32(radius)); stats:=glass_study_stats(&g.world.scene,{-0.6,1.25})
  fmt.printf("Glass check 1 radius=%d pieces=%d largest_fraction=%.8f shard_medians=%v bands=%v\n",radius,stats.pieces,stats.largest_fraction,stats.medians,stats.band_counts)
  testing.expect(t,stats.pieces>1 && stats.largest_fraction<limits[i])
  sandbox_destroy(&g)
 }
}

glass_shock_chain :: proc() -> Scene {
 s:=new_scene(0.1); material:=add_material(&s,editor_material(.Glass)); piece:=add_piece(&s,material,42)
 previous:=u64(0)
 for i in 0..<5 {
  x:=f32(i); points:=[4]Vec2{{x,0},{x+1,0},{x+1,1},{x,1}}; p:=Polygon{points=points[:]}
  id:=add_subdivision(&s,piece,p,Pose{position=centroid(p)}); if previous!=0 { add_connection(&s,previous,id) }; previous=id
 }
 return s
}
@(test)
glass_shock_follows_bonds_with_exact_centroid_costs :: proc(t: ^testing.T) {
 s:=glass_shock_chain(); defer scene_destroy(&s)
 tx:=shock_begin_blast(&s,Blast{{-0.6,0.5},3}); defer shock_destroy(&tx)
 testing.expect(t,len(tx.sources)==1)
 shock_travel(&s,&tx,tx.sources[0])
 expected:=[5]f32{22,18,14,10,6}
 for sub,i in s.subdivisions { testing.expect(t,tx.cells[sub.id].reached && math.abs(tx.cells[sub.id].load-expected[i])<1e-5) }
 // The gap cannot be crossed geometrically: these are still cells of the
 // same original piece, with a disconnected live bond graph.
 s.connections[2].live=false
 disconnected:=shock_begin_blast(&s,Blast{{-0.6,0.5},3}); defer shock_destroy(&disconnected)
 shock_travel(&s,&disconnected,disconnected.sources[0])
 testing.expect(t,!disconnected.cells[s.subdivisions[3].id].reached && !disconnected.cells[s.subdivisions[4].id].reached)
 fmt.println("Glass Dijkstra: loads=22/18/14/10/6; disconnected far cells unreached")
}
@(test)
glass_shock_is_one_wave_and_inherits_load_without_impulse :: proc(t: ^testing.T) {
 s:=glass_shock_chain(); defer scene_destroy(&s)
 original:=[5]u64{}; for sub,i in s.subdivisions { original[i]=sub.id }
 tx:=shock_begin_blast(&s,Blast{{-0.6,0.5},3}); defer shock_destroy(&tx)
 first_child:=s.next_id+1; affected:=make(map[u64]bool); defer delete(affected)
 testing.expect(t,shock_apply(&s,&tx,&affected,false))
 // Only the two original cells at 22 and 18 exceed subdivision strength.
 testing.expect(t,!is_live_subdivision(&s,original[0]) && !is_live_subdivision(&s,original[1]))
 for id in original[2:] { testing.expect(t,is_live_subdivision(&s,id)) }
 children:=0
 for sub in s.subdivisions {
  if !sub.live || sub.id<first_child { continue }; children+=1
  cell:=tx.cells[sub.id]
  testing.expect(t,cell.reached && (cell.load==22 || cell.load==18))
  testing.expect(t,sub.pose.velocity==Vec2{} && sub.pose.angular_velocity==0)
 }
 for c in s.connections { if c.live { testing.expect(t,c.a<first_child && c.b<first_child,"Shock children must not retain loaded bonds or sibling glue") } }
 testing.expect(t,children==20,"The two known squares produce ten first-generation children each")
 rebuild_affected_pieces(&s,affected); commit_structure(&s); expect_valid(t,&s)
 fmt.printf("Glass one-wave check: children=%d; inherited loads=22/18; extra velocities=0\n",children)
}
@(test)
glass_shock_material_roundtrips_and_legacy_defaults_off :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 for &material in g.world.scene.materials { if material.name=="glass" { material.shock_loss=0.031250003 } }
 g.world.scene.materials[0].shock_loss=transmute(f32)u32(0x80000000)
 data,ok:=encode_world_snapshot(&g.world); defer delete(data); testing.expect(t,ok && strings.contains(string(data),"shock_loss"))
 copy,decoded:=decode_world_snapshot(data); testing.expect(t,decoded); defer { scene_destroy(&copy.scene); delete(copy.bombs) }
 for material,i in g.world.scene.materials { testing.expect(t,transmute(u32)material.shock_loss==transmute(u32)copy.scene.materials[i].shock_loss) }
 again,encoded:=encode_world_snapshot(&copy); defer delete(again); testing.expect(t,encoded && string(data)==string(again))
 legacy,loaded:=decode_world_snapshot(transmute([]byte)#load("../evidence/world-v3/before-v2-ticked.json")); testing.expect(t,loaded)
 defer { scene_destroy(&legacy.scene); delete(legacy.bombs) }
 for material in legacy.scene.materials { testing.expect(t,material.shock_loss==0) }
 wire:=read_world_state(&g.world); defer release_world_state(&wire)
 wire.scene.materials[0].shock_loss=f32(-1)
 invalid,encoded_invalid:=exact_json_encode(wire); defer delete(invalid); testing.expect(t,encoded_invalid)
 rejected,accepted:=decode_world_snapshot(invalid); testing.expect(t,!accepted)
 if accepted { scene_destroy(&rejected.scene); delete(rejected.bombs) }
 fmt.println("Glass material: exact shock_loss bits/re-encoding; legacy=0; negative rejected")
}
@(test)
glass_drop_shock_reduces_largest_piece :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g,tick:=glass_impact_yard(); defer sandbox_destroy(&g)
 stats:=glass_study_stats(&g.world.scene,{0,0})
 fmt.printf("Glass check 2 tick=%d pieces=%d largest_fraction=%.8f\n",tick,stats.pieces,stats.largest_fraction)
 // Measured on the original build at the first damaging impact batch.
 testing.expect(t,tick>0 && stats.pieces>8 && stats.largest_fraction<0.88401365)
}
when ODIN_TEST {
@(thread_local) glass_commit_test_calls: int
@(test)
glass_blast_and_impact_use_one_structural_commit :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g); g.editor.palette=recipe_slot(.Glass)
 testing.expect(t,editor_place(&g,{0,0},{5,2.5})); sandbox_toggle_editor(&g)
 for _ in 0..<120 { sandbox_tick(&g,0,false) }
 before:=glass_commit_test_calls; sandbox_fixture_radius(&g,3); sandbox_explode(&g,{-0.6,1.25})
 blast_commits:=glass_commit_test_calls-before
 drop:=sandbox_editor_create(); defer sandbox_destroy(&drop); drop.editor.palette=recipe_slot(.Glass)
 testing.expect(t,editor_place(&drop,{0,0},{2,1})); sandbox_toggle_editor(&drop)
 for p in drop.world.scene.pieces {
  if drop.world.scene.materials[p.material].name!="glass" { continue }
  position:=b2.Body_GetPosition(p.body); position.y+=0.8; b2.Body_SetTransform(p.body,position,b2.MakeRot(0))
 }
 physics_read_motion(&drop.world.scene); revision:=drop.world.scene.revision; impact_commits:=0
 for _ in 0..<180 {
  before=glass_commit_test_calls; sandbox_tick(&drop,0,false)
  if drop.world.scene.revision!=revision { impact_commits=glass_commit_test_calls-before; break }
 }
 fmt.printf("Glass commit check: blast=%d impact_batch=%d\n",blast_commits,impact_commits)
 testing.expect(t,blast_commits==1 && impact_commits==1)
}
}
