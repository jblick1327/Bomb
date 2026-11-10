package main
import "core:fmt"
when ODIN_OS == .Windows {
 foreign import msaa_gl "system:opengl32.lib"
 foreign msaa_gl {
  @(link_name="glGetIntegerv") msaa_gl_integer :: proc "system" (name:u32,value:^i32) ---
 }
}
msaa_edge_distance :: proc(p,a,b: Vec2) -> f32 {
 edge:=vsub(b,a)
 t:=clamp(vdot(vsub(p,a),edge)/max(vdot(edge,edge),f32(1e-20)),f32(0),f32(1))
 return vlen(vsub(p,vadd(a,vmul(edge,t))))
}

// Textured comparison replaces the former flat-colour seam test.
sandbox_smoke_msaa :: proc() {
 samples,buffers:i32;msaa_gl_integer(0x80a9,&samples);msaa_gl_integer(0x80a8,&buffers)
 fmt.printf("Actual MSAA samples=%d buffers=%d fonts_loaded=%v\n",samples,buffers,ui_fonts_ready)
 assert(samples==4 && buffers==1 && ui_fonts_ready)
 texture_compare_cells()
}
// Two anchored neighbours and a rigid cycle with a broken internal bond.
msaa_border_scene :: proc() -> Scene {
 s:=new_scene(0.1)
 stone:=add_material(&s,editor_material(.Stone)); wood:=add_material(&s,editor_material(.Wood))
 for side in 0..<2 {
  p:=add_piece(&s,stone,u8(42+side)); x0,x1:=f32(-8),f32(0); if side==1 { x0=0; x1=9 }
  points:=[4]Vec2{{x0,-3},{x1,-3},{x1,0},{x0,0}}; poly:=Polygon{points=points[:]}
  add_subdivision(&s,p,poly,Pose{position=centroid(poly)}); presplit_piece(&s,p)
 }
 owner:=add_piece(&s,wood,0); ids:[4]u64
 for i in 0..<4 {
  x,y:=f32(1+i%2),f32(i/2); points:=[4]Vec2{{x,y},{x+1,y},{x+1,y+1},{x,y+1}}; p:=Polygon{points=points[:]}
  ids[i]=add_subdivision(&s,owner,p,Pose{position=centroid(p)})
 }
 for a in 0..<4 { for b in a+1..<4 { add_connection(&s,ids[a],ids[b]) } }
 physics_init(&s,{},-3)
 f:=Failures{}; append(&f.connections,s.connection_pairs[pair_key(ids[0],ids[1])]); apply_failures(&s,f); free_failures(&f); physics_sync_structure(&s)
 return s
}
