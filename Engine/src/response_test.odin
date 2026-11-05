package main

import "core:testing"
import "core:sync"
import "core:math"
import "core:strings"
import "core:fmt"
import b2 "vendor:box2d"

@(test)
placed_materials_and_floor_survive_support_and_negligible_settling :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	choices:=[2]Recipe{.Wood,.Stone}
	// Include the prior drop rectangle, a translated floor-torque reproducer,
	// and a larger root whose ordinary support exceeded both preset strengths.
	cases:=[4][3]f32{{1.5,2.4,0},{2,2.4,0},{1.5,3.8,0},{1.5,3.8,0.005}}
	for choice in choices {
		for placement in cases {
			g:=sandbox_editor_create(); g.editor.palette=recipe_slot(choice)
			x,size,gap:=placement[0],placement[1],placement[2]
			testing.expect(t,editor_place(&g,{x,gap},{x+size,gap+size})); sandbox_toggle_editor(&g)
			object:=g.world.scene.subdivisions[0].id
            ground:=g.world.scene.subdivisions[len(g.world.scene.subdivisions)-1].id
			before_regions,before_links,before_pieces:=counts(&g.world.scene)
            before_id:=g.world.scene.next_id
			for _ in 0..<300 { sandbox_tick(&g,0,false) }
			a,b,c:=counts(&g.world.scene)
			testing.expectf(t,a==before_regions && b==before_links && c==before_pieces && g.world.scene.next_id==before_id,"%v size %.1f gap %.3f must stay intact: %d/%d/%d",choice,size,gap,a,b,c)
			testing.expect(t,is_live_subdivision(&g.world.scene,object) && is_live_subdivision(&g.world.scene,ground))
			expect_valid(t,&g.world.scene); sandbox_destroy(&g)
		}
	}
}

