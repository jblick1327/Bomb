#+feature dynamic-literals
package shared

import time "core:time"
import math "core:math"
import b2 "vendor:box2d"

Vec2 :: struct { x, y: f32 }

Polygon :: struct { points: []Vec2 }

Pose :: struct { position: Vec2, angle: f32, velocity: Vec2, angular_velocity: f32 }

Material :: struct {
	name: string,
	subdivision_strength, connection_strength: f32,
	flexibility: f32,
	impact_scale: f32, // Constructors use 1; zero explicitly disables physical damage.
	generation_count: int,
	aspect_ratio: f32,
	triangulate: bool,
 shock_loss: f32,
 blast_resistance: f32,
 strip_thickness: f32, // Explicit for grained recipes; zero when unused.
 color: [3]u8,
}

Subdivision :: struct {
 provenance:Cell_Provenance,
 frame:f32 `json:"frame,omitempty"`,
	id, owner: u64,
	material: int,
	seed: u8,
	outline: Polygon,
	body: b2.BodyId `json:"-"`,
	fixture_count: int `json:"-"`,
	shapes: [dynamic]b2.ShapeId `json:"-"`,
	incident_links: [dynamic]u64 `json:"-"`,
	width: f32 `json:"-"`,
	rest_center: Vec2,
	pose: Pose,
	live: bool,
}

Glue_Sample :: struct { p,q:Vec2, w:f32 }

Connection :: struct {
 glue:[dynamic]Glue_Sample `json:"-"`,
	id, a, b: u64,
	rest_point, local_a, local_b: Vec2,
 rest_segments: [dynamic]Segment `json:"-"`,
	joint: b2.JointId `json:"-"`,
	live: bool,
 mortar: bool,
 damage: f32, // seconds of excess capacity absorbed by this mortar/glue seam (shared by its members)
}

Piece :: struct {
	id: u64,
	ref_rest: Vec2 `json:"-"`, // Immutable after construction; network structure, not the solo snapshot format.
	has_ref_rest: bool `json:"-"`,
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
 level_json:string,
 level_policy:Resolved_Level_Policy,
 gameplay_manifest,config_hash:[32]u8,
 catalog:^Level_Layout,
 source_parts:[dynamic]Source_Part_Anchors,
	physics: Physics,
	materials: [dynamic]Material,
	owned_names: [dynamic]string,
	subdivisions: [dynamic]Subdivision,
	connections: [dynamic]Connection,
	pieces: [dynamic]Piece,
	sub_rows, conn_rows, piece_rows: map[u64]int,
	connection_pairs: map[Endpoint_Pair]u64,
	structure_revision: u64,
	anchor_y: f32, // Structural: pieces with a live cell edge on this height are static. Replicated.
	epoch: u32, // Replication epoch; bumped whenever the world is rebuilt.
	pending_regions: [dynamic]u64,
	next_id: u64,
	revision: u64,
	minimum_width: f32,
}

vadd :: proc(a, b: Vec2) -> Vec2 { return {a.x+b.x, a.y+b.y} }

vsub :: proc(a, b: Vec2) -> Vec2 { return {a.x-b.x, a.y-b.y} }

vmul :: proc(a: Vec2, s: f32) -> Vec2 { return {a.x*s, a.y*s} }

vdot :: proc(a, b: Vec2) -> f32 { return a.x*b.x+a.y*b.y }

vcross :: proc(a, b: Vec2) -> f32 { return a.x*b.y-a.y*b.x }

vlen :: proc(a: Vec2) -> f32 { return math.sqrt(vdot(a,a)) }

make_polygon :: proc(points: []Vec2) -> Polygon {
	result:=Polygon{points=make([]Vec2,len(points))}
	copy(result.points,points)
	return result
}

shared_boundary :: proc(a, b: Polygon) -> (f32, Vec2) {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(13,started); if blast_profile!=nil { blast_profile.counts[5]+=1 } }

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

new_scene :: proc(minimum_width: f32) -> Scene {
	return Scene{sub_rows=make(map[u64]int),conn_rows=make(map[u64]int),piece_rows=make(map[u64]int),connection_pairs=make(map[Endpoint_Pair]u64),minimum_width=minimum_width,anchor_y=-1e30}
}

piece_finish_reference :: proc(s: ^Scene,p: ^Piece) {
 if p.has_ref_rest || !p.live || len(p.subdivisions)==0 { return }
 area,x,y: f64
 for id in p.subdivisions {
  sub:=s.subdivisions[s.sub_rows[id]]
  if !sub.live { continue }
  // Fan around a nearby vertex avoids cancellation in far-from-origin debris.
  pts:=sub.outline.points
  if len(pts)<3 { continue }
  a:=pts[0]; signed,cx,cy:f64
  for i in 1..<len(pts)-1 {
   b,c:=pts[i],pts[i+1]
   cross:=(f64(b.x)-f64(a.x))*(f64(c.y)-f64(a.y))-(f64(b.y)-f64(a.y))*(f64(c.x)-f64(a.x))
   signed+=cross; cx+=(f64(a.x)+f64(b.x)+f64(c.x))*cross; cy+=(f64(a.y)+f64(b.y)+f64(c.y))*cross
  }
  if signed==0 { continue }
  weight:=math.abs(signed)
  area+=weight; x+=cx/signed/3*weight; y+=cy/signed/3*weight
 }
 if area>0 { p.ref_rest={f32(x/area),f32(y/area)}; p.has_ref_rest=true }
}

scene_finish_references :: proc(s: ^Scene) { for &p in s.pieces { piece_finish_reference(s,&p) } }

is_live_subdivision :: proc(s: ^Scene,id: u64) -> bool {
	if row,ok:=s.sub_rows[id]; ok { return s.subdivisions[row].live }; return false
}

scene_destroy :: proc(s: ^Scene) {
	physics_destroy(s)
 delete(s.level_json)
 if s.catalog!=nil {destroy_level_layout(s.catalog);free(s.catalog)}
 for part in s.source_parts { delete(part.segments) };delete(s.source_parts)
 for c in s.connections { delete(c.rest_segments); delete(c.glue) }
	for &sub in s.subdivisions { delete(sub.outline.points); delete(sub.incident_links); delete(sub.shapes) }
	for p in s.pieces { delete(p.subdivisions); delete(p.connections) }
	delete(s.subdivisions); delete(s.connections); delete(s.pieces)
	delete(s.materials)
	for name in s.owned_names { delete(name) }
	delete(s.owned_names)
	delete(s.sub_rows); delete(s.conn_rows); delete(s.piece_rows); delete(s.connection_pairs); delete(s.pending_regions)
	s^ = {}
}
