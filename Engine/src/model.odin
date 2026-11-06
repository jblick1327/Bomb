#+feature dynamic-literals
package main

import shared "shared"
import "core:time"

import "core:math"
import "core:slice"
import b2 "vendor:box2d"

// Procedural materials use this helper; the fixed palette explicitly lists every field.
make_material :: proc(name: string = "", subdivision_strength: f32 = 0, connection_strength: f32 = 0,
                      flexibility: f32 = 0, generation_count: int = 1, aspect_ratio: f32 = 1,
                      triangulate: bool = false, impact_scale: f32 = 1, shock_loss: f32 = 0, blast_resistance: f32 = 0, strip_thickness: f32 = 0, color: [3]u8 = {131,145,152}) -> Material {
 return Material{name=name,strip_thickness=strip_thickness,color=color,subdivision_strength=subdivision_strength,connection_strength=connection_strength,
                 flexibility=flexibility,generation_count=generation_count,aspect_ratio=aspect_ratio,
                 triangulate=triangulate,impact_scale=impact_scale,shock_loss=shock_loss,blast_resistance=blast_resistance}
}

posed_polygon :: proc(sub: Subdivision) -> Polygon {
	result := Polygon{points=make([]Vec2,len(sub.outline.points))}
	for point,i in sub.outline.points { result.points[i]=posed_point(sub,point) }
	return result
}
// Returns the common collinear edge length and its length-weighted midpoint.
// add_piece reserves an id before its cells exist. Seal that construction once,
// before physics, publication or damage can observe/change the membership.
reference_to_frame :: proc(reference: Pose,ref_rest: Vec2) -> Pose {
 out:=reference; out.position=vsub(reference.position,vrotate(ref_rest,reference.angle)); return out
}
// Each record owns its undeformed outline; staging may read dead parents until commit.
contains_id :: proc(ids: []u64,id: u64) -> bool {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(12,started); if shared.blast_profile!=nil { shared.blast_profile.counts[6]+=1 } }
 for x in ids { if x == id { return true } }; return false }
// The only reclamation point. Inheritance/regrouping must finish before this:
// parent outlines and old membership lists are still used during staging.
subdivision_body :: proc(s: ^Scene,id: u64) -> b2.BodyId {
	if row,ok:=s.sub_rows[id]; ok { return s.subdivisions[row].body }; return {}
}
connection_joint :: proc(s: ^Scene,id: u64) -> b2.JointId {
	if row,ok:=s.conn_rows[id]; ok { return s.connections[row].joint }; return {}
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
