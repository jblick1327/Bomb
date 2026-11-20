package main

import b2 "vendor:box2d"
import "core:math"

Physics :: struct {
	world: b2.WorldId,
	bodies: map[u64]b2.BodyId,
	joints: map[u64]b2.JointId,
	fixture_counts: map[u64]int,
	active: bool,
}
Interaction :: struct { force: Vec2, torque: f32 }
REFERENCE_LENGTH :: f32(1)
PHYSICS_SUBSTEPS :: 4
GLOBAL_DAMPING :: f32(0.7)

to_b2 :: proc(v: Vec2) -> b2.Vec2 { return {v.x,v.y} }
from_b2 :: proc(v: b2.Vec2) -> Vec2 { return {v.x,v.y} }
interaction_load :: proc(i: Interaction) -> f32 {
	return max(vlen(i.force),math.abs(i.torque)/REFERENCE_LENGTH)
}
equivalent_force :: proc(impulse: Vec2, interval: f32) -> Vec2 {
	assert(interval > 0)
	return vmul(impulse,1/interval)
}
physics_init :: proc(s: ^Scene, gravity: Vec2 = {}) {
	assert(!s.physics.active)
	def := b2.DefaultWorldDef()
	def.gravity = to_b2(gravity)
	s.physics = Physics{world=b2.CreateWorld(def),bodies=make(map[u64]b2.BodyId),joints=make(map[u64]b2.JointId),fixture_counts=make(map[u64]int),active=true}
	physics_sync_structure(s)
}
physics_destroy :: proc(s: ^Scene) {
	if !s.physics.active { return }
	b2.DestroyWorld(s.physics.world)
	delete(s.physics.bodies); delete(s.physics.joints); delete(s.physics.fixture_counts)
	s.physics = {}
}
physics_read_motion :: proc(s: ^Scene) {
	if !s.physics.active { return }
	for id,body in s.physics.bodies {
		row := s.sub_rows[id]
		rotation := b2.Body_GetRotation(body)
		s.subdivisions[row].pose = Pose{
			position=from_b2(b2.Body_GetPosition(body)),angle=math.atan2(rotation.s,rotation.c),
			velocity=from_b2(b2.Body_GetLinearVelocity(body)),angular_velocity=b2.Body_GetAngularVelocity(body),
		}
	}
}
physics_create_fixture :: proc(s: ^Scene, body: b2.BodyId, sub: Subdivision, outline: Polygon) -> bool {
	points: [dynamic]b2.Vec2
	defer delete(points)
	for point in outline.points { append(&points,to_b2(vsub(point,sub.rest_center))) }
	hull := b2.ComputeHull(points[:])
	// Hull welding can collapse a thin ear below Box2D's collision tolerance.
	if hull.count < 3 { return false }
	polygon := b2.MakePolygon(hull,0)
	def := b2.DefaultShapeDef()
	def.density = 1
	_ = b2.CreatePolygonShape(body,def,polygon)
	s.physics.fixture_counts[sub.id] += 1
	return true
}
physics_finish_mass :: proc(s: ^Scene,body: b2.BodyId,sub: Subdivision) {
	if s.physics.fixture_counts[sub.id]==0 {
		// A microscopic attached subdivision is still one live logical entity.
		// Use a bounding fixture when the engine cannot resolve any of its ears.
		lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
		for rest in sub.outline.points { p:=vsub(rest,sub.rest_center); lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)} }
		polygon:=b2.MakeOffsetBox(max(f32(0.0025),(hi.x-lo.x)*0.5),max(f32(0.0025),(hi.y-lo.y)*0.5),to_b2(vmul(vadd(lo,hi),0.5)),b2.MakeRot(0))
		def:=b2.DefaultShapeDef(); def.density=1
		_ = b2.CreatePolygonShape(body,def,polygon)
		s.physics.fixture_counts[sub.id]=1
	}
	// Keep mass and the body origin tied to the exact logical polygon, including
	// when Box2D simplifies a fixture. This also makes rotational inheritance exact.
	inertia: f32
	for i in 0..<len(sub.outline.points) {
		a,b:=vsub(sub.outline.points[i],sub.rest_center),vsub(sub.outline.points[(i+1)%len(sub.outline.points)],sub.rest_center)
		inertia+=vcross(a,b)*(vdot(a,a)+vdot(a,b)+vdot(b,b))/12
	}
	b2.Body_SetMassData(body,b2.MassData{mass=polygon_area(sub.outline),center={},rotationalInertia=math.abs(inertia)})
	b2.Body_SetLinearVelocity(body,to_b2(sub.pose.velocity))
	b2.Body_SetAngularVelocity(body,sub.pose.angular_velocity)
}
// This runs only between World_Step calls. Existing handles survive ownership changes.
physics_sync_structure :: proc(s: ^Scene) {
	if !s.physics.active { return }
	dead_joints: [dynamic]u64
	dead_bodies: [dynamic]u64
	defer delete(dead_joints); defer delete(dead_bodies)
	for id,joint in s.physics.joints {
		row,ok := s.conn_rows[id]
		if !ok || !s.connections[row].live { b2.DestroyJoint(joint); append(&dead_joints,id) }
	}
	for id in dead_joints { delete_key(&s.physics.joints,id) }
	for id,body in s.physics.bodies {
		row,ok := s.sub_rows[id]
		if !ok || !s.subdivisions[row].live { b2.DestroyBody(body); append(&dead_bodies,id) }
	}
	for id in dead_bodies { delete_key(&s.physics.bodies,id); delete_key(&s.physics.fixture_counts,id) }
	for sub in s.subdivisions {
		if !sub.live { continue }
		if _,exists := s.physics.bodies[sub.id]; exists { continue }
		def := b2.DefaultBodyDef()
		def.type = .dynamicBody
		def.position = to_b2(sub.pose.position)
		def.rotation = b2.MakeRot(sub.pose.angle)
		def.linearVelocity = to_b2(sub.pose.velocity)
		def.angularVelocity = sub.pose.angular_velocity
		body := b2.CreateBody(s.physics.world,def)
		s.physics.bodies[sub.id] = body
		if is_convex(sub.outline) && len(sub.outline.points) <= 8 {
			physics_create_fixture(s,body,sub,sub.outline)
		} else {
			triangles := convex_decomposition(sub.outline)
			for triangle in triangles { physics_create_fixture(s,body,sub,triangle); delete(triangle.points) }
			delete(triangles)
		}
		physics_finish_mass(s,body,sub)
	}
	for c in s.connections {
		if !c.live { continue }
		if _,exists := s.physics.joints[c.id]; exists { continue }
		a := s.subdivisions[s.sub_rows[c.a]]
		b := s.subdivisions[s.sub_rows[c.b]]
		def := b2.DefaultWeldJointDef()
		def.bodyIdA = s.physics.bodies[c.a]
		def.bodyIdB = s.physics.bodies[c.b]
		def.localAnchorA = to_b2(c.local_a)
		def.localAnchorB = to_b2(c.local_b)
		// All outlines share one undeformed frame. Its relative rest angle is zero.
		def.referenceAngle = 0
		flexibility := max(s.materials[a.material].flexibility,s.materials[b.material].flexibility)
		if flexibility > 0 {
			def.linearHertz = 1/max(flexibility,0.01)
			def.angularHertz = def.linearHertz
		}
		def.linearDampingRatio = GLOBAL_DAMPING
		def.angularDampingRatio = GLOBAL_DAMPING
		s.physics.joints[c.id] = b2.CreateWeldJoint(s.physics.world,def)
	}
}
apply_blast_motion :: proc(s: ^Scene, sub: ^Subdivision, direction: Vec2, load: f32) {
	delta_v := vmul(direction,load*BLAST_IMPULSE_SCALE)
	if s.physics.active {
		body := s.physics.bodies[sub.id]
		impulse := vmul(delta_v,b2.Body_GetMass(body))
		b2.Body_ApplyLinearImpulseToCenter(body,to_b2(impulse),true)
		sub.pose.velocity = from_b2(b2.Body_GetLinearVelocity(body))
	} else {
		sub.pose.velocity = vadd(sub.pose.velocity,delta_v)
	}
}
// Contact points and fixtures against the same other body form one interaction.
// Joint reactions are already forces; totalNormalImpulse covers the full tick.
// Box2D's tangent/rolling impulses cover the final substep in this binding version.
calculate_physics_loads :: proc(s: ^Scene, dt: f32) -> Failures {
	assert(dt > 0)
	failures := Failures{}
	loads := make(map[u64]f32)
	defer delete(loads)
	for sub in s.subdivisions {
		if !sub.live { continue }
		body := s.physics.bodies[sub.id]
		capacity := int(b2.Body_GetContactCapacity(body))
		buffer := make([]b2.ContactData,capacity)
		contacts := b2.Body_GetContactData(body,buffer)
		interactions := make(map[b2.BodyId]Interaction)
		for contact in contacts {
			body_a,body_b := b2.Shape_GetBody(contact.shapeIdA),b2.Shape_GetBody(contact.shapeIdB)
			other := body_b
			sign := f32(-1)
			if body_b == body { other=body_a; sign=1 }
			normal := from_b2(contact.manifold.normal)
			tangent := Vec2{normal.y,-normal.x}
			interaction := interactions[other]
			for k in 0..<int(contact.manifold.pointCount) {
				point := contact.manifold.points[k]
				force := vadd(equivalent_force(vmul(normal,point.totalNormalImpulse*sign),dt),equivalent_force(vmul(tangent,point.tangentImpulse*sign),dt/f32(PHYSICS_SUBSTEPS)))
				interaction.force = vadd(interaction.force,force)
				interaction.torque += vcross(vsub(from_b2(point.point),sub.pose.position),force)
			}
			interaction.torque += contact.manifold.rollingImpulse*sign/(dt/f32(PHYSICS_SUBSTEPS))
			interactions[other] = interaction
		}
		for _,interaction in interactions { loads[sub.id] = max(loads[sub.id],interaction_load(interaction)) }
		delete(interactions); delete(buffer)
	}
	for c in s.connections {
		if !c.live { continue }
		joint := s.physics.joints[c.id]
		interaction := Interaction{force=from_b2(b2.Joint_GetConstraintForce(joint)),torque=b2.Joint_GetConstraintTorque(joint)}
		load := interaction_load(interaction)
		a,b := s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
		a_interaction,b_interaction := interaction,interaction
		a_interaction.torque += vcross(vsub(posed_point(a,c.rest_point),a.pose.position),interaction.force)
		b_interaction.torque += vcross(vsub(posed_point(b,c.rest_point),b.pose.position),interaction.force)
		loads[c.a] = max(loads[c.a],interaction_load(a_interaction))
		loads[c.b] = max(loads[c.b],interaction_load(b_interaction))
		material := s.materials[s.subdivisions[s.sub_rows[c.a]].material]
		if fails(load,material.connection_strength) { append(&failures.connections,c.id) }
	}
	for sub in s.subdivisions {
		if sub.live && fails(loads[sub.id],s.materials[sub.material].subdivision_strength) { append(&failures.subdivisions,sub.id) }
	}
	return failures
}
Load_Calculator :: #type proc(s: ^Scene,dt: f32) -> Failures
physics_tick :: proc(s: ^Scene, dt: f32,calculate_loads: Load_Calculator = calculate_physics_loads) {
	assert(s.physics.active && dt > 0)
	physics_sync_structure(s)
	b2.World_Step(s.physics.world,dt,PHYSICS_SUBSTEPS)
	physics_read_motion(s)
	failures := calculate_loads(s,dt)
	apply_failures(s,failures)
	delete(failures.subdivisions); delete(failures.connections)
	delete(failures.discard_subdivisions)
	physics_sync_structure(s)
	fade_step(s,dt)
}
