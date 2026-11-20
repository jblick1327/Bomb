#+feature dynamic-literals
package main

import "core:math"
import "core:math/rand"
import "core:testing"

@(test)
reference_pose_frame_round_trip :: proc(t: ^testing.T) {
 random:=rand.create(734); gen:=rand.default_random_generator(&random)
 for _ in 0..<5000 {
  frame:=Pose{position={rand.float32_range(-30,30,gen),rand.float32_range(-30,30,gen)},angle=rand.float32_range(-20,20,gen)}
  ref_rest:=Vec2{rand.float32_range(-10,10,gen),rand.float32_range(-10,10,gen)}
  reference:=frame_to_reference(frame,ref_rest)
  back:=reference_to_frame(reference,ref_rest)
  testing.expect(t,vlen(vsub(back.position,frame.position))<1e-5 && back.angle==frame.angle)
  pt:=vadd(ref_rest,Vec2{0.2,-0.4})
  visible:=vadd(reference.position,vrotate(vsub(pt,ref_rest),reference.angle))
  testing.expect(t,vlen(vsub(visible,rigid_render_point(frame,pt)))<1e-5)
 }
}

@(test)
reference_rest_is_area_weighted_and_immutable_across_cell_changes :: proc(t: ^testing.T) {
 s:=new_scene(0.1); defer scene_destroy(&s)
 add_material(&s,editor_material(.Stone))
 owner:=add_piece(&s,0,42)
 a:=shape_polygon(Authored_Shape{lo={8,2},hi={9,3}}); defer delete(a.points)
 b:=shape_polygon(Authored_Shape{lo={9,2},hi={12,3}}); defer delete(b.points)
 ca:=add_subdivision(&s,owner,a,Pose{position=centroid(a)})
 cb:=add_subdivision(&s,owner,b,Pose{position=centroid(b)})
 srv:Repl_Server; defer repl_server_destroy(&srv)
 rep:Replica; replica_init(&rep); defer replica_destroy(&rep)
 base:=repl_server_update(&srv,&s,0); defer repl_output_destroy(&base)
 testing.expect(t,repl_apply_output(&rep,&base)=="")
 reference:=s.pieces[s.piece_rows[owner]].ref_rest
 testing.expect(t,vlen(vsub(reference,Vec2{10,2.5}))<1e-6)
 // Exercise the wire's same-id membership update, without a physics regroup
 // (regrouping deliberately creates new ids).
 s.subdivisions[s.sub_rows[ca]].live=false
 s.pieces[s.piece_rows[owner]].subdivisions[0]=cb
 resize(&s.pieces[s.piece_rows[owner]].subdivisions,1)
 s.structure_revision+=1
 commit_structure(&s); scene_finish_references(&s)
 delta:=repl_server_update(&srv,&s,1); defer repl_output_destroy(&delta)
 testing.expect(t,delta.delta_pieces_changed==1 && delta.delta_pieces_added==0)
 testing.expect(t,repl_apply_output(&rep,&delta)=="" && scenes_equal(&s,&rep.scene))
 testing.expect(t,s.pieces[s.piece_rows[owner]].ref_rest==reference && rep.scene.pieces[rep.scene.piece_rows[owner]].ref_rest==reference)
 // A late join must retain the original reference too, rather than deriving it
 // from the remaining cell (whose centroid is 10.5,2.5).
 join:=repl_server_baseline(&srv,&s,2); defer repl_output_destroy(&join)
 other:Replica; replica_init(&other); defer replica_destroy(&other)
 testing.expect(t,repl_apply_output(&other,&join)=="" && scenes_equal(&s,&other.scene))
 testing.expect(t,other.scene.pieces[other.scene.piece_rows[owner]].ref_rest==reference)
 // New ids in Delta pieces-added carry their own centroid.
 fresh:=add_piece(&s,0,1); add_subdivision(&s,fresh,a,Pose{position=centroid(a)})
 added:=repl_server_update(&srv,&s,3); defer repl_output_destroy(&added)
 testing.expect(t,added.delta_pieces_added==1 && repl_apply_output(&rep,&added)=="" && scenes_equal(&s,&rep.scene))
 testing.expect(t,math.abs(rep.scene.pieces[rep.scene.piece_rows[fresh]].ref_rest.x-8.5)<1e-6)
}

@(test)
reference_pose_spinning_distant_piece_keeps_visible_center :: proc(t: ^testing.T) {
 c:=test_client(); defer net_client_destroy(&c)
 s:=&c.rep.scene
 add_material(s,editor_material(.Stone))
 owner:=add_piece(s,0,42)
 poly:=shape_polygon(Authored_Shape{lo={8,2},hi={9,3}}); defer delete(poly.points)
 cell:=add_subdivision(s,owner,poly,Pose{position=centroid(poly)})
 scene_finish_references(s)
 reference:=s.pieces[s.piece_rows[owner]].ref_rest
 key:=ent_key(.Piece,owner)
 rows0:=map[u64]Pose_State{key=pose_state_make(3,4,-0.6)}; defer delete(rows0)
 rows1:=map[u64]Pose_State{key=pose_state_make(3,4,0.6)}; defer delete(rows1)
 put_frame(&c,100,rows0); put_frame(&c,102,rows1); c.clock=101
 net_client_compute_drawn(&c)
 poses,frames:=net_client_draw_inputs(&c); defer { delete(poses); delete(frames) }
 testing.expect(t,vlen(vsub(poses[cell].position,Vec2{3,4}))<0.003)
 testing.expect(t,vlen(vsub(rigid_render_point(frames[owner],reference),Vec2{3,4}))<0.003)
}
