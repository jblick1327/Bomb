package main

import "core:testing"
import "core:sync"
import "core:math"
import b2 "vendor:box2d"

@(test)
yard_rests_under_gravity_and_player_moves_and_jumps :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=editor_test_yard(); defer sandbox_destroy(&game)
	initial_regions,initial_links,initial_pieces:=counts(&game.scene)
	for _ in 0..<360 { sandbox_tick(&game,0,false) }
	a,b,c:=counts(&game.scene)
	testing.expect(t,a==initial_regions && b==initial_links && c==initial_pieces,"The objects and pre-split floor must remain intact under ordinary gravity")
	testing.expect(t,game.player.grounded)
	testing.expectf(t,math.abs(b2.Body_GetPosition(game.player.body).y-PLAYER_HALF_HEIGHT)<0.025,"Player support height %v",b2.Body_GetPosition(game.player.body))
	for sub in game.scene.subdivisions { testing.expect(t,vlen(vsub(sub.pose.position,sub.rest_center))<0.04) }
	for _ in 0..<50 { sandbox_tick(&game,1,false) }
	testing.expect(t,b2.Body_GetPosition(game.player.body).x > PLAYER_SPAWN.x+2)
	sandbox_tick(&game,0,true)
	for _ in 0..<5 { if b2.Body_GetLinearVelocity(game.player.body).y>5 { break }; sandbox_tick(&game,0,false) }
	testing.expectf(t,b2.Body_GetLinearVelocity(game.player.body).y>5 && !game.player.grounded,"Jump pose %v velocity %v grounded %v",b2.Body_GetPosition(game.player.body),b2.Body_GetLinearVelocity(game.player.body),game.player.grounded)
	max_height:=f32(0)
	for _ in 0..<150 {
		sandbox_tick(&game,0,false)
		max_height=max(max_height,b2.Body_GetPosition(game.player.body).y)
	}
	testing.expect(t,max_height>2 && game.player.grounded,"One jump must reach its apex and land without another airborne jump")
	testing.expect(t,close(b2.Body_GetRotation(game.player.body).s,0))
	expect_valid(t,&game.scene)
}

@(test)
player_stands_on_and_pushes_a_real_fragment :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=sandbox_editor_create(); defer sandbox_destroy(&game)
	game.editor.palette=.Stone; assert(editor_place(&game,{1.5,0},{2.35,0.85})); sandbox_toggle_editor(&game)
	// Detach a ground-level block, leaving an actual destruction body to stand on.
	id:=game.scene.subdivisions[0].id
	failures:=Failures{}
	for connection in game.scene.connections {
		if connection.a==id || connection.b==id { append(&failures.connections,connection.id) }
	}
	apply_failures(&game.scene,failures); free_failures(&failures)
	physics_sync_structure(&game.scene)
	body:=subdivision_body(&game.scene,id)
	position:=to_b2(game.scene.subdivisions[game.scene.sub_rows[id]].pose.position)
	// Begin on the surface, rather than dropping the player onto finite debris.
	b2.Body_SetTransform(game.player.body,{position.x,0.85+PLAYER_HALF_HEIGHT+0.005},b2.MakeRot(0))
	for _ in 0..<120 { sandbox_tick(&game,0,false) }
	testing.expect(t,game.player.grounded && b2.Body_GetPosition(game.player.body).y>1.35,"Support must come from fragment contacts")
	// Move alongside the detached block and push it using the same collision world.
	b2.Body_SetTransform(body,to_b2(vsub(Vec2{-1,0.43},game.scene.subdivisions[game.scene.sub_rows[id]].rest_center)),b2.MakeRot(0))
	b2.Body_SetLinearVelocity(body,{})
	b2.Body_SetTransform(game.player.body,{-2,0.6},b2.MakeRot(0))
	b2.Body_SetLinearVelocity(game.player.body,{})
	for _ in 0..<30 { sandbox_tick(&game,0,false) }
	start:=b2.Body_GetPosition(body).x
	// Test a slow physical push below impact speed. A running collision can
	// legitimately damage finite material under the contact impact policy.
	for _ in 0..<60 { sandbox_tick(&game,0.2,false) }
	testing.expect(t,b2.Body_IsValid(body),"Routine player contact should leave the fragment intact")
	if b2.Body_IsValid(body) { testing.expect(t,b2.Body_GetPosition(body).x>start+0.05,"The player should physically push debris") }
}

