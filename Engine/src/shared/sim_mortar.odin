#+feature dynamic-literals
package shared

import math "core:math"
import b2 "vendor:box2d"

Built_Object :: struct { identity: u64, mortar: bool, vertices:[4]Vec2,count:int, lo,hi: Vec2, first_id,end_id: u64 }

MORTAR_STRENGTH :: f32(280)

SEAM_TOUGHNESS :: f32(#config(SEAM_TOUGHNESS,0.4))

mortar_length :: proc(c: Connection) -> f32 {
 length,_:=seam_geometry(c);return length
}

mortar_local_anchor :: proc(s: ^Scene,sub: Subdivision,rest_point: Vec2) -> Vec2 {
 if s.materials[sub.material].flexibility==0 { return rest_point }
 return vsub(rest_point,sub.rest_center)
}

object_cells :: proc(s: ^Scene,obj: Built_Object) -> [dynamic]u64 {
 result:[dynamic]u64
 for sub in s.subdivisions { if sub.live && obj.first_id<=sub.id && sub.id<obj.end_id { append(&result,sub.id) } }
 sort_ids(result[:]); return result
}

mortar_touch :: proc(a,b: Built_Object) -> bool {
 if a.count!=0 || b.count!=0 { pa,pb:=built_polygon(a),built_polygon(b);defer delete(pa.points);defer delete(pb.points);length,_:=shared_boundary(pa,pb);return length>0 }
 return ((a.hi.x==b.lo.x || b.hi.x==a.lo.x) && min(a.hi.y,b.hi.y)-max(a.lo.y,b.lo.y)>0) ||
        ((a.hi.y==b.lo.y || b.hi.y==a.lo.y) && min(a.hi.x,b.hi.x)-max(a.lo.x,b.lo.x)>0)
}

mortar_bounds :: proc(p: Polygon) -> (lo,hi: Vec2) {
 lo={1e30,1e30}; hi={-1e30,-1e30}
 for v in p.points { lo={min(lo.x,v.x),min(lo.y,v.y)}; hi={max(hi.x,v.x),max(hi.y,v.y)} }; return
}

mortar_cells :: proc(s: ^Scene,cells_a,cells_b: []u64) {
 for a in cells_a { for b in cells_b {
  sa,sb:=s.subdivisions[s.sub_rows[a]],s.subdivisions[s.sub_rows[b]]
  alo,ahi:=mortar_bounds(sa.outline); blo,bhi:=mortar_bounds(sb.outline)
  if ahi.x+1e-4<blo.x || bhi.x+1e-4<alo.x || ahi.y+1e-4<blo.y || bhi.y+1e-4<alo.y { continue }
  if length,_:=shared_boundary(sa.outline,sb.outline); length>0 { add_connection(s,a,b,true) }
 } }
}

build_mortar :: proc(s: ^Scene,objects: []Built_Object,ground: Built_Object) {
 for i in 0..<len(objects) { for j in i+1..<len(objects) {
  a,b:=objects[i],objects[j]
  if (a.mortar || b.mortar) && mortar_touch(a,b) {
   left,right:=object_cells(s,a),object_cells(s,b)
   mortar_cells(s,left[:],right[:]); delete(left); delete(right)
  }
 } }
 for a in objects { if a.mortar && built_on_ground(a) {
  left,right:=object_cells(s,a),object_cells(s,ground)
  mortar_cells(s,left[:],right[:]); delete(left); delete(right)
 } }
}

Mortar_Seam :: struct {
 bodies: [2]b2.BodyId,
 members: [dynamic]u64,
 length: f32,
 center, force: Vec2,   // force: the welds' force on bodies[1]
 torque: f32,
 damage: f32,
 normal: Vec2,          // OD-10: unit seam normal, world frame, bodies[0] -> bodies[1] (zero if none is defined)
 bearing: f32,          // OD-10: compression across the seam face (force·normal when > 0); not charged to the glue
 charged: Vec2,         // OD-10: force with the bearing part removed; this, not force, drives the load ratio
 hanging: bool,         // P6: a moving body of this seam has no other glue seam (it hangs by this one); see mortar_seam_ratio
}

// OD-10 (G-N10b): the seam normal of one mortar/glue link, unit length in rest coordinates, pointing from cell a to cell b.
// This is G-N10's measured variant v3, byte for byte (owner decision OD-10):
//  - a link with rest segments (sandbox mortar, `build_mortar`) uses the perpendicular of its longest rest segment
//    (a tie keeps the first);
//  - a glue-sample link has no rest segments. Every glued seam in a level is one (`level_glue_link`), touching or across
//    a gap. It uses the direction between the two cell centres.
// G-N10b also measured the shared-face normal for glue links and rejected it: at G1 point a it brings back v4's
// post-blast sag (evidence/G-N10b/README.md).
// A pure function of the link's rest geometry, so builds, snapshot rebuilds, replicas and round restarts agree. It is
// computed once when the link is built and cached on the Connection (seam_normal).
mortar_link_normal :: proc(s: ^Scene,c: Connection) -> Vec2 {
 a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
 toward:=vsub(b.rest_center,a.rest_center)
 n:=toward
 if len(c.rest_segments)>0 {
  face:=c.rest_segments[0]; best:=f32(0)
  for x in c.rest_segments { l:=vlen(vsub(x.b,x.a)); if l>best { best=l; face=x } }
  d:=vsub(face.b,face.a); if vlen(d)>1e-7 { n=Vec2{d.y,-d.x}; if vdot(n,toward)<0 { n=vmul(n,-1) } }
 }
 if l:=vlen(n); l>0 { n=vmul(n,1/l) }
 return n
}

mortar_seams :: proc(s: ^Scene) -> [dynamic]Mortar_Seam {
 seams:[dynamic]Mortar_Seam
 rows:=make(map[[2]b2.BodyId]int); defer delete(rows)
 ids:[dynamic]u64; defer delete(ids)
 for c in s.connections { if c.live && c.mortar && c.joint!=b2.nullJointId && b2.Joint_IsValid(c.joint) { append(&ids,c.id) } }
 sort_ids(ids[:])
 for id in ids {
  c:=s.connections[s.conn_rows[id]]
  bodies:=[2]b2.BodyId{b2.Joint_GetBodyA(c.joint),b2.Joint_GetBodyB(c.joint)}
  row,ok:=rows[bodies]
  if !ok { row,ok=rows[[2]b2.BodyId{bodies[1],bodies[0]}] }
  if !ok { row=len(seams); rows[bodies]=row; append(&seams,Mortar_Seam{bodies=bodies}) }
  seam:=&seams[row]; length:=mortar_length(c)
  append(&seam.members,id)
  seam.length+=length
  // OD-10: length-weighted link normals, oriented bodies[0] -> bodies[1] (the joint's body B is cell b's body).
  normal:=c.seam_normal; if bodies[1]!=seam.bodies[1] { normal=vmul(normal,-1) }
  seam.normal=vadd(seam.normal,vmul(normal,length))
  seam.center=vadd(seam.center,vmul(connection_sample(s,c),length))
  // New members / merged groups can have different histories: retain the
  // largest surviving history, then write the group value to every member.
  seam.damage=max(seam.damage,c.damage)
 }
 // P6: a seam whose moving (dynamic) body has no other glue seam carries that piece alone, like a shelf.
 // Counted per body over all seams, so it does not depend on order.
 counts:=make(map[b2.BodyId]int); defer delete(counts)
 for seam in seams { for body in seam.bodies { counts[body]+=1 } }
 // Level glue only (a world built from a level, glue-sample links): the Odin sandbox editor keeps today's rule, so its
 // demo layout and glue/mortar fixtures stand as authored.
 for &seam in seams {
  if s.catalog==nil { break }
  level_glue:=true
  for id in seam.members { if len(s.connections[s.conn_rows[id]].rest_segments)>0 { level_glue=false; break } }
  if !level_glue { continue }
  for body in seam.bodies { if counts[body]==1 && b2.Body_GetType(body)==.dynamicBody { seam.hanging=true } }
 }
 for &seam in seams {
  seam.center=vmul(seam.center,1/seam.length)
  // Rest frame -> world: rigid bodies are built at their rest angle 0 and rebuilt bodies keep their frame.
  if l:=vlen(seam.normal); l>0 { seam.normal=vmul(seam.normal,1/l) }
  rot:=b2.Body_GetRotation(seam.bodies[1])
  seam.normal=vrotate(seam.normal,math.atan2(rot.s,rot.c))
  for id in seam.members {
   c:=s.connections[s.conn_rows[id]]
   force:=from_b2(b2.Joint_GetConstraintForce(c.joint))
   torque:=b2.Joint_GetConstraintTorque(c.joint)
   body:=seam.bodies[1]
   local:=b2.Joint_GetLocalAnchorB(c.joint)
   if b2.Joint_GetBodyB(c.joint)!=body {
    force=vmul(force,-1); torque=-torque; local=b2.Joint_GetLocalAnchorA(c.joint)
   }
   point:=from_b2(b2.Body_GetWorldPoint(body,local))
   seam.force=vadd(seam.force,force)
   seam.torque+=torque+vcross(vsub(point,seam.center),force)
  }
  mortar_seam_split(&seam)
 }
 return seams
}

// OD-10: weight resting on the seam (the weld pushing bodies[1] away from bodies[0] across the face) is not charged to the glue.
// Tension, shear and torque are charged as before; there is no moment relief. Splits seam.force by seam.normal.
mortar_seam_split :: proc(seam: ^Mortar_Seam) {
 seam.bearing=0; seam.charged=seam.force
 if fn:=vdot(seam.force,seam.normal); fn>0 { seam.bearing=fn; seam.charged=vsub(seam.force,vmul(seam.normal,fn)) }
}

mortar_free_seams :: proc(seams: [dynamic]Mortar_Seam) {
 for seam in seams { delete(seam.members) }; delete(seams)
}

mortar_force_failures :: proc(s: ^Scene,failures: ^Failures,dt: f32) {
 seams:=mortar_seams(s); defer mortar_free_seams(seams)
 for seam in seams {
  mortar_apply_seam(s,seam,failures,dt)
 }
}

material_glue_toughness :: proc(m: Material) -> f32 { if m.glue_toughness>0 { return m.glue_toughness }; return 1 }

// G-N1: a seam's load capacity scales with the weakest material on any of its links.
mortar_seam_toughness :: proc(s: ^Scene,seam: Mortar_Seam) -> f32 {
 if len(seam.members)==0 { return 1 }
 toughness:=f32(math.F32_MAX)
 for id in seam.members {
  c:=s.connections[s.conn_rows[id]]
  a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
  toughness=min(toughness,material_glue_toughness(s.materials[a.material]),material_glue_toughness(s.materials[b.material]))
 }
 return toughness
}

// P6 / G-N12 (owner-delegated 2026-11-27): a piece hanging by a single glue seam (a shelf: nothing else glued to it)
// is held like mortar, weak against sliding and bending on its own. Weight pressing across the seam (OD-10 bearing) adds
// friction against sliding and a lever against bending (the load can move to the seam's edge, half its length), so a
// piece resting on its one support still holds while one sticking out sideways gives way. Seams of pieces glued in two
// or more places (beams, the Bridge's frame, the Tower's slabs) keep the full rule: a uniform cut broke the Bridge and
// Yard at round start (evidence/P6/README.md §3).
GLUE_COHESION :: f32(#config(GLUE_COHESION,0.3)) // share of MORTAR_STRENGTH a hanging seam keeps against shear and bending
GLUE_FRICTION :: f32(0.6)                         // shear resisted per unit of bearing on a hanging seam

// Load ratio r of a seam: 1 at capacity. Strength S is MORTAR_STRENGTH per unit length times the seam toughness.
// The force term uses the charged force: compression across the seam face is not charged (OD-10).
// A hanging seam charges tension against S·L, shear against cohesion·S·L + friction·bearing and torque against
// ½·cohesion·S·L² + ½·bearing·L.
mortar_seam_ratio :: proc(s: ^Scene,seam: Mortar_Seam) -> f32 {
 strength:=MORTAR_STRENGTH*mortar_seam_toughness(s,seam)
 if !seam.hanging { return vlen(seam.charged)/(strength*seam.length)+math.abs(seam.torque)/(0.5*strength*seam.length*seam.length) }
 cohesion:=strength*GLUE_COHESION
 fn:=vdot(seam.charged,seam.normal);tension:=max(-fn,0)
 shear:=vlen(vsub(seam.charged,vmul(seam.normal,fn)))
 shear_capacity:=cohesion*seam.length+GLUE_FRICTION*seam.bearing
 moment_capacity:=0.5*cohesion*seam.length*seam.length+0.5*seam.bearing*seam.length
 return tension/(strength*seam.length)+shear/shear_capacity+math.abs(seam.torque)/moment_capacity
}

mortar_apply_seam :: proc(s: ^Scene,seam: Mortar_Seam,failures: ^Failures,dt: f32) {
  r:=mortar_seam_ratio(s,seam)
  damage:=f32(0); if r>=1 { damage=seam.damage+(r-1)*dt }
  broken:=damage>=SEAM_TOUGHNESS
  seam_diagnostic_force(s,seam,r,broken,damage)
  if broken { damage=0 }
  for id in seam.members {
   s.connections[s.conn_rows[id]].damage=damage
   if broken {
    append(&failures.connections,id)
    when BOM_MORTAR_MEASURE { mortar_measured_force_breaks+=1 }
   }
  }
}
