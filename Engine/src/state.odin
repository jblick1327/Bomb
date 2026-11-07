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
 blast_resistance: union { f32 } `json:"blast_resistance,omitempty"`,
 shock_loss: union { f32 } `json:"shock_loss,omitempty"`, // Disabled/legacy stays absent.
 strip_thickness: union { f32 } `json:"strip_thickness,omitempty"`,
 color: union { [3]u8 } `json:"color,omitempty"`,
}
Wire_Connection :: struct {
 id,a,b: u64,
 glue:[]Glue_Sample `json:"glue,omitempty"`,
 mortar: union { bool } `json:"mortar,omitempty"`,
 damage: union { f32 } `json:"damage,omitempty"`,
 overload_ticks: union { u8 } `json:"overload_ticks,omitempty"`, // legacy: accepted on load, ignored, never written
}
Snapshot :: struct {
 provenance_version:int,
 level_json:string,
 source_parts:[dynamic]Source_Part_Anchors,
	version: int,
	next_id: u64,
	revision: u64,
	minimum_width: f32,
	materials: [dynamic]Wire_Material,
	subdivisions: [dynamic]Subdivision,
	connections: [dynamic]Wire_Connection,
	pieces: [dynamic]Piece,
}
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
		if !finite(sub.frame) { return false,"invalid subdivision frame" }
  if len(sub.outline.points) < 3 || polygon_area(sub.outline) <= 0 { return false,"invalid polygon" }
		for point in sub.outline.points { if !valid_vec(point) { return false,"invalid polygon coordinate" } }
		if !valid_vec(sub.pose.position) || !valid_vec(sub.pose.velocity) || !finite(sub.pose.angle) || !finite(sub.pose.angular_velocity) { return false,"invalid motion" }
	}
	for c in s.connections {
		if !c.live { continue }
		a_row,a_ok := s.sub_rows[c.a]; b_row,b_ok := s.sub_rows[c.b]
		if !a_ok || !b_ok { return false,"missing endpoint" }
		a,b := s.subdivisions[a_row],s.subdivisions[b_row]
  if len(c.glue)>0 { if reason:=validate_glue_samples(c,a,b);reason!="" { return false,reason } }
  if c.mortar {
   if !a.live || !b.live || a.owner==b.owner { return false,"invalid mortar endpoints" }
   for p in s.pieces { if contains_id(p.connections[:],c.id) { return false,"mortar in piece connections" } }
   continue
  }
		if !a.live || !b.live || a.owner != b.owner { return false,"invalid live connection endpoints" }
		p := s.pieces[s.piece_rows[a.owner]]
		if !contains_id(p.connections[:],c.id) { return false,"connection absent from its piece" }
	}
	return true,""
}

