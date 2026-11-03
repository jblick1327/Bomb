package main

import "core:testing"
import "core:sync"
import "core:math"
import b2 "vendor:box2d"

@(test)
editor_layout_placement_materials_and_repeatable_test_transitions :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=sandbox_editor_create(); defer sandbox_destroy(&game)
	initial_ground:=counts_live_subdivisions(&game.scene)
	testing.expect(t,game.editor.editing && counts_live_subdivisions(&game.scene)==initial_ground)
	testing.expect(t,!editor_place(&game,{0,1},{0,2}))
	testing.expect(t,!editor_place(&game,{0,-0.1},{1,1}))
	testing.expect(t,!editor_place(&game,{-5,0},{-4,1}))
	for choice in Palette {
		game.editor.palette=choice
		x:=f32(int(choice))*1.5-2
		testing.expect(t,editor_place(&game,{x,0},{x+1,1}))
	}
	testing.expect(t,!editor_place(&game,{-2,0.5},{-1,1.5}),"Authored overlaps must be rejected")
	testing.expect(t,editor_remove(&game,{-1.5,0.5}) && len(game.editor.objects)==3)
	game.editor.palette=.Wood
	testing.expect(t,editor_place(&game,{-1,1},{-2,0}),"Dragging in reverse must normalize the rectangle")
	identity:=game.editor.objects[3].identity
	testing.expect(t,identity==5,"Deleting an object must not recycle another object's generation context")
	pose:=b2.Body_GetPosition(game.player.body)
	sandbox_advance(&game,10,{move=1,jump_pressed=true})
	testing.expect(t,b2.Body_GetPosition(game.player.body)==pose && game.accumulator==0)
	sandbox_toggle_editor(&game)
	sandbox_reset(&game)
	testing.expect(t,len(game.scene.materials)==5 && game.scene.materials[0].subdivision_strength==35 && !game.scene.materials[0].triangulate)
	for object,i in game.editor.objects {
		piece:=game.scene.pieces[i]
		expected:=editor_material(object.material)
		actual:=game.scene.materials[piece.material]
		testing.expect(t,actual.impact_scale==expected.impact_scale && actual.name==expected.name && actual.subdivision_strength==expected.subdivision_strength && actual.connection_strength==expected.connection_strength && actual.flexibility==expected.flexibility && actual.triangulate==expected.triangulate)
		for id in piece.subdivisions {
			sub:=game.scene.subdivisions[game.scene.sub_rows[id]]
			testing.expect(t,sub.owner==piece.id && b2.Body_GetType(subdivision_body(&game.scene,id))==.dynamicBody)
			testing.expect(t,sub.seed==derive_seed(42,0x10000+object.identity) || object.material==.Rubber && sub.seed==0)
		}
	}
	for link in game.scene.connections {
		a,b:=game.scene.subdivisions[game.scene.sub_rows[link.a]],game.scene.subdivisions[game.scene.sub_rows[link.b]]
		testing.expect(t,a.owner==b.owner,"Separate objects must not acquire logical attachments")
	}
	initial,ok:=encode_snapshot(&game.scene); defer delete(initial); testing.expect(t,ok)
	testing.expect(t,sandbox_blast(&game,{-2.5,0.5}))
	_ = sandbox_route_input(&game,{reset_pressed=true},false)
	reset,reset_ok:=encode_snapshot(&game.scene); defer delete(reset); testing.expect(t,reset_ok)
	// A reset changes the revision, so compare the decoded graph and geometry.
	a,a_ok:=decode_snapshot(initial); defer scene_destroy(&a)
	b,b_ok:=decode_snapshot(reset); defer scene_destroy(&b)
	testing.expect(t,a_ok && b_ok); expect_same_blast_result(t,&a,&b)
	sandbox_toggle_editor(&game)
	testing.expect(t,game.editor.editing && len(game.editor.objects)==4 && game.editor.objects[3].identity==identity && counts_live_subdivisions(&game.scene)==initial_ground)
	expect_valid(t,&game.scene)
}

