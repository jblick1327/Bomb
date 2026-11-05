package main
import "core:time"

import "core:math"
import "core:slice"

Segment :: struct { a,b: Vec2 }
Cut_Boundary :: struct { a,b: int, segment: Segment }
convex_hull :: proc(points: []Vec2) -> [dynamic]Vec2 {
	sorted: [dynamic]Vec2
	defer delete(sorted)
	for point in points { append(&sorted,point) }
	slice.sort_by(sorted[:],proc(a,b: Vec2) -> bool { return a.x<b.x || a.x==b.x && a.y<b.y })

	hull: [dynamic]Vec2
	if len(sorted)<2 { for p in sorted { append(&hull,p) }; return hull }
	for p in sorted {
		for len(hull)>=2 && vcross(vsub(hull[len(hull)-1],hull[len(hull)-2]),vsub(p,hull[len(hull)-1]))<=0 { resize(&hull,len(hull)-1) }
		append(&hull,p)
	}
	upper_start:=len(hull)+1
	for i:=len(sorted)-2; i>=0; i-=1 {
		p:=sorted[i]
		for len(hull)>=upper_start && vcross(vsub(hull[len(hull)-1],hull[len(hull)-2]),vsub(p,hull[len(hull)-1]))<=0 { resize(&hull,len(hull)-1) }
		append(&hull,p)
	}
	resize(&hull,len(hull)-1)
	return hull
}
// Same monotone chain and sort as convex_hull, with caller-owned storage.
convex_hull_into :: proc(points,sorted_storage,hull:[]Vec2) -> []Vec2 {
 sorted:=sorted_storage[:len(points)]; copy(sorted,points)
 slice.sort_by(sorted,proc(a,b:Vec2)->bool { return a.x<b.x || a.x==b.x && a.y<b.y })
 count:=0
 if len(sorted)<2 { copy(hull,sorted); return hull[:len(sorted)] }
 for p in sorted {
  for count>=2 && vcross(vsub(hull[count-1],hull[count-2]),vsub(p,hull[count-1]))<=0 { count-=1 }
  hull[count]=p; count+=1
 }
 upper:=count+1
 for i:=len(sorted)-2; i>=0; i-=1 { p:=sorted[i]
  for count>=upper && vcross(vsub(hull[count-1],hull[count-2]),vsub(p,hull[count-1]))<=0 { count-=1 }
  hull[count]=p; count+=1
 }
 return hull[:count-1]
}
segment_overlap :: proc(a,b: Segment) -> (Segment,bool) {
	d := vsub(a.b,a.a)
	length := vlen(d)
	if length < 0.00001 { return {},false }
	if math.abs(vcross(d,vsub(b.a,a.a))) > 0.0001*length || math.abs(vcross(d,vsub(b.b,a.a))) > 0.0001*length { return {},false }
	unit := vmul(d,1/length)
	t0,t1 := vdot(vsub(b.a,a.a),unit),vdot(vsub(b.b,a.a),unit)
	lo,hi := max(f32(0),min(t0,t1)),min(length,max(t0,t1))
	if hi-lo <= 0.0001 { return {},false }
	return Segment{vadd(a.a,vmul(unit,lo)),vadd(a.a,vmul(unit,hi))},true
}
shared_segments :: proc(a,b: Polygon) -> [dynamic]Segment {
	result: [dynamic]Segment
	for i in 0..<len(a.points) {
		for j in 0..<len(b.points) {
			if segment,ok := segment_overlap(Segment{a.points[i],a.points[(i+1)%len(a.points)]},Segment{b.points[j],b.points[(j+1)%len(b.points)]}); ok { append(&result,segment) }
		}
	}
	return result
}
inherits_old_boundary :: proc(a,b,old_a,old_b: Polygon,known: []Segment = nil,known_current: []Segment = nil) -> bool {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(14,started); if blast_profile!=nil { blast_profile.counts[4]+=1 } }

 current:=known_current
 current_owned:[dynamic]Segment; defer delete(current_owned)
 if current==nil { current_owned=shared_segments(a,b); current=current_owned[:] }
	original := known
 owned:[dynamic]Segment; defer delete(owned)
 if original==nil { owned=shared_segments(old_a,old_b); original=owned[:] }
	for x in current { for y in original { if _,ok := segment_overlap(x,y); ok { return true } } }
	return false
}
insert_polygon_vertex :: proc(p: ^Polygon,index: int,point: Vec2) {
	points:=make([]Vec2,len(p.points)+1)
	copy(points[:index],p.points[:index]); points[index]=point
	copy(points[index+1:],p.points[index:])
	delete(p.points); p.points=points
}
insert_boundary_endpoint :: proc(p: ^Polygon,point: Vec2) {
	for existing in p.points { if vlen(vsub(existing,point)) < 0.00001 { return } }
	for i in 0..<len(p.points) {
		a,b := p.points[i],p.points[(i+1)%len(p.points)]
		edge := vsub(b,a)
		length := vlen(edge)
		if length < 0.00001 { continue }
		t := vdot(vsub(point,a),edge)/(length*length)
		if t > 0 && t < 1 && math.abs(vcross(edge,vsub(point,a))) < 0.00001*length { insert_polygon_vertex(p,i+1,point); return }
	}
}
insert_shared_midpoint :: proc(p: ^Polygon,segment: Segment,point: Vec2) {
	insert_boundary_endpoint(p,segment.a)
	insert_boundary_endpoint(p,segment.b)
	for i in 0..<len(p.points) {
		a,b := p.points[i],p.points[(i+1)%len(p.points)]
		if (vlen(vsub(a,segment.a)) < 0.00001 && vlen(vsub(b,segment.b)) < 0.00001) || (vlen(vsub(b,segment.a)) < 0.00001 && vlen(vsub(a,segment.b)) < 0.00001) {
			insert_polygon_vertex(p,i+1,point)
			return
		}
	}
}
// Capture each common cut once, then install the exact same displaced midpoint
// in both outlines. Parent boundary vertices are untouched, including T junctions.
displace_shared_boundaries :: proc(children: []Polygon,seed: u8,minimum_width: f32 = 0,grained: bool = false) {
	boundaries: [dynamic]Cut_Boundary
	defer delete(boundaries)
	for i in 0..<len(children) {
		for j in i+1..<len(children) {
			segments := shared_segments(children[i],children[j])
			for segment in segments { append(&boundaries,Cut_Boundary{i,j,segment}) }
			delete(segments)
		}
	}
	for boundary,index in boundaries {
  if grained && displace_grained_seam(children,boundary,seed,index,minimum_width) { continue }
		edge := vsub(boundary.segment.b,boundary.segment.a)
		length := vlen(edge)
		normal := Vec2{-edge.y/length,edge.x/length}
		amplitude := min(length*0.04,min(polygon_area(children[boundary.a]),polygon_area(children[boundary.b]))/length*0.08)
		base := vmul(vadd(boundary.segment.a,boundary.segment.b),0.5)
		// The area cap alone can cross another edge in thin or concave children.
		// Bound displacement by clearance, as in the reference partition generator.
		neighbors := [2]int{boundary.a,boundary.b}
		for index in neighbors {
			polygon := children[index]
			for a,i in polygon.points {
				b := polygon.points[(i+1)%len(polygon.points)]
				edge := vsub(b,a)
				if vdot(edge,edge)<0.000000000001 { continue }
				if _,shared := segment_overlap(Segment{a,b},boundary.segment); shared { continue }
				t := clamp(vdot(vsub(base,a),edge)/vdot(edge,edge),f32(0),f32(1))
				amplitude=min(amplitude,vlen(vsub(base,vadd(a,vmul(edge,t))))*0.2)
			}
		}
		if derive_seed(seed,u64(index+1))%2 == 0 { amplitude = -amplitude }
  // Test both complete outlines, including endpoint touches. Shallow bends
  // may approach a concave edge; reduce only this seam before giving it up.
  for attempt in 0..<4 {
   mid:=vadd(base,vmul(normal,amplitude))
   left,right:=make_polygon(children[boundary.a].points),make_polygon(children[boundary.b].points)
   insert_shared_midpoint(&left,boundary.segment,mid); insert_shared_midpoint(&right,boundary.segment,mid)
   valid:=simple_polygon(left) && simple_polygon(right) && outline_width(left.points)>=minimum_width && outline_width(right.points)>=minimum_width
   if valid {
    delete(children[boundary.a].points); delete(children[boundary.b].points)
    children[boundary.a]=left; children[boundary.b]=right
    break
   }
   delete(left.points); delete(right.points); amplitude*=0.5
  }
	}
}

