package main
import rl "vendor:raylib"
import "core:math"

angle_wrap :: proc(angle:f32)->f32 { result:=math.mod(angle,360);if result<0 { result+=360 };return result }
draw_shape_outline :: proc(view:View,r:Authored_Shape,width:f32,color:rl.Color) {
 p:=shape_polygon(r);defer delete(p.points)
 for v,i in p.points { rl.DrawLineEx(screen_point(view,v),screen_point(view,p.points[(i+1)%len(p.points)]),width,color) }
}
draw_shape_preview :: proc(view:View,r:Authored_Shape,color:rl.Color) {
 p:=shape_polygon(r);defer delete(p.points)
 for i in 1..<len(p.points)-1 { rl.DrawTriangle(screen_point(view,p.points[0]),screen_point(view,p.points[i+1]),screen_point(view,p.points[i]),color) }
}
editor_glue_click :: proc(g:^Sandbox,p:Vec2) {
 id:=u64(0)
 for object in g.layout.objects { poly:=shape_polygon(object);inside:=convex_contains(poly,p);delete(poly.points);if inside { id=object.identity;break } }
 if g.editor.glue_first==0 { if id!=0 { g.editor.glue_first=id };return }
 if id==0 && p.y>0 { return }
 a:=g.editor.glue_first;b:=id;g.editor.glue_first=0
 if a==b { return };if b!=0 && a>b { a,b=b,a }
 link:=Glue_Link{a,b}
 for old,i in g.layout.glue { if old==link { ordered_remove(&g.layout.glue,i);sandbox_layout_changed(g);return } }
 if reason:=layout_glue_problem(&g.layout,link);reason!="" { sandbox_notice(g,reason);return }
 append(&g.layout.glue,link);sandbox_layout_changed(g)
}
// Flush classification is in rest space; solver drift must not erase a seam.
draw_glue_strip :: proc(view:View,samples:[]Glue_Sample,a,b:Subdivision,pose:bool,outline_width:f32=2) {
 width:=max(f32(2),outline_width)
 for sample,i in samples {
  p,q:=sample.p,sample.q
  if pose { p=posed_point(a,p);q=posed_point(b,q) }
  flush:=vlen(vsub(sample.p,sample.q))<1e-5
  if i>0 {
   prev:=samples[i-1];previous_flush:=vlen(vsub(prev.p,prev.q))<1e-5
   pp,qq:=prev.p,prev.q;if pose { pp=posed_point(a,pp);qq=posed_point(b,qq) }
   if flush && previous_flush {
    rl.DrawLineEx(screen_point(view,vmul(vadd(pp,qq),0.5)),screen_point(view,vmul(vadd(p,q),0.5)),width,MORTAR_COLOR)
   } else {
    screen:=[4]rl.Vector2{screen_point(view,pp),screen_point(view,p),screen_point(view,q),screen_point(view,qq)}
    winding:=f64(0)
    for point,j in screen { next:=screen[(j+1)%4];winding+=f64(point.x)*f64(next.y)-f64(point.y)*f64(next.x) }
    if winding<0 { rl.DrawTriangle(screen[0],screen[1],screen[2],MORTAR_COLOR);rl.DrawTriangle(screen[0],screen[2],screen[3],MORTAR_COLOR) }
    else { rl.DrawTriangle(screen[2],screen[1],screen[0],MORTAR_COLOR);rl.DrawTriangle(screen[3],screen[2],screen[0],MORTAR_COLOR) }
   }
  }
  if flush {
   // Samples are midpoints. Extend the run to its weighted ends, including
   // cell-pair boundaries and singleton runs, so adjacent runs meet exactly.
   tangent:=glue_flush_tangent(sample,a,b,samples,i)
   lo,hi:=vsub(sample.p,vmul(tangent,sample.w*0.5)),vadd(sample.p,vmul(tangent,sample.w*0.5))
   if pose { lo=vmul(vadd(posed_point(a,lo),posed_point(b,lo)),0.5);hi=vmul(vadd(posed_point(a,hi),posed_point(b,hi)),0.5) }
   rl.DrawLineEx(screen_point(view,lo),screen_point(view,hi),width,MORTAR_COLOR)
  } else if len(samples)==1 { rl.DrawLineEx(screen_point(view,p),screen_point(view,q),max(f32(1),sample.w*view.scale),MORTAR_COLOR) }
 }
}
glue_flush_tangent :: proc(sample:Glue_Sample,a,b:Subdivision,samples:[]Glue_Sample,index:int)->Vec2 {
 segments:=shared_segments(a.outline,b.outline);defer delete(segments)
 for segment in segments { if msaa_edge_distance(sample.p,segment.a,segment.b)<1e-4 { d:=vsub(segment.b,segment.a);return vmul(d,1/vlen(d)) } }
 if len(samples)>1 { other:=index-1;if other<0 { other=1 };d:=vsub(sample.p,samples[other].p);if vlen(d)>1e-7 { return vmul(d,1/vlen(d)) } }
 for v,i in a.outline.points { next:=a.outline.points[(i+1)%len(a.outline.points)];if msaa_edge_distance(sample.p,v,next)<1e-4 { d:=vsub(next,v);if vlen(d)>1e-7 { return vmul(d,1/vlen(d)) } } }
 return {0,1}
}

draw_glue_connection :: proc(s:^Scene,c:Connection,view:View,poses,frames:map[u64]Pose,outline_width:f32=2) {
 a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
 a=render_subdivision(s,a,poses,frames);b=render_subdivision(s,b,poses,frames)
 draw_glue_strip(view,c.glue[:],a,b,true,outline_width)
}
draw_editor_glue :: proc(g:^Sandbox,view:View) {
 for link in g.layout.glue {
  a,ok:=layout_object(&g.layout,link.a);if !ok { continue };b:=Authored_Shape{lo={YARD_LEFT,YARD_FLOOR_BOTTOM},hi={YARD_RIGHT,0}}
  if link.b!=0 { b,_=layout_object(&g.layout,link.b) }
  pa,pb:=shape_polygon(a),shape_polygon(b);samples:=glue_samples(pa,pb,link.b==0)
  draw_glue_strip(view,samples[:],Subdivision{outline=pa},Subdivision{outline=pb},false,g.outline_width);delete(samples);delete(pa.points);delete(pb.points)
 }
}
