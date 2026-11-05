package main
import "core:time"

import b2 "vendor:box2d"
import "core:math"

Physics :: struct {
 world: b2.WorldId,
 synced_revision: u64,
 synced: bool,
 active: bool,
 mortar_breaking: bool,
}
PHYSICS_SUBSTEPS :: 4
GLOBAL_DAMPING :: f32(0.7)

to_b2 :: proc(v: Vec2) -> b2.Vec2 { return {v.x,v.y} }
from_b2 :: proc(v: b2.Vec2) -> Vec2 { return {v.x,v.y} }
// The single anchoring rule shared by physics and presentation: a piece is
// static when some live cell has a non-degenerate edge lying on anchor_y.
piece_anchored :: proc(s: ^Scene,piece_id: u64,anchor_y: f32) -> bool {
 if !(anchor_y>-1e30) { return false }
 row,ok:=s.piece_rows[piece_id]; if !ok { return false }
 for id in s.pieces[row].subdivisions {
  srow,found:=s.sub_rows[id]; if !found { continue }
  sub:=s.subdivisions[srow]
  if !sub.live { continue }
  for a,i in sub.outline.points {
   b:=sub.outline.points[(i+1)%len(sub.outline.points)]
   if math.abs(a.y-anchor_y)<0.00001 && math.abs(b.y-anchor_y)<0.00001 && math.abs(a.x-b.x)>0.00001 { return true }
  }
 }
 return false
}
physics_init :: proc(s: ^Scene, gravity: Vec2 = {}, anchor_y: f32 = -1e30) {
 assert(!s.physics.active)
 def := b2.DefaultWorldDef()
 def.gravity = to_b2(gravity)
 // Hit events are evaluated every step in Box2D 3.1.1, not just on begin.
 def.hitEventThreshold = 0
 s.anchor_y = anchor_y
 s.physics = Physics{world=b2.CreateWorld(def),active=true,mortar_breaking=true}
 physics_sync_structure(s)
}
physics_destroy :: proc(s: ^Scene) {
 if !s.physics.active { return }
 b2.DestroyWorld(s.physics.world)
 for &sub in s.subdivisions { sub.body={}; sub.fixture_count=0; clear(&sub.shapes) }
 for &p in s.pieces { p.body={}; p.physics_revision=0; p.has_body_frame=false; p.source_body={} }
 for &c in s.connections { c.joint={} }
 s.physics = {}
}
physics_read_motion :: proc(s: ^Scene) {
 if !s.physics.active { return }
 for &sub in s.subdivisions {
  body:=sub.body
  if body==b2.nullBodyId { continue }
  rotation := b2.Body_GetRotation(body)
  position:=from_b2(b2.Body_GetPosition(body))
  if s.materials[sub.material].flexibility==0 { position=from_b2(b2.Body_GetWorldPoint(body,to_b2(sub.rest_center))) }
  sub.pose = Pose{position=position,angle=math.atan2(rotation.s,rotation.c),
   velocity=from_b2(b2.Body_GetWorldPointVelocity(body,to_b2(position))),angular_velocity=b2.Body_GetAngularVelocity(body)}
 }
}
physics_shape_def :: proc(id: u64) -> b2.ShapeDef {
 def:=b2.DefaultShapeDef()
 def.density=1; def.enableHitEvents=true; def.updateBodyMass=false
 def.userData=rawptr(uintptr(id))
 return def
}
physics_create_fixture :: proc(s: ^Scene, body: b2.BodyId, sub: Subdivision, outline: Polygon) -> bool {


 points: [dynamic]b2.Vec2; defer delete(points)
 offset:=Vec2{}
 if s.materials[sub.material].flexibility>0 { offset=sub.rest_center }
 for point in outline.points { append(&points,to_b2(vsub(point,offset))) }
 hull:=b2.ComputeHull(points[:])
 // Hull welding can collapse a thin ear below Box2D's collision tolerance.
 if hull.count<3 { return false }
 when BOM_PROFILE { if blast_profile!=nil { blast_profile.counts[3]+=1 } }
 shape:=b2.CreatePolygonShape(body,physics_shape_def(sub.id),b2.MakePolygon(hull,0))
 append(&s.subdivisions[s.sub_rows[sub.id]].shapes,shape)
 s.subdivisions[s.sub_rows[sub.id]].fixture_count+=1
 return true
}
physics_create_region_shapes :: proc(s: ^Scene,id: u64,body: b2.BodyId) {
 sub:=s.subdivisions[s.sub_rows[id]]
 if is_convex(sub.outline) && len(sub.outline.points)<=8 { physics_create_fixture(s,body,sub,sub.outline) }
 else {
  parts:=convex_decomposition(sub.outline)
  for part in parts { physics_create_fixture(s,body,sub,part); delete(part.points) }
  delete(parts)
 }
 if s.subdivisions[s.sub_rows[id]].fixture_count==0 {
  // Preserve the existing microscopic-outline fallback, in the body's frame.
  offset:=Vec2{}
  if s.materials[sub.material].flexibility>0 { offset=sub.rest_center }
  lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
  for rest in sub.outline.points { p:=vsub(rest,offset); lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)} }
  polygon:=b2.MakeOffsetBox(max(f32(0.0025),(hi.x-lo.x)*0.5),max(f32(0.0025),(hi.y-lo.y)*0.5),to_b2(vmul(vadd(lo,hi),0.5)),b2.MakeRot(0))
  when BOM_PROFILE { if blast_profile!=nil { blast_profile.counts[3]+=1 } }
 shape:=b2.CreatePolygonShape(body,physics_shape_def(id),polygon)
  append(&s.subdivisions[s.sub_rows[id]].shapes,shape)
  s.subdivisions[s.sub_rows[id]].fixture_count=1
 }
}
physics_remove_region_shapes :: proc(sub: ^Subdivision) {
 for shape in sub.shapes { b2.DestroyShape(shape,false) }
 clear(&sub.shapes); sub.fixture_count=0
}
// Reclamation is ordered by logical IDs, before packed records are removed.
physics_remove_dead :: proc(s: ^Scene) {
 if !s.physics.active { return }
 ids: [dynamic]u64; defer delete(ids)
 for c in s.connections { if !c.live { append(&ids,c.id) } }; sort_ids(ids[:])
 for id in ids { c:=&s.connections[s.conn_rows[id]]; if c.joint!=b2.nullJointId { b2.DestroyJoint(c.joint); c.joint={} } }
 clear(&ids)
 for sub in s.subdivisions { if !sub.live { append(&ids,sub.id) } }; sort_ids(ids[:])
 for id in ids {
  sub:=&s.subdivisions[s.sub_rows[id]]
  physics_remove_region_shapes(sub)
  if sub.body!=b2.nullBodyId && s.materials[sub.material].flexibility>0 { b2.DestroyBody(sub.body) }
  sub.body={}
 }
 clear(&ids)
 for p in s.pieces { if !p.live && p.body!=b2.nullBodyId { append(&ids,p.id) } }; sort_ids(ids[:])
 // Reach refinement can regroup before the damage pass. If its provisional
 // keeper then vanishes, retain the body on the largest remaining descendant.
 claims:=make(map[b2.BodyId]u64); defer delete(claims)
 for p in s.pieces {
  if !p.live || p.body!=b2.nullBodyId || p.source_body==b2.nullBodyId { continue }
  current:=claims[p.source_body]
  if current==0 { claims[p.source_body]=p.id; continue }
  other:=s.pieces[s.piece_rows[current]]
  if len(p.subdivisions)>len(other.subdivisions) || len(p.subdivisions)==len(other.subdivisions) && p.subdivisions[0]<other.subdivisions[0] { claims[p.source_body]=p.id }
 }
 for id in ids {
  p:=&s.pieces[s.piece_rows[id]]
  if keeper:=claims[p.body]; keeper!=0 { s.pieces[s.piece_rows[keeper]].body=p.body }
  else { b2.DestroyBody(p.body) }
  p.body={}
 }
}
polygon_centred_inertia :: proc(sub: Subdivision) -> f32 {
 inertia:f32
 for a,i in sub.outline.points {
  b:=sub.outline.points[(i+1)%len(sub.outline.points)]
  x,y:=vsub(a,sub.rest_center),vsub(b,sub.rest_center)
  inertia+=vcross(x,y)*(vdot(x,x)+vdot(x,y)+vdot(y,y))/12
 }
 return math.abs(inertia)
}
physics_finish_mass :: proc(s: ^Scene,body: b2.BodyId,sub: Subdivision) {
 b2.Body_ApplyMassFromShapes(body) // Also refresh Box2D collision extents for CCD.
 b2.Body_SetMassData(body,b2.MassData{mass=polygon_area(sub.outline),center={},rotationalInertia=polygon_centred_inertia(sub)})
 b2.Body_SetLinearVelocity(body,to_b2(sub.pose.velocity)); b2.Body_SetAngularVelocity(body,sub.pose.angular_velocity)
}
physics_finish_piece_mass :: proc(s: ^Scene,p: ^Piece) {
 mass,inertia:f32; center:=Vec2{}
 for id in p.subdivisions {
  sub:=s.subdivisions[s.sub_rows[id]]; area:=polygon_area(sub.outline)
  mass+=area; center=vadd(center,vmul(sub.rest_center,area))
 }
 center=vmul(center,1/mass)
 for id in p.subdivisions {
  sub:=s.subdivisions[s.sub_rows[id]]; r:=vsub(sub.rest_center,center)
  inertia+=polygon_centred_inertia(sub)+polygon_area(sub.outline)*vdot(r,r)
 }
 // Preserve the old rigid velocity field at this group's new centre of mass.
 sub:=s.subdivisions[s.sub_rows[p.subdivisions[0]]]
 world_center:=from_b2(b2.Body_GetWorldPoint(p.body,to_b2(center)))
 r:=vsub(world_center,sub.pose.position)
 velocity:=vadd(sub.pose.velocity,Vec2{-sub.pose.angular_velocity*r.y,sub.pose.angular_velocity*r.x})
 // 3.1.1 SetMassData consumes COM inertia directly (the binding's
 // local-origin comment is stale). Refresh extents before the exact override.
 b2.Body_ApplyMassFromShapes(p.body)
 b2.Body_SetMassData(p.body,b2.MassData{mass=mass,center=to_b2(center),rotationalInertia=inertia})
 b2.Body_SetLinearVelocity(p.body,to_b2(velocity)); b2.Body_SetAngularVelocity(p.body,sub.pose.angular_velocity)
 p.physics_revision=p.render_revision+1
}
// Bodies use the shared rest origin for rigid pieces, region centres for soft cells.
physics_new_body :: proc(s: ^Scene,sub: Subdivision,kind: b2.BodyType,rigid: bool,frame: b2.Transform = {},has_frame: bool = false) -> b2.BodyId {
 when BOM_PROFILE { if blast_profile!=nil { blast_profile.counts[2]+=1 } }

 def:=b2.DefaultBodyDef(); def.type=kind
 position:=sub.pose.position
 if rigid { position=vsub(position,vrotate(sub.rest_center,sub.pose.angle)) }
 def.position=to_b2(position); def.rotation=b2.MakeRot(sub.pose.angle)
 if has_frame { def.position=frame.p; def.rotation=frame.q }
 // Mass data below supplies COM velocity after fixtures have been assembled.
 // Rigid contacts use the body mass. A retained body must not carry a region
 // tag that could later belong to another group; shape tags identify regions.
 if !rigid { def.userData=rawptr(uintptr(sub.id)) }
 return b2.CreateBody(s.physics.world,def)
}
// This runs only between steps. Regrouping transfers one rigid body to its largest group.
physics_sync_structure :: proc(s: ^Scene) {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(7,started) }

 if !s.physics.active || (s.physics.synced && s.physics.synced_revision==s.structure_revision) { return }
 scene_finish_references(s)
 s.physics.synced=true; s.physics.synced_revision=s.structure_revision
 clear(&s.pending_regions)
 anchored:=make(map[u64]bool); defer delete(anchored)
 if s.anchor_y>-1e30 {
  for p in s.pieces { if p.live && piece_anchored(s,p.id,s.anchor_y) { anchored[p.id]=true } }
 }
 ids: [dynamic]u64; defer delete(ids)
 for p in s.pieces { if p.live { append(&ids,p.id) } }; sort_ids(ids[:])
 for id in ids {
  p:=&s.pieces[s.piece_rows[id]]
  if s.materials[p.material].flexibility>0 { continue }
  kind:=b2.BodyType.dynamicBody; if anchored[id] { kind=.staticBody }
  if p.body==b2.nullBodyId { p.body=physics_new_body(s,s.subdivisions[s.sub_rows[p.subdivisions[0]]],kind,true,p.body_frame,p.has_body_frame) }
  else if b2.Body_GetType(p.body)!=kind { b2.Body_SetType(p.body,kind); p.physics_revision=0 }
  p.has_body_frame=false; p.source_body={}
 }
 clear(&ids)
 for sub in s.subdivisions { if sub.live { append(&ids,sub.id) } }; sort_ids(ids[:])
 // Detach old shapes before adding any: a moved region cannot occupy both bodies.
 for id in ids {
  sub:=&s.subdivisions[s.sub_rows[id]]
  if s.materials[sub.material].flexibility==0 && sub.body!=s.pieces[s.piece_rows[sub.owner]].body {
   physics_remove_region_shapes(sub); sub.body={}
  }
 }
 for id in ids {
  sub:=s.subdivisions[s.sub_rows[id]]
  rigid:=s.materials[sub.material].flexibility==0
  kind:=b2.BodyType.dynamicBody; if anchored[sub.owner] { kind=.staticBody }
  if rigid {
   if sub.body==b2.nullBodyId {
    body:=s.pieces[s.piece_rows[sub.owner]].body
    s.subdivisions[s.sub_rows[id]].body=body; physics_create_region_shapes(s,id,body)
   }
  } else if sub.body==b2.nullBodyId {
   body:=physics_new_body(s,sub,kind,false); s.subdivisions[s.sub_rows[id]].body=body
   physics_create_region_shapes(s,id,body); physics_finish_mass(s,body,sub)
  } else if b2.Body_GetType(sub.body)!=kind {
   b2.Body_SetType(sub.body,kind); if kind==.dynamicBody { physics_finish_mass(s,sub.body,sub) }
  }
 }
 clear(&ids)
 for p in s.pieces { if p.live { append(&ids,p.id) } }; sort_ids(ids[:])
 for id in ids {
  p:=&s.pieces[s.piece_rows[id]]
  if p.body!=b2.nullBodyId && p.physics_revision!=p.render_revision+1 { physics_finish_piece_mass(s,p) }
 }
 clear(&ids)
 for c in s.connections { if c.live { append(&ids,c.id) } }; sort_ids(ids[:])
 for id in ids {
  c:=s.connections[s.conn_rows[id]]
  a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
  if c.mortar {
   static_pair:=b2.Body_GetType(a.body)==.staticBody && b2.Body_GetType(b.body)==.staticBody
   valid:=c.joint!=b2.nullJointId && b2.Joint_IsValid(c.joint)
   if static_pair { if valid { b2.DestroyJoint(c.joint) }; s.connections[s.conn_rows[id]].joint={}; continue }
   if valid && b2.Joint_GetBodyA(c.joint)==a.body && b2.Joint_GetBodyB(c.joint)==b.body { continue }
   if valid { b2.DestroyJoint(c.joint) }
   def:=b2.DefaultWeldJointDef(); def.bodyIdA=a.body; def.bodyIdB=b.body
   def.localAnchorA=to_b2(mortar_local_anchor(s,a,c.rest_point))
   def.localAnchorB=to_b2(mortar_local_anchor(s,b,c.rest_point))
   def.referenceAngle=0; def.linearHertz=0; def.angularHertz=0
   s.connections[s.conn_rows[id]].joint=b2.CreateWeldJoint(s.physics.world,def)
   continue
  }
  flexibility:=max(s.materials[a.material].flexibility,s.materials[b.material].flexibility)
  static_pair:=b2.Body_GetType(a.body)==.staticBody && b2.Body_GetType(b.body)==.staticBody
  if c.joint!=b2.nullJointId && (flexibility==0 || static_pair) { b2.DestroyJoint(c.joint); s.connections[s.conn_rows[id]].joint={}; continue }
  if flexibility==0 || static_pair || c.joint!=b2.nullJointId { continue }
  def:=b2.DefaultWeldJointDef(); def.bodyIdA=a.body; def.bodyIdB=b.body
  def.localAnchorA=to_b2(c.local_a); def.localAnchorB=to_b2(c.local_b)
  def.referenceAngle=0
  def.linearHertz=1/max(flexibility,0.01); def.angularHertz=def.linearHertz
  def.linearDampingRatio=GLOBAL_DAMPING; def.angularDampingRatio=GLOBAL_DAMPING
  s.connections[s.conn_rows[id]].joint=b2.CreateWeldJoint(s.physics.world,def)
 }
 physics_read_motion(s)
}
apply_blast_motion :: proc(s: ^Scene, sub: ^Subdivision, direction: Vec2, load: f32) {
 delta_v:=vmul(direction,load*BLAST_IMPULSE_SCALE)
 if s.physics.active {
  impulse:=vmul(delta_v,polygon_area(sub.outline))
  if s.materials[sub.material].flexibility>0 { b2.Body_ApplyLinearImpulseToCenter(sub.body,to_b2(impulse),true) }
  else { b2.Body_ApplyLinearImpulse(sub.body,to_b2(impulse),to_b2(sub.pose.position),true) }
 } else { sub.pose.velocity=vadd(sub.pose.velocity,delta_v) }
}
// Contacts use the inelastic, normal velocity change implied by approach speed.
// A max across events also combines multiple points/fixtures of one body pair
// without counting their shared approach velocity more than once.
// Region contacts use their current connected piece; external actors use body mass.
interaction_mass :: proc(s: ^Scene,body: b2.BodyId) -> f32 {
 if b2.Body_GetType(body)!=.dynamicBody { return math.inf_f32(1) }
 id:=u64(uintptr(b2.Body_GetUserData(body)))
 if row,ok:=s.sub_rows[id]; ok { return s.pieces[s.piece_rows[s.subdivisions[row].owner]].mass }
 return b2.Body_GetMass(body)
}
contact_damage_load :: proc(s: ^Scene,body,other: b2.BodyId,approach_speed,impact_scale: f32) -> f32 {
 if impact_scale==0 || b2.Body_GetType(body)!=.dynamicBody { return 0 }
 own_mass,other_mass:=interaction_mass(s,body),interaction_mass(s,other)
 dv:=max(f32(0),approach_speed)
 if finite(other_mass) { dv*=other_mass/(own_mass+other_mass) }
 return dv*impact_scale/BLAST_IMPULSE_SCALE
}
calculate_physics_loads :: proc(s: ^Scene, dt: f32) -> Failures {
	assert(dt > 0)
	failures := Failures{impact=true}
	loads := make(map[u64]f32)
	defer delete(loads)
 points:map[u64]Vec2; defer delete(points)
	events:=b2.World_GetContactEvents(s.physics.world)
	for hit in events.hitEvents[:events.hitCount] {
		a,b:=b2.Shape_GetBody(hit.shapeIdA),b2.Shape_GetBody(hit.shapeIdB)
		bodies:=[2]b2.BodyId{a,b}
		shapes:=[2]b2.ShapeId{hit.shapeIdA,hit.shapeIdB}
		for body,i in bodies {
			id:=u64(uintptr(b2.Shape_GetUserData(shapes[i])))
			row,exists:=s.sub_rows[id]
			if !exists || !s.subdivisions[row].live { continue }
			sub:=s.subdivisions[row]
			load:=contact_damage_load(s,body,bodies[1-i],hit.approachSpeed,s.materials[sub.material].impact_scale)
   if s.materials[sub.material].shock_loss>0 {
    if points==nil { points=make(map[u64]Vec2) }
    point:=from_b2(hit.point); previous,has_point:=points[id]
    if !has_point || load>loads[id] || load==loads[id] && (point.x<previous.x || point.x==previous.x && point.y<previous.y) { points[id]=point }
   }
			loads[id]=max(loads[id],load)
		}
	}
 if s.physics.mortar_breaking { mortar_force_failures(s,&failures,dt) }

	for sub in s.subdivisions {
		if sub.seed==0 && sub.width>s.minimum_width { continue }
		if sub.live && fails(loads[sub.id],s.materials[sub.material].subdivision_strength) {
   append(&failures.subdivisions,sub.id)
   if s.materials[sub.material].shock_loss>0 { append(&failures.impact_sources,Impact_Shock_Source{sub.id,points[sub.id],loads[sub.id]}) }
  }
	}
	return failures
}
Load_Calculator :: #type proc(s: ^Scene,dt: f32) -> Failures
physics_tick :: proc(s: ^Scene, dt: f32,calculate_loads: Load_Calculator = calculate_physics_loads) {
 when BOM_FRAME_BENCH { frame_start:=time.tick_now(); defer { if frame_measuring { frame_physics_ms+=frame_ms(frame_start) } } }

	assert(s.physics.active && dt > 0)
	physics_sync_structure(s)
	b2.World_Step(s.physics.world,dt,PHYSICS_SUBSTEPS)
	physics_read_motion(s)
	failures := calculate_loads(s,dt)
	apply_failures(s,failures)
	free_failures(&failures)
	physics_sync_structure(s)
}
