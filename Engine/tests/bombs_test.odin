package main

import "core:testing"
import "core:sync"
import b2 "vendor:box2d"

@(test)
falling_bomb_waits_for_landing_then_explodes_once :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	settings:=DEFAULT_SANDBOX_SETTINGS; settings.blast_mode=.Falling_Bombs
	game:=editor_test_yard(settings); defer sandbox_destroy(&game)
	game.world.rain.until_drop=1000
	bomb_spawn(&game,{-2,4.5})
	body:=game.world.bombs[0].body
	sandbox_tick(&game,0,false)
	testing.expect(t,b2.Body_GetPosition(body).y<4.5 && b2.Body_GetLinearVelocity(body).y<0)
	testing.expect(t,!game.world.bombs[0].landed && game.world.bombs[0].fuse==BOMB_FUSE)
	for _ in 0..<180 {
		if game.world.bombs[0].landed { break }
		sandbox_tick(&game,0,false)
	}
	testing.expect(t,game.world.bombs[0].landed && game.world.bombs[0].fuse==BOMB_FUSE)
	testing.expect(t,b2.Body_GetPosition(body).y>=BOMB_RADIUS-0.025 && b2.Body_GetPosition(body).y<=BOMB_RADIUS+0.025)
	for _ in 0..<59 { sandbox_tick(&game,0,false) }
	testing.expect(t,b2.Body_IsValid(body) && len(game.bursts)==0,"The bomb must remain physical for a full second after first landing")
	last_position:=from_b2(b2.Body_GetPosition(body))
	sandbox_tick(&game,0,false)
	testing.expect(t,!b2.Body_IsValid(body) && len(game.world.bombs)==0 && len(game.bursts)==1)
	testing.expect(t,vlen(vsub(game.bursts[0].position,last_position))<0.025)
	for _ in 0..<60 { sandbox_tick(&game,0,false) }
	testing.expect(t,len(game.bursts)==0 && b2.World_GetCounters(game.world.scene.physics.world).bodyCount==i32(physics_body_count(&game.world.scene)+2),"An exploded bomb must leave only live geometry, the player and base; no bomb body or repeated explosion")
}

@(test)
bomb_fuse_needs_support_and_accepts_destructible_surfaces :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	settings:=DEFAULT_SANDBOX_SETTINGS; settings.blast_mode=.Falling_Bombs
	game:=editor_test_yard(settings); defer sandbox_destroy(&game)
	game.world.rain.until_drop=1000
	bomb_spawn(&game,{-2,4})
	body:=game.world.bombs[0].body
	b2.Body_SetGravityScale(body,0)
	for _ in 0..<120 { sandbox_tick(&game,0,false) }
	testing.expect(t,!game.world.bombs[0].landed && game.world.bombs[0].fuse==BOMB_FUSE,"Time spent airborne must not light the fuse")
	b2.Body_SetTransform(body,{1.5-BOMB_RADIUS-0.005,1.25},b2.MakeRot(0))
	b2.Body_SetLinearVelocity(body,{1,0})
	for _ in 0..<20 { sandbox_tick(&game,0,false) }
	testing.expect(t,!game.world.bombs[0].landed,"Brushing a vertical wall must not count as landing")
	b2.Body_SetTransform(body,{2.8,3.2},b2.MakeRot(0))
	b2.Body_SetLinearVelocity(body,{})
	b2.Body_SetGravityScale(body,1)
	for _ in 0..<90 {
		if game.world.bombs[0].landed { break }
		sandbox_tick(&game,0,false)
	}
	testing.expect(t,game.world.bombs[0].landed && b2.Body_GetPosition(body).y>2.6,"A bomb should rest and arm on the authored object, not pass through it")
}

@(test)
bomb_blasts_use_current_radius_and_remove_all_expired_bodies :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	// The explicit 30/24 fixture makes the later radius 4.2 hit fail the target
	// directly, independently of changes to the sandbox's starting strengths.
	settings:=DEFAULT_SANDBOX_SETTINGS; settings.blast_mode=.Falling_Bombs; settings.blast_radius=0.5
	game:=editor_test_yard(settings); defer sandbox_destroy(&game)
	game.world.rain.until_drop=1000
	target:=game.world.scene.subdivisions[0].id
	bomb_spawn(&game,{1,BOMB_RADIUS}); bomb_spawn(&game,{6,BOMB_RADIUS})
	first,second:=game.world.bombs[0].body,game.world.bombs[1].body
	for _ in 0..<10 {
		sandbox_tick(&game,0,false)
		if game.world.bombs[0].landed && game.world.bombs[1].landed { break }
	}
	testing.expect(t,game.world.bombs[0].landed && game.world.bombs[1].landed)
	revision:=game.world.scene.revision
	testing.expect(t,!sandbox_fixture_blast(&game,{1,1.3}) && game.world.scene.revision==revision,"Manual clicks must be disabled while bombs are active")
	sandbox_fixture_radius(&game,5.2)
	for _ in 0..<60 { sandbox_tick(&game,0,false) }
	testing.expect(t,len(game.world.bombs)==0 && !b2.Body_IsValid(first) && !b2.Body_IsValid(second))
	testing.expect(t,len(game.bursts)==2 && game.bursts[0].radius==5.2)
	testing.expect(t,game.world.scene.revision>revision && !is_live_subdivision(&game.world.scene,target),"Landed bombs must invoke real destruction using the live radius")
	testing.expect(t,b2.Body_IsValid(game.world.players[0].body) && b2.Body_IsValid(game.world.floor))
	expect_valid(t,&game.world.scene)
}

