package main
import "core:testing"
import "core:sync"
import "core:math"
import "core:fmt"
import b2 "vendor:box2d"

@(test)
creation_partition_preserves_area_mass_contexts_and_length :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 for choice in Recipe {
  g:=sandbox_editor_create(); g.editor.palette=recipe_slot(choice)
  testing.expect(t,editor_place(&g,{0,0},{2.4,1.2})); sandbox_toggle_editor(&g)
  for piece in g.world.scene.pieces {
   parts:=[dynamic]Polygon{}
   sum:=f32(0)
   for id in piece.subdivisions {
    sub:=g.world.scene.subdivisions[g.world.scene.sub_rows[id]]; sum+=polygon_area(sub.outline); append(&parts,sub.outline)
    grained:=g.world.scene.materials[sub.material].aspect_ratio<1
    oversized:=longest_dimension(sub.outline)>PRESPLIT_SIZE+0.00001
    if grained { oversized,_=grain_cut_kind(sub.outline,g.world.scene.minimum_width,true,g.world.scene.materials[sub.material].strip_thickness) }
    if oversized {
     children:=generate_children(sub.outline,g.world.scene.materials[sub.material],sub.seed,g.world.scene.minimum_width,true)
     testing.expectf(t,choice==.Wood && sub.material!=0 && len(children)==0,"%v region %d exceeds pre-split size without being grain-limited",choice,id)
     for child in children { delete(child.points) }; delete(children)
    }
    if sub.material==0 { testing.expect(t,b2.Body_GetType(sub.body)==.staticBody) }
   }
   if piece.material!=0 || choice==.Glass {
    bounds:=[4]Vec2{{0,0},{2.4,0},{2.4,1.2},{0,1.2}}
    if piece.material==0 { bounds={{-8,-3},{9,-3},{9,0},{-8,0}} }
    expect_generation_partition(t,Polygon{points=bounds[:]},parts[:])
   }
   delete(parts)
   testing.expect(t,math.abs(sum-piece.mass)<0.0001)
   if piece.material==0 { testing.expect(t,math.abs(sum-51)<0.001) }
   else { testing.expect(t,math.abs(sum-2.88)<0.001) }
  }
  render_cache_prepass(&g.world.scene,&g.render_caches)
  bytes,ok:=encode_snapshot(&g.world.scene); testing.expect(t,ok)
  copy,decoded:=decode_snapshot(bytes); testing.expect(t,decoded)
  for piece in copy.pieces { testing.expect(t,close(piece.mass,g.world.scene.pieces[g.world.scene.piece_rows[piece.id]].mass)) }
  scene_destroy(&copy); delete(bytes); expect_valid(t,&g.world.scene); sandbox_destroy(&g)
 }
 testing.expect(t,make_material(name="omitted scale").impact_scale==1)
}
@(test)
strips_lengthen_then_cross_cut_and_square_recipe_is_unchanged :: proc(t: ^testing.T) {
 shapes:=[4]Vec2{{2,1},{1,2},{8,0.5},{8,0.15}}
 recipe:=make_material(generation_count=2,strip_thickness=0.3,aspect_ratio=0.2)
 for size,i in shapes {
  points:=[4]Vec2{{0,0},{size.x,0},{size.x,size.y},{0,size.y}}; parent:=Polygon{points=points[:]}
  children:=generate_children(parent,recipe,42,0.1)
  expect_generation_partition(t,parent,children[:])
  // The outer straight sides distinguish the requested axis despite seam jitter.
  for child in children {
   if i==0 { testing.expect(t,longest_dimension(child)>=1.99) }
   if i==1 { testing.expect(t,longest_dimension(child)>=1.99) }
   if i==2 { testing.expect(t,longest_dimension(child)>=7.99,"Thin before cross-cutting even beyond the old 5:1 limit") }
   if i==3 { testing.expect(t,longest_dimension(child)<5,"A long strip too thin to halve gets a slanted cross-cut") }
   delete(child.points)
  }
  delete(children)
 }
}
// One ordinary flat drop. Counts damage, never adds an extra deliberate impact.
presplit_drop :: proc(choice: Recipe,size,height: f32) -> (crack,separate: bool) {
 g:=sandbox_editor_create(); defer sandbox_destroy(&g); g.editor.palette=recipe_slot(choice)
 assert(editor_place(&g,{0,0},{2.4,1.2})); sandbox_toggle_editor(&g)
 s:=&g.world.scene
 if size<PRESPLIT_SIZE { presplit_piece(s,s.subdivisions[0].owner,size); physics_sync_structure(s) }
 moved:=make(map[b2.BodyId]bool); defer delete(moved)
 for sub in s.subdivisions {
  if sub.material==0 || moved[sub.body] { continue }
  moved[sub.body]=true
  p:=b2.Body_GetPosition(sub.body); p.y+=height; b2.Body_SetTransform(sub.body,p,b2.MakeRot(0)); b2.Body_SetAwake(sub.body,true)
 }
 ticks:=int((math.sqrt(2*height/9.8)+1.5)*60)
 for _ in 0..<ticks {
  b2.World_Step(s.physics.world,1.0/60,PHYSICS_SUBSTEPS); physics_read_motion(s)
  f:=calculate_physics_loads(s,1.0/60)
  for id in f.subdivisions { if s.subdivisions[s.sub_rows[id]].material!=0 { crack=true } }
  apply_failures(s,f); free_failures(&f); physics_sync_structure(s)
  groups:=0; for p in s.pieces { if p.material!=0 { groups+=1 } }
  separate=groups>1
 }
 return
}
// Bracket measured cell-crack onset to 5 cm.
presplit_drop_threshold :: proc(choice: Recipe,size: f32) -> f32 {
 lo,hi:=f32(0),f32(0.1)
 for hi<=25.6 {
  c,_:=presplit_drop(choice,size,hi)
  found:=c
  if found { break }; lo=hi; hi*=2
 }
 if hi>25.6 { return math.inf_f32(1) }
 for hi-lo>0.05 {
  mid:=(lo+hi)*0.5; c,_:=presplit_drop(choice,size,mid)
  found:=c
  if found { hi=mid } else { lo=mid }
 }
 return hi
}
@(test)
physical_loads_use_connected_piece_mass_after_refinement :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=make_wall(42); defer scene_destroy(&s); physics_init(&s)
 owner:=s.pieces[0].id; id:=s.subdivisions[0].id
 before:=interaction_mass(&s,subdivision_body(&s,id)); testing.expect(t,close(before,3))
 def:=b2.DefaultBodyDef(); def.type=.dynamicBody; actor:=b2.CreateBody(s.physics.world,def)
 b2.Body_SetMassData(actor,b2.MassData{mass=2,rotationalInertia=1})
 before_load:=contact_damage_load(&s,subdivision_body(&s,id),actor,4,1)
 testing.expect(t,close(before_load,8))
 f:=failure_for(id); apply_failures(&s,f); free_failures(&f); physics_sync_structure(&s)
 for sub in s.subdivisions { testing.expect(t,close(interaction_mass(&s,sub.body),before)); testing.expect(t,close(contact_damage_load(&s,sub.body,actor,4,1),before_load)) }
 testing.expect(t,!(owner in s.piece_rows))
}

