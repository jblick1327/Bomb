#+feature dynamic-literals
package main

import "core:math"

Vec2 :: struct { x, y: f32 }
Polygon :: struct { points: []Vec2 }
Pose :: struct { position: Vec2, angle: f32, velocity: Vec2, angular_velocity: f32 }
Material :: struct {
	name: string,
	subdivision_strength, connection_strength: f32,
	flexibility: f32,
	generation_count: int,
	aspect_ratio: f32,
	triangulate: bool,
}
Subdivision :: struct {
	id, owner: u64,
	material: int,
	outline: Polygon,
	outline_start,outline_count: int `json:"-"`,
	rest_center: Vec2,
	pose: Pose,
	live: bool,
}
Connection :: struct {
	id, a, b: u64,
	rest_point, local_a, local_b: Vec2,
	live: bool,
}
Piece :: struct {
	id: u64,
	material: int,
	seed: u8,
	subdivisions, connections: [dynamic]u64,
	live: bool,
}
Remnant :: struct { subdivision: u64, pose: Pose, age: f32 }
Scene :: struct {
	physics: Physics,
	materials: [dynamic]Material,
	owned_names: [dynamic]string,
	subdivisions: [dynamic]Subdivision,
	vertices: [dynamic]Vec2,
	connections: [dynamic]Connection,
	pieces: [dynamic]Piece,
	remnants: [dynamic]Remnant,
	sub_rows, conn_rows, piece_rows: map[u64]int,
	next_id: u64,
	revision: u64,
	minimum_width: f32,
}
Blast :: struct { position: Vec2, radius: f32 }
Failures :: struct { subdivisions, connections, discard_subdivisions: [dynamic]u64 }

