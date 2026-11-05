package main

import "core:testing"
import "core:sync"
import "core:math"
import b2 "vendor:box2d"

@(test)
editor_layout_placement_materials_and_repeatable_test_transitions :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=sandbox_editor_create(); defer sandbox_destroy(&game)
	initial_ground:=counts_live_subdivisions(&game.world.scene)
	testing.expect(t,game.editor.editing && counts_live_subdivisions(&game.world.scene)==initial_ground)
	testing.expect(t,!editor_place(&game,{0,1},{0,2}))
	testing.expect(t,!editor_place(&game,{0,-0.1},{1,1}))
	testing.expect(t,!editor_place(&game,{-5,0},{-4,1}))
	for choice in Recipe {
		game.editor.palette=recipe_slot(choice)
		x:=f32(int(choice))*1.5-2
		testing.expect(t,editor_place(&game,{x,0},{x+1,1}))
	}
	testing.expect(t,!editor_place(&game,{-2,0.5},{-1,1.5}),"Authored overlaps must be rejected")
	testing.expect(t,editor_remove(&game,{-1.5,0.5}) && len(game.layout.objects)==3)
	game.editor.palette=recipe_slot(.Wood)
	testing.expect(t,editor_place(&game,{-1,1},{-2,0}),"Dragging in reverse must normalize the rectangle")
	identity:=game.layout.objects[3].identity
	testing.expect(t,identity==5,"Deleting an object must not recycle another object's generation context")
	pose:=b2.Body_GetPosition(game.world.player.body)
	sandbox_advance(&game,10,{move=1,jump_pressed=true})
	testing.expect(t,b2.Body_GetPosition(game.world.player.body)==pose && game.accumulator==0)
	sandbox_toggle_editor(&game)
	sandbox_reset(&game)
	testing.expect(t,len(game.world.scene.materials)==5 && game.world.scene.materials[0].subdivision_strength==35 && !game.world.scene.materials[0].triangulate)
	for object,i in game.layout.objects {
		piece:=game.world.scene.pieces[i]
		expected:=layout_material(&game.layout,object.material)
		actual:=game.world.scene.materials[piece.material]
		testing.expect(t,actual.impact_scale==expected.impact_scale && actual.name==expected.name && actual.subdivision_strength==expected.subdivision_strength && actual.connection_strength==expected.connection_strength && actual.flexibility==expected.flexibility && actual.triangulate==expected.triangulate)
		for id in piece.subdivisions {
			sub:=game.world.scene.subdivisions[game.world.scene.sub_rows[id]]
			testing.expect(t,sub.owner==piece.id && b2.Body_GetType(subdivision_body(&game.world.scene,id))==.dynamicBody)
   // Wood now refines even a 1x1 root. Its descendant birth contexts are
   // checked exactly by the reset comparison below, rather than as roots.
   if object.material==recipe_slot(.Wood) { testing.expect(t,sub.seed!=0) }
   else { testing.expect(t,sub.seed==derive_seed(42,0x10000+object.identity) || object.material==recipe_slot(.Rubber) && sub.seed==0) }
		}
	}
	for link in game.world.scene.connections {
		a,b:=game.world.scene.subdivisions[game.world.scene.sub_rows[link.a]],game.world.scene.subdivisions[game.world.scene.sub_rows[link.b]]
		testing.expect(t,a.owner==b.owner,"Separate objects must not acquire logical attachments")
	}
	initial,ok:=encode_snapshot(&game.world.scene); defer delete(initial); testing.expect(t,ok)
	testing.expect(t,sandbox_fixture_blast(&game,{-2.5,0.5}))
	_ = sandbox_route_input(&game,{reset_pressed=true},false)
	reset,reset_ok:=encode_snapshot(&game.world.scene); defer delete(reset); testing.expect(t,reset_ok)
	// A reset changes the revision, so compare the decoded graph and geometry.
	a,a_ok:=decode_snapshot(initial); defer scene_destroy(&a)
	b,b_ok:=decode_snapshot(reset); defer scene_destroy(&b)
	testing.expect(t,a_ok && b_ok); expect_same_blast_result(t,&a,&b)
	sandbox_toggle_editor(&game)
	testing.expect(t,game.editor.editing && len(game.layout.objects)==4 && game.layout.objects[3].identity==identity && counts_live_subdivisions(&game.world.scene)==initial_ground)
	expect_valid(t,&game.world.scene)
}

