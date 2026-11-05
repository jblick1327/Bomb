package main
import "core:fmt"
import "core:math"
import b2 "vendor:box2d"

seam_diagnostic_scene:^Scene
seam_diagnostic_layout:^Layout
seam_diagnostic_tick:int
seam_diagnostic_run:string
seam_diagnostic_phase:string
seam_object :: proc(sub:Subdivision)->u64 {
 if seam_diagnostic_layout==nil { return 0 }
 for object in seam_diagnostic_layout.objects { p:=shape_polygon(object);inside:=convex_contains(p,sub.rest_center);delete(p.points);if inside { return object.identity } };return 0
}
seam_diagnostic_death :: proc(s:^Scene,c:Connection,path:string) {
 if s!=seam_diagnostic_scene { return }
 a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
 fmt.printf("DEATH run=%s tick=%d phase=%s path=%s id=%d objects=%d/%d glue=%v endpoints_live=%v/%v\n",seam_diagnostic_run,seam_diagnostic_tick,seam_diagnostic_phase,path,c.id,seam_object(a),seam_object(b),len(c.glue)>0,a.live,b.live)
}
seam_diagnostic_force :: proc(s:^Scene,seam:Mortar_Seam,r:f32,broken:bool) {
 if s!=seam_diagnostic_scene { return }
 fmt.printf("FORCE run=%s tick=%d bodies=%v/%v r=%.9f counter_before=%d broken=%v ids=%v\n",seam_diagnostic_run,seam_diagnostic_tick,seam.bodies[0],seam.bodies[1],r,seam.overload_ticks,broken,seam.members[:])
}
demo_trace :: proc(blast:bool) {
 g:=sandbox_editor_create();defer sandbox_destroy(&g)
 layout:=shape_demo_layout();data,ok:=encode_layout(&layout,42);destroy_layout(&layout);assert(ok);defer delete(data);assert(sandbox_load_layout_data(&g,data));sandbox_toggle_editor(&g)
 s:=&g.world.scene;seam_diagnostic_scene=s;seam_diagnostic_layout=&g.layout
 defer { seam_diagnostic_scene=nil;seam_diagnostic_layout=nil }
 seam_diagnostic_run="quiet";if blast { seam_diagnostic_run="blast" };seam_diagnostic_tick=0;seam_diagnostic_phase="initial"
 demo_trace_state(&g);demo_trace_bodies(&g)
 if blast { seam_diagnostic_phase="blast";radius:=f32(4);point:=Vec2{-3.8,0.5};when #config(SEAM_DIAG_FIXTURE,false) { radius=3;point={-4.4,1.5} };sandbox_fixture_radius(&g,radius);sandbox_explode(&g,point);demo_trace_state(&g);demo_trace_bodies(&g) }
 when #config(SEAM_DIAG_NO_CONTACTS,false) { for sub in s.subdivisions { for shape in sub.shapes { filter:=b2.Shape_GetFilter(shape);filter.maskBits=0;b2.Shape_SetFilter(shape,filter) } } }
 when #config(SEAM_DIAG_ZERO_VELOCITY,false) { for p in s.pieces { b2.Body_SetLinearVelocity(p.body,{});b2.Body_SetAngularVelocity(p.body,0) } }
 for tick in 1..=30 { seam_diagnostic_tick=tick;seam_diagnostic_phase="physics";sandbox_tick(&g,0,false);demo_trace_state(&g);if tick==1 || tick==8 { demo_trace_bodies(&g) } }
 seam_diagnostic_scene=nil
 for _ in 30..<600 { sandbox_tick(&g,0,false) }
 max_move:=f32(0);count:=0
 for sub in s.subdivisions { if sub.rest_center.y<0 { continue };max_move=max(max_move,vlen(vsub(sub.pose.position,sub.rest_center))) }
 for c in s.connections { if c.mortar { count+=1 } }
 fmt.printf("SUMMARY run=%s tick600 live_seam_connections=%d max_object_movement=%.9f\n",seam_diagnostic_run,count,max_move)
}
demo_trace_state :: proc(g:^Sandbox) {
 s:=&g.world.scene;seams:=mortar_seams(s);defer mortar_free_seams(seams)
 for seam in seams {
  mortar,glue:=0,0;for id in seam.members { c:=s.connections[s.conn_rows[id]];if len(c.glue)>0 { glue+=1 } else { mortar+=1 } }
  c:=s.connections[s.conn_rows[seam.members[0]]];a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
  r:=vlen(seam.force)/(MORTAR_STRENGTH*seam.length)+math.abs(seam.torque)/(0.5*MORTAR_STRENGTH*seam.length*seam.length)
  fmt.printf("SEAM run=%s tick=%d phase=%s objects=%d/%d bodies=%v/%v mortar=%d glue=%d L=%.9f r=%.9f counter=%d collide=%v ids=%v\n",seam_diagnostic_run,seam_diagnostic_tick,seam_diagnostic_phase,seam_object(a),seam_object(b),seam.bodies[0],seam.bodies[1],mortar,glue,seam.length,r,seam.overload_ticks,b2.Joint_GetCollideConnected(c.joint),seam.members[:])
  if glue>0 {
   rest_gap,posed_gap:=f32(0),f32(0)
   for id in seam.members { link:=s.connections[s.conn_rows[id]];sa,sb:=s.subdivisions[s.sub_rows[link.a]],s.subdivisions[s.sub_rows[link.b]]
    for sample in link.glue { rest_gap=max(rest_gap,vlen(vsub(sample.p,sample.q)));posed_gap=max(posed_gap,vlen(vsub(posed_point(sa,sample.p),posed_point(sb,sample.q)))) }
   }
   fmt.printf("GLUE_GAP run=%s tick=%d objects=%d/%d rest_max=%.9f posed_max=%.9f\n",seam_diagnostic_run,seam_diagnostic_tick,seam_object(a),seam_object(b),rest_gap,posed_gap)
  }
 }
 displacement,maximum:=f32(0),f32(0);n:=0
 for sub in s.subdivisions { if seam_object(sub)==6 { d:=vlen(vsub(sub.pose.position,sub.rest_center));displacement+=d;maximum=max(maximum,d);n+=1 } }
 fmt.printf("BRACE run=%s tick=%d phase=%s cells=%d mean_displacement=%.9f max_displacement=%.9f live_seams=%d\n",seam_diagnostic_run,seam_diagnostic_tick,seam_diagnostic_phase,n,displacement/max(f32(1),f32(n)),maximum,len(seams))
}
run_seam_diagnostics :: proc() { demo_trace(false);demo_trace(true) }

demo_trace_bodies :: proc(g:^Sandbox) {
 s:=&g.world.scene
 for p in s.pieces { if !p.live { continue }
  fmt.printf("BODY run=%s tick=%d owner=%d material=%s body=%v type=%v velocity=%v omega=%g position=%v mass=%g\n",seam_diagnostic_run,seam_diagnostic_tick,p.id,s.materials[p.material].name,p.body,b2.Body_GetType(p.body),b2.Body_GetLinearVelocity(p.body),b2.Body_GetAngularVelocity(p.body),b2.Body_GetPosition(p.body),b2.Body_GetMass(p.body))
  buffer:=make([]b2.ContactData,int(b2.Body_GetContactCapacity(p.body)))
  for contact in b2.Body_GetContactData(p.body,buffer) { a,b:=b2.Shape_GetBody(contact.shapeIdA),b2.Shape_GetBody(contact.shapeIdB);if a!=p.body { continue };points:=contact.manifold.points;fmt.printf("CONTACT run=%s tick=%d pair=%v/%v normal=%v points=%v\n",seam_diagnostic_run,seam_diagnostic_tick,a,b,contact.manifold.normal,points[:contact.manifold.pointCount]) }
  delete(buffer)
 }
}
