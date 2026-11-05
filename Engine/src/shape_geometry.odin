package main
import "core:math"

shape_polygon :: proc(r:Authored_Shape)->Polygon {
 points:=[4]Vec2{r.lo,{r.hi.x,r.lo.y},r.hi,{r.lo.x,r.hi.y}}
 count:=4
 if r.shape==.Wedge { points[2]=points[3];count=3 }
 result:=make_polygon(points[:count])
 if r.angle!=0 { center:=vmul(vadd(r.lo,r.hi),0.5); for &p in result.points { p=vadd(center,vrotate(vsub(p,center),r.angle*math.PI/180)) } }
 return result
}
boundary_nearest :: proc(poly:Polygon,p:Vec2)->Vec2 {
 best:=Vec2{};distance:=f32(1e30)
 for a,i in poly.points { b:=poly.points[(i+1)%len(poly.points)];d:=vsub(b,a);dd:=vdot(d,d);if dd==0 { continue }
  q:=vadd(a,vmul(d,clamp(vdot(vsub(p,a),d)/dd,0,1)));dist:=vlen(vsub(p,q));if dist<distance { best=q;distance=dist }
 };return best
}
polygon_contact :: proc(a,b:Polygon)->(distance:f32,translation:Vec2) {
 distance=1e30
 for p in a.points { q:=boundary_nearest(b,p);d:=vsub(q,p);if vlen(d)<distance { distance=vlen(d);translation=d } }
 for q in b.points { p:=boundary_nearest(a,q);d:=vsub(q,p);if vlen(d)<distance { distance=vlen(d);translation=d } }
 return
}
convex_contains :: proc(poly:Polygon,p:Vec2)->bool {
 for a,i in poly.points { b:=poly.points[(i+1)%len(poly.points)];if vcross(vsub(b,a),vsub(p,a))< -1e-6 { return false } };return true
}
convex_intersection :: proc(a,b:Polygon)->Polygon {
 result:=make_polygon(a.points)
 for q,i in b.points {
  edge:=vsub(b.points[(i+1)%len(b.points)],q);points:[dynamic]Vec2
  for p,j in result.points { next:=result.points[(j+1)%len(result.points)];u,v:=vcross(edge,vsub(p,q)),vcross(edge,vsub(next,q))
   if u>=0 { append(&points,p) };if (u>=0)!=(v>=0) { append(&points,vadd(p,vmul(vsub(next,p),u/(u-v)))) }
  }
  delete(result.points);result=make_polygon(points[:]);delete(points)
 };return result
}
shape_overlap :: proc(a,b:Authored_Shape)->bool {
 pa,pb:=shape_polygon(a),shape_polygon(b);defer delete(pa.points);defer delete(pb.points)
 for source in ([2]Polygon{pa,pb}) { for v,i in source.points {
  edge:=vsub(source.points[(i+1)%len(source.points)],v);axis:=Vec2{-edge.y,edge.x}
  alo,ahi,blo,bhi:=f32(1e30),f32(-1e30),f32(1e30),f32(-1e30)
  for point in pa.points { d:=vdot(point,axis);alo=min(alo,d);ahi=max(ahi,d) }
  for point in pb.points { d:=vdot(point,axis);blo=min(blo,d);bhi=max(bhi,d) }
  if ahi<=blo || bhi<=alo { return false }
 } }
 p:=convex_intersection(pa,pb);defer delete(p.points);return polygon_area(p)>1e-6
}
shape_snap :: proc(layout:^Layout,r:Authored_Shape)->Authored_Shape {
 if r.shape==.Rect && math.mod(r.angle,90)==0 { return r }
 spawn:=Authored_Shape{lo={PLAYER_SPAWN.x-PLAYER_RADIUS,0},hi={PLAYER_SPAWN.x+PLAYER_RADIUS,PLAYER_SPAWN.y+PLAYER_HALF_HEIGHT}}
 if shape_overlap(r,spawn) { return r }
 for other in layout.objects { if shape_overlap(r,other) { return r } }
 p:=shape_polygon(r);defer delete(p.points)
 lowest:=f32(1e30);for v in p.points { lowest=min(lowest,v.y) }
 if lowest< -1e-6 { return r }
 distance:=math.abs(lowest);move:=Vec2{0,-lowest}
 for other in layout.objects { q:=shape_polygon(other);d,v:=polygon_contact(p,q);delete(q.points);if d<distance { distance=d;move=v } }
 if distance>0.3 { return r }
 snapped:=r;snapped.lo=vadd(r.lo,move);snapped.hi=vadd(r.hi,move)
 test:=shape_polygon(snapped);defer delete(test.points);for v in test.points { if v.y< -1e-6 { return r } }
 if shape_overlap(snapped,spawn) { return r }
 for other in layout.objects { if shape_overlap(snapped,other) { return r } }
 return snapped
}
frame_polygon :: proc(p:Polygon,frame:f32)->Polygon {
 out:=make_polygon(p.points);if frame!=0 { for &v in out.points { v=frame_unrotate(v,frame) } };return out
}
frame_longest :: proc(p:Polygon,frame:f32)->f32 {
 if frame==0 { return longest_dimension(p) };local:=frame_polygon(p,frame);defer delete(local.points);return longest_dimension(local)
}
frame_grain :: proc(p:Polygon,frame:f32)->(lo,hi:Vec2,axis:int,length,thickness:f32) {
 if frame==0 { return grain_bounds(p) };local:=frame_polygon(p,frame);defer delete(local.points);return grain_bounds(local)
}
generate_framed :: proc(parent:Polygon,recipe:Material,seed:u8,minimum_width:f32,creation:bool,frame:f32)->[dynamic]Polygon {
 if frame==0 { return generate_children(parent,recipe,seed,minimum_width,creation) }
 local:=frame_polygon(parent,frame);defer delete(local.points)
 children:=generate_children(local,recipe,seed,minimum_width,creation)
 // Cache by exact local vertex bits: siblings transform a new cut only once.
 restored:=make(map[Vec2]Vec2);defer delete(restored)
 for v,i in local.points { restored[v]=parent.points[i] }
 for &child in children { for &v in child.points { world,ok:=restored[v];if !ok { world=vrotate(v,frame);restored[v]=world };v=world } }
 return children
}

// Invert the actual f32 rotation matrix in f64, avoiding a second scale error.
frame_unrotate :: proc(v:Vec2,frame:f32)->Vec2 {
 c,s:=f64(f32(math.cos(frame))),f64(f32(math.sin(frame)));det:=c*c+s*s
 return {f32((f64(v.x)*c+f64(v.y)*s)/det),f32((-f64(v.x)*s+f64(v.y)*c)/det)}
}