// A shallow read view. Geometry and memberships remain owned by the scene.
read_state :: proc(s: ^Scene) -> Snapshot {
	out := Snapshot{version=3,provenance_version=1,next_id=s.next_id,revision=s.revision,minimum_width=s.minimum_width,level_json=s.level_json,source_parts=s.source_parts}
	for m in s.materials {
		wire := Wire_Material{impact_scale=m.impact_scale,name=m.name,subdivision_strength=m.subdivision_strength,connection_strength=m.connection_strength,flexibility=m.flexibility,generation_count=m.generation_count,aspect_ratio=m.aspect_ratio,triangulate=m.triangulate}
  if transmute(u32)m.blast_resistance!=0 { wire.blast_resistance=m.blast_resistance }
  if transmute(u32)m.shock_loss!=0 { wire.shock_loss=m.shock_loss }
  if m.aspect_ratio<1 && m.strip_thickness!=0.3 { wire.strip_thickness=m.strip_thickness }
  if m.color!=snapshot_legacy_color(m.name) { wire.color=m.color }
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
	for id in ids {
  c:=s.connections[s.conn_rows[id]]; wire:=Wire_Connection{id=c.id,a=c.a,b=c.b,glue=c.glue[:]}
  if c.mortar { wire.mortar=true }; if c.damage!=0 { wire.damage=c.damage }
  append(&out.connections,wire)
 }
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
 if view.version==3 {
  legacy:=s.level_json==""&&len(s.source_parts)==0
  for sub in s.subdivisions { if sub.provenance.motion!=.Legacy { legacy=false;break } }
  // Legacy standalone Scene captures retain their original decimal formatting;
  // the World path already uses exact floats. Authored v4 scenes use exact data.
  if legacy { bytes,err:=json.marshal(view,{pretty=true});return bytes,err==nil }
  return exact_json_encode(view,true)
 }
	wire:=Legacy_Scene_Wire{version=view.version,next_id=view.next_id,revision=view.revision,minimum_width=view.minimum_width,materials=view.materials,connections=view.connections,pieces=view.pieces}
 defer delete(wire.subdivisions)
 for sub in view.subdivisions { item:=Snapshot_Cell{id=sub.id,owner=sub.owner,material=sub.material,seed=sub.seed,outline=sub.outline,rest_center=sub.rest_center,pose=sub.pose,live=sub.live};if sub.frame!=0 { item.frame=sub.frame };append(&wire.subdivisions,item) }
 data,err := json.marshal(wire,{pretty=true})
	return data,err == nil
}
destroy_decoded_snapshot :: proc(snapshot: ^Snapshot) {
 delete(snapshot.level_json);for part in snapshot.source_parts { delete(part.segments) };delete(snapshot.source_parts)
	for m in snapshot.materials { delete(m.name) }
	for c in snapshot.connections { delete(c.glue) }
 for sub in snapshot.subdivisions { delete(sub.outline.points) }
	for p in snapshot.pieces { delete(p.subdivisions); delete(p.connections) }
	release_state_view(snapshot)
}
decode_snapshot :: proc(data: []byte) -> (Scene,bool) {
	wire := Snapshot{}
	defer destroy_decoded_snapshot(&wire)
	if err := json.unmarshal(data,&wire); err != nil { return {},false }
 return decode_scene_state(&wire)
}
decode_scene_state :: proc(wire: ^Snapshot) -> (Scene,bool) {
	if (wire.version != 1 && wire.version != 2 && wire.version!=3) || !finite(wire.minimum_width) || wire.minimum_width < 0 { return {},false }
 if wire.version==3&&wire.provenance_version!=1 { return {},false }
	s := new_scene(wire.minimum_width)
	s.next_id = wire.next_id
	s.revision = wire.revision
	seen := make(map[u64]bool)
	defer delete(seen)
	ok := false
	defer { if !ok { scene_destroy(&s) } }
 if wire.version==3&&!scene_restore_catalog_data(&s,wire.level_json,wire.source_parts[:]) { return {},false }
	for m in wire.materials {
		if !finite(m.subdivision_strength) || !finite(m.connection_strength) || m.subdivision_strength < 0 || m.connection_strength < 0 || !finite(m.flexibility) || m.flexibility < 0 || m.generation_count < 1 || !finite(m.aspect_ratio) || m.aspect_ratio <= 0 { return {},false }
		impact_scale:=f32(1)
		if value,exists:=m.impact_scale.(f32); exists { impact_scale=value }
		if !finite(impact_scale) || impact_scale<0 { return {},false }
  blast_resistance:=f32(0)
  if value,exists:=m.blast_resistance.(f32); exists { blast_resistance=value }
  if !finite(blast_resistance) || blast_resistance<0 { return {},false }
  shock_loss:=f32(0)
  if value,exists:=m.shock_loss.(f32); exists { shock_loss=value }
  if !finite(shock_loss) || shock_loss<0 { return {},false }
  strip:=f32(0); if m.aspect_ratio<1 { strip=0.3 }
  if v,present:=m.strip_thickness.(f32); present {
   if m.aspect_ratio>=1 || !finite(v) || v<=0 { return {},false }; strip=v
  }
  color:=snapshot_legacy_color(m.name)
  if v,present:=m.color.([3]u8); present { color=v }
		material := make_material(strip_thickness=strip,color=color,blast_resistance=blast_resistance,impact_scale=impact_scale,shock_loss=shock_loss,name=strings.clone(m.name),subdivision_strength=m.subdivision_strength,connection_strength=m.connection_strength,flexibility=m.flexibility,generation_count=m.generation_count,aspect_ratio=m.aspect_ratio,triangulate=m.triangulate)
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
  if wire.version<3 { sub.provenance={} }else{
   _,valid:=cell_policy_decode(sub.provenance.source_identity,sub.provenance.source_part_id,cell_policy_flags(sub.provenance));if !valid { return {},false }
   if sub.provenance.motion!=.Legacy&&cell_pinned(&s,sub)!=sub.provenance.pinned { return {},false }
  }
		if sub.id == 0 || sub.id > s.next_id || seen[sub.id] || !sub.live { return {},false }
		seen[sub.id] = true
		if len(sub.outline.points)<3 { return {},false }
		if wire.version==1 {
			owner,exists := s.piece_rows[sub.owner]
			if !exists { return {},false }
			sub.seed=s.pieces[owner].seed
		}
		retain_subdivision(&s,sub)
        s.subdivisions[s.sub_rows[sub.id]].rest_center=sub.rest_center
		if row,exists:=s.piece_rows[sub.owner]; exists { s.pieces[row].mass+=polygon_area(sub.outline) }
	}
	for c in wire.connections {
		if c.id == 0 || c.id > s.next_id || seen[c.id] { return {},false }
		seen[c.id] = true
		a_row,a_ok := s.sub_rows[c.a]; b_row,b_ok := s.sub_rows[c.b]
		if !a_ok || !b_ok || c.a == c.b { return {},false }
		a,b := s.subdivisions[a_row],s.subdivisions[b_row]
		length,point := shared_boundary(a.outline,b.outline)
		if len(c.glue)>0 {
   temp:=Connection{glue=nil};append(&temp.glue,..c.glue); length,point=seam_geometry(temp);delete(temp.glue)
  } else if length <= 0 { return {},false }
		if _,duplicate:=s.connection_pairs[pair_key(c.a,c.b)]; duplicate { return {},false }
		s.connection_pairs[pair_key(c.a,c.b)]=c.id
		append(&s.subdivisions[a_row].incident_links,c.id); append(&s.subdivisions[b_row].incident_links,c.id)
		s.conn_rows[c.id]=len(s.connections)
		mortar:=false; damage:=f32(0)
  if value,exists:=c.mortar.(bool); exists { mortar=value }
  if value,exists:=c.damage.(f32); exists { if !finite(value) || value<0 { return {},false }; damage=value }
		append(&s.connections,Connection{mortar=mortar,damage=damage,id=c.id,a=c.a,b=c.b,rest_point=point,local_a=vsub(point,a.rest_center),local_b=vsub(point,b.rest_center),rest_segments=shared_segments(a.outline,b.outline),live=true})
  if len(c.glue)>0 { target:=&s.connections[len(s.connections)-1];delete(target.rest_segments);target.rest_segments=nil;append(&target.glue,..c.glue) }
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


@(private="file")
snapshot_legacy_color :: proc(name:string)->[3]u8 {
 switch name {
 case "wood":return {180,136,82}
 case "glass":return {86,153,174}
 case "rubber":return {162,112,184}
 }
 return {131,145,152}
}

// The legacy scene writer uses fixed decimal formatting; optional scalar fields
// use presence unions because the standard writer does not omit numeric zero.
Snapshot_Cell :: struct {
 frame:union { f32 } `json:"frame,omitempty"`,
 id,owner:u64, material:int, seed:u8, outline:Polygon, rest_center:Vec2,pose:Pose,live:bool,
}
Legacy_Scene_Wire :: struct {
 version:int,next_id,revision:u64,minimum_width:f32,
 materials:[dynamic]Wire_Material,subdivisions:[dynamic]Snapshot_Cell,
 connections:[dynamic]Wire_Connection,pieces:[dynamic]Piece,
}
