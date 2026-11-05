package main
import "core:math"

GLUE_CONTACT :: f32(0.001)
GLUE_FILLET :: f32(0.2)
GLUE_STEP :: f32(0.05)
layout_object :: proc(l:^Layout,id:u64)->(Authored_Shape,bool) {
 for object in l.objects { if object.identity==id { return object,true } };return {},false
}
layout_glue_problem :: proc(l:^Layout,link:Glue_Link)->string {
 if link.a==0 || link.a==link.b || link.b!=0 && link.a>link.b { return "Invalid glue identities" }
 a,ok:=layout_object(l,link.a);if !ok { return "Glue references a missing identity" }
 b:=Authored_Shape{lo={YARD_LEFT,YARD_FLOOR_BOTTOM},hi={YARD_RIGHT,0}}
 if link.b!=0 { exists:bool;b,exists=layout_object(l,link.b);if !exists { return "Glue references a missing identity" } }
 for old in l.glue { if old==link { return "Duplicate glue" } }
 pa,pb:=shape_polygon(a),shape_polygon(b);defer delete(pa.points);defer delete(pb.points)
 if !glue_valid_contact(pa,pb,link.b==0) { return "Objects must touch to glue" };return ""
}
validate_glue_samples :: proc(c:Connection,a,b:Subdivision)->string {
 if !c.mortar { return "Glue must be mortar" }
 for sample in c.glue {
  if !valid_vec(sample.p) || !valid_vec(sample.q) || !finite(sample.w) || sample.w<=0 { return "Invalid glue sample" }
  if vlen(vsub(sample.p,sample.q))>GLUE_FILLET+1e-4 { return "Glue sample too wide" }
  if vlen(vsub(sample.p,boundary_nearest(a.outline,sample.p)))>1e-4 || vlen(vsub(sample.q,boundary_nearest(b.outline,sample.q)))>1e-4 { return "Glue sample off boundary" }
 };return ""
}
built_polygon :: proc(o:Built_Object)->Polygon {
 if o.count>0 { vertices:=o.vertices; return make_polygon(vertices[:o.count]) };return shape_polygon(Authored_Shape{lo=o.lo,hi=o.hi})
}
built_on_ground :: proc(o:Built_Object)->bool {
 if o.count==0 { return o.lo.y==0 };p:=built_polygon(o);defer delete(p.points)
 for v,i in p.points { if math.abs(v.y)<1e-6 && math.abs(p.points[(i+1)%len(p.points)].y)<1e-6 { return true } };return false
}
seam_geometry :: proc(c:Connection)->(length:f32,center:Vec2) {
 if len(c.glue)>0 {
  for sample in c.glue { length+=sample.w;center=vadd(center,vmul(vadd(sample.p,sample.q),sample.w*0.5)) }
  if length>0 { center=vmul(center,1/length) };return
 }
 for seg in c.rest_segments { w:=vlen(vsub(seg.b,seg.a));length+=w;center=vadd(center,vmul(vadd(seg.a,seg.b),w*0.5)) }
 if length>0 { center=vmul(center,1/length) };return
}
glue_side :: proc(x,y:Polygon,ground:bool=false)->[dynamic]Glue_Sample {
 samples:[dynamic]Glue_Sample
 for a,i in x.points {
  edge:=vsub(x.points[(i+1)%len(x.points)],a);length:=vlen(edge);if length<1e-7 { continue }
  n:=int(math.ceil(length/GLUE_STEP));normal:=Vec2{edge.y/length,-edge.x/length}
  for j in 0..<n {
   p:=vadd(a,vmul(edge,(f32(j)+0.5)/f32(n)));q:=p;hit:=false;distance:=GLUE_FILLET+1e-6
   if ground {
    if math.abs(p.y)<=GLUE_CONTACT { q={p.x,0};hit=true } else if normal.y<0 { t:=-p.y/normal.y;if t>=0 && t<=GLUE_FILLET { q=vadd(p,vmul(normal,t));hit=true } }
   } else {
    nearest:=boundary_nearest(y,p)
    if vlen(vsub(nearest,p))<=GLUE_CONTACT { q=nearest;hit=true } else {
     for c,k in y.points { d:=vsub(y.points[(k+1)%len(y.points)],c);denom:=vcross(normal,d);if math.abs(denom)<1e-8 { continue }
      t:=vcross(vsub(c,p),d)/denom;u:=vcross(vsub(c,p),normal)/denom
      if t>=0 && t<=distance && u>=0 && u<=1 { distance=t;q=vadd(p,vmul(normal,t));hit=true }
     }
    }
   }
   if hit { append(&samples,Glue_Sample{p,q,length/f32(n)}) }
  }
 };return samples
}
glue_samples :: proc(a,b:Polygon,ground:bool=false)->[dynamic]Glue_Sample {
 left:=glue_side(a,b,ground)
 // The finite ground boundary is the yard floor; side(ground,A) uses upward normals.
 right:=glue_side(b,a)
 wl,wr:f32;for s in left { wl+=s.w };for s in right { wr+=s.w }
 if wr<wl { delete(left);for &s in right { s.p,s.q=s.q,s.p };return right }
 delete(right);return left
}
glue_valid_contact :: proc(a,b:Polygon,ground:bool)->bool {
 if ground { low:=f32(1e30);for p in a.points { low=min(low,p.y) };return low<=GLUE_CONTACT }
 distance,_:=polygon_contact(a,b);return distance<=GLUE_CONTACT
}
glue_add :: proc(s:^Scene,a,b:u64,samples:[]Glue_Sample,inherit:bool=false)->u64 {
 if len(samples)==0 || a==0 || b==0 { return 0 }
 if id,ok:=s.connection_pairs[pair_key(a,b)];ok && s.connections[s.conn_rows[id]].live {
  c:=&s.connections[s.conn_rows[id]]
  if inherit && len(c.glue)>0 { append(&c.glue,..samples);_,point:=seam_geometry(c^);c.rest_point=point;c.local_a=vsub(point,s.subdivisions[s.sub_rows[a]].rest_center);c.local_b=vsub(point,s.subdivisions[s.sub_rows[b]].rest_center);s.structure_revision+=1 };return id
 }
 c:=Connection{id=new_id(s),a=a,b=b,mortar=true,live=true};append(&c.glue,..samples)
 _,point:=seam_geometry(c);c.rest_point=point
 sa,sb:=s.subdivisions[s.sub_rows[a]],s.subdivisions[s.sub_rows[b]]
 c.local_a=vsub(point,sa.rest_center);c.local_b=vsub(point,sb.rest_center)
 s.conn_rows[c.id]=len(s.connections);append(&s.connections,c);s.connection_pairs[pair_key(a,b)]=c.id
 append(&s.subdivisions[s.sub_rows[a]].incident_links,c.id);append(&s.subdivisions[s.sub_rows[b]].incident_links,c.id)
 s.structure_revision+=1;return c.id
}
nearest_sample_cell :: proc(s:^Scene,ids:[]u64,p:Vec2)->u64 {
 id:=u64(0);distance:=f32(1e30)
 for candidate in ids { sub:=s.subdivisions[s.sub_rows[candidate]];if !sub.live { continue };d:=vlen(vsub(p,boundary_nearest(sub.outline,p)))
  if d<distance-1e-7 || math.abs(d-distance)<=1e-7 && (id==0 || candidate<id) { id=candidate;distance=d }
 };return id
}
assign_glue :: proc(s:^Scene,samples:[]Glue_Sample,left,right:[]u64,inherit:bool=false) {
 groups:=make(map[Endpoint_Pair][dynamic]Glue_Sample);defer { for _,group in groups { delete(group) };delete(groups) }
 order:[dynamic]Endpoint_Pair;defer delete(order)
 for sample in samples {
  a,b:=nearest_sample_cell(s,left,sample.p),nearest_sample_cell(s,right,sample.q);if a==0 || b==0 { continue }
  key:=Endpoint_Pair{a,b};group,ok:=groups[key];if !ok { append(&order,key) };append(&group,sample);groups[key]=group
 }
 for key in order { glue_add(s,key.a,key.b,groups[key][:],inherit) }
}
inherit_glue :: proc(s:^Scene,c:Connection,left,right:[]u64) { assign_glue(s,c.glue[:],left,right,true) }
build_glue :: proc(s:^Scene,links:[]Glue_Link,objects:[]Built_Object,ground:Built_Object) {
 for link in links {
  a,b:=Built_Object{},ground
  for object in objects { if object.identity==link.a { a=object };if object.identity==link.b { b=object } }
  pa,pb:=built_polygon(a),built_polygon(b);samples:=glue_samples(pa,pb,link.b==0)
  left,right:=object_cells(s,a),object_cells(s,b);assign_glue(s,samples[:],left[:],right[:])
  delete(left);delete(right);delete(samples);delete(pa.points);delete(pb.points)
 }
}
