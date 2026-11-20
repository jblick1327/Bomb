package main

import "core:math"

Segment :: struct { a,b: Vec2 }
Cut_Boundary :: struct { a,b: int, segment: Segment }
convex_hull :: proc(points: []Vec2) -> [dynamic]Vec2 {
	sorted: [dynamic]Vec2
	defer delete(sorted)
	for point in points { append(&sorted,point) }
	for i in 1..<len(sorted) {
		j:=i
		for j>0 && (sorted[j].x<sorted[j-1].x || (sorted[j].x==sorted[j-1].x && sorted[j].y<sorted[j-1].y)) { sorted[j],sorted[j-1]=sorted[j-1],sorted[j]; j-=1 }
	}
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
inherits_old_boundary :: proc(a,b,old_a,old_b: Polygon) -> bool {
	current := shared_segments(a,b)
	original := shared_segments(old_a,old_b)
	defer delete(current); defer delete(original)
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
displace_shared_boundaries :: proc(children: []Polygon,seed: u8) {
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
		edge := vsub(boundary.segment.b,boundary.segment.a)
		length := vlen(edge)
		normal := Vec2{-edge.y/length,edge.x/length}
		amplitude := min(length*0.04,min(polygon_area(children[boundary.a]),polygon_area(children[boundary.b]))/length*0.08)
		if derive_seed(seed,u64(index+1))%2 == 0 { amplitude = -amplitude }
		mid := vadd(vmul(vadd(boundary.segment.a,boundary.segment.b),0.5),vmul(normal,amplitude))
		insert_shared_midpoint(&children[boundary.a],boundary.segment,mid)
		insert_shared_midpoint(&children[boundary.b],boundary.segment,mid)
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
