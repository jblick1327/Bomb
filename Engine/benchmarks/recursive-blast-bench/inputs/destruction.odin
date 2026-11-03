#+feature dynamic-literals
package main

import "core:math"

polygon_area :: proc(p: Polygon) -> f32 {
	a: f32
	for i in 0..<len(p.points) { a += vcross(p.points[i],p.points[(i+1)%len(p.points)]) }
	return math.abs(a)*0.5
}
clip_polygon :: proc(p: Polygon, axis: int, cut: f32, keep_low: bool) -> Polygon {
	points: [dynamic]Vec2
	defer delete(points)
	for i in 0..<len(p.points) {
		a,b := p.points[i],p.points[(i+1)%len(p.points)]
		av,bv := a.x-cut,b.x-cut
		if axis == 1 { av = a.y-cut; bv = b.y-cut }
		if !keep_low { av = -av; bv = -bv }
		inside_a, inside_b := av <= 0.00001,bv <= 0.00001
		if inside_a { append(&points,a) }
		if inside_a != inside_b {
			t := av/(av-bv)
			append(&points,vadd(a,vmul(vsub(b,a),t)))
		}
	}
	return make_polygon(points[:])
}
is_convex :: proc(p: Polygon) -> bool {
	if len(p.points) < 3 { return false }
	sign: f32
	for i in 0..<len(p.points) {
		cross := vcross(vsub(p.points[(i+1)%len(p.points)],p.points[i]),vsub(p.points[(i+2)%len(p.points)],p.points[(i+1)%len(p.points)]))
		if math.abs(cross) < 0.00001 { continue }
		if sign == 0 { sign = cross } else if cross*sign < 0 { return false }
	}
	return true
}
point_in_triangle :: proc(p,a,b,c: Vec2, orientation: f32) -> bool {
	return vcross(vsub(b,a),vsub(p,a))*orientation >= -0.00001 &&
	       vcross(vsub(c,b),vsub(p,b))*orientation >= -0.00001 &&
	       vcross(vsub(a,c),vsub(p,c))*orientation >= -0.00001
}
triangulate_polygon :: proc(p: Polygon) -> [dynamic]Polygon {
	result: [dynamic]Polygon
	indices: [dynamic]int
	defer delete(indices)
	for i in 0..<len(p.points) { append(&indices,i) }
	signed: f32
	for i in 0..<len(p.points) { signed += vcross(p.points[i],p.points[(i+1)%len(p.points)]) }
	orientation := f32(1)
	if signed < 0 { orientation = -1 }
	for len(indices) > 3 {
		found := false
		for k in 0..<len(indices) {
			i,j,l := indices[(k+len(indices)-1)%len(indices)],indices[k],indices[(k+1)%len(indices)]
			a,b,c := p.points[i],p.points[j],p.points[l]
			if vcross(vsub(b,a),vsub(c,b))*orientation <= 0.00001 { continue }
			contains := false
			for n in indices { if n != i && n != j && n != l && point_in_triangle(p.points[n],a,b,c,orientation) { contains = true; break } }
			if contains { continue }
			append(&result,make_polygon([]Vec2{a,b,c}))
			ordered_remove(&indices,k)
			found = true
			break
		}
		if !found { break }
	}
	if len(indices) == 3 { append(&result,make_polygon([]Vec2{p.points[indices[0]],p.points[indices[1]],p.points[indices[2]]})) }
	return result
}
// Straight shared cuts are constructed by clipping both sides at one value.
// Outside edges are never moved; no gap or overlap is introduced at the cut.
generate_children :: proc(parent: Polygon, recipe: Material, seed: u8) -> [dynamic]Polygon {
	result: [dynamic]Polygon
	if seed == 0 { return result }
	if !is_convex(parent) || recipe.triangulate { result = triangulate_polygon(parent) } else {
		append(&result,make_polygon(parent.points))
	}
	target := max(recipe.generation_count,len(result))
	for len(result) < target {
		chosen := -1
		largest: f32
		for p,i in result { a := polygon_area(p); if a > largest { largest = a; chosen = i } }
		if chosen < 0 || largest < 0.0001 { break }
		p := result[chosen]
		min_x,min_y := f32(1e30),f32(1e30)
		max_x,max_y := f32(-1e30),f32(-1e30)
		for point in p.points { min_x=min(min_x,point.x); max_x=max(max_x,point.x); min_y=min(min_y,point.y); max_y=max(max_y,point.y) }
		axis := 0
		if (max_x-min_x) < (max_y-min_y)*max(recipe.aspect_ratio,0.1) { axis = 1 }
		fraction := 0.4+0.2*f32(derive_seed(seed,u64(len(result))))/255
		cut := min_x+(max_x-min_x)*fraction
		if axis == 1 { cut = min_y+(max_y-min_y)*fraction }
		low, high := clip_polygon(p,axis,cut,true),clip_polygon(p,axis,cut,false)
		if polygon_area(low) < 0.0001 || polygon_area(high) < 0.0001 { delete(low.points); delete(high.points); break }
		delete(p.points)
		result[chosen] = low
		append(&result,high)
	}
	displace_shared_boundaries(result[:],seed)
	if recipe.triangulate {
		triangles: [dynamic]Polygon
		for polygon in result {
			parts:=triangulate_polygon(polygon)
			for part in parts { append(&triangles,part) }
			delete(parts); delete(polygon.points)
		}
		delete(result)
		result=triangles
	}
	return result
}