vadd :: proc(a, b: Vec2) -> Vec2 { return {a.x+b.x, a.y+b.y} }
vsub :: proc(a, b: Vec2) -> Vec2 { return {a.x-b.x, a.y-b.y} }
vmul :: proc(a: Vec2, s: f32) -> Vec2 { return {a.x*s, a.y*s} }
vdot :: proc(a, b: Vec2) -> f32 { return a.x*b.x+a.y*b.y }
vcross :: proc(a, b: Vec2) -> f32 { return a.x*b.y-a.y*b.x }
vlen :: proc(a: Vec2) -> f32 { return math.sqrt(vdot(a,a)) }
vrotate :: proc(a: Vec2, angle: f32) -> Vec2 {
	c, s := f32(math.cos(angle)), f32(math.sin(angle))
	return {a.x*c-a.y*s,a.x*s+a.y*c}
}
centroid :: proc(p: Polygon) -> Vec2 {
	area, x, y: f32
	for i in 0..<len(p.points) {
		a, b := p.points[i], p.points[(i+1)%len(p.points)]
		cross := vcross(a,b)
		area += cross
		x += (a.x+b.x)*cross
		y += (a.y+b.y)*cross
	}
	if math.abs(area) < 0.00001 {
		for point in p.points { x += point.x; y += point.y }
		return {x/f32(len(p.points)),y/f32(len(p.points))}
	}
	return {x/(3*area),y/(3*area)}
}
posed_point :: proc(sub: Subdivision, rest: Vec2) -> Vec2 {
	return vadd(sub.pose.position,vrotate(vsub(rest,sub.rest_center),sub.pose.angle))
}
posed_polygon :: proc(sub: Subdivision) -> Polygon {
	result := Polygon{points=make([]Vec2,len(sub.outline.points))}
	for point,i in sub.outline.points { result.points[i]=posed_point(sub,point) }
	return result
}
make_polygon :: proc(points: []Vec2) -> Polygon {
	result:=Polygon{points=make([]Vec2,len(points))}
	copy(result.points,points)
	return result
}
// Returns the common collinear edge length and its length-weighted midpoint.
shared_boundary :: proc(a, b: Polygon) -> (f32, Vec2) {
	total: f32
	weighted := Vec2{}
	for i in 0..<len(a.points) {
		p, q := a.points[i], a.points[(i+1)%len(a.points)]
		d := vsub(q,p)
		length := vlen(d)
		if length < 0.00001 { continue }
		unit := vmul(d,1/length)
		for j in 0..<len(b.points) {
			r, s := b.points[j], b.points[(j+1)%len(b.points)]
			if math.abs(vcross(d,vsub(r,p))) > 0.0001*length || math.abs(vcross(d,vsub(s,p))) > 0.0001*length { continue }
			t0, t1 := vdot(vsub(r,p),unit), vdot(vsub(s,p),unit)
			lo := max(f32(0),min(t0,t1))
			hi := min(length,max(t0,t1))
			if hi-lo > 0.0001 {
				span := hi-lo
				total += span
				weighted = vadd(weighted,vmul(vadd(p,vmul(unit,(lo+hi)*0.5)),span))
			}
		}
	}
	if total == 0 { return 0, {} }
	return total,vmul(weighted,1/total)
}
new_id :: proc(s: ^Scene) -> u64 { s.next_id += 1; return s.next_id }
new_scene :: proc(minimum_width: f32) -> Scene {
	return Scene{sub_rows=make(map[u64]int),conn_rows=make(map[u64]int),piece_rows=make(map[u64]int),minimum_width=minimum_width}
}
add_material :: proc(s: ^Scene, m: Material) -> int { append(&s.materials,m); return len(s.materials)-1 }
add_piece :: proc(s: ^Scene, material: int, seed: u8) -> u64 {
	id := new_id(s)
	s.piece_rows[id] = len(s.pieces)
	append(&s.pieces,Piece{id=id,material=material,seed=seed,live=true})
	return id
}
add_subdivision :: proc(s: ^Scene, owner: u64, outline: Polygon, pose: Pose) -> u64 {
	id := new_id(s)
	retain_subdivision(s,Subdivision{id=id,owner=owner,material=s.pieces[s.piece_rows[owner]].material,outline=outline,pose=pose,live=true})
	return id
}
// Outlines use ranges in one append-only undeformed vertex pool. The outline
// slice is a derived read view, refreshed whenever appending can move the pool.
// Callers may release their source polygon immediately after this call.
retain_subdivision :: proc(s: ^Scene,source: Subdivision) {
	sub:=source
	points:=make_polygon(source.outline.points)
	defer delete(points.points)
	sub.rest_center=centroid(points)
	sub.outline_start=len(s.vertices); sub.outline_count=len(points.points)
	for point in points.points { append(&s.vertices,point) }
	for i in 0..<len(s.subdivisions) {
		existing:=&s.subdivisions[i]
		existing.outline.points=s.vertices[existing.outline_start:existing.outline_start+existing.outline_count]
	}
	sub.outline.points=s.vertices[sub.outline_start:sub.outline_start+sub.outline_count]
	s.sub_rows[sub.id]=len(s.subdivisions)
	append(&s.subdivisions,sub)
}
add_connection :: proc(s: ^Scene, a, b: u64) -> u64 {
	if a == b { return 0 }
	for c in s.connections { if c.live && ((c.a == a && c.b == b) || (c.a == b && c.b == a)) { return c.id } }
	sa, sb := s.subdivisions[s.sub_rows[a]],s.subdivisions[s.sub_rows[b]]
	length, point := shared_boundary(sa.outline,sb.outline)
	if length <= 0 { return 0 }
	id := new_id(s)
	s.conn_rows[id] = len(s.connections)
	append(&s.connections,Connection{id=id,a=a,b=b,rest_point=point,local_a=vsub(point,sa.rest_center),local_b=vsub(point,sb.rest_center),live=true})
	return id
}
connection_sample :: proc(s: ^Scene, c: Connection) -> Vec2 {
	a,b := s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
	return vmul(vadd(vadd(a.pose.position,vrotate(c.local_a,a.pose.angle)),vadd(b.pose.position,vrotate(c.local_b,b.pose.angle))),0.5)
}
subdivision_sample :: proc(sub: Subdivision) -> Vec2 { return sub.pose.position }
contains_id :: proc(ids: []u64,id: u64) -> bool { for x in ids { if x == id { return true } }; return false }
sort_ids :: proc(ids: []u64) {
	for i in 1..<len(ids) {
		j := i
		for j > 0 && ids[j] < ids[j-1] { ids[j],ids[j-1] = ids[j-1],ids[j]; j -= 1 }
	}
}
sorted_ids :: proc(ids: []u64) -> [dynamic]u64 {
	result: [dynamic]u64
	for id in ids { if !contains_id(result[:],id) { append(&result,id) } }
	sort_ids(result[:])
	return result
}
derive_seed :: proc(seed: u8, identity: u64) -> u8 {
	if seed == 0 { return 0 }
	x := identity ~ (u64(seed)*0x9e3779b97f4a7c15)
	x ~= x >> 30; x *= 0xbf58476d1ce4e5b9
	x ~= x >> 27; x *= 0x94d049bb133111eb
	x ~= x >> 31
	return u8(x%255+1)
}
piece_width :: proc(s: ^Scene, ids: []u64) -> f32 {
	if len(ids) == 0 { return 0 }
	points: [dynamic]Vec2
	defer delete(points)
	for id in ids { for point in s.subdivisions[s.sub_rows[id]].outline.points { append(&points,point) } }
	hull:=convex_hull(points[:])
	defer delete(hull)
	if len(hull)<3 { return 0 }
	width := f32(1e30)
	for i in 0..<len(hull) {
		edge:=vsub(hull[(i+1)%len(hull)],hull[i]); length:=vlen(edge)
		if length<0.00001 { continue }
		normal:=Vec2{-edge.y/length,edge.x/length}
		lo,hi:=f32(1e30),f32(-1e30)
		for point in hull { projection:=vdot(point,normal); lo=min(lo,projection); hi=max(hi,projection) }
		width=min(width,hi-lo)
	}
	return width
}
rebuild_piece :: proc(s: ^Scene, old_id: u64) {
	old_row, ok := s.piece_rows[old_id]
	if !ok || !s.pieces[old_row].live { return }
	old_seed := s.pieces[old_row].seed
	material := s.pieces[old_row].material
	groups: [dynamic][dynamic]u64
	visited := make(map[u64]bool)
	adjacency:=make(map[u64][dynamic]u64)
	defer delete(visited)
	defer { for _,neighbors in adjacency { delete(neighbors) }; delete(adjacency) }
	for c in s.connections {
		if !c.live { continue }
		a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
		if !a.live || !b.live || a.owner!=old_id || b.owner!=old_id { continue }
		left,right:=adjacency[c.a],adjacency[c.b]
		append(&left,c.b); append(&right,c.a)
		adjacency[c.a]=left; adjacency[c.b]=right
	}
	defer {
		for group in groups { delete(group) }
		delete(groups)
	}
	// Find the lowest unvisited ID each time, independent of storage order.
	for {
		start := u64(0)
		for sub in s.subdivisions {
			if sub.live && sub.owner == old_id && !visited[sub.id] && (start == 0 || sub.id < start) { start = sub.id }
		}
		if start == 0 { break }
		group: [dynamic]u64
		queue := [dynamic]u64{start}
		visited[start] = true
		for head := 0; head < len(queue); head += 1 {
			id := queue[head]
			append(&group,id)
			neighbors:=adjacency[id]
			for other in neighbors {
				if !visited[other] {
					visited[other] = true; append(&queue,other)
				}
			}
		}
		delete(queue)
		sort_ids(group[:])
		append(&groups,group)
	}
	s.pieces[old_row].live = false
	for group in groups {
		min_id := group[0]
		for id in group { min_id = min(min_id,id) }
		if piece_width(s,group[:]) < s.minimum_width {
			for id in group {
				row := s.sub_rows[id]
				append(&s.remnants,Remnant{subdivision=id,pose=s.subdivisions[row].pose})
				s.subdivisions[row].live = false
			}
			continue
		}
		new_owner := add_piece(s,material,derive_seed(old_seed,min_id))
		for id in group {
			s.subdivisions[s.sub_rows[id]].owner = new_owner
			append(&s.pieces[s.piece_rows[new_owner]].subdivisions,id)
		}
		for c in s.connections {
			if c.live && contains_id(group[:],c.a) && contains_id(group[:],c.b) { append(&s.pieces[s.piece_rows[new_owner]].connections,c.id) }
		}
		sort_ids(s.pieces[s.piece_rows[new_owner]].connections[:])
	}
	for i in 0..<len(s.connections) {
		c := &s.connections[i]
		if c.live && (!s.subdivisions[s.sub_rows[c.a]].live || !s.subdivisions[s.sub_rows[c.b]].live) { c.live = false }
	}
}