@(test)
presplit_cell_crack_onset_agrees_at_both_resolutions :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 choices:=[3]Recipe{.Glass,.Stone,.Wood}
 for choice in choices {
  coarse:=presplit_drop_threshold(choice,1); fine:=presplit_drop_threshold(choice,0.5)
  testing.expectf(t,math.abs(coarse-fine)<=0.2*coarse,"%v cell-crack heights %.4f / %.4f",choice,coarse,fine)
  fmt.printf("Pre-split %v: crack size1 %.4f / size0.5 %.4f\n",choice,coarse,fine)
 }
}
@(test)
impact_cracked_glass_separates :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 crack,separate:=presplit_drop(.Glass,1,0.8)
 testing.expect(t,crack && separate,"A pre-split pane must crack into multiple pieces above its impact threshold")
}

@(test)
impact_children_inherit_neighbours_without_sibling_bonds :: proc(t: ^testing.T) {
 s:=make_wall(42); defer scene_destroy(&s)
 parent:=s.subdivisions[0].id; neighbour:=s.subdivisions[1].id
 first_child:=s.next_id
 f:=failure_for(parent); f.impact=true
 apply_failures(&s,f); free_failures(&f)
 children,attachments:=0,0
 for sub in s.subdivisions { if sub.id>=first_child { children+=1 } }
 for c in s.connections {
  testing.expect(t,!(c.a>=first_child && c.b>=first_child),"Impact siblings must not be glued together")
  if c.a==neighbour && c.b>=first_child || c.b==neighbour && c.a>=first_child { attachments+=1 }
 }
 testing.expect(t,children>=2 && attachments>=1,"Children must retain surviving outside attachments")
 expect_valid(t,&s)
}