// A flat, single-region drop isolates region impact damage from bond stress.
@(test)
flat_drops_match_velocity_change_thresholds_and_leave_floor_intact :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	choices:=[3]Recipe{.Glass,.Stone,.Wood}
	ratios:=[2]f32{0.7,1.3}
	for choice in choices {
		m:=editor_material(choice)
		threshold:=math.pow(m.subdivision_strength*BLAST_IMPULSE_SCALE/m.impact_scale,2)/(2*9.8)
		steps:=[3]f32{1.0/60,1.0/30,1.0/120}
		for dt in steps { for ratio in ratios {
			g:=single_region_drop_yard(choice)
			object,ground:=g.world.scene.subdivisions[0].id,g.world.scene.subdivisions[1].id
			testing.expect(t,len(g.world.scene.subdivisions)==2 && len(g.world.scene.connections)==0)
			body:=subdivision_body(&g.world.scene,object); pos:=b2.Body_GetPosition(body); pos.y+=threshold*ratio
			b2.Body_SetTransform(body,pos,b2.MakeRot(0)); b2.Body_SetAwake(body,true)
			first_speed,first_load:=f32(0),f32(0)
			for _ in 0..<int(3/dt) {
				// Inspect events before the structural update invalidates shape IDs.
				b2.World_Step(g.world.scene.physics.world,dt,PHYSICS_SUBSTEPS)
				if first_speed==0 && is_live_subdivision(&g.world.scene,object) {
					events:=b2.World_GetContactEvents(g.world.scene.physics.world)
					for hit in events.hitEvents[:events.hitCount] {
						a,b:=b2.Shape_GetBody(hit.shapeIdA),b2.Shape_GetBody(hit.shapeIdB)
						if a==body || b==body {
							other:=a; if a==body { other=b }
							first_speed=max(first_speed,hit.approachSpeed)
							first_load=max(first_load,contact_damage_load(&g.world.scene,body,other,hit.approachSpeed,m.impact_scale))
						}
					}
				}
				physics_read_motion(&g.world.scene)
				f:=calculate_physics_loads(&g.world.scene,dt); apply_failures(&g.world.scene,f); free_failures(&f)
				physics_sync_structure(&g.world.scene)
			}
			intact:=is_live_subdivision(&g.world.scene,object)
			testing.expectf(t,intact==(ratio<1),"%v dt %.5f drop %.4f (%.1fx threshold %.4f)",choice,dt,threshold*ratio,ratio,threshold)
			testing.expect(t,first_speed>0 && is_live_subdivision(&g.world.scene,ground),"Static anchored floor must take no contact damage")
			if dt==steps[0] { fmt.printf("Drop %v: h=%.4f threshold=%.4f closing=%.4f load=%.4f intact=%v floor_intact=true\n",choice,threshold*ratio,threshold,first_speed,first_load,intact) }
			expect_valid(t,&g.world.scene); sandbox_destroy(&g)
		} }

	}
}
@(test)
rubber_high_drop_survives_and_blasts_still_destroy_every_material :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	for choice in Recipe {
		g:=sandbox_editor_create(); g.editor.palette=recipe_slot(choice)
		gap:=f32(0); if choice==.Rubber { gap=3.6 }
		testing.expect(t,editor_place(&g,{1.5,gap},{3.9,gap+1.2})); sandbox_toggle_editor(&g)
		ids:=[dynamic]u64{}; for sub in g.world.scene.subdivisions { append(&ids,sub.id) }
		before,initial_links:=g.world.scene.next_id,len(g.world.scene.connections)
		for _ in 0..<240 { sandbox_tick(&g,0,false) }
		for id in ids { testing.expect(t,is_live_subdivision(&g.world.scene,id)) }
		testing.expect(t,g.world.scene.next_id==before && len(g.world.scene.connections)==initial_links,"Placement/drop must retain all cells and bonds without refining geometry")
		
		testing.expect(t,sandbox_fixture_blast(&g,{1.45,0.6}))
		removed:=false
		for id in ids { if !is_live_subdivision(&g.world.scene,id) { removed=true } }
		testing.expectf(t,removed && g.world.scene.next_id>before,"%v object and floor must still fail from a blast",choice)
		delete(ids); expect_valid(t,&g.world.scene); sandbox_destroy(&g)
	}
}
@(test)
weld_reactions_never_damage_geometry_or_bonds :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	cases:=[2]bool{true,false}
	for breaks in cases {
		s:=make_wall(); s.materials[0].subdivision_strength=0.000001
		s.materials[0].connection_strength=math.inf_f32(1)
		if breaks { s.materials[0].connection_strength=0.001 }
		physics_init(&s)
		b2.Body_ApplyLinearImpulseToCenter(subdivision_body(&s,s.subdivisions[0].id),{0,10},true)
		b2.World_Step(s.physics.world,1.0/60.0,PHYSICS_SUBSTEPS); physics_read_motion(&s)
		f:=calculate_physics_loads(&s,1.0/60.0)
		testing.expect(t,len(f.subdivisions)==0)
		testing.expect(t,len(f.connections)==0)
		free_failures(&f); scene_destroy(&s)
	}
}
@(test)
player_and_bomb_contacts_do_not_damage_palette_objects :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	for choice in Recipe {
		g:=sandbox_editor_create(); g.editor.palette=recipe_slot(choice)
		testing.expect(t,editor_place(&g,{-3.5,0},{-1.1,2.4})); sandbox_toggle_editor(&g)
		before:=g.world.scene.next_id
		// Full speed before contact; then keep running into the rectangle.
		b2.Body_SetLinearVelocity(g.world.players[0].body,{PLAYER_TUNING.speed,0})
		for _ in 0..<120 { sandbox_tick(&g,1,false) }
		testing.expectf(t,g.world.scene.next_id==before,"Player must not damage %v",choice)
		// Drop onto both the object and the exposed floor from normal bomb height.
		positions:=[2]Vec2{{-2.3,BOMB_SKY_HEIGHT},{5,BOMB_SKY_HEIGHT}}
		for position in positions {
			bomb_spawn(&g,position)
			landed:=false
			for _ in 0..<180 {
				sandbox_tick(&g,0,false)
				if g.world.bombs[0].landed { landed=true; break }
			}
			testing.expect(t,landed)
			for _ in 0..<30 { sandbox_tick(&g,0,false) }
			testing.expectf(t,g.world.scene.next_id==before,"Bomb landing/fuse must not damage %v or floor",choice)
			bomb_rain_clear(&g.world)
		}
		expect_valid(t,&g.world.scene); sandbox_destroy(&g)
	}
}
@(test)
hit_events_include_impacts_after_contact_begin :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	g:=single_region_drop_yard(.Wood); defer sandbox_destroy(&g)
	for _ in 0..<120 { physics_tick(&g.world.scene,1.0/60) }
	body:=g.world.scene.subdivisions[0].body
	// Repeated closing motion without separating the existing contact pair.
	for _ in 0..<2 {
		b2.Body_SetLinearVelocity(body,{0,-2})
		b2.World_Step(g.world.scene.physics.world,1.0/60.0,PHYSICS_SUBSTEPS)
		events:=b2.World_GetContactEvents(g.world.scene.physics.world)
		found:=false
		for hit in events.hitEvents[:events.hitCount] {
			if b2.Shape_GetBody(hit.shapeIdA)==body || b2.Shape_GetBody(hit.shapeIdB)==body {
				found=hit.approachSpeed>1.9
			}
		}
		testing.expect(t,events.beginCount==0 && found,"Hit events must report closing speed on existing contact every step")
	}
}