make_wall :: proc(seed: u8 = 0, minimum_width: f32 = 0) -> Scene {
	s := new_scene(minimum_width)
	m := add_material(&s,Material{name="brick",subdivision_strength=6,connection_strength=4,flexibility=0.25,generation_count=2,aspect_ratio=1.5})
	p := add_piece(&s,m,seed)
	ids: [3]u64
	for i in 0..<3 {
		x := f32(i)
		poly := make_polygon([]Vec2{{x,0},{x+1,0},{x+1,1},{x,1}})
		center := centroid(poly)
		ids[i] = add_subdivision(&s,p,poly,Pose{position=center})
		delete(poly.points)
	}
	add_connection(&s,ids[0],ids[1]); add_connection(&s,ids[1],ids[2])
	for id in ids { append(&s.pieces[s.piece_rows[p]].subdivisions,id) }
	for c in s.connections { append(&s.pieces[s.piece_rows[p]].connections,c.id) }
	return s
}

scene_destroy :: proc(s: ^Scene) {
	physics_destroy(s)
	delete(s.vertices)
	for p in s.pieces { delete(p.subdivisions); delete(p.connections) }
	delete(s.subdivisions); delete(s.connections); delete(s.pieces)
	delete(s.materials); delete(s.remnants)
	for name in s.owned_names { delete(name) }
	delete(s.owned_names)
	delete(s.sub_rows); delete(s.conn_rows); delete(s.piece_rows)
	s^ = {}
}
