#+feature dynamic-literals
package main

import "core:math"
import "core:slice"
import b2 "vendor:box2d"

Vec2 :: struct { x, y: f32 }
Polygon :: struct { points: []Vec2 }
Pose :: struct { position: Vec2, angle: f32, velocity: Vec2, angular_velocity: f32 }
// Procedural materials use this helper; the fixed palette explicitly lists every field.
make_material :: proc(name: string = "", subdivision_strength: f32 = 0, connection_strength: f32 = 0,
                      flexibility: f32 = 0, generation_count: int = 1, aspect_ratio: f32 = 1,
                      triangulate: bool = false, impact_scale: f32 = 1) -> Material {
 return Material{name=name,subdivision_strength=subdivision_strength,connection_strength=connection_strength,
                 flexibility=flexibility,generation_count=generation_count,aspect_ratio=aspect_ratio,
                 triangulate=triangulate,impact_scale=impact_scale}
}
Material :: struct {
	name: string,
	subdivision_strength, connection_strength: f32,
	flexibility: f32,
	impact_scale: f32, // Constructors use 1; zero explicitly disables physical damage.
	generation_count: int,
	aspect_ratio: f32,
	triangulate: bool,
}
Subdivision :: struct {
	id, owner: u64,
	material: int,
	seed: u8,
	outline: Polygon,
	body: b2.BodyId `json:"-"`,
	fixture_count: int `json:"-"`,
	shapes: [dynamic]b2.ShapeId `json:"-"`,
	render: Render_Cache `json:"-"`,
	incident_links: [dynamic]u64 `json:"-"`,
	width: f32 `json:"-"`,
	rest_center: Vec2,
	pose: Pose,
	live: bool,
}
Connection :: struct {
	id, a, b: u64,
	rest_point, local_a, local_b: Vec2,
	joint: b2.JointId `json:"-"`,
	live: bool,
}
Piece :: struct {
	id: u64,
	material: int,
	seed: u8,
	subdivisions, connections: [dynamic]u64,
	render_revision: u64 `json:"-"`,
	mass: f32 `json:"-"`,
	body: b2.BodyId `json:"-"`, // Owned here for rigid pieces; regions alias it.
	physics_revision: u64 `json:"-"`,
	body_frame: b2.Transform `json:"-"`,
	source_body: b2.BodyId `json:"-"`,
	has_body_frame: bool `json:"-"`,
	live: bool,
}
Endpoint_Pair :: struct { a,b: u64 }
pair_key :: proc(a,b: u64) -> Endpoint_Pair { return {min(a,b),max(a,b)} }
Scene :: struct {
	physics: Physics,
	materials: [dynamic]Material,
	owned_names: [dynamic]string,
	subdivisions: [dynamic]Subdivision,
	connections: [dynamic]Connection,
	pieces: [dynamic]Piece,
	sub_rows, conn_rows, piece_rows: map[u64]int,
	connection_pairs: map[Endpoint_Pair]u64,
	structure_revision: u64,
 static_render_revision,static_render_signature: u64 `json:"-"`,
	pending_regions: [dynamic]u64,
	next_id: u64,
	revision: u64,
	minimum_width: f32,
}
Blast :: struct { position: Vec2, radius: f32 }
Failures :: struct { subdivisions, connections, discard_subdivisions: [dynamic]u64, impact: bool }

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
	return Scene{sub_rows=make(map[u64]int),conn_rows=make(map[u64]int),piece_rows=make(map[u64]int),connection_pairs=make(map[Endpoint_Pair]u64),minimum_width=minimum_width}
}
add_material :: proc(s: ^Scene, m: Material) -> int { append(&s.materials,m); return len(s.materials)-1 }
add_piece :: proc(s: ^Scene, material: int, seed: u8) -> u64 {
	id := new_id(s)
	s.piece_rows[id] = len(s.pieces)
	append(&s.pieces,Piece{id=id,material=material,seed=seed,live=true})
	s.structure_revision+=1
	return id
}
add_subdivision :: proc(s: ^Scene, owner: u64, outline: Polygon, pose: Pose) -> u64 {
	id := new_id(s)
	piece := s.pieces[s.piece_rows[owner]]
	retain_subdivision(s,Subdivision{id=id,owner=owner,material=piece.material,seed=piece.seed,outline=outline,pose=pose,live=true})
	append(&s.pieces[s.piece_rows[owner]].subdivisions,id)
	s.pieces[s.piece_rows[owner]].mass+=polygon_area(outline)
	s.pieces[s.piece_rows[owner]].render_revision+=1
	return id
}
// Each record owns its undeformed outline; staging may read dead parents until commit.
retain_subdivision :: proc(s: ^Scene,source: Subdivision) {
	sub:=source
	sub.outline=make_polygon(source.outline.points)
	sub.rest_center=centroid(sub.outline)
	sub.width=outline_width(sub.outline.points)
	sub.body={}; sub.fixture_count=0; sub.shapes=nil; sub.render={}; sub.incident_links=nil
	s.sub_rows[sub.id]=len(s.subdivisions)
	append(&s.subdivisions,sub)
	append(&s.pending_regions,sub.id)
	s.structure_revision+=1
}
add_connection :: proc(s: ^Scene, a, b: u64) -> u64 {
	if a == b { return 0 }
	if id,ok:=s.connection_pairs[pair_key(a,b)]; ok { if s.connections[s.conn_rows[id]].live { return id } }
	sa, sb := s.subdivisions[s.sub_rows[a]],s.subdivisions[s.sub_rows[b]]
	length, point := shared_boundary(sa.outline,sb.outline)
	if length <= 0 { return 0 }
	id := new_id(s)
	s.conn_rows[id] = len(s.connections)
	append(&s.connections,Connection{id=id,a=a,b=b,rest_point=point,local_a=vsub(point,sa.rest_center),local_b=vsub(point,sb.rest_center),live=true})
	s.connection_pairs[pair_key(a,b)]=id
	append(&s.subdivisions[s.sub_rows[a]].incident_links,id)
	append(&s.subdivisions[s.sub_rows[b]].incident_links,id)
	append(&s.pieces[s.piece_rows[sa.owner]].connections,id)
	s.pieces[s.piece_rows[sa.owner]].render_revision+=1
	s.structure_revision+=1
	return id
}
connection_sample :: proc(s: ^Scene, c: Connection) -> Vec2 {
	a,b := s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
	return vmul(vadd(vadd(a.pose.position,vrotate(c.local_a,a.pose.angle)),vadd(b.pose.position,vrotate(c.local_b,b.pose.angle))),0.5)
}
subdivision_sample :: proc(sub: Subdivision) -> Vec2 { return sub.pose.position }
contains_id :: proc(ids: []u64,id: u64) -> bool { for x in ids { if x == id { return true } }; return false }
sort_ids :: proc(ids: []u64) { slice.sort(ids) }
sorted_ids :: proc(ids: []u64) -> [dynamic]u64 {
	result: [dynamic]u64
	for id in ids { append(&result,id) }
	sort_ids(result[:])
	count:=0
	for id in result { if count==0 || id!=result[count-1] { result[count]=id; count+=1 } }
	resize(&result,count)
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
	return outline_width(points[:])
}
outline_width :: proc(points: []Vec2) -> f32 {
	hull:=convex_hull(points)
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
	old:=s.pieces[old_row]
	visited:=make(map[u64]bool)
	adjacency:=make(map[u64][dynamic]u64)
	defer delete(visited)
	defer { for _,neighbors in adjacency { delete(neighbors) }; delete(adjacency) }
	for id in old.connections {
		c:=s.connections[s.conn_rows[id]]
		if !c.live { continue }
		a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
		if !a.live || !b.live { continue }
		left,right:=adjacency[c.a],adjacency[c.b]
		append(&left,c.b); append(&right,c.a)
		adjacency[c.a]=left; adjacency[c.b]=right
	}
	ids:=sorted_ids(old.subdivisions[:]); defer delete(ids)
	s.pieces[old_row].live=false
	// Preserve the exact engine transform across multiple staged regroupings,
    // including groups whose members are all newly generated and have no body.
    frame,has_frame:=old.body_frame,old.has_body_frame
    source_body:=old.source_body
    if old.body!=b2.nullBodyId { frame=b2.Body_GetTransform(old.body); has_frame=true; source_body=old.body }
	// Sorted starts preserve component IDs after swap-removal changes row order.
	for start in ids {
		if visited[start] || !s.subdivisions[s.sub_rows[start]].live { continue }
		group:=[dynamic]u64{start}; visited[start]=true
		for head:=0; head<len(group); head+=1 {
			neighbors:=adjacency[group[head]]
			for other in neighbors { if !visited[other] { visited[other]=true; append(&group,other) } }
		}
		sort_ids(group[:])
		// The union cannot be narrower than a member it contains.
		wide_member:=false
		for id in group { if s.subdivisions[s.sub_rows[id]].width>=s.minimum_width { wide_member=true; break } }
		if !wide_member && piece_width(s,group[:])<s.minimum_width {
			for id in group { s.subdivisions[s.sub_rows[id]].live=false }
			delete(group)
			continue
		}
		seed:u8
		for id in group { if child_seed:=s.subdivisions[s.sub_rows[id]].seed; child_seed!=0 { seed=child_seed; break } }
		owner:=add_piece(s,old.material,seed)
        s.pieces[s.piece_rows[owner]].source_body=source_body
        s.pieces[s.piece_rows[owner]].body_frame=frame
        s.pieces[s.piece_rows[owner]].has_body_frame=has_frame
		for id in group {
			s.subdivisions[s.sub_rows[id]].owner=owner
			s.pieces[s.piece_rows[owner]].mass+=polygon_area(s.subdivisions[s.sub_rows[id]].outline)
		}
		s.pieces[s.piece_rows[owner]].subdivisions=group
	}
	// Owner lookup is a set test for each endpoint, rather than linear group searches.
	for id in old.connections {
		c:=&s.connections[s.conn_rows[id]]
		if !c.live { continue }
		a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
		if !a.live || !b.live { c.live=false; continue }
		assert(a.owner==b.owner)
		append(&s.pieces[s.piece_rows[a.owner]].connections,id)
	}
	// Retain the old rigid body on the largest resulting group, ties by first ID.
	keeper:=u64(0)
	for id in ids {
		sub:=s.subdivisions[s.sub_rows[id]]
		if !sub.live { continue }
		p:=s.pieces[s.piece_rows[sub.owner]]
		if keeper==0 { keeper=p.id; continue }
		k:=s.pieces[s.piece_rows[keeper]]
		if len(p.subdivisions)>len(k.subdivisions) || len(p.subdivisions)==len(k.subdivisions) && p.subdivisions[0]<k.subdivisions[0] { keeper=p.id }
	}
	if keeper!=0 && old.body!=b2.nullBodyId {
		s.pieces[s.piece_rows[keeper]].body=old.body
		s.pieces[s.piece_rows[old_id]].body={}
	}
	owners:=make(map[u64]bool); defer delete(owners)
	for id in ids { sub:=s.subdivisions[s.sub_rows[id]]; if sub.live { owners[sub.owner]=true } }
	for owner in owners { sort_ids(s.pieces[s.piece_rows[owner]].connections[:]) }
}
// The only reclamation point. Inheritance/regrouping must finish before this:
// parent outlines and old membership lists are still used during staging.
commit_structure :: proc(s: ^Scene) {
	physics_remove_dead(s)
	removed:=false
	for i:=len(s.connections)-1; i>=0; i-=1 {
		c:=s.connections[i]
		if c.live { continue }
		removed=true
		key:=pair_key(c.a,c.b)
		if s.connection_pairs[key]==c.id { delete_key(&s.connection_pairs,key) }
		endpoints:=[2]u64{c.a,c.b}
		for endpoint in endpoints {
			links:=&s.subdivisions[s.sub_rows[endpoint]].incident_links
			for id,j in links^ { if id==c.id { unordered_remove(links,j); break } }
		}
		delete_key(&s.conn_rows,c.id)
		unordered_remove(&s.connections,i)
		if i<len(s.connections) { s.conn_rows[s.connections[i].id]=i }
	}
	for i:=len(s.subdivisions)-1; i>=0; i-=1 {
		sub:=s.subdivisions[i]
		if sub.live { continue }
		removed=true
		delete(sub.outline.points); delete(sub.incident_links); delete(sub.shapes); release_render_cache(&sub.render)
		delete_key(&s.sub_rows,sub.id)
		unordered_remove(&s.subdivisions,i)
		if i<len(s.subdivisions) { s.sub_rows[s.subdivisions[i].id]=i }
	}
	for i:=len(s.pieces)-1; i>=0; i-=1 {
		p:=s.pieces[i]
		if p.live { continue }
		removed=true
		delete(p.subdivisions); delete(p.connections)
		delete_key(&s.piece_rows,p.id)
		unordered_remove(&s.pieces,i)
		if i<len(s.pieces) { s.piece_rows[s.pieces[i].id]=i }
	}
	count:=0
	for id in s.pending_regions { if _,ok:=s.sub_rows[id]; ok { s.pending_regions[count]=id; count+=1 } }
	resize(&s.pending_regions,count)
	if removed { s.structure_revision+=1 }
}
subdivision_body :: proc(s: ^Scene,id: u64) -> b2.BodyId {
	if row,ok:=s.sub_rows[id]; ok { return s.subdivisions[row].body }; return {}
}
connection_joint :: proc(s: ^Scene,id: u64) -> b2.JointId {
	if row,ok:=s.conn_rows[id]; ok { return s.connections[row].joint }; return {}
}
is_live_subdivision :: proc(s: ^Scene,id: u64) -> bool {
	if row,ok:=s.sub_rows[id]; ok { return s.subdivisions[row].live }; return false
}
vertex_count :: proc(s: ^Scene) -> int {
	count:=0; for sub in s.subdivisions { count+=len(sub.outline.points) }; return count
}
physics_body_count :: proc(s: ^Scene) -> int {
	count:=0
	for p in s.pieces { if p.body!=b2.nullBodyId { count+=1 } }
	for sub in s.subdivisions { if s.materials[sub.material].flexibility>0 && sub.body!=b2.nullBodyId { count+=1 } }
	return count
}
scene_destroy :: proc(s: ^Scene) {
	physics_destroy(s)
	for &sub in s.subdivisions { delete(sub.outline.points); delete(sub.incident_links); delete(sub.shapes); release_render_cache(&sub.render) }
	for p in s.pieces { delete(p.subdivisions); delete(p.connections) }
	delete(s.subdivisions); delete(s.connections); delete(s.pieces)
	delete(s.materials)
	for name in s.owned_names { delete(name) }
	delete(s.owned_names)
	delete(s.sub_rows); delete(s.conn_rows); delete(s.piece_rows); delete(s.connection_pairs); delete(s.pending_regions)
	s^ = {}
}
