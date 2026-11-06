#+feature dynamic-literals
package shared

import math "core:math"

built_object :: proc(r:Authored_Shape,first,last:u64)->Built_Object {
 p:=shape_polygon(r);defer delete(p.points)
 out:=Built_Object{identity=r.identity,mortar=r.mortar,lo=r.lo,hi=r.hi,first_id=first,end_id=last,count=len(p.points)}
 copy(out.vertices[:],p.points);return out
}

build_shaped_object :: proc(s:^Scene,r:Authored_Shape,owner:u64) {
 first:=s.next_id+1
 frame:=r.angle*math.PI/180;local_shape:=r;local_shape.angle=0
 outline:=shape_polygon(local_shape);defer delete(outline.points)
 cells:[dynamic]Polygon;defer { for cell in cells { delete(cell.points) };delete(cells) }
 if s.materials[s.pieces[s.piece_rows[owner]].material].flexibility==0 { append(&cells,make_polygon(outline.points)) } else {
  nx:=int(math.ceil((r.hi.x-r.lo.x)/RUBBER_CELL_SIZE-0.00001));ny:=int(math.ceil((r.hi.y-r.lo.y)/RUBBER_CELL_SIZE-0.00001))
  dx,dy:=(r.hi.x-r.lo.x)/f32(nx),(r.hi.y-r.lo.y)/f32(ny)
  for row in 0..<ny { for col in 0..<nx {
   box:=shape_polygon(Authored_Shape{lo={r.lo.x+f32(col)*dx,r.lo.y+f32(row)*dy},hi={r.lo.x+f32(col+1)*dx,r.lo.y+f32(row+1)*dy}})
   clipped:=convex_intersection(box,outline);delete(box.points)
   if len(clipped.points)>=3 && polygon_area(clipped)>1e-8 { append(&cells,clipped) } else { delete(clipped.points) }
  } }
  for i:=0;i<len(cells); {
   if outline_width(cells[i].points)>=s.minimum_width && polygon_area(cells[i])>=dx*dy*0.2 { i+=1;continue }
   best:=-1;length:=f32(0)
   for cell,j in cells { if i==j { continue };l,_:=shared_boundary(cells[i],cell);if l>length { best=j;length=l } }
   assert(best>=0)
   merged:=polygon_union_touching(cells[i],cells[best]);delete(cells[best].points);cells[best]=merged;delete(cells[i].points);ordered_remove(&cells,i);i=0
  }
 }
 ids:[dynamic]u64;defer delete(ids)
 center:=vmul(vadd(r.lo,r.hi),0.5)
 transformed:=make(map[Vec2]Vec2);defer delete(transformed)
 for cell in cells {
  world:=make_polygon(cell.points)
 
  id:=add_subdivision(s,owner,world,Pose{position=centroid(world)});delete(world.points)
  for other in ids { add_connection(s,other,id) };append(&ids,id)
 }
 if s.materials[s.pieces[s.piece_rows[owner]].material].flexibility==0 { presplit_piece(s,owner) }
 if frame!=0 {
  // The authored rotation is part of construction, before these ids are published.
  for &p in s.pieces { if p.id>=owner && p.has_ref_rest { p.ref_rest=vadd(center,vrotate(vsub(p.ref_rest,center),frame)) } }
  for &sub in s.subdivisions { if sub.id<first { continue }
   for &v in sub.outline.points { p,ok:=transformed[v];if !ok { p=vadd(center,vrotate(vsub(v,center),frame));transformed[v]=p };v=p }
   sub.rest_center=vadd(center,vrotate(vsub(sub.rest_center,center),frame));sub.pose.position=sub.rest_center;sub.frame=frame
  }
  for &c in s.connections { if c.a<first || c.b<first { continue };c.rest_point=vadd(center,vrotate(vsub(c.rest_point,center),frame))
   c.local_a=vsub(c.rest_point,s.subdivisions[s.sub_rows[c.a]].rest_center);c.local_b=vsub(c.rest_point,s.subdivisions[s.sub_rows[c.b]].rest_center)
   for &segment in c.rest_segments { segment.a=vadd(center,vrotate(vsub(segment.a,center),frame));segment.b=vadd(center,vrotate(vsub(segment.b,center),frame)) }
  }
 }
}

polygon_union_touching :: proc(a,b:Polygon)->Polygon {
 aa,bb:=make_polygon(a.points),make_polygon(b.points);defer delete(aa.points);defer delete(bb.points)
 for p in a.points { insert_boundary_endpoint(&bb,p) };for p in b.points { insert_boundary_endpoint(&aa,p) }
 edges:[dynamic]Segment;defer delete(edges)
 polys:=[2]Polygon{aa,bb}
 for poly in polys { for p,i in poly.points {
  q:=poly.points[(i+1)%len(poly.points)];shared:=false
  for other in polys { if raw_data(other.points)==raw_data(poly.points) { continue };for v,j in other.points { w:=other.points[(j+1)%len(other.points)];if vlen(vsub(p,w))<1e-5 && vlen(vsub(q,v))<1e-5 { shared=true } } }
  if !shared { append(&edges,Segment{p,q}) }
 } }
 points:[dynamic]Vec2;defer delete(points)
 if len(edges)==0 { return {} };current:=edges[0].a
 for len(edges)>0 { found:=-1;for edge,i in edges { if vlen(vsub(current,edge.a))<1e-5 { found=i;break } };assert(found>=0);append(&points,current);current=edges[found].b;ordered_remove(&edges,found) }
 return make_polygon(points[:])
}