@(test)
editor_input_consumption_and_touching_objects_stay_separate :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=sandbox_editor_create(); defer sandbox_destroy(&game)
	game.editor.palette=recipe_slot(.Stone)
	testing.expect(t,editor_place(&game,{0,0},{0.8,0.8}) && editor_place(&game,{0.8,0},{1.6,0.8}))
	input:=sandbox_route_input(&game,{move=1,jump_pressed=true,blast_pressed=true,wheel=2},false)
	testing.expect(t,!input.jump_pressed && !input.blast_pressed && input.move==0 && game.world.settings.blast_radius==5)
	game.editor.dragging=true
	_ = sandbox_route_input(&game,{menu_pressed=true},false)
	testing.expect(t,!game.editor.dragging && game.panel_open)
	_ = sandbox_route_input(&game,{edit_pressed=true},false)
	testing.expect(t,game.editor.editing,"The paused settings panel must consume the Test shortcut")
	sandbox_set_panel(&game,false)
	_ = sandbox_route_input(&game,{edit_pressed=true,blast_down=true,jump_down=true},false)
	testing.expect(t,!game.editor.editing && len(game.world.scene.pieces)==3)
	input=sandbox_route_input(&game,{blast_pressed=true,blast_down=true,jump_pressed=true,jump_down=true},false)
	testing.expect(t,!input.blast_pressed && !input.jump_pressed,"A held drag or jump must not leak through the Test transition")
	_ = sandbox_route_input(&game,{},false)
	input=sandbox_route_input(&game,{blast_pressed=true,wheel=1},true)
	testing.expect(t,!input.blast_pressed && game.world.settings.blast_radius==5)
	input=sandbox_route_input(&game,{jump_pressed=true,jump_down=true},false)
	testing.expect(t,input.jump_pressed,"Space remains jump during Test")
	for _ in 0..<120 { sandbox_tick(&game,0,false) }
	testing.expect(t,len(game.world.scene.pieces)==3)
	expect_valid(t,&game.world.scene)
}

@(test)
rubber_deforms_before_failure_and_survives_a_removed_cell :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=sandbox_editor_create(); defer sandbox_destroy(&game)
	game.editor.palette=recipe_slot(.Rubber)
	testing.expect(t,editor_place(&game,{0,0},{2.4,0.8}))
	sandbox_toggle_editor(&game)
	owner:=game.world.scene.pieces[0].id
	ids:=game.world.scene.pieces[0].subdivisions
	initial_links:=len(game.world.scene.connections)
	initial_regions:=len(game.world.scene.subdivisions)
	testing.expect(t,len(ids)==12 && len(game.world.scene.pieces[0].connections)==16)
	for id in ids {
		sub:=game.world.scene.subdivisions[game.world.scene.sub_rows[id]]
		testing.expect(t,sub.seed==0 && sub.owner==owner && b2.Body_GetType(subdivision_body(&game.world.scene,id))==.dynamicBody)
	}
	grid: [dynamic]Polygon
	defer delete(grid)
	for id in ids { append(&grid,game.world.scene.subdivisions[game.world.scene.sub_rows[id]].outline) }
	points:=[4]Vec2{{0,0},{2.4,0},{2.4,0.8},{0,0.8}}
	expect_generation_partition(t,Polygon{points=points[:]},grid[:])
	for _ in 0..<60 { sandbox_tick(&game,0,false) }
	// A local nudge deforms the soft mesh under normal finite failure checks.
	b2.Body_ApplyLinearImpulseToCenter(subdivision_body(&game.world.scene,ids[len(ids)-1]),{0,0.3},true)
	max_gap,max_angle:=f32(0),f32(0)
	for _ in 0..<12 {
		sandbox_tick(&game,0,false)
		for c in game.world.scene.connections {
			if !c.live { continue }
			a,b:=game.world.scene.subdivisions[game.world.scene.sub_rows[c.a]],game.world.scene.subdivisions[game.world.scene.sub_rows[c.b]]
			max_gap=max(max_gap,vlen(vsub(posed_point(a,c.rest_point),posed_point(b,c.rest_point))))
			max_angle=max(max_angle,math.abs(a.pose.angle-b.pose.angle))
		}
	}
	live,links,pieces:=counts(&game.world.scene)
	testing.expectf(t,live==initial_regions && links==initial_links && pieces==2,"Ordinary deformation must precede failure: %d regions, %d links, %d pieces",live,links,pieces)
	testing.expectf(t,max_gap>0.015 && max_angle>0.02,"Rubber must stretch and bend: gap %.4f, angle %.4f",max_gap,max_angle)
	removed:=ids[8]
	f:=Failures{}; append(&f.discard_subdivisions,removed)
	apply_failures(&game.world.scene,f); free_failures(&f)
	physics_sync_structure(&game.world.scene)
	testing.expect(t,!b2.Body_IsValid(subdivision_body(&game.world.scene,removed)))
	live,links,pieces=counts(&game.world.scene)
	testing.expect(t,live==initial_regions-1 && links>0 && pieces==2,"Removing one internal cell must leave the remaining grid connected")
	for _ in 0..<120 { sandbox_tick(&game,0,false) }
	live,links,pieces=counts(&game.world.scene)
	testing.expect(t,live==initial_regions-1 && links>0 && pieces==2)
	expect_valid(t,&game.world.scene)
	// A sufficiently close ordinary radius-5 blast can remove finite cells.
	testing.expect(t,sandbox_fixture_blast(&game,{-0.2,0.5}))
	rubber_remaining:=0
	for sub in game.world.scene.subdivisions { if sub.live && game.world.scene.materials[sub.material].name=="rubber" { rubber_remaining+=1 } }
	testing.expect(t,rubber_remaining<11,"Finite terminal rubber cells must be removable by the blast")
	expect_valid(t,&game.world.scene)
}