@(test)
player_jump_buffer_and_coyote_window :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=editor_test_yard(); defer sandbox_destroy(&game)
	// Queue a jump shortly before landing.
	b2.Body_SetTransform(game.player.body,{-4.5,0.64},b2.MakeRot(0))
	b2.Body_SetLinearVelocity(game.player.body,{0,-1})
	jumped:=false
	for i in 0..<10 {
		sandbox_tick(&game,0,i==0)
		if b2.Body_GetLinearVelocity(game.player.body).y>5 { jumped=true }
	}
	testing.expect(t,jumped,"A buffered press just before landing should jump")
	// The support was lost recently, but the player is still inside the coyote window.
	b2.Body_SetTransform(game.player.body,{-4.5,2},b2.MakeRot(0))
	b2.Body_SetLinearVelocity(game.player.body,{0,-0.1})
	game.player.coyote=0.08
	sandbox_tick(&game,0,true)
	testing.expect(t,b2.Body_GetLinearVelocity(game.player.body).y>5)
	game.player.coyote=0
	game.player.buffered_jump=0
	b2.Body_SetLinearVelocity(game.player.body,{0,-0.1})
	sandbox_tick(&game,0,true)
	testing.expect(t,b2.Body_GetLinearVelocity(game.player.body).y<0,"Jump assistance must not permit an airborne second jump")
}

@(test)
yard_reset_restores_same_setup_after_blast_and_respawn :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=editor_test_yard(); defer sandbox_destroy(&game)
	initial_regions,initial_links,initial_pieces:=counts(&game.scene)
	for _ in 0..<3 {
		testing.expect(t,sandbox_blast(&game,{1,1.3}))
		for _ in 0..<30 { sandbox_tick(&game,1,false) }
		b2.Body_SetTransform(game.player.body,{0,-4},b2.MakeRot(0))
		game.player.coyote=0.1; game.player.buffered_jump=0.1
		testing.expect(t,player_after_step(&game.player))
		testing.expect(t,close_vec(from_b2(b2.Body_GetPosition(game.player.body)),PLAYER_SPAWN))
		testing.expect(t,!game.player.grounded && game.player.coyote==0 && game.player.buffered_jump==0)
		sandbox_reset(&game)
		a,b,c:=counts(&game.scene)
		testing.expect(t,a==initial_regions && b==initial_links && c==initial_pieces)
		testing.expect(t,b2.World_GetCounters(game.scene.physics.world).bodyCount==i32(physics_body_count(&game.scene)+2),"Reset must restore regions, player and base")
		testing.expect(t,game.applied.blast_radius==5.0 && game.scene.materials[0].flexibility==0)
		testing.expect(t,game.accumulator==0 && !game.jump_queued && game.selected==0)
		for sub in game.scene.subdivisions { testing.expect(t,close_vec(sub.pose.position,sub.rest_center) && close_vec(sub.pose.velocity,{})) }
		expect_valid(t,&game.scene)
	}
}

counts_live_subdivisions :: proc(s: ^Scene) -> int { result:=0; for sub in s.subdivisions { if sub.live { result+=1 } }; return result }

