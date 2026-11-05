package main

import "core:testing"
import "core:sync"
import "core:fmt"
import b2 "vendor:box2d"

mortar_test_place :: proc(g: ^Sandbox, material: Recipe,lo,hi: Vec2) {
 g.editor.palette=recipe_slot(material); g.editor.mortar=true; assert(editor_place(g,lo,hi))
}
mortar_test_count :: proc(s: ^Scene) -> int { n:=0; for c in s.connections { if c.live && c.mortar { n+=1 } }; return n }
mortar_check_joints :: proc(t: ^testing.T,s: ^Scene) {
 for c in s.connections { if !c.live || !c.mortar { continue }
  a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
  if b2.Body_GetType(a.body)==.staticBody && b2.Body_GetType(b.body)==.staticBody { testing.expect(t,c.joint==b2.nullJointId); continue }
  valid:=c.joint!=b2.nullJointId && b2.Joint_IsValid(c.joint); testing.expect(t,valid)
  if valid { testing.expect(t,b2.Joint_GetBodyA(c.joint)==a.body && b2.Joint_GetBodyB(c.joint)==b.body) }
 }
}
@(test)
mortar_build_and_blast :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 mortar_test_place(&g,.Stone,{0,0},{1,1}); mortar_test_place(&g,.Stone,{1,0},{2,1}); sandbox_toggle_editor(&g)
 s:=&g.world.scene
 ids:[2]u64
 for sub in s.subdivisions { if sub.rest_center.y>0 { if sub.rest_center.x<1 { ids[0]=sub.id } else { ids[1]=sub.id } } }
 owners:=[2]u64{s.subdivisions[s.sub_rows[ids[0]]].owner,s.subdivisions[s.sub_rows[ids[1]]].owner}
 testing.expect(t,owners[0]!=owners[1])
 facing,floor:=0,0
 for c in s.connections { if c.mortar { if c.a==ids[0] && c.b==ids[1] { facing+=1 } else { floor+=1 } } }
 expected_floor:=0
 for id in ids { for sub in s.subdivisions { if sub.rest_center.y<0 { length,_:=shared_boundary(s.subdivisions[s.sub_rows[id]].outline,sub.outline); if length>0 { expected_floor+=1 } } } }
 testing.expect(t,facing==1 && floor==expected_floor && mortar_test_count(s)==1+expected_floor)
 expect_valid(t,s); mortar_check_joints(t,s)
 max_cell_load:=f32(0)
 for id in ids { sub:=s.subdivisions[s.sub_rows[id]]; max_cell_load=max(max_cell_load,blast_load(vlen(vsub(sub.pose.position,{1,3})),5)) }
 seam:=s.connections[s.conn_rows[s.connection_pairs[pair_key(ids[0],ids[1])]]]
 seam_load:=blast_load(vlen(vsub(connection_sample(s,seam),{1,3})),5)
 testing.expect(t,max_cell_load<35 && seam_load>=20)
 blast_pass(s,Blast{position={1,3},radius=5})
 _,remaining:=s.connection_pairs[pair_key(ids[0],ids[1])]; testing.expect(t,!remaining)
 for id,i in ids { testing.expect(t,is_live_subdivision(s,id) && s.subdivisions[s.sub_rows[id]].owner==owners[i]) }
 fmt.printf("Mortar A1/A2 facing=%d floor=%d expected_floor=%d seam_load=%g max_cell_load=%g\n",facing,floor,expected_floor,seam_load,max_cell_load)
 expect_valid(t,s)
}
@(test)
mortar_reattach_snapshot_layout :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 mortar_test_place(&g,.Stone,{-0.4,0},{0.8,1});
 mortar_test_place(&g,.Wood,{0,1},{4,1.4}); sandbox_toggle_editor(&g)
 s:=&g.world.scene; initial:=mortar_test_count(s); testing.expect(t,initial>0)
 beam_ids:[dynamic]u64; defer delete(beam_ids)
 mortared:=make(map[u64]bool); defer delete(mortared)
 held_links:=make(map[u64]bool); defer delete(held_links)
 for sub in s.subdivisions { if s.materials[sub.material].name=="wood" { append(&beam_ids,sub.id) } }; sort_ids(beam_ids[:])
 b0:=s.subdivisions[s.sub_rows[beam_ids[0]]].body
 for c in s.connections { if !c.live || !c.mortar { continue }
  a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
  if s.materials[a.material].name=="wood" && s.materials[b.material].name=="stone" && b.rest_center.y>=0 { mortared[a.id]=true; held_links[c.id]=true }
  if s.materials[b.material].name=="wood" && s.materials[a.material].name=="stone" && a.rest_center.y>=0 { mortared[b.id]=true; held_links[c.id]=true }
 }
 testing.expect(t,len(mortared)>0)
 failures:=Failures{}; defer free_failures(&failures)
 // Isolate the mortared cell(s), preserving their mortar and all geometry.
 for c in s.connections {
  if !c.live || c.mortar { continue }
  a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
  if s.materials[a.material].name=="wood" && s.materials[b.material].name=="wood" && mortared[c.a]!=mortared[c.b] { append(&failures.connections,c.id) }
 }
 sort_ids(failures.connections[:])
 initial_heights:=make(map[u64]f32); defer delete(initial_heights)
 for id in mortared { initial_heights[id]=s.subdivisions[s.sub_rows[id]].pose.position.y }
 apply_failures(s,failures); physics_sync_structure(s)
 owners:=make(map[u64]bool); defer delete(owners)
 for id in beam_ids { if is_live_subdivision(s,id) { owners[s.subdivisions[s.sub_rows[id]].owner]=true } }
 retained:=0
 for id in mortared { if is_live_subdivision(s,id) { retained+=1 } }
 fmt.printf("Mortar revised A3 pieces=%d mortared_cells_retained=%d/%d broken_bonds=%d\n",len(owners),retained,len(mortared),len(failures.connections))
 testing.expect(t,len(owners)>=2 && retained==len(mortared),"Bond cut must isolate the supported part without deleting mortared cells")
 if len(owners)<2 || retained!=len(mortared) { return }
 for id in mortared { testing.expect(t,s.subdivisions[s.sub_rows[id]].body!=b0) }
 mortar_check_joints(t,s); expect_valid(t,s)
 max_drop:=f32(0)
 for _ in 0..<60 {
  sandbox_tick(&g,0,false)
  for id in mortared { if is_live_subdivision(s,id) { max_drop=max(max_drop,initial_heights[id]-s.subdivisions[s.sub_rows[id]].pose.position.y) } else { testing.expect(t,false,"Mortared cell disappeared") } }
 }
 held_count:=0
 for id in held_links { if row,exists:=s.conn_rows[id]; exists && s.connections[row].live { held_count+=1 } }
 testing.expect(t,held_count>0,"A re-created support weld must still hold the beam after 60 ticks")
 fmt.printf("Mortar A3 re-created support welds surviving60=%d/%d\n",held_count,len(held_links))
 mortar_check_joints(t,s); expect_valid(t,s)
 testing.expect(t,max_drop<=0.1); fmt.printf("Mortar A3 held_max_drop=%.9f\n",max_drop)
 for &c in s.connections { if c.mortar { c.overload_ticks=2; break } }
 bytes,ok:=encode_world_snapshot(&g.world); defer delete(bytes); testing.expect(t,ok)
 restored,loaded:=decode_world_snapshot(bytes); testing.expect(t,loaded)
 if loaded {
  defer { scene_destroy(&restored.scene); delete(restored.bombs) }
  again,encoded:=encode_world_snapshot(&restored); defer delete(again)
  testing.expect(t,encoded && string(bytes)==string(again)); mortar_check_joints(t,&restored.scene)
 }
 data,encoded:=encode_layout(&g.layout,42); defer delete(data); testing.expect(t,encoded)
 layout,seed,decoded,problem:=decode_layout(data); defer destroy_layout(&layout); testing.expect(t,decoded,problem)
 testing.expect(t,seed==42 && len(layout.objects)==2 && layout.objects[0].mortar && layout.objects[1].mortar)
 old,_,oldok,_:=decode_layout(transmute([]byte)PRESET_LAYOUTS[0]); defer destroy_layout(&old)
 testing.expect(t,oldok); for object in old.objects { testing.expect(t,!object.mortar) }
 fmt.printf("Mortar A3/A4/A5 initial=%d surviving=%d new_wood_owners=%d snapshot_equal=%v\n",initial,mortar_test_count(s),len(owners),loaded)
}
@(test)
mortar_shock_does_not_cross_objects :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 mortar_test_place(&g,.Glass,{0,0},{3,2.5}); mortar_test_place(&g,.Glass,{3,0},{6,2.5}); sandbox_toggle_editor(&g)
 right:=make(map[u64]bool); defer delete(right)
 for sub in g.world.scene.subdivisions { if sub.rest_center.x>3 && sub.rest_center.y>0 { right[sub.id]=true } }
 testing.expect(t,mortar_test_count(&g.world.scene)>0)
 blast_pass(&g.world.scene,Blast{position={-0.6,1.25},radius=3})
 survived:=0; for id in right { if is_live_subdivision(&g.world.scene,id) { survived+=1 } }
 testing.expect(t,survived==len(right)); expect_valid(t,&g.world.scene)
 fmt.printf("Mortar A6 pane_B=%d->%d\n",len(right),survived)
}
@(test)
mortar_object_ranges_presets :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 for data,i in PRESET_LAYOUTS {
  g:=sandbox_editor_create()
  layout,seed,ok,_:=decode_layout(transmute([]byte)data); testing.expect(t,ok)
  destroy_layout(&g.layout); g.layout=layout; g.world.settings.seed=seed; g.editor.editing=false
  scene_destroy(&g.world.scene); g.world.scene=new_scene(0.1)
  material:=add_material(&g.world.scene,editor_material(.Stone))
  objects:[dynamic]Built_Object; editor_build_objects(&g,&objects)
  ground:=sandbox_add_ground(&g.world.scene,material,seed)
  append(&objects,ground)
  for obj in objects {
   cells:=object_cells(&g.world.scene,obj); testing.expect(t,len(cells)>0)
   for id in cells { owner:=g.world.scene.subdivisions[g.world.scene.sub_rows[id]].owner; row,exists:=g.world.scene.piece_rows[owner]; testing.expect(t,exists && g.world.scene.pieces[row].live) }
   delete(cells)
  }
  fmt.printf("Mortar ranges preset=%d objects_including_floor=%d valid\n",i+1,len(objects))
  delete(objects); sandbox_destroy(&g)
 }
}