@(test)
editor_input_consumption_and_touching_objects_stay_separate :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=sandbox_editor_create(); defer sandbox_destroy(&game)
	game.editor.palette=.Stone
	testing.expect(t,editor_place(&game,{0,0},{0.8,0.8}) && editor_place(&game,{0.8,0},{1.6,0.8}))
	input:=sandbox_route_input(&game,{move=1,jump_pressed=true,blast_pressed=true,wheel=2},false)
	testing.expect(t,!input.jump_pressed && !input.blast_pressed && input.move==0 && game.applied.blast_radius==5)
	game.editor.dragging=true
	_ = sandbox_route_input(&game,{menu_pressed=true},false)
	testing.expect(t,!game.editor.dragging && game.panel_open)
	_ = sandbox_route_input(&game,{edit_pressed=true},false)
	testing.expect(t,game.editor.editing,"The paused settings panel must consume the Test shortcut")
	sandbox_set_panel(&game,false)
	_ = sandbox_route_input(&game,{edit_pressed=true,blast_down=true,jump_down=true},false)
	testing.expect(t,!game.editor.editing && len(game.scene.pieces)==3)
	input=sandbox_route_input(&game,{blast_pressed=true,blast_down=true,jump_pressed=true,jump_down=true},false)
	testing.expect(t,!input.blast_pressed && !input.jump_pressed,"A held drag or jump must not leak through the Test transition")
	_ = sandbox_route_input(&game,{},false)
	input=sandbox_route_input(&game,{blast_pressed=true,wheel=1},true)
	testing.expect(t,!input.blast_pressed && game.applied.blast_radius==5)
	input=sandbox_route_input(&game,{jump_pressed=true,jump_down=true},false)
	testing.expect(t,input.jump_pressed,"Space remains jump during Test")
	for _ in 0..<120 { sandbox_tick(&game,0,false) }
	testing.expect(t,len(game.scene.pieces)==3)
	expect_valid(t,&game.scene)
}

@(test)
rubber_deforms_before_failure_and_survives_a_removed_cell :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=sandbox_editor_create(); defer sandbox_destroy(&game)
	game.editor.palette=.Rubber
	testing.expect(t,editor_place(&game,{0,0},{2.4,0.8}))
	sandbox_toggle_editor(&game)
	owner:=game.scene.pieces[0].id
	ids:=game.scene.pieces[0].subdivisions
	initial_links:=len(game.scene.connections)
	initial_regions:=len(game.scene.subdivisions)
	testing.expect(t,len(ids)==12 && len(game.scene.pieces[0].connections)==16)
	for id in ids {
		sub:=game.scene.subdivisions[game.scene.sub_rows[id]]
		testing.expect(t,sub.seed==0 && sub.owner==owner && b2.Body_GetType(subdivision_body(&game.scene,id))==.dynamicBody)
	}
	grid: [dynamic]Polygon
	defer delete(grid)
	for id in ids { append(&grid,game.scene.subdivisions[game.scene.sub_rows[id]].outline) }
	points:=[4]Vec2{{0,0},{2.4,0},{2.4,0.8},{0,0.8}}
	expect_generation_partition(t,Polygon{points=points[:]},grid[:])
	for _ in 0..<60 { sandbox_tick(&game,0,false) }
	// A local nudge deforms the soft mesh under normal finite failure checks.
	b2.Body_ApplyLinearImpulseToCenter(subdivision_body(&game.scene,ids[len(ids)-1]),{0,0.3},true)
	max_gap,max_angle:=f32(0),f32(0)
	for _ in 0..<12 {
		sandbox_tick(&game,0,false)
		for c in game.scene.connections {
			if !c.live { continue }
			a,b:=game.scene.subdivisions[game.scene.sub_rows[c.a]],game.scene.subdivisions[game.scene.sub_rows[c.b]]
			max_gap=max(max_gap,vlen(vsub(posed_point(a,c.rest_point),posed_point(b,c.rest_point))))
			max_angle=max(max_angle,math.abs(a.pose.angle-b.pose.angle))
		}
	}
	live,links,pieces:=counts(&game.scene)
	testing.expectf(t,live==initial_regions && links==initial_links && pieces==2,"Ordinary deformation must precede failure: %d regions, %d links, %d pieces",live,links,pieces)
	testing.expectf(t,max_gap>0.015 && max_angle>0.02,"Rubber must stretch and bend: gap %.4f, angle %.4f",max_gap,max_angle)
	removed:=ids[8]
	f:=Failures{}; append(&f.discard_subdivisions,removed)
	apply_failures(&game.scene,f); free_failures(&f)
	physics_sync_structure(&game.scene)
	testing.expect(t,!b2.Body_IsValid(subdivision_body(&game.scene,removed)))
	live,links,pieces=counts(&game.scene)
	testing.expect(t,live==initial_regions-1 && links>0 && pieces==2,"Removing one internal cell must leave the remaining grid connected")
	for _ in 0..<120 { sandbox_tick(&game,0,false) }
	live,links,pieces=counts(&game.scene)
	testing.expect(t,live==initial_regions-1 && links>0 && pieces==2)
	expect_valid(t,&game.scene)
	// A sufficiently close ordinary radius-5 blast can remove finite cells.
	testing.expect(t,sandbox_blast(&game,{-0.2,0.5}))
	rubber_remaining:=0
	for sub in game.scene.subdivisions { if sub.live && game.scene.materials[sub.material].name=="rubber" { rubber_remaining+=1 } }
	testing.expect(t,rubber_remaining<11,"Finite terminal rubber cells must be removable by the blast")
	expect_valid(t,&game.scene)
}
