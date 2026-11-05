package main

import "core:math"

WOOD_MINIMUM_WIDTH :: f32(0.1)
STRIP_MIN :: 2*WOOD_MINIMUM_WIDTH

WOOD_CELL_MAX :: f32(2)
WOOD_SPLINTER_RATIO :: f32(4)

grain_bounds :: proc(p: Polygon) -> (lo,hi: Vec2,axis: int,length,thickness: f32) {
 lo,hi={1e30,1e30},{-1e30,-1e30}
 for v in p.points { lo={min(lo.x,v.x),min(lo.y,v.y)}; hi={max(hi.x,v.x),max(hi.y,v.y)} }
 width,height:=hi.x-lo.x,hi.y-lo.y
 if width>=height { return lo,hi,0,width,height }; return lo,hi,1,height,width
}
grain_cut_kind :: proc(p: Polygon,minimum_width: f32,creation: bool,strip: f32) -> (needed,cross_cut: bool) {
 _,_,_,length,thickness:=grain_bounds(p)
 if creation {
  if thickness>strip+0.00001 { return true,false }
  return length>WOOD_CELL_MAX+0.00001,true
 }
 if thickness>=2*minimum_width { return true,false }
 return length>=2*WOOD_SPLINTER_RATIO*thickness,true
}

// General straight half-plane clip. The same intersection arithmetic is used
// for both halves, so a slanted cut has exactly shared boundary vertices.
clip_halfplane :: proc(p: Polygon,a,b: Vec2,keep_low: bool) -> Polygon {
 points:[dynamic]Vec2; defer delete(points)
 for v,i in p.points {
  w:=p.points[(i+1)%len(p.points)]
  side_v,side_w:=polygon_turn(a,b,v),polygon_turn(a,b,w)
  if !keep_low { side_v=-side_v; side_w=-side_w }
  inside_v,inside_w:=side_v<=0,side_w<=0
  if inside_v { append(&points,v) }
  if inside_v!=inside_w {
   fraction:=side_v/(side_v-side_w)
   point:=Vec2{f32(f64(v.x)+(f64(w.x)-f64(v.x))*fraction),f32(f64(v.y)+(f64(w.y)-f64(v.y))*fraction)}
   append(&points,point)
  }
 }
 return make_polygon(points[:])
}

generate_grained_children :: proc(parent: Polygon,recipe: Material,seed: u8,minimum_width: f32,creation: bool) -> [dynamic]Polygon {
 if seed==0 || !valid_partition_half(parent,minimum_width) { return nil }
 result:[dynamic]Polygon; append(&result,make_polygon(parent.points))
 blocked:=make(map[int]bool); defer delete(blocked)
 for len(result)<recipe.generation_count {
  chosen:=-1; largest:=f32(0)
  for p,i in result {
   needed,_:=grain_cut_kind(p,minimum_width,creation,recipe.strip_thickness)
   area:=polygon_area(p)
   if needed && !blocked[i] && area>largest { chosen=i; largest=area }
  }
  if chosen<0 { break }
  p:=result[chosen]; lo,hi,axis,length,thickness:=grain_bounds(p)
  _,cross_cut:=grain_cut_kind(p,minimum_width,creation,recipe.strip_thickness)
  fraction:=f32(0.4)+0.2*f32(derive_seed(seed,u64(len(result))))/255
  low,high:Polygon
  if !cross_cut {
   low_fraction,high_fraction:=max(f32(0.4),minimum_width/thickness),min(f32(0.6),1-minimum_width/thickness)
   if low_fraction>high_fraction { blocked[chosen]=true; continue }
   fraction=clamp(fraction,low_fraction,high_fraction)
   cut_axis:=1-axis; cut:=lo.y+(hi.y-lo.y)*fraction
   if cut_axis==0 { cut=lo.x+(hi.x-lo.x)*fraction }
   low,high=clip_polygon(p,cut_axis,cut,true),clip_polygon(p,cut_axis,cut,false)
  } else {
   slant:=f32(0.75)*thickness
   if derive_seed(seed,u64(len(result))+0x1000)%2==0 { slant=-slant }
   a,b:=Vec2{lo.x+length*fraction-slant,lo.y},Vec2{lo.x+length*fraction+slant,hi.y}
   if axis==1 { a,b={lo.x,lo.y+length*fraction-slant},{hi.x,lo.y+length*fraction+slant} }
   low,high=clip_halfplane(p,a,b,true),clip_halfplane(p,a,b,false)
  }
  valid:=valid_partition_half(low,minimum_width) && valid_partition_half(high,minimum_width)
  valid=valid && math.abs(polygon_area(low)+polygon_area(high)-polygon_area(p))<=max(f32(0.0000002),polygon_area(p)*0.00002)
  if valid { delete(p.points); result[chosen]=low; append(&result,high) }
  else { delete(low.points); delete(high.points); blocked[chosen]=true }
 }
 displace_shared_boundaries(result[:],seed,minimum_width,true)
 area:=f32(0); parent_area:=polygon_area(parent); genuine:=len(result)>=2
 for p in result { area+=polygon_area(p); genuine=genuine && valid_partition_half(p,minimum_width) && polygon_area(p)<parent_area }
 if !genuine || math.abs(area-parent_area)>max(f32(0.000002),parent_area*0.0002) {
  for p in result { delete(p.points) }; delete(result); return nil
 }
 return result
}