apply_failures :: proc(s: ^Scene, failures: Failures) {
	if len(failures.subdivisions) == 0 && len(failures.connections) == 0 && len(failures.discard_subdivisions) == 0 { return }
	s.revision+=1
	affected := make(map[u64]bool)
	replacements := make(map[u64][dynamic]u64)
	defer delete(affected)
	defer { for _,children in replacements { delete(children) }; delete(replacements) }
	failed_subs := sorted_ids(failures.subdivisions[:])
	for id in failures.discard_subdivisions { if !contains_id(failed_subs[:],id) { append(&failed_subs,id) } }
	sort_ids(failed_subs[:])
	failed_conns := sorted_ids(failures.connections[:])
	defer delete(failed_subs); defer delete(failed_conns)
	old_connection_count := len(s.connections)
	old_connections: [dynamic]u64
	defer delete(old_connections)
	for i in 0..<old_connection_count { append(&old_connections,s.connections[i].id) }
	sort_ids(old_connections[:])
	for id in failed_subs {
		row, ok := s.sub_rows[id]
		if !ok || !s.subdivisions[row].live { continue }
		parent := s.subdivisions[row]
		affected[parent.owner] = true
		seed := s.pieces[s.piece_rows[parent.owner]].seed
		if contains_id(failures.discard_subdivisions[:],id) { seed=0 }
		children := generate_children(parent.outline,s.materials[parent.material],seed)
		for outline in children {
			center := centroid(outline)
			world_center := posed_point(parent,center)
			r := vsub(world_center,parent.pose.position)
			pose := Pose{position=world_center,angle=parent.pose.angle,velocity=vadd(parent.pose.velocity,Vec2{-parent.pose.angular_velocity*r.y,parent.pose.angular_velocity*r.x}),angular_velocity=parent.pose.angular_velocity}
			child := add_subdivision(s,parent.owner,outline,pose)
			delete(outline.points)
			child_ids := replacements[id]
			append(&child_ids,child)
			replacements[id] = child_ids
		}
		delete(children)
		s.subdivisions[row].live = false
	}
	for id in failed_conns {
		row, ok := s.conn_rows[id]
		if ok && s.connections[row].live {
			c := s.connections[row]
			affected[s.subdivisions[s.sub_rows[c.a]].owner] = true
			affected[s.subdivisions[s.sub_rows[c.b]].owner] = true
			s.connections[row].live = false
		}
	}
	for old_id in old_connections {
		i := s.conn_rows[old_id]
		c := s.connections[i]
		if !c.live { continue }
		a_dead := !s.subdivisions[s.sub_rows[c.a]].live
		b_dead := !s.subdivisions[s.sub_rows[c.b]].live
		if !a_dead && !b_dead { continue }
		s.connections[i].live = false
		left_default,right_default := [1]u64{c.a},[1]u64{c.b}
		left,right := left_default[:],right_default[:]
		if a_dead { left = replacements[c.a][:] }
		if b_dead { right = replacements[c.b][:] }
		old_a,old_b := s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
		old_length,_ := shared_boundary(old_a.outline,old_b.outline)
		if old_length <= 0 { continue }
		for a in left {
			for b in right {
				if inherits_old_boundary(s.subdivisions[s.sub_rows[a]].outline,s.subdivisions[s.sub_rows[b]].outline,old_a.outline,old_b.outline) { add_connection(s,a,b) }
			}
		}
	}
	for id in failed_subs {
		children := replacements[id]
		for i in 0..<len(children) { for j in i+1..<len(children) { add_connection(s,children[i],children[j]) } }
	}
	owners: [dynamic]u64
	defer delete(owners)
	for owner in affected { append(&owners,owner) }
	sort_ids(owners[:])
	for owner in owners { rebuild_piece(s,owner) }
}

BLAST_MAX_LOAD :: f32(10)
BLAST_IMPULSE_SCALE :: f32(0.1)
blast_load :: proc(distance,radius: f32) -> f32 {
	if radius <= 0 || distance >= radius { return 0 }
	return BLAST_MAX_LOAD*(1-distance/radius)
}
fails :: proc(load,strength: f32) -> bool { return load > 0 && load >= strength }
evaluate_blast :: proc(s: ^Scene, blast: Blast) -> Failures {
	f := Failures{}
	for i in 0..<len(s.subdivisions) {
		sub := &s.subdivisions[i]
		if !sub.live { continue }
		offset := vsub(subdivision_sample(sub^),blast.position)
		distance := vlen(offset)
		load := blast_load(distance,blast.radius)
		if load <= 0 { continue }
		if distance > 0.00001 { apply_blast_motion(s,sub,vmul(offset,1/distance),load) }
		if fails(load,s.materials[sub.material].subdivision_strength) { append(&f.subdivisions,sub.id) }
	}
	for c in s.connections {
		if !c.live { continue }
		a := s.subdivisions[s.sub_rows[c.a]]
		load := blast_load(vlen(vsub(connection_sample(s,c),blast.position)),blast.radius)
		if fails(load,s.materials[a.material].connection_strength) { append(&f.connections,c.id) }
	}
	return f
}
blast_pass :: proc(s: ^Scene, blast: Blast) {
	physics_read_motion(s)
	f := evaluate_blast(s,blast)
	apply_failures(s,f)
	delete(f.subdivisions); delete(f.connections)
	physics_sync_structure(s)
}
fade_step :: proc(s: ^Scene, dt: f32) {
	for i := len(s.remnants)-1; i >= 0; i -= 1 {
		s.remnants[i].age += dt
		if s.remnants[i].age >= 1 { ordered_remove(&s.remnants,i) }
	}
}