@(test)
mortar_force_calibration_and_cantilevers :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 n1,n2:=mortar_calibrate(2.4),mortar_calibrate(4.4)
 testing.expect(t,n2>2*n1)
 ends:=[2]f32{2.4,4.4}; for end_x,index in ends {
  g:=mortar_cantilever(end_x)
  initial:=mortar_test_count(&g.world.scene); first_break,below_tick:=0,0; broken:=0
  lowest:=f32(1e30); ticks:=600; if index==1 { ticks=240 }
  for tick in 1..=ticks {
   sandbox_tick(&g,0,false)
   n:=mortar_test_count(&g.world.scene)
   if n<initial && first_break==0 { first_break=tick }; broken=max(broken,initial-n)
   lowest=f32(1e30)
   for sub in g.world.scene.subdivisions { if g.world.scene.materials[sub.material].name=="wood" { lowest=min(lowest,sub.pose.position.y) } }
   if lowest<1 && below_tick==0 { below_tick=tick }
  }
  fmt.printf("Mortar B beam_end=%.1f initial=%d broken=%d first_break=%d below_y1_tick=%d final_lowest=%.9f\n",end_x,initial,broken,first_break,below_tick,lowest)
  if index==0 { testing.expect(t,broken==0) } else { testing.expect(t,first_break>0 && first_break<=120 && below_tick>0 && below_tick<=240) }
  expect_valid(t,&g.world.scene); sandbox_destroy(&g)
 }
}


@(test)
mortar_bridge_holds_600_ticks :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=mortar_bridge_yard(); defer sandbox_destroy(&g)
 regions,links,pieces:=counts_runtime(&g.world.scene); mortar:=mortar_live_count(&g.world.scene)
 bad_ticks:=0
 for _ in 0..<600 {
  sandbox_tick(&g,0,false)
  r,l,p:=counts_runtime(&g.world.scene)
  if r!=regions || l!=links || p!=pieces || mortar_live_count(&g.world.scene)!=mortar { bad_ticks+=1 }
 }
 testing.expect(t,bad_ticks==0 && mortar>0); expect_valid(t,&g.world.scene); mortar_check_joints(t,&g.world.scene)
 fmt.printf("Mortar C1 idle: regions=%d links=%d pieces=%d mortar=%d changed_count_ticks=%d\n",regions,links,pieces,mortar,bad_ticks)
}
