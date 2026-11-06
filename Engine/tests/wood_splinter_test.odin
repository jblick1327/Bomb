package main
import "core:testing"
import "core:fmt"
import "core:sync"
import "core:strings"

@(test)
wood_plank_has_long_thin_creation_cells :: proc(t: ^testing.T) {
 // Seed 47 keeps the original >=1 length check after the thinner default.
 s:=wood_plank_scene(47); defer scene_destroy(&s)
 short,thick,oversize,_,_:=wood_plank_checks(&s)
 fmt.printf("Wood check 1: cells=%d short=%d thick=%d oversize=%d\n",len(s.subdivisions),short,thick,oversize)
 testing.expect(t,short==0 && thick==0 && oversize==0)
}
@(test)
wood_plank_has_multiple_jagged_seam_vertices :: proc(t: ^testing.T) {
 s:=wood_plank_scene(); defer scene_destroy(&s)
 _,_,_,seams,bad:=wood_plank_checks(&s)
 fmt.printf("Wood check 3: along-grain seams=%d with_fewer_than_two_displaced_vertices=%d\n",seams,bad)
 testing.expect(t,seams>0 && bad==0)
}
@(test)
wood_thins_before_cross_cutting_and_finishes_short_thin_cells :: proc(t: ^testing.T) {
 recipe:=editor_material(.Wood); recipe.generation_count=2
 points:=[4]Vec2{{0,0},{8,0},{8,0.3},{0,0.3}}
 children:=generate_children(Polygon{points=points[:]},recipe,42,0.1)
 cross_cuts:=0
 for child in children { length,_:=wood_study_dimensions(child); if length<7.99 { cross_cuts+=1 }; delete(child.points) }; delete(children)
 small:=[4]Vec2{{0,0},{0.8,0},{0.8,0.15},{0,0.15}}
 finished:=generate_children(Polygon{points=small[:]},recipe,42,0.1)
 fmt.printf("Wood check 5: premature_cross_cuts=%d finished_cell_children=%d\n",cross_cuts,len(finished))
 testing.expect(t,cross_cuts==0 && len(finished)==0)
 for child in finished { delete(child.points) }; delete(finished)
}
@(test)
wood_long_bond_blast_reaches_nearest_boundary :: proc(t: ^testing.T) {
 s:=new_scene(0.1); defer scene_destroy(&s)
 m:=add_material(&s,editor_material(.Wood)); p:=add_piece(&s,m,42)
 ids:[2]u64
 for row in 0..<2 {
  y:=f32(row)*0.2; points:=[4]Vec2{{0,y},{6,y},{6,y+0.2},{0,y+0.2}}; poly:=Polygon{points=points[:]}
  ids[row]=add_subdivision(&s,p,poly,Pose{position=centroid(poly)})
 }
 link:=add_connection(&s,ids[0],ids[1]); f:=evaluate_blast(&s,Blast{{-0.1,0.2},3}); defer free_failures(&f)
 fmt.printf("Wood bond check: peeled=%d expected=1\n",int(contains_id(f.connections[:],link)))
 testing.expect(t,contains_id(f.connections[:],link))
}

@(test)
wood_derived_bond_segments_rebuild_exactly_from_snapshot :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 testing.expect(t,editor_place(&g,{0,0},{6,0.8})); sandbox_toggle_editor(&g)
 data,ok:=encode_world_snapshot(&g.world); defer delete(data); testing.expect(t,ok && !strings.contains(string(data),"rest_segments"))
 copy,decoded:=decode_world_snapshot(data); testing.expect(t,decoded)
 defer { scene_destroy(&copy.scene); delete(copy.bombs) }
 mismatch,jagged,points_checked:=0,0,0
 for c in g.world.scene.connections {
  other:=copy.scene.connections[copy.scene.conn_rows[c.id]]
  if len(c.rest_segments)!=len(other.rest_segments) { mismatch+=1; continue }
  for segment,i in c.rest_segments {
   if transmute([4]u32)segment!=transmute([4]u32)other.rest_segments[i] { mismatch+=1 }
  }
  a:=g.world.scene.subdivisions[g.world.scene.sub_rows[c.a]]
  if g.world.scene.materials[a.material].aspect_ratio>=1 || len(c.rest_segments)<3 { continue }
  jagged+=1
  // Rotate/translate a copy of the two cell poses; query every actual seam
  // vertex. A midpoint or a straight envelope cannot return these points.
  pose_a:=a.pose; row_b:=g.world.scene.sub_rows[c.b]; pose_b:=g.world.scene.subdivisions[row_b].pose
  angle:=f32(0.37); offset:=Vec2{2.7,-1.3}
  endpoints:=[2]u64{c.a,c.b}
  for id in endpoints {
   sub:=&g.world.scene.subdivisions[g.world.scene.sub_rows[id]]
   sub.pose.angle=angle; sub.pose.position=vadd(offset,vrotate(sub.rest_center,angle))
  }
  for segment in c.rest_segments {
   p:=vadd(offset,vrotate(segment.a,angle)); q:=connection_blast_sample(&g.world.scene,c,p)
   testing.expect(t,vlen(vsub(p,q))<1e-5); points_checked+=1
  }
  g.world.scene.subdivisions[g.world.scene.sub_rows[c.a]].pose=pose_a; g.world.scene.subdivisions[row_b].pose=pose_b
 }
 fmt.printf("Wood derived bonds: mismatches=%d jagged_connections=%d posed_vertices_checked=%d\n",mismatch,jagged,points_checked)
 testing.expect(t,mismatch==0 && jagged>0 && points_checked>0)
}