// Merge adjacent triangles whenever their union is convex. In particular this
// avoids feeding thin ears from a displaced boundary to Box2D as tiny fixtures.
convex_decomposition :: proc(outline: Polygon) -> [dynamic]Polygon {
	parts:=triangulate_polygon(outline)
	for {
		merged:=false
		for i in 0..<len(parts) {
			for j in i+1..<len(parts) {
				if !inheritance_bounds_overlap(parts[i],parts[j]) { continue }
				if length,_:=shared_boundary(parts[i],parts[j]); length<=0 { continue }
				points: [dynamic]Vec2
				for point in parts[i].points { append(&points,point) }
				for point in parts[j].points { append(&points,point) }
				hull:=convex_hull(points[:]); delete(points)
				combined:=make_polygon(hull[:]); delete(hull)
				error:=math.abs(polygon_area(combined)-polygon_area(parts[i])-polygon_area(parts[j]))
				if len(combined.points)<=8 && error<0.000001 {
					delete(parts[i].points); delete(parts[j].points)
					parts[i]=combined; ordered_remove(&parts,j); merged=true; break
				}
				delete(combined.points)
			}
			if merged { break }
		}
		if !merged { break }
	}
	return parts
}

// Local double-precision predicates distinguish real crossings from f32
// cancellation at translated, nearly collinear seam vertices.
polygon_turn :: proc(a,b,c: Vec2) -> f64 {
 return (f64(b.x)-f64(a.x))*(f64(c.y)-f64(a.y))-(f64(b.y)-f64(a.y))*(f64(c.x)-f64(a.x))
}
segments_touch :: proc(a,b,c,d: Vec2,tolerance: f64) -> bool {
 ab_c,ab_d:=polygon_turn(a,b,c),polygon_turn(a,b,d)
 cd_a,cd_b:=polygon_turn(c,d,a),polygon_turn(c,d,b)
 if (ab_c>0 && ab_d<0 || ab_c<0 && ab_d>0) && (cd_a>0 && cd_b<0 || cd_a<0 && cd_b>0) { return true }
 pairs:=[4][3]Vec2{{a,b,c},{a,b,d},{c,d,a},{c,d,b}}
 for pair in pairs {
  x,y,p:=pair[0],pair[1],pair[2]
  if math.abs(polygon_turn(x,y,p))<=tolerance*f64(vlen(vsub(y,x))) &&
     f64(p.x)>=f64(min(x.x,y.x))-tolerance && f64(p.x)<=f64(max(x.x,y.x))+tolerance &&
     f64(p.y)>=f64(min(x.y,y.y))-tolerance && f64(p.y)<=f64(max(x.y,y.y))+tolerance { return true }
 }
 return false
}
simple_polygon :: proc(p: Polygon) -> bool {
 if active_cover!=nil && !blast_scratch_active && len(p.points)>=12 { return blast_cached_simple(p) }
 return simple_polygon_uncached(p)
}
simple_polygon_uncached :: proc(p: Polygon) -> bool {
 if len(p.points)<3 { return false }
 tolerance:=f64(longest_dimension(p))*0.00000001
 for a,i in p.points {
  b:=p.points[(i+1)%len(p.points)]
  if f64(vlen(vsub(b,a)))<=tolerance { return false }
  for j in i+1..<len(p.points) {
   if j==i+1 || i==0 && j==len(p.points)-1 { continue }
   if segments_touch(a,b,p.points[j],p.points[(j+1)%len(p.points)],tolerance) { return false }
  }
 }
 return true
}
