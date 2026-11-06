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
 center, force: Vec2,
 torque: f32,
 damage: f32,
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
  seam.center=vadd(seam.center,vmul(connection_sample(s,c),length))
  // New members / merged groups can have different histories: retain the
  // largest surviving history, then write the group value to every member.
  seam.damage=max(seam.damage,c.damage)
 }
 for &seam in seams {
  seam.center=vmul(seam.center,1/seam.length)
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
 }
 return seams
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

mortar_apply_seam :: proc(s: ^Scene,seam: Mortar_Seam,failures: ^Failures,dt: f32) {
  r:=vlen(seam.force)/(MORTAR_STRENGTH*seam.length)+math.abs(seam.torque)/(0.5*MORTAR_STRENGTH*seam.length*seam.length)
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
