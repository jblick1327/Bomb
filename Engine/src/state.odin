package main

import "core:encoding/json"
import "core:math"
import "core:os"
import "core:strings"

Wire_Material :: struct {
	name: string,
	subdivision_strength,connection_strength: f32,
	subdivision_infinite,connection_infinite: bool,
	flexibility: f32,
	impact_scale: union { f32 }, // Presence preserves explicit zero; older snapshots default to 1.
	generation_count: int,
	aspect_ratio: f32,
	triangulate: bool,
}
Wire_Connection :: struct { id,a,b: u64 }
Snapshot :: struct {
	version: int,
	next_id: u64,
	revision: u64,
	minimum_width: f32,
	materials: [dynamic]Wire_Material,
	subdivisions: [dynamic]Subdivision,
	connections: [dynamic]Wire_Connection,
	pieces: [dynamic]Piece,
}
finite :: proc(value: f32) -> bool { return !math.is_nan(value) && !math.is_inf(value) }
valid_vec :: proc(v: Vec2) -> bool { return finite(v.x) && finite(v.y) }
validate_scene :: proc(s: ^Scene) -> (bool,string) {
	membership := make(map[u64]int)
	defer delete(membership)
	for p in s.pieces {
		if !p.live { continue }
		if len(p.subdivisions) == 0 { return false,"empty live piece" }
		if p.material < 0 || p.material >= len(s.materials) { return false,"invalid material" }
		for id in p.subdivisions {
			row,ok := s.sub_rows[id]
			if !ok { return false,"missing subdivision" }
			sub := s.subdivisions[row]
			if !sub.live || sub.owner != p.id || sub.material != p.material { return false,"invalid subdivision ownership" }
			membership[id] += 1
		}
		for id in p.connections {
			row,ok := s.conn_rows[id]
			if !ok || !s.connections[row].live { return false,"invalid connection membership" }
			c := s.connections[row]
			if !contains_id(p.subdivisions[:],c.a) || !contains_id(p.subdivisions[:],c.b) { return false,"connection crosses pieces" }
		}
		visited := make(map[u64]bool)
		queue: [dynamic]u64
		append(&queue,p.subdivisions[0]); visited[p.subdivisions[0]] = true
		for head := 0; head < len(queue); head += 1 {
			for id in p.connections {
				c := s.connections[s.conn_rows[id]]
				other := u64(0)
				if c.a == queue[head] { other=c.b } else if c.b == queue[head] { other=c.a }
				if other != 0 && !visited[other] { visited[other]=true; append(&queue,other) }
			}
		}
		connected := len(queue) == len(p.subdivisions)
		delete(queue); delete(visited)
		if !connected { return false,"piece is disconnected" }
	}
	for sub in s.subdivisions {
		if !sub.live { continue }
		if membership[sub.id] != 1 { return false,"subdivision must belong to exactly one piece" }
		if len(sub.outline.points) < 3 || polygon_area(sub.outline) <= 0 { return false,"invalid polygon" }
		for point in sub.outline.points { if !valid_vec(point) { return false,"invalid polygon coordinate" } }
		if !valid_vec(sub.pose.position) || !valid_vec(sub.pose.velocity) || !finite(sub.pose.angle) || !finite(sub.pose.angular_velocity) { return false,"invalid motion" }
	}
	for c in s.connections {
		if !c.live { continue }
		a_row,a_ok := s.sub_rows[c.a]; b_row,b_ok := s.sub_rows[c.b]
		if !a_ok || !b_ok { return false,"missing endpoint" }
		a,b := s.subdivisions[a_row],s.subdivisions[b_row]
		if !a.live || !b.live || a.owner != b.owner { return false,"invalid live connection endpoints" }
		p := s.pieces[s.piece_rows[a.owner]]
		if !contains_id(p.connections[:],c.id) { return false,"connection absent from its piece" }
	}
	return true,""
}

