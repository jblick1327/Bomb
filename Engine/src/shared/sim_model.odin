#+feature dynamic-literals
package shared

import time "core:time"
import math "core:math"
import slice "core:slice"
import b2 "vendor:box2d"

Blast :: struct { position: Vec2, radius: f32 }

Impact_Shock_Source :: struct { cell: u64, point: Vec2, load: f32 }

Failures :: struct {
 administrative:bool,
 subdivisions, connections, discard_subdivisions: [dynamic]u64,
 impact: bool,
 no_sibling_bonds: bool,
 impact_sources: [dynamic]Impact_Shock_Source,
}

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

new_id :: proc(s: ^Scene) -> u64 { s.next_id += 1; return s.next_id }

add_material :: proc(s: ^Scene, m: Material) -> int { append(&s.materials,m); s.structure_revision+=1; return len(s.materials)-1 }

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
	retain_subdivision(s,Subdivision{id=id,owner=owner,material=piece.material,seed=piece.seed,outline=outline,pose=pose,live=true,provenance={source_identity=SOURCE_DIAGNOSTIC,source_part_id=owner}})
	append(&s.pieces[s.piece_rows[owner]].subdivisions,id)
	s.pieces[s.piece_rows[owner]].mass+=polygon_area(outline)
	s.pieces[s.piece_rows[owner]].render_revision+=1
	return id
}

frame_to_reference :: proc(frame: Pose,ref_rest: Vec2) -> Pose {
 out:=frame; out.position=vadd(frame.position,vrotate(ref_rest,frame.angle)); return out
}

retain_subdivision :: proc(s: ^Scene,source: Subdivision) {
	sub:=source
	sub.outline=make_polygon(source.outline.points)
	sub.rest_center=centroid(sub.outline)
	sub.width=outline_width(sub.outline.points)
	sub.body={}; sub.fixture_count=0; sub.shapes=nil; sub.incident_links=nil
	s.sub_rows[sub.id]=len(s.subdivisions)
	append(&s.subdivisions,sub)
	append(&s.pending_regions,sub.id)
	s.structure_revision+=1
}

add_connection :: proc(s: ^Scene, a, b: u64, mortar: bool = false, known_segments: []Segment=nil) -> u64 {
	if a == b { return 0 }
	if id,ok:=s.connection_pairs[pair_key(a,b)]; ok { if s.connections[s.conn_rows[id]].live { return id } }
	sa, sb := s.subdivisions[s.sub_rows[a]],s.subdivisions[s.sub_rows[b]]
	length, point := shared_boundary(sa.outline,sb.outline)
	if length <= 0 { return 0 }
	id := new_id(s)
	s.conn_rows[id] = len(s.connections)
 segments:[dynamic]Segment
 if known_segments==nil { segments=shared_segments(sa.outline,sb.outline) } else { append(&segments,..known_segments) }
	append(&s.connections,Connection{id=id,a=a,b=b,mortar=mortar,rest_point=point,local_a=vsub(point,sa.rest_center),local_b=vsub(point,sb.rest_center),rest_segments=segments,live=true})
	s.connection_pairs[pair_key(a,b)]=id
	append(&s.subdivisions[s.sub_rows[a]].incident_links,id)
	append(&s.subdivisions[s.sub_rows[b]].incident_links,id)
	if !mortar { append(&s.pieces[s.piece_rows[sa.owner]].connections,id) }
	s.pieces[s.piece_rows[sa.owner]].render_revision+=1
 if mortar { s.pieces[s.piece_rows[sb.owner]].render_revision+=1 }
	s.structure_revision+=1
	return id
}

connection_sample :: proc(s: ^Scene, c: Connection) -> Vec2 {
	a,b := s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
	return vmul(vadd(vadd(a.pose.position,vrotate(c.local_a,a.pose.angle)),vadd(b.pose.position,vrotate(c.local_b,b.pose.angle))),0.5)
}

subdivision_sample :: proc(sub: Subdivision) -> Vec2 { return sub.pose.position }

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
 if active_cover!=nil && !blast_scratch_active && len(points)>32 { return blast_cached_width(points) }
 return outline_width_uncached(points)
}

outline_width_uncached :: proc(points: []Vec2) -> f32 {
	sorted_inline:[32]Vec2; hull_inline:[64]Vec2
 hull:[]Vec2; heap:[dynamic]Vec2; defer delete(heap)
 if len(points)<=len(sorted_inline) { hull=convex_hull_into(points,sorted_inline[:],hull_inline[:]) } else { heap=convex_hull(points); hull=heap[:] }
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
		for id in group { sub:=s.subdivisions[s.sub_rows[id]];if sub.width>=s.minimum_width||!cell_damage_allowed(sub) { wide_member=true; break } }
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
		piece_finish_reference(s,&s.pieces[s.piece_rows[owner]])
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

commit_structure :: proc(s: ^Scene) {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(6,started) }

 when ODIN_TEST { glass_commit_test_calls+=1 }
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
  delete(c.rest_segments); delete(c.glue)
		unordered_remove(&s.connections,i)
		if i<len(s.connections) { s.conn_rows[s.connections[i].id]=i }
	}
	for i:=len(s.subdivisions)-1; i>=0; i-=1 {
		sub:=s.subdivisions[i]
		if sub.live { continue }
		removed=true
		delete(sub.outline.points); delete(sub.incident_links); delete(sub.shapes)
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
