#+feature dynamic-literals
package main

import "core:math"
import "core:testing"
import "core:sync"
import b2 "vendor:box2d"

// Box2D's process-wide world registry is not safe for concurrent world creation.
physics_test_mutex: sync.Mutex

counts :: proc(s: ^Scene) -> (int,int,int) {
	a,b,c := 0,0,0
	for x in s.subdivisions { if x.live { a+=1 } }
	for x in s.connections { if x.live { b+=1 } }
	for x in s.pieces { if x.live { c+=1 } }
	return a,b,c
}
expect_valid :: proc(t: ^testing.T,s: ^Scene) { ok,message:=validate_scene(s); testing.expect(t,ok,message) }
close :: proc(a,b: f32) -> bool { return math.abs(a-b) < 0.001 }
close_vec :: proc(a,b: Vec2) -> bool { return vlen(vsub(a,b)) < 0.001 }
failure_for :: proc(ids: ..u64) -> Failures {
	f := Failures{}
	for id in ids { append(&f.subdivisions,id) }
	return f
}


@(test)
bridge_and_incident_removal :: proc(t: ^testing.T) {
	s:=make_wall(); defer scene_destroy(&s)
	f:=Failures{connections=[dynamic]u64{s.connections[0].id}}; defer free_failures(&f)
	apply_failures(&s,f)
	a,b,c:=counts(&s)
	testing.expect(t,a==3 && b==1 && c==2)
	expect_valid(t,&s)
	s2:=make_wall(); defer scene_destroy(&s2)
	f2:=failure_for(s2.subdivisions[1].id); defer free_failures(&f2)
	apply_failures(&s2,f2)
	a,b,c=counts(&s2)
	testing.expect(t,a==2 && b==0 && c==2)
	expect_valid(t,&s2)
}
@(test)
terminal_and_subthreshold_events :: proc(t: ^testing.T) {
	s:=make_wall(); defer scene_destroy(&s)
	strength:=s.materials[0].subdivision_strength
	for _ in 0..<10 { blast_pass(&s,Blast{position={1.5,-0.49},radius=1}) }
	a,b,c:=counts(&s)
	testing.expect(t,a==3 && b==2 && c==1)
	testing.expect(t,s.materials[0].subdivision_strength==strength)
	blast_pass(&s,Blast{position={1.5,0.5},radius=0.8})
	a,b,c=counts(&s)
	testing.expect(t,a==2 && b==0 && c==2 && len(s.subdivisions)==2)
	expect_valid(t,&s)
}
@(test)
infinite_strengths_survive :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	s.materials[0].subdivision_strength=math.inf_f32(1)
	s.materials[0].connection_strength=math.inf_f32(1)
	blast_pass(&s,Blast{position={1.5,0.5},radius=100})
	a,b,c:=counts(&s)
	testing.expect(t,a==3 && b==2 && c==1)
}
@(test)
replacement_inherits_surviving_attachments :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	f:=failure_for(s.subdivisions[1].id); defer free_failures(&f)
	apply_failures(&s,f)
	a,_,c:=counts(&s)
	testing.expect(t,a==4 && c==1)
	expect_valid(t,&s)
}
@(test)
broken_boundaries_do_not_heal :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	left:=s.subdivisions[0].id
	f:=failure_for(s.subdivisions[1].id); defer free_failures(&f)
	append(&f.connections,s.connections[0].id)
	apply_failures(&s,f)
	a,_,c:=counts(&s)
	testing.expect(t,a==4 && c==2)
	for connection in s.connections { testing.expect(t,!connection.live || (connection.a!=left && connection.b!=left)) }
	expect_valid(t,&s)
}
@(test)
simultaneous_endpoint_replacement :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	f:=failure_for(s.subdivisions[0].id,s.subdivisions[1].id); defer free_failures(&f)
	apply_failures(&s,f)
	a,_,c:=counts(&s)
	testing.expect(t,a==5 && c==1)
	expect_valid(t,&s)
}
@(test)
storage_and_failure_order_independence :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	r:=make_wall(42); defer scene_destroy(&r)
	f:=failure_for(s.subdivisions[0].id,s.subdivisions[1].id); defer free_failures(&f)
	g:=failure_for(r.subdivisions[1].id,r.subdivisions[0].id); defer free_failures(&g)
	r.subdivisions[0],r.subdivisions[2]=r.subdivisions[2],r.subdivisions[0]
	r.connections[0],r.connections[1]=r.connections[1],r.connections[0]
	for sub,i in r.subdivisions { r.sub_rows[sub.id]=i }
	for conn,i in r.connections { r.conn_rows[conn.id]=i }
	apply_failures(&s,f); apply_failures(&r,g)
	a,a_ok:=encode_snapshot(&s); defer delete(a)
	b,b_ok:=encode_snapshot(&r); defer delete(b)
	testing.expect(t,a_ok && b_ok && string(a)==string(b))
	expect_valid(t,&s); expect_valid(t,&r)
}
@(test)
same_blast_resolves_failed_children :: proc(t: ^testing.T) {
	s:=make_wall(42,0.08); defer scene_destroy(&s)
	s.materials[0].subdivision_strength=4.5
	s.materials[0].connection_strength=math.inf_f32(1)
	blast:=Blast{position={1.5,0.5},radius=0.8}
	blast_pass(&s,blast)
	a,_,_:=counts(&s)
	testing.expect(t,a>2 && s.next_id>10 && !is_live_subdivision(&s,7),"Children must be eligible to fail in their birth blast")
	remaining:=evaluate_blast(&s,blast); defer free_failures(&remaining)
	testing.expect(t,len(remaining.subdivisions)==0 && len(remaining.connections)==0)
	testing.expect(t,s.revision==1,"All refinement waves form one structural event")
	expect_valid(t,&s)
}
@(test)
motion_includes_rotation :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	parent:=s.subdivisions[1]
	parent.outline=make_polygon(parent.outline.points); defer delete(parent.outline.points)
	parent.pose=Pose{position={10,4},angle=0.7,velocity={1,2},angular_velocity=3}
	s.subdivisions[1].pose=parent.pose
	f:=failure_for(parent.id); defer free_failures(&f)
	apply_failures(&s,f)
	for child in s.subdivisions {
		if child.id<=6 { continue }
		r:=vsub(child.pose.position,parent.pose.position)
		expected:=vadd(parent.pose.velocity,Vec2{-3*r.y,3*r.x})
		testing.expect(t,close_vec(child.pose.velocity,expected) && close(child.pose.angular_velocity,3))
		testing.expect(t,close_vec(child.pose.position,posed_point(parent,child.rest_center)))
	}
}
@(test)
blast_impulse_is_applied_once_to_final_survivors :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=make_wall(42,0.04); defer scene_destroy(&s)
	s.materials[0].subdivision_strength=4.5
	s.materials[0].connection_strength=math.inf_f32(1)
	for &sub in s.subdivisions {
		sub.pose.velocity=vadd(Vec2{1,2},Vec2{-3*sub.pose.position.y,3*sub.pose.position.x})
		sub.pose.angular_velocity=3
	}
	physics_init(&s)
	last_root:=s.subdivisions[2].id
	retained_id:=s.subdivisions[0].id
	retained_body:=subdivision_body(&s,retained_id)
	blast:=Blast{position={1.5,0.5},radius=0.8}
	blast_pass(&s,blast)
	impulsed_children:=0
	for sub in s.subdivisions {
		expected:=vadd(Vec2{1,2},Vec2{-3*sub.pose.position.y,3*sub.pose.position.x})
		if sub.live {
			offset:=vsub(sub.pose.position,blast.position)
			distance:=vlen(offset)
			load:=blast_load(distance,blast.radius)
			if load>0 && distance>0.00001 {
				expected=vadd(expected,vmul(offset,load*BLAST_IMPULSE_SCALE/distance))
				if sub.id>last_root { impulsed_children+=1 }
			}
			testing.expect(t,close_vec(from_b2(b2.Body_GetLinearVelocity(subdivision_body(&s,sub.id))),expected))
			testing.expect(t,close(sub.pose.angular_velocity,3))
		} else {
			has_body:=subdivision_body(&s,sub.id)!=b2.nullBodyId
			testing.expect(t,!has_body)
		}
		testing.expect(t,close_vec(sub.pose.velocity,expected),"Removed ancestors receive no impulse; each final child uses its own sample once")
	}
	a,_,_:=counts(&s)
	testing.expect(t,impulsed_children>0 && physics_body_count(&s)==a && subdivision_body(&s,retained_id)==retained_body)
	expect_valid(t,&s)
}
@(test)
width_is_rotation_independent :: proc(t: ^testing.T) {
	s:=make_wall(); defer scene_destroy(&s)
	ids:=s.pieces[0].subdivisions[:]
	before:=piece_width(&s,ids)
	for i in 0..<len(s.subdivisions) { for j in 0..<len(s.subdivisions[i].outline.points) { s.subdivisions[i].outline.points[j]=vrotate(s.subdivisions[i].outline.points[j],0.738) } }
	testing.expect(t,close(before,piece_width(&s,ids)))
}
@(test)
small_subdivisions_can_form_large_piece :: proc(t: ^testing.T) {
 s:=make_wall(42,0.75); defer scene_destroy(&s)
 // Authored/legacy cells may be narrower than the generation cutoff. Group
 // filtering must retain them when connected; generation cannot create them.
 for &sub in s.subdivisions {
  for &point in sub.outline.points { point.x*=0.5 }
  sub.rest_center=centroid(sub.outline); sub.pose.position=sub.rest_center; sub.width=outline_width(sub.outline.points)
 }
 owner:=s.pieces[0].id; rebuild_piece(&s,owner); commit_structure(&s)
 a,_,c:=counts(&s)
 testing.expect(t,a==3 && c==1)
}
@(test)
width_filter_precedes_physics_creation :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=make_wall(42,1.1); defer scene_destroy(&s)
	physics_init(&s)
	f:=failure_for(s.subdivisions[1].id); defer free_failures(&f)
	apply_failures(&s,f)
	physics_sync_structure(&s)
	a,_,c:=counts(&s)
	// The failed parent is already below the subdivision cutoff, so it is
	// removed directly; its two former neighbors vanish immediately as well.
	testing.expect(t,a==0 && c==0 && physics_body_count(&s)==0 && len(s.subdivisions)==0 && len(s.connections)==0 && len(s.pieces)==0)
}
@(test)
ownership_split_preserves_body_handles_and_motion :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=make_wall(); defer scene_destroy(&s)
	physics_init(&s)
	id:=s.subdivisions[0].id
	body:=subdivision_body(&s,id)
	b2.Body_SetLinearVelocity(body,{3,4})
	physics_read_motion(&s)
	f:=Failures{connections=[dynamic]u64{s.connections[0].id}}; defer free_failures(&f)
	apply_failures(&s,f); physics_sync_structure(&s)
	testing.expect(t,subdivision_body(&s,id)==body && close_vec(from_b2(b2.Body_GetLinearVelocity(body)),Vec2{3,4}))
}
@(test)
concave_collision_fixtures_are_one_entity :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=new_scene(0); defer scene_destroy(&s)
	m:=add_material(&s,make_material(impact_scale=1,name="concave",subdivision_strength=math.inf_f32(1),connection_strength=math.inf_f32(1),generation_count=3,aspect_ratio=1))
	p:=add_piece(&s,m,1)
	poly:=make_polygon([]Vec2{{0,0},{2,0},{2,1},{1,1},{1,2},{0,2}}); defer delete(poly.points)
	id:=add_subdivision(&s,p,poly,Pose{position=centroid(poly)})

	physics_init(&s)
	testing.expect(t,len(s.subdivisions)==1 && physics_body_count(&s)==1 && s.subdivisions[s.sub_rows[id]].fixture_count>1)
	children:=generate_children(poly,s.materials[m],42)
	area: f32
	for child in children { area+=polygon_area(child); delete(child.points) }
	delete(children)
	testing.expect(t,close(area,3))
}
@(test)
joint_overload_keeps_bonds_intact :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=make_wall(); defer scene_destroy(&s)
	s.materials[0].subdivision_strength=math.inf_f32(1)
	s.materials[0].connection_strength=0.001
	physics_init(&s)
	b2.Body_ApplyLinearImpulseToCenter(subdivision_body(&s,s.subdivisions[0].id),{0,10},true)
	physics_tick(&s,1.0/60.0)
	a,b,c:=counts(&s)
	testing.expect(t,a==3 && b==2 && c==1)
	expect_valid(t,&s)
}
@(test)
physical_impact_removes_geometry :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=new_scene(0); defer scene_destroy(&s)
	m:=add_material(&s,make_material(impact_scale=1,name="impact",subdivision_strength=0.1,connection_strength=1,generation_count=2,aspect_ratio=1))
	p:=add_piece(&s,m,42)
	poly:=make_polygon([]Vec2{{0,0},{1,0},{1,1},{0,1}}); defer delete(poly.points)
	id:=add_subdivision(&s,p,poly,Pose{position=centroid(poly),velocity={0,-10}})

	physics_init(&s,Vec2{0,-10})
	ground_def:=b2.DefaultBodyDef(); ground_def.position={0,-1}
	ground:=b2.CreateBody(s.physics.world,ground_def)
	shape_def:=b2.DefaultShapeDef()
	box:=b2.MakeBox(10,0.1)
	_ = b2.CreatePolygonShape(ground,shape_def,box)
	for _ in 0..<30 { if !is_live_subdivision(&s,id) { break }; physics_tick(&s,1.0/60.0) }
	testing.expect(t,!is_live_subdivision(&s,id))
}
overload_every_subdivision :: proc(s: ^Scene,dt: f32) -> Failures {
	f:=Failures{}
	for sub in s.subdivisions { if sub.live { append(&f.subdivisions,sub.id) } }
	return f
}
@(test)
replaceable_load_policy_advances_on_later_ticks :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=make_wall(42,0.01); defer scene_destroy(&s)
	physics_init(&s)
	physics_tick(&s,1.0/60.0,overload_every_subdivision)
	a,_,_:=counts(&s)
	testing.expect(t,a==6 && len(s.subdivisions)==6)
	physics_tick(&s,1.0/60.0,overload_every_subdivision)
	b,_,_:=counts(&s)
	testing.expect(t,b>a)
	expect_valid(t,&s)
}
@(test)
snapshot_roundtrip_and_split :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	s.materials[0].connection_strength=math.inf_f32(1)
	f:=failure_for(s.subdivisions[1].id); defer free_failures(&f)
	apply_failures(&s,f)
	bytes,ok:=encode_snapshot(&s); defer delete(bytes)
	testing.expect(t,ok)
	receiver,decoded:=decode_snapshot(bytes); defer scene_destroy(&receiver)
	testing.expect(t,decoded)
	if !decoded { return }
	expect_valid(t,&receiver)
	roundtrip,encoded:=encode_snapshot(&receiver); defer delete(roundtrip)
	testing.expect(t,encoded && string(bytes)==string(roundtrip))
	g:=Failures{connections=[dynamic]u64{receiver.connections[0].id}}; defer free_failures(&g)
	apply_failures(&receiver,g)
	expect_valid(t,&receiver)
	invalid_json := string(`{"version":3}`)
	invalid,accepted:=decode_snapshot(transmute([]byte)invalid_json)
	testing.expect(t,!accepted)
	if accepted { scene_destroy(&invalid) }
}
@(test)
interpolation_wraps_angles :: proc(t: ^testing.T) {
	a:=Pose{position={0,0},angle=3.1}
	b:=Pose{position={2,4},angle=-3.1}
	mid:=interpolate_pose(a,b,0.5)
	testing.expect(t,close_vec(mid.position,Vec2{1,2}) && math.abs(mid.angle-f32(math.PI))<0.001)
}
@(test)
direct_debug_removal_discards_nonterminal_geometry :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	f:=Failures{discard_subdivisions=[dynamic]u64{s.subdivisions[1].id}}; defer free_failures(&f)
	apply_failures(&s,f)
	a,_,c:=counts(&s)
	testing.expect(t,a==2 && c==2 && len(s.subdivisions)==2)
}
@(test)
unpartitionable_attached_subdivision_is_removed :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	cases:=[4]struct { width,height: f32, count: int, triangular: bool }{
		{0.005,0.01,2,false}, // Below the minimum split area.
		{0.015,0.01,2,false}, // Both cut children would be too small.
		{0.01,0.01,2,true},   // Triangulation yields the same single triangle.
		{0.5,1,1,false},      // A recipe requesting only one region.
	}
	for fixture in cases {
		s:=new_scene(0.1); defer scene_destroy(&s)
		m:=add_material(&s,make_material(impact_scale=1,name="small attached",subdivision_strength=6,connection_strength=math.inf_f32(1),generation_count=fixture.count,aspect_ratio=1,triangulate=fixture.triangular))
		owner:=add_piece(&s,m,42)
		w,h:=fixture.width,fixture.height
		small:=make_polygon([]Vec2{{0,0},{w,0},{w,h},{0,h}})
		if fixture.triangular { delete(small.points); small=make_polygon([]Vec2{{0,0},{w,0},{w,h}}) }
		defer delete(small.points)
		large:=make_polygon([]Vec2{{w,0},{w+1,0},{w+1,1},{w,1}}); defer delete(large.points)
		small_id:=add_subdivision(&s,owner,small,Pose{position=centroid(small)})
		large_id:=add_subdivision(&s,owner,large,Pose{position=centroid(large)})

		connection:=add_connection(&s,small_id,large_id)

		testing.expect(t,connection!=0 && piece_width(&s,s.pieces[0].subdivisions[:])>=s.minimum_width)
		physics_init(&s)
		large_body:=subdivision_body(&s,large_id)
		live_vertices:=len(large.points)
		last_id:=s.next_id
		for pass in 0..<4 {
			// Re-select any replacement of the small region on each overload pass.
			f:=Failures{}
			for sub in s.subdivisions { if sub.live && sub.id!=large_id { append(&f.subdivisions,sub.id) } }
			apply_failures(&s,f); free_failures(&f); physics_sync_structure(&s)
			subs,conns,pieces:=counts(&s)
			testing.expect(t,subs==1 && conns==0 && pieces==1)
			testing.expect(t,len(s.subdivisions)==1 && vertex_count(&s)==live_vertices && physics_body_count(&s)==1)
			testing.expect(t,subdivision_body(&s,large_id)==large_body)
			if pass>0 { testing.expect(t,s.next_id==last_id) }
			last_id=s.next_id
			expect_valid(t,&s)
		}
	}
}
@(test)
partial_generation_keeps_a_genuine_partition :: proc(t: ^testing.T) {
	parent:=make_polygon([]Vec2{{0,0},{0.03,0},{0.03,0.01},{0,0.01}}); defer delete(parent.points)
	children:=generate_children(parent,make_material(impact_scale=1,generation_count=4,aspect_ratio=1),42)
	defer { for child in children { delete(child.points) }; delete(children) }
	testing.expect(t,len(children)==2)
	area: f32
	for child in children {
		child_area:=polygon_area(child)
		testing.expect(t,child_area>0 && child_area<polygon_area(parent))
		area+=child_area
	}
	testing.expect(t,math.abs(area-polygon_area(parent))<0.000001)
}
@(test)
blast_radius_controls_direct_load_and_power :: proc(t: ^testing.T) {
	s:=make_wall(); defer scene_destroy(&s)
	s.materials[0].subdivision_strength=20
	s.materials[0].connection_strength=20
	weak:=evaluate_blast(&s,Blast{position={1,0.5},radius=1}); defer free_failures(&weak)
	testing.expect(t,len(weak.subdivisions)==0 && len(weak.connections)==0)
	strong:=evaluate_blast(&s,Blast{position={1,0.5},radius=3}); defer free_failures(&strong)
	// The same samples at distance 0.5 now receive 25, exceeding strength 20.
	testing.expect(t,len(strong.subdivisions)==2 && contains_id(strong.subdivisions[:],s.subdivisions[0].id) && contains_id(strong.subdivisions[:],s.subdivisions[1].id))
	testing.expect(t,len(strong.connections)==2)
	testing.expect(t,close(blast_load(0.5,1),5) && close(blast_load(0.5,3),25))
	testing.expect(t,blast_load(3,3)==0 && blast_load(4,3)==0 && blast_load(0,0)==0 && blast_load(0,-1)==0)
}
@(test)
flexible_and_stiff_materials_respond_differently :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	separations: [2]f32
	for i in 0..<2 {
		s:=make_wall()
		s.materials[0].flexibility=f32(i)
		s.materials[0].subdivision_strength=math.inf_f32(1); s.materials[0].connection_strength=math.inf_f32(1)
		physics_init(&s)
		b2.Body_ApplyLinearImpulseToCenter(subdivision_body(&s,s.subdivisions[0].id),{0,1},true)
		physics_tick(&s,1.0/60.0)
		c:=s.connections[0]
		a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
		separations[i]=vlen(vsub(posed_point(a,c.rest_point),posed_point(b,c.rest_point)))
		scene_destroy(&s)
	}
	testing.expect(t,separations[1]>separations[0]+0.001)
}
@(test)
preset_scenes_remain_valid_through_repeated_blasts :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	for preset in 0..<3 {
		s:=make_wall(42,0.08)
		s.materials[0]=test_recipe(preset)
		physics_init(&s)
		for _ in 0..<6 {
			point:=Vec2{}
			selected:=u64(0)
			for sub in s.subdivisions { if sub.live { point=vadd(sub.pose.position,Vec2{0.05,0}); selected=sub.id; break } }
			if selected==0 { break }
			// Exercise actual recursive breakup at each preset's strength.
			// A radius of 1.05 alone cannot fail their 30..55 thresholds.
			blast_pass(&s,Blast{position=point,radius=1.05+s.materials[0].subdivision_strength/BLAST_LOAD_MULTIPLIER})
			testing.expect(t,!is_live_subdivision(&s,selected))
			for _ in 0..<3 { physics_tick(&s,1.0/60.0) }
			expect_valid(t,&s)
		}
		scene_destroy(&s)
	}
}
@(test)
narrow_separated_group_vanishes :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=new_scene(0.1); defer scene_destroy(&s)
	m:=add_material(&s,test_recipe(0))
	owner:=add_piece(&s,m,0)
	thin:=make_polygon([]Vec2{{0,0},{0.05,0},{0.05,1},{0,1}}); defer delete(thin.points)
	wide:=make_polygon([]Vec2{{0.05,0},{1.05,0},{1.05,1},{0.05,1}}); defer delete(wide.points)
	a:=add_subdivision(&s,owner,thin,Pose{position=centroid(thin)})
	b:=add_subdivision(&s,owner,wide,Pose{position=centroid(wide)})

	c:=add_connection(&s,a,b);
	physics_init(&s)
	f:=Failures{connections=[dynamic]u64{c}}; defer free_failures(&f)
	apply_failures(&s,f); physics_sync_structure(&s)
	subs,conns,pieces:=counts(&s)
	testing.expect(t,subs==1 && conns==0 && pieces==1 && len(s.subdivisions)==1 && physics_body_count(&s)==1)
	testing.expect(t,is_live_subdivision(&s,b) && !is_live_subdivision(&s,a))
	expect_valid(t,&s)
}
@(test)
opposing_contacts_do_not_cancel_destruction_load :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=new_scene(0); defer scene_destroy(&s)
	m:=add_material(&s,make_material(impact_scale=1,name="squeeze",subdivision_strength=0.01,connection_strength=1,generation_count=2,aspect_ratio=1))
	owner:=add_piece(&s,m,42)
	outline:=make_polygon([]Vec2{{0,0},{1,0},{1,1},{0,1}}); defer delete(outline.points)
	id:=add_subdivision(&s,owner,outline,Pose{position=centroid(outline)})

	physics_init(&s)
	for i in 0..<2 {
		def:=b2.DefaultBodyDef(); def.position={-0.1+1.2*f32(i),0.5}
		// Opposing damaging contacts must be actual impacts, not stationary
		// overlap correction, which is deliberately harmless now.
		def.type=.kinematicBody; def.linearVelocity={2-4*f32(i),0}
		wall:=b2.CreateBody(s.physics.world,def)
		shape_def:=b2.DefaultShapeDef(); box:=b2.MakeBox(0.2,2)
		_ = b2.CreatePolygonShape(wall,shape_def,box)
	}
	physics_tick(&s,1.0/60.0)
	testing.expect(t,!is_live_subdivision(&s,id))
}