// A shallow read view. Geometry and memberships remain owned by the scene.
read_state :: proc(s: ^Scene) -> Snapshot {
	out := Snapshot{version=2,next_id=s.next_id,revision=s.revision,minimum_width=s.minimum_width}
	for m in s.materials {
		wire := Wire_Material{impact_scale=m.impact_scale,name=m.name,subdivision_strength=m.subdivision_strength,connection_strength=m.connection_strength,flexibility=m.flexibility,generation_count=m.generation_count,aspect_ratio=m.aspect_ratio,triangulate=m.triangulate}
		if math.is_inf(m.subdivision_strength) { wire.subdivision_infinite=true; wire.subdivision_strength=0 }
		if math.is_inf(m.connection_strength) { wire.connection_infinite=true; wire.connection_strength=0 }
		append(&out.materials,wire)
	}
	ids: [dynamic]u64
	defer delete(ids)
	for sub in s.subdivisions { if sub.live { append(&ids,sub.id) } }
	sort_ids(ids[:])
	for id in ids { append(&out.subdivisions,s.subdivisions[s.sub_rows[id]]) }
	clear(&ids)
	for c in s.connections { if c.live { append(&ids,c.id) } }
	sort_ids(ids[:])
	for id in ids { c:=s.connections[s.conn_rows[id]]; append(&out.connections,Wire_Connection{c.id,c.a,c.b}) }
	clear(&ids)
	for p in s.pieces { if p.live { append(&ids,p.id) } }
	sort_ids(ids[:])
	for id in ids { append(&out.pieces,s.pieces[s.piece_rows[id]]) }
	return out
}
release_state_view :: proc(snapshot: ^Snapshot) {
	delete(snapshot.materials); delete(snapshot.subdivisions); delete(snapshot.connections); delete(snapshot.pieces)
	snapshot^ = {}
}
encode_snapshot :: proc(s: ^Scene) -> ([]byte,bool) {
	view := read_state(s)
	defer release_state_view(&view)
	data,err := json.marshal(view,{pretty=true})
	return data,err == nil
}
destroy_decoded_snapshot :: proc(snapshot: ^Snapshot) {
	for m in snapshot.materials { delete(m.name) }
	for sub in snapshot.subdivisions { delete(sub.outline.points) }
	for p in snapshot.pieces { delete(p.subdivisions); delete(p.connections) }
	release_state_view(snapshot)
}
decode_snapshot :: proc(data: []byte) -> (Scene,bool) {
	wire := Snapshot{}
	defer destroy_decoded_snapshot(&wire)
	if err := json.unmarshal(data,&wire); err != nil { return {},false }
	if (wire.version != 1 && wire.version != 2) || !finite(wire.minimum_width) || wire.minimum_width < 0 { return {},false }
	s := new_scene(wire.minimum_width)
	s.next_id = wire.next_id
	s.revision = wire.revision
	seen := make(map[u64]bool)
	defer delete(seen)
	ok := false
	defer { if !ok { scene_destroy(&s) } }
	for m in wire.materials {
		if !finite(m.subdivision_strength) || !finite(m.connection_strength) || m.subdivision_strength < 0 || m.connection_strength < 0 || !finite(m.flexibility) || m.flexibility < 0 || m.generation_count < 1 || !finite(m.aspect_ratio) || m.aspect_ratio <= 0 { return {},false }
		impact_scale:=f32(1)
		if value,exists:=m.impact_scale.(f32); exists { impact_scale=value }
		if !finite(impact_scale) || impact_scale<0 { return {},false }
		material := make_material(impact_scale=impact_scale,name=strings.clone(m.name),subdivision_strength=m.subdivision_strength,connection_strength=m.connection_strength,flexibility=m.flexibility,generation_count=m.generation_count,aspect_ratio=m.aspect_ratio,triangulate=m.triangulate)
		append(&s.owned_names,material.name)
		if m.subdivision_infinite { material.subdivision_strength = math.inf_f32(1) }
		if m.connection_infinite { material.connection_strength = math.inf_f32(1) }
		add_material(&s,material)
	}
	for p in wire.pieces {
		if p.id == 0 || p.id > s.next_id || seen[p.id] || !p.live { return {},false }
		seen[p.id] = true
		copy := p
		copy.subdivisions=nil; copy.connections=nil
		for id in p.subdivisions { append(&copy.subdivisions,id) }
		for id in p.connections { append(&copy.connections,id) }
		s.piece_rows[p.id]=len(s.pieces); append(&s.pieces,copy)
	}
	for &sub in wire.subdivisions {
		if sub.id == 0 || sub.id > s.next_id || seen[sub.id] || !sub.live { return {},false }
		seen[sub.id] = true
		if len(sub.outline.points)<3 { return {},false }
		if wire.version==1 {
			owner,exists := s.piece_rows[sub.owner]
			if !exists { return {},false }
			sub.seed=s.pieces[owner].seed
		}
		retain_subdivision(&s,sub)
		if row,exists:=s.piece_rows[sub.owner]; exists { s.pieces[row].mass+=polygon_area(sub.outline) }
	}
	for c in wire.connections {
		if c.id == 0 || c.id > s.next_id || seen[c.id] { return {},false }
		seen[c.id] = true
		a_row,a_ok := s.sub_rows[c.a]; b_row,b_ok := s.sub_rows[c.b]
		if !a_ok || !b_ok || c.a == c.b { return {},false }
		a,b := s.subdivisions[a_row],s.subdivisions[b_row]
		length,point := shared_boundary(a.outline,b.outline)
		if length <= 0 { return {},false }
		if _,duplicate:=s.connection_pairs[pair_key(c.a,c.b)]; duplicate { return {},false }
		s.connection_pairs[pair_key(c.a,c.b)]=c.id
		append(&s.subdivisions[a_row].incident_links,c.id); append(&s.subdivisions[b_row].incident_links,c.id)
		s.conn_rows[c.id]=len(s.connections)
		append(&s.connections,Connection{id=c.id,a=c.a,b=c.b,rest_point=point,local_a=vsub(point,a.rest_center),local_b=vsub(point,b.rest_center),live=true})
	}
	if valid,_ := validate_scene(&s); !valid { return {},false }
	ok = true
	return s,true
}
save_snapshot :: proc(s: ^Scene,path: string) -> bool {
	data,ok := encode_snapshot(s)
	defer delete(data)
	return ok && os.write_entire_file(path,data) == nil
}
load_snapshot :: proc(path: string) -> (Scene,bool) {
	data,err := os.read_entire_file(path,context.allocator)
	defer delete(data)
	if err != nil { return {},false }
	return decode_snapshot(data)
}
interpolate_pose :: proc(previous,current: Pose,alpha: f32) -> Pose {
	t := clamp(alpha,f32(0),f32(1))
	angle := current.angle-previous.angle
	for angle > math.PI { angle -= 2*math.PI }
	for angle < -math.PI { angle += 2*math.PI }
	result := current
	result.position=vadd(previous.position,vmul(vsub(current.position,previous.position),t))
	result.angle=previous.angle+angle*t
	return result
}

// Interpolate the shared frame, so rendered rigid cells stay rigid between ticks too.
interpolate_region_pose :: proc(s: ^Scene,sub: Subdivision,old: Pose,alpha: f32) -> Pose {
 if s.materials[sub.material].flexibility>0 { return interpolate_pose(old,sub.pose,alpha) }
 a,b:=old,sub.pose
 a.position=vsub(a.position,vrotate(sub.rest_center,a.angle))
 b.position=vsub(b.position,vrotate(sub.rest_center,b.angle))
 pose:=interpolate_pose(a,b,alpha)
 pose.position=vadd(pose.position,vrotate(sub.rest_center,pose.angle))
 return pose
}