@(test)
sandbox_menu_and_ui_consume_input_without_catchup :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=editor_test_yard(); defer sandbox_destroy(&game)
	_ = sandbox_route_input(&game,{},false)
	game.jump_queued=true
	game.accumulator=0.01
	before:=game.scene.subdivisions[0].pose
	pose:=b2.Body_GetPosition(game.player.body)
	input:=sandbox_route_input(&game,{menu_pressed=true,jump_pressed=true,jump_down=true,blast_pressed=true,blast_down=true,move=1,wheel=1},false)
	sandbox_advance(&game,5,input)
	testing.expect(t,game.panel_open && !input.jump_pressed && !input.blast_pressed && input.move==0)
	testing.expect(t,game.accumulator==0 && !game.jump_queued && b2.Body_GetPosition(game.player.body)==pose && game.scene.subdivisions[0].pose==before)
	testing.expect(t,!sandbox_blast(&game,{0,1}))
	input=sandbox_route_input(&game,{menu_pressed=true,jump_pressed=true,jump_down=true,blast_pressed=true,blast_down=true},false)
	testing.expect(t,!game.panel_open && !input.jump_pressed && !input.blast_pressed)
	input=sandbox_route_input(&game,{jump_pressed=true,jump_down=true,blast_pressed=true,blast_down=true},false)
	testing.expect(t,!input.jump_pressed && !input.blast_pressed,"Held menu inputs must be released before they can act")
	_ = sandbox_route_input(&game,{},false)
	radius:=game.applied.blast_radius
	input=sandbox_route_input(&game,{blast_pressed=true,blast_down=true,wheel=2},true)
	testing.expect(t,!input.blast_pressed && input.wheel==0 && game.applied.blast_radius==radius)
	input=sandbox_route_input(&game,{jump_pressed=true,jump_down=true,blast_pressed=true,blast_down=true},false)
	testing.expect(t,input.jump_pressed && input.blast_pressed)
	_ = sandbox_route_input(&game,{menu_pressed=true},false)
	_ = sandbox_route_input(&game,{menu_pressed=true},false)
	input=sandbox_route_input(&game,{jump_pressed=true,jump_down=true,blast_pressed=true,blast_down=true},false)
	testing.expect(t,input.jump_pressed && input.blast_pressed,"A fresh press immediately after closing settings must work")
	sandbox_advance(&game,1.0/60.0,{})
	testing.expect(t,game.accumulator<0.001 && b2.Body_GetPosition(game.player.body).y>pose.y-0.01,"Resume must advance only the current frame")
}

@(test)
sandbox_aim_uses_posed_outlines_and_suppresses_invalid_blast :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	game:=editor_test_yard(); defer sandbox_destroy(&game)
	before_regions:=counts_live_subdivisions(&game.scene)
	sub:=game.scene.subdivisions[0]
	testing.expect(t,!sandbox_valid_aim(&game.scene,sub.pose.position))
	testing.expect(t,!sandbox_valid_aim(&game.scene,sub.outline.points[0]),"Boundary points must also be invalid")
	revision:=game.scene.revision
	testing.expect(t,!sandbox_blast(&game,sub.pose.position) && game.scene.revision==revision)
	testing.expect(t,counts_live_subdivisions(&game.scene)==before_regions)
	moved:=sub; moved.pose.position={-2,3}; moved.pose.angle=0.7
	testing.expect(t,point_in_subdivision(moved,{-2,3}) && !point_in_subdivision(moved,sub.pose.position))
	testing.expect(t,sandbox_valid_aim(&game.scene,{-1,2}))
	testing.expect(t,sandbox_blast(&game,{1,1.3}) && game.scene.revision>revision)
	testing.expect(t,b2.Body_IsValid(game.player.body),"Blasts must not replace or remove the player")
}

@(test)
sandbox_camera_keeps_yard_inside_resized_window :: proc(t: ^testing.T) {
	sizes:=[3]Vec2{{1280,800},{900,700},{1600,900}}
	points:=[4]Vec2{{-7.5,-3.4},{8.5,-3.4},{-7.5,5},{8.5,5}}
	for size in sizes {
		view:=sandbox_view(size.x,size.y)
		for point in points {
			screen:=screen_point(view,point)
			testing.expect(t,screen.x>=31 && screen.x<=size.x-31 && screen.y>=88 && screen.y<=size.y-56)
		}
	}
}