insert_shared_path :: proc(p: ^Polygon,segment: Segment,path: []Vec2) {
 insert_boundary_endpoint(p,segment.a); insert_boundary_endpoint(p,segment.b)
 for a,i in p.points {
  b:=p.points[(i+1)%len(p.points)]
  forward:=vlen(vsub(a,segment.a))<0.00001 && vlen(vsub(b,segment.b))<0.00001
  reverse:=vlen(vsub(b,segment.a))<0.00001 && vlen(vsub(a,segment.b))<0.00001
  if !forward && !reverse { continue }
  for k in 0..<len(path) { j:=k; if reverse { j=len(path)-1-k }; insert_polygon_vertex(p,i+1+k,path[j]) }
  return
 }
}

// Returns false for cross-grain seams, which retain the existing midpoint tent.
displace_grained_seam :: proc(children: []Polygon,boundary: Cut_Boundary,seed: u8,index: int,minimum_width: f32) -> bool {
 edge:=vsub(boundary.segment.b,boundary.segment.a); length:=vlen(edge)
 _,_,axis,_,_:=grain_bounds(children[boundary.a])
 parallel,across:=math.abs(edge.x),math.abs(edge.y); if axis==1 { parallel,across=across,parallel }
 if across>parallel*0.25 { return false }
 normal:=Vec2{-edge.y/length,edge.x/length}
 amplitude:=min(f32(0.03),min(length*0.04,min(polygon_area(children[boundary.a]),polygon_area(children[boundary.b]))/length*0.08))
 n:=max(2,int(math.ceil(length/0.25)))
 bases:[dynamic]Vec2; defer delete(bases)
 for k in 1..<n { append(&bases,vadd(boundary.segment.a,vmul(edge,f32(k)/f32(n)))) }
 neighbours:=[2]int{boundary.a,boundary.b}
 for base in bases { for row in neighbours { for a,i in children[row].points {
  b:=children[row].points[(i+1)%len(children[row].points)]; e:=vsub(b,a)
  if vdot(e,e)<1e-12 { continue }
  if _,shared:=segment_overlap(Segment{a,b},boundary.segment); shared { continue }
  t:=clamp(vdot(vsub(base,a),e)/vdot(e,e),f32(0),f32(1))
  amplitude=min(amplitude,vlen(vsub(base,vadd(a,vmul(e,t))))*0.2)
 } } }
 if derive_seed(seed,u64(index+1))%2==0 { amplitude=-amplitude }
 path:=make([]Vec2,len(bases)); defer delete(path)
 for attempt in 0..<4 {
  for base,k in bases {
   jitter:=f32(0.6)+0.4*f32(derive_seed(seed,u64(index+1)*0x10000+u64(k+1)))/255
   sign:=f32(1); if k%2==1 { sign=-1 }
   path[k]=vadd(base,vmul(normal,amplitude*sign*jitter))
  }
  left,right:=make_polygon(children[boundary.a].points),make_polygon(children[boundary.b].points)
  insert_shared_path(&left,boundary.segment,path); insert_shared_path(&right,boundary.segment,path)
  valid:=simple_polygon(left) && simple_polygon(right) && outline_width(left.points)>=minimum_width && outline_width(right.points)>=minimum_width
  if valid {
   delete(children[boundary.a].points); delete(children[boundary.b].points); children[boundary.a]=left; children[boundary.b]=right; break
  }
  delete(left.points); delete(right.points); amplitude*=0.5
 }
 return true
}

connection_blast_sample :: proc(s: ^Scene,c: Connection,blast_position: Vec2) -> Vec2 {
 a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
 if s.materials[a.material].aspect_ratio>=1 || s.materials[b.material].aspect_ratio>=1 { return connection_sample(s,c) }
 closest:=connection_sample(s,c); distance:=f32(1e30)
 for segment in c.rest_segments {
  // Pose each shared endpoint exactly as the old midpoint sample: average
  // the two cells' transforms (a single rigid frame for ordinary Wood).
  p:=vmul(vadd(posed_point(a,segment.a),posed_point(b,segment.a)),0.5)
  q:=vmul(vadd(posed_point(a,segment.b),posed_point(b,segment.b)),0.5)
  edge:=vsub(q,p); squared:=vdot(edge,edge); if squared<=0 { continue }
  t:=clamp(vdot(vsub(blast_position,p),edge)/squared,f32(0),f32(1))
  point:=vadd(p,vmul(edge,t)); d:=vdot(vsub(blast_position,point),vsub(blast_position,point))
  if d<distance { distance=d; closest=point }
 }
 return closest
}