@(test)
bomb_rain_random_drops_pause_switch_and_reset :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	settings:=DEFAULT_SANDBOX_SETTINGS; settings.blast_mode=.Falling_Bombs
	game:=editor_test_yard(settings); defer sandbox_destroy(&game)
	first_delay:=game.world.rain.until_drop
	testing.expect(t,first_delay>=BOMB_DROP_MIN && first_delay<=BOMB_DROP_MAX)
	for _ in 0..<160 {
		sandbox_tick(&game,0,false)
		if len(game.world.bombs)>0 { break }
	}
	first_body:=game.world.bombs[0].body
	first_position:=game.previous_bombs[game.world.bombs[0].id]
	second_delay:=game.world.rain.until_drop
	testing.expect(t,first_position.y==BOMB_SKY_HEIGHT && first_position.x>=-7 && first_position.x<=8)
	testing.expect(t,second_delay>=BOMB_DROP_MIN-1.0/60.0 && second_delay<=BOMB_DROP_MAX && second_delay!=first_delay)
	_ = sandbox_route_input(&game,{},false)
	input:=sandbox_route_input(&game,{blast_pressed=true,blast_down=true},false)
	testing.expect(t,!input.blast_pressed,"Input routing must also suppress manual blasts in bomb mode")
	for _ in 0..<160 {
		sandbox_tick(&game,0,false)
		if game.world.bombs[0].landed { break }
	}
	fuse:=game.world.bombs[0].fuse
	delay:=game.world.rain.until_drop
	position:=b2.Body_GetPosition(first_body)
	bomb_count:=len(game.world.bombs)
	sandbox_set_panel(&game,true)
	sandbox_advance(&game,5,{})
	testing.expect(t,game.world.rain.until_drop==delay && len(game.world.bombs)==bomb_count)
	testing.expect(t,game.world.bombs[0].fuse==fuse && b2.Body_GetPosition(first_body)==position,"Settings must pause landed fuses as well as the spawn schedule and physics")
	revision:=game.world.scene.revision
	sandbox_fixture_mode(&game,.Manual)
	testing.expect(t,game.world.settings.blast_mode==.Manual && game.world.scene.revision==revision)
	testing.expect(t,len(game.world.bombs)==0 && !b2.Body_IsValid(first_body),"Switching back must clear existing bombs without resetting the yard")
	sandbox_set_panel(&game,false)
	_ = sandbox_route_input(&game,{},false)
	input=sandbox_route_input(&game,{blast_pressed=true},false)
	testing.expect(t,input.blast_pressed)
	// Reset repeats the applied seed's drops and restores clean physics ownership.
	sandbox_fixture_mode(&game,.Falling_Bombs)
	sandbox_reset(&game)
	testing.expect(t,game.world.rain.until_drop==first_delay && len(game.world.bombs)==0 && len(game.bursts)==0)
	for _ in 0..<160 {
		sandbox_tick(&game,0,false)
		if len(game.world.bombs)>0 { break }
	}
	testing.expect(t,close_vec(game.previous_bombs[game.world.bombs[0].id],first_position))
	game.world.rain.until_drop=0
	sandbox_tick(&game,0,false)
	testing.expect(t,len(game.world.bombs)==2 && game.previous_bombs[game.world.bombs[1].id].x!=first_position.x,"Successive drops should use different random sky positions")
	b2.Body_SetTransform(game.world.bombs[0].body,{-2,-4},b2.MakeRot(0))
	sandbox_tick(&game,0,false)
	testing.expect(t,len(game.world.bombs)==1 && len(game.bursts)==0,"Bombs lost outside the yard must be cleaned up")
	sandbox_reset(&game)
	testing.expect(t,b2.World_GetCounters(game.world.scene.physics.world).bodyCount==i32(physics_body_count(&game.world.scene)+2) && len(game.world.bombs)==0)
}