@(test)
render_seams_share_t_junctions_without_changing_simulation :: proc(t: ^testing.T) {
 cache_state:=Render_Cache_State{}; defer release_render_caches(&cache_state)
 caches:=&cache_state
	s:=new_scene(0.1); defer scene_destroy(&s)
	m:=add_material(&s,editor_material(.Wood)); p:=add_piece(&s,m,42)
	bounds:=[3][4]Vec2{{{0,0},{1,0},{1,2},{0,2}},{{1,0},{2,0},{2,1},{1,1}},{{1,1},{2,1},{2,2},{1,2}}}
	ids:[3]u64
	for points,i in bounds { vertices:=points; outline:=Polygon{points=vertices[:]}; ids[i]=add_subdivision(&s,p,outline,Pose{position=centroid(outline)}); }
	for i in 1..<3 { add_connection(&s,ids[0],ids[i]); }
	s.subdivisions[1].pose.position.x+=0.0002; s.subdivisions[2].pose.position.y+=0.0002
	poses:=make(map[u64]Pose); defer delete(poses)
	before,ok:=encode_snapshot(&s); defer delete(before); testing.expect(t,ok)
	render_cache_prepass(&s,caches)
	outline:=render_outline(&s,caches,s.subdivisions[0],poses,true); defer delete(outline.points)
	testing.expect(t,len(outline.points)==5,"Render copy must include the T junction")
	after,after_ok:=encode_snapshot(&s); defer delete(after)
	testing.expect(t,after_ok && string(before)==string(after),"Rendering must not mutate simulation geometry or poses")
}

@(test)
physical_loads_use_mass_ratio_and_velocity_units :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=make_wall(); defer scene_destroy(&s); physics_init(&s)
	a,b:=s.subdivisions[0].body,s.subdivisions[1].body
	b2.Body_SetUserData(a,nil); b2.Body_SetUserData(b,nil)
	b2.Body_SetMassData(a,b2.MassData{mass=2,rotationalInertia=1})
	b2.Body_SetMassData(b,b2.MassData{mass=6,rotationalInertia=1})
	testing.expect(t,close(contact_damage_load(&s,a,b,4,1),15))
	testing.expect(t,close(contact_damage_load(&s,b,a,4,1),5))
	testing.expect(t,close(contact_damage_load(&s,a,b,4,1.6),24))
	testing.expect(t,contact_damage_load(&s,a,b,100,0)==0)
	b2.Body_SetType(b,.staticBody)
	testing.expect(t,close(contact_damage_load(&s,a,b,4,1),20))
	testing.expect(t,contact_damage_load(&s,b,a,100,1)==0)
	// There is no former one-unit/s gate, nor an impulse/time/lever-arm term.
	testing.expect(t,close(contact_damage_load(&s,a,b,0.5,1),2.5))
}
@(test)
impact_scale_roundtrips_zero_and_old_snapshots_default_to_one :: proc(t: ^testing.T) {
	s:=make_wall(); defer scene_destroy(&s)
	s.materials[0].impact_scale=0
	data,ok:=encode_snapshot(&s); defer delete(data); testing.expect(t,ok)
	r,decoded:=decode_snapshot(data); defer scene_destroy(&r)
	testing.expect(t,decoded && r.materials[0].impact_scale==0)
	old,allocated:=strings.replace_all(string(data),"\"impact_scale\": 0.00000000,",""); defer { if allocated { delete(old) } }
	legacy,legacy_ok:=decode_snapshot(transmute([]byte)old); defer scene_destroy(&legacy)
	testing.expect(t,legacy_ok && legacy.materials[0].impact_scale==1)
	s.materials[0].impact_scale=1.6
	stone,stone_ok:=encode_snapshot(&s); defer delete(stone); testing.expect(t,stone_ok)
	r2,r2_ok:=decode_snapshot(stone); defer scene_destroy(&r2)
	testing.expect(t,r2_ok && r2.materials[0].impact_scale==1.6)
	s.materials[0].impact_scale=-1
	bad,bad_ok:=encode_snapshot(&s); defer delete(bad); testing.expect(t,bad_ok)
	r3,accepted:=decode_snapshot(bad); defer scene_destroy(&r3); testing.expect(t,!accepted)
	for i in 0..<3 { testing.expect(t,test_recipe(i).impact_scale==1) }
}

// Retain the isolated, single-region analytic test alongside pre-split drop tests.
single_region_drop_yard :: proc(choice: Recipe) -> Sandbox {
 g:=Sandbox{world=World{scene=new_scene(0.1)}}; s:=&g.world.scene
 m:=add_material(s,editor_material(choice)); p:=add_piece(s,m,42)
 vertices:=[4]Vec2{{1.5,0},{3.9,0},{3.9,2.4},{1.5,2.4}}; poly:=Polygon{points=vertices[:]}
 add_subdivision(s,p,poly,Pose{position=centroid(poly)})
 p=add_piece(s,m,42); floor:=[4]Vec2{{-8,-3},{9,-3},{9,0},{-8,0}}; poly={points=floor[:]}
 add_subdivision(s,p,poly,Pose{position=centroid(poly)})
 physics_init(s,{0,-9.8},-3)
 return g
}
