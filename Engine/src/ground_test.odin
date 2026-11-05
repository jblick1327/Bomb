package main

import "core:math"
import "core:sync"
import "core:testing"
import b2 "vendor:box2d"

@(test)
excavated_ground_keeps_player_bombs_and_rubble_above_screen_bottom :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	settings:=DEFAULT_SANDBOX_SETTINGS; settings.blast_mode=.Falling_Bombs
	game:=sandbox_editor_create(); game.world.settings=settings; game.editor.palette=recipe_slot(.Stone); assert(editor_place(&game,{1.5,0},{2.35,0.85})); sandbox_toggle_editor(&game); defer sandbox_destroy(&game)
	game.world.rain.until_drop=1000
	// Expose the base completely and retain one ordinary debris body. Infinite
	// strength isolates support contacts from the separate impact-failure tests.
	game.world.scene.materials[0].subdivision_strength=math.inf_f32(1)
	game.world.scene.materials[0].connection_strength=math.inf_f32(1)
	game.world.scene.materials[4].subdivision_strength=math.inf_f32(1)
	retained:=game.world.scene.subdivisions[0].id
	failures:=Failures{}; defer free_failures(&failures)
	for sub in game.world.scene.subdivisions { if sub.id!=retained { append(&failures.discard_subdivisions,sub.id) } }
	apply_failures(&game.world.scene,failures)
	physics_sync_structure(&game.world.scene)
	body:=subdivision_body(&game.world.scene,retained)
	b2.Body_SetTransform(body,{2,2.5},b2.MakeRot(0))
	b2.Body_SetLinearVelocity(body,{})
	bomb_spawn(&game,{-2,2})
	game.world.bombs[0].fuse=100
	bomb:=game.world.bombs[0].body
	for _ in 0..<240 { sandbox_tick(&game,0,false) }
	testing.expect(t,game.world.player.grounded && close(b2.Body_GetPosition(game.world.player.body).y,YARD_FLOOR_BOTTOM+PLAYER_HALF_HEIGHT))
	testing.expect(t,game.world.bombs[0].landed && math.abs(b2.Body_GetPosition(bomb).y-(YARD_FLOOR_BOTTOM+BOMB_RADIUS))<0.025)
	testing.expect(t,b2.Body_IsValid(body) && math.abs(game.world.scene.subdivisions[game.world.scene.sub_rows[retained]].pose.position.y-(YARD_FLOOR_BOTTOM+0.425))<0.025)
	testing.expect(t,b2.Body_IsValid(game.world.floor) && b2.Body_GetType(game.world.floor)==.staticBody)
	sizes:=[3]Vec2{{1280,800},{900,700},{1600,900}}
	for size in sizes {
		bottom:=screen_point(sandbox_view(size.x,size.y),{0,YARD_FLOOR_BOTTOM})
		testing.expect(t,bottom.y<size.y-56,"The unbreakable base must catch objects above the bottom HUD")
	}
	expect_valid(t,&game.world.scene)
}

@(test)
ground_descendants_release_when_their_connection_to_support_breaks :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=new_scene(0.1); defer scene_destroy(&s)
	recipe:=test_recipe(0)
	recipe.subdivision_strength=math.inf_f32(1); recipe.connection_strength=math.inf_f32(1)
	material:=add_material(&s,recipe)
	owner:=add_piece(&s,material,42)
	points:=[4]Vec2{{-1,-1},{1,-1},{1,1},{-1,1}}
	outline:=Polygon{points=points[:]}
	root:=add_subdivision(&s,owner,outline,Pose{position=centroid(outline)})

	physics_init(&s,{0,-9.8},-1)
	testing.expect(t,b2.Body_GetType(subdivision_body(&s,root))==.staticBody)
	failures:=Failures{}; append(&failures.subdivisions,root)
	apply_failures(&s,failures); free_failures(&failures)
	physics_sync_structure(&s)
	loose:=u64(0)
	for sub in s.subdivisions {
		if !sub.live { continue }
		testing.expect(t,b2.Body_GetType(subdivision_body(&s,sub.id))==.staticBody,"Refinement alone must preserve the anchored piece's support")
		bottom:=f32(1e30)
		for point in sub.outline.points { bottom=min(bottom,point.y) }
		if bottom>-1 { loose=sub.id }
	}
	testing.expect(t,loose!=0,"The partition must include a region above the support edge")
	retained_body:=subdivision_body(&s,loose)
	for c in s.connections { if c.live && (c.a==loose || c.b==loose) { append(&failures.connections,c.id) } }
	apply_failures(&s,failures); free_failures(&failures)
	physics_sync_structure(&s)
	body:=subdivision_body(&s,loose)
	testing.expect(t,body==retained_body,"Release must preserve the existing physics handle")
	testing.expect(t,b2.Body_GetType(body)==.dynamicBody,"Losing the last anchored connection must release an existing body")
	testing.expect(t,close(b2.Body_GetMass(body),polygon_area(s.subdivisions[s.sub_rows[loose]].outline)),"Released ground must recover its logical polygon mass")
	before:=b2.Body_GetPosition(body)
	b2.Body_ApplyLinearImpulseToCenter(body,{0,2},true)
	physics_tick(&s,1.0/60.0)
	testing.expect(t,b2.Body_GetPosition(body).y>before.y,"Detached ground must respond to impulses through the ordinary solver")
	expect_valid(t,&s)
}

@(test)
shared_blast_refines_reached_cells_above_ground :: proc(t: ^testing.T) {
 s:=new_scene(0.1); defer scene_destroy(&s)
 m:=add_material(&s,editor_material(.Stone)); owner:=add_piece(&s,m,42)
 points:=[4]Vec2{{0,1},{4,1},{4,3},{0,3}}; outline:=Polygon{points=points[:]}
 root:=add_subdivision(&s,owner,outline,Pose{position=centroid(outline)})
 blast:=Blast{position={-0.5,2},radius=5}
 testing.expect(t,!fails(blast_load(vlen(vsub(centroid(outline),blast.position)),blast.radius),35))
 blast_pass(&s,blast)
 area:=f32(0); for sub in s.subdivisions { area+=polygon_area(sub.outline) }
 testing.expect(t,!is_live_subdivision(&s,root) && area>0 && area<8,"The shared pass must excavate a reached edge even when the above-ground parent centre survives")
 remaining:=evaluate_blast(&s,blast); defer free_failures(&remaining)
 testing.expect(t,len(remaining.subdivisions)==0 && len(remaining.connections)==0,"Reach refinement and same-blast failure must finish together")
 expect_valid(t,&s)
}
