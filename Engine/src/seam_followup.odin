package main
import "core:fmt"
import "core:math"
import "core:os"

seam_demo_game :: proc()->Sandbox {
 g:=sandbox_editor_create();l:=shape_demo_layout();data,ok:=encode_layout(&l,42);destroy_layout(&l);assert(ok);defer delete(data)
 assert(sandbox_load_layout_data(&g,data));sandbox_toggle_editor(&g);return g
}
seam_far :: proc(c:Connection,blast:Blast)->bool {
 for segment in c.rest_segments { if msaa_edge_distance(blast.position,segment.a,segment.b)<=blast.radius+1 { return false } }
 for sample in c.glue { if msaa_edge_distance(blast.position,sample.p,sample.q)<=blast.radius+1 { return false } }
 return true
}
seam_demo_movement :: proc(g:^Sandbox)->f32 {
 maximum:=f32(0)
 for sub in g.world.scene.subdivisions { if sub.rest_center.y<0 { continue };for p in sub.outline.points { maximum=max(maximum,vlen(vsub(posed_point(sub,p),p))) } };return maximum
}
probe_demo_blasts :: proc() {
 for x in ([5]f32{-4.6,-3.8,-3,-2.2,-1.5}) { for y in ([7]f32{0.2,0.7,1.2,1.7,2.2,2.7,3.2}) { for radius in ([4]f32{2.8,3.2,3.6,4}) {
  g:=seam_demo_game();s:=&g.world.scene;far:[dynamic]u64;before:=0
  blast:=Blast{{x,y},radius}
  if !sandbox_valid_aim(s,blast.position) { sandbox_destroy(&g);continue }
  for c in s.connections { if c.mortar && seam_far(c,blast) { append(&far,c.id) } }
  for sub in s.subdivisions { if sub.frame>0 && sub.frame<1 { before+=1 } }
  sandbox_fixture_radius(&g,radius);sandbox_explode(&g,blast.position)
  for _ in 0..<20 { sandbox_tick(&g,0,false) }
  kept,after:=0,0
  for id in far { if row,ok:=s.conn_rows[id];ok && s.connections[row].live { kept+=1 } }
  for sub in s.subdivisions { if sub.frame>0 && sub.frame<1 { after+=1 } }
  fmt.printf("PROBE x=%.1f y=%.1f radius=%.1f far=%d/%d wood_cells=%d/%d\n",x,y,radius,kept,len(far),before,after)
  delete(far);sandbox_destroy(&g)
 } } }
}
