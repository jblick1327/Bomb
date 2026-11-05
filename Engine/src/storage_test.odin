package main

import "core:testing"
import "core:sync"
import b2 "vendor:box2d"

expect_packed_storage :: proc(t: ^testing.T,s: ^Scene) {
	testing.expect(t,len(s.sub_rows)==len(s.subdivisions) && len(s.conn_rows)==len(s.connections) && len(s.piece_rows)==len(s.pieces))
	testing.expect(t,len(s.connection_pairs)==len(s.connections))
	for sub,i in s.subdivisions {
		testing.expect(t,sub.live && s.sub_rows[sub.id]==i)
		for id in sub.incident_links {
			row,ok:=s.conn_rows[id]; testing.expect(t,ok)
			if ok { c:=s.connections[row]; testing.expect(t,c.a==sub.id || c.b==sub.id) }
		}
	}
	for c,i in s.connections {
		testing.expect(t,c.live && s.conn_rows[c.id]==i && s.connection_pairs[pair_key(c.a,c.b)]==c.id)
		testing.expect(t,contains_id(s.subdivisions[s.sub_rows[c.a]].incident_links[:],c.id) && contains_id(s.subdivisions[s.sub_rows[c.b]].incident_links[:],c.id))
	}
	for p,i in s.pieces { testing.expect(t,p.live && s.piece_rows[p.id]==i) }
	expect_valid(t,s)
}
@(test)
dead_storage_reclaims_outlines_caches_keys_and_handles :: proc(t: ^testing.T) {
 cache_state:=Render_Cache_State{}; defer release_render_caches(&cache_state)
 caches:=&cache_state
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=make_wall(); defer scene_destroy(&s)
	physics_init(&s)
	retained:=s.subdivisions[0].body
	for _ in 0..<48 {
		owner:=add_piece(&s,0,0)
		points:=[4]Vec2{{10,0},{11,0},{11,1},{10,1}}
		outline:=Polygon{points=points[:]}
		id:=add_subdivision(&s,owner,outline,Pose{position=centroid(outline)})
		physics_sync_structure(&s)
		body:=subdivision_body(&s,id)
		render_cache_prepass(&s,caches)
		f:=Failures{}; append(&f.discard_subdivisions,id)
		apply_failures(&s,f); free_failures(&f)
		testing.expect(t,!b2.Body_IsValid(body) && !is_live_subdivision(&s,id))
		_,has_sub:=s.sub_rows[id]; _,has_piece:=s.piece_rows[owner]
		testing.expect(t,!has_sub && !has_piece && len(s.subdivisions)==3 && len(s.connections)==2 && len(s.pieces)==1 && vertex_count(&s)==12)
		testing.expect(t,len(s.pending_regions)==0 && s.subdivisions[s.sub_rows[2]].body==retained)
		expect_packed_storage(t,&s)
	}
	id:=s.connections[0].id; joint:=connection_joint(&s,id)
	f:=Failures{}; append(&f.connections,id); apply_failures(&s,f); free_failures(&f)
	_,exists:=s.conn_rows[id]
	testing.expect(t,!exists && !b2.Joint_IsValid(joint))
	expect_packed_storage(t,&s)
}
@(test)
staged_memberships_cover_children_and_inherited_links :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	owner:=s.pieces[0].id
	f:=failure_for(s.subdivisions[1].id); defer free_failures(&f)
	affected:=make(map[u64]bool); defer delete(affected)
	stage_failures(&s,f,&affected)
	piece:=s.pieces[s.piece_rows[owner]]
	for sub in s.subdivisions { testing.expect(t,contains_id(piece.subdivisions[:],sub.id)) }
	for c in s.connections { testing.expect(t,contains_id(piece.connections[:],c.id)) }
	rebuild_affected_pieces(&s,affected); commit_structure(&s)
	expect_packed_storage(t,&s)
}
full_blast_for_test :: proc(s: ^Scene,blast: Blast) -> Failures {
	f:=Failures{}
	for sub in s.subdivisions { if sub.live && fails(blast_load(vlen(vsub(sub.pose.position,blast.position)),blast.radius),s.materials[sub.material].subdivision_strength) { append(&f.subdivisions,sub.id) } }
	for c in s.connections { if c.live && fails(blast_load(vlen(vsub(connection_sample(s,c),blast.position)),blast.radius),s.materials[s.subdivisions[s.sub_rows[c.a]].material].connection_strength) { append(&f.connections,c.id) } }
	sort_ids(f.subdivisions[:]); sort_ids(f.connections[:])
	return f
}
@(test)
blast_query_agrees_with_full_scan_including_staged_children :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	s:=make_wall(42); defer scene_destroy(&s)
	physics_init(&s)
	far:=add_piece(&s,0,0)
	points:=[4]Vec2{{100,0},{101,0},{101,1},{100,1}}
	outline:=Polygon{points=points[:]}; far_id:=add_subdivision(&s,far,outline,Pose{position=centroid(outline)})
	physics_sync_structure(&s)
	for pass in 0..<2 {
		blast:=Blast{position={1.5,0.5},radius=1}
		regions:=blast_regions(&s,blast)
		testing.expect(t,!contains_id(regions[:],far_id)); delete(regions)
		a:=evaluate_blast(&s,blast); b:=full_blast_for_test(&s,blast)
		testing.expect(t,len(a.subdivisions)==len(b.subdivisions) && len(a.connections)==len(b.connections))
		for id,i in a.subdivisions { testing.expect(t,id==b.subdivisions[i]) }
		for id,i in a.connections { testing.expect(t,id==b.connections[i]) }
		free_failures(&a); free_failures(&b)
		if pass==0 {
			f:=failure_for(s.subdivisions[1].id)
			affected:=make(map[u64]bool)
			stage_failures(&s,f,&affected); rebuild_affected_pieces(&s,affected)
			free_failures(&f); delete(affected)
		}
	}
	commit_structure(&s); physics_sync_structure(&s)
	expect_packed_storage(t,&s)
}
@(test)
physics_creation_order_ignores_storage_rows :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	a:=make_wall(); b:=make_wall(); defer scene_destroy(&a); defer scene_destroy(&b)
	b.subdivisions[0],b.subdivisions[2]=b.subdivisions[2],b.subdivisions[0]
	b.connections[0],b.connections[1]=b.connections[1],b.connections[0]
	for sub,i in b.subdivisions { b.sub_rows[sub.id]=i }
	for c,i in b.connections { b.conn_rows[c.id]=i }
	physics_init(&a); physics_init(&b)
	b2.Body_ApplyLinearImpulseToCenter(subdivision_body(&a,2),{0,0.1},true)
	b2.Body_ApplyLinearImpulseToCenter(subdivision_body(&b,2),{0,0.1},true)
	for _ in 0..<12 { physics_tick(&a,1.0/60); physics_tick(&b,1.0/60) }
	x,x_ok:=encode_snapshot(&a); y,y_ok:=encode_snapshot(&b); defer delete(x); defer delete(y)
	testing.expect(t,x_ok && y_ok && string(x)==string(y))
}
@(test)
yard_removes_escaped_regions_for_every_material :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	cases:=[6]struct { position: Vec2, removed: bool }{
		{{YARD_LEFT-0.01,1},false},{{YARD_RIGHT+0.01,1},false},{{0,YARD_FLOOR_BOTTOM-2.01},true},
		{{YARD_LEFT,1},false},{{YARD_RIGHT,1},false},{{0,YARD_FLOOR_BOTTOM-2},false},
	}
	for material in Recipe {
		for exit in cases {
			g:=sandbox_editor_create(); g.editor.palette=recipe_slot(material)
			testing.expect(t,editor_place(&g,{0,0},{0.2,0.2})); sandbox_toggle_editor(&g)
			id:=g.world.scene.subdivisions[0].id; body:=subdivision_body(&g.world.scene,id)
			before,last_id:=len(g.world.scene.subdivisions),g.world.scene.next_id
			position:=exit.position
            if g.world.scene.materials[g.world.scene.subdivisions[g.world.scene.sub_rows[id]].material].flexibility==0 { position=vsub(position,g.world.scene.subdivisions[g.world.scene.sub_rows[id]].rest_center) }
            b2.Body_SetTransform(body,to_b2(position),b2.MakeRot(0))
			physics_read_motion(&g.world.scene)
			g.selected=id
			sandbox_remove_out_of_bounds(&g)
			testing.expect(t,is_live_subdivision(&g.world.scene,id)!=exit.removed && b2.Body_IsValid(body)!=exit.removed)
			expected:=before; if exit.removed { expected-=1 }
			testing.expect(t,len(g.world.scene.subdivisions)==expected)
			for sub in g.world.scene.subdivisions { testing.expect(t,sub.id<=last_id,"Cleanup must discard, not generate children") }
			if exit.removed { testing.expect(t,g.selected==0) }
			testing.expect(t,b2.Body_IsValid(g.world.floor) && b2.Body_IsValid(g.world.players[0].body))
			testing.expect(t,b2.World_GetCounters(g.world.scene.physics.world).bodyCount==i32(physics_body_count(&g.world.scene)+2))
			expect_packed_storage(t,&g.world.scene); sandbox_destroy(&g)
		}
	}
 g:=sandbox_editor_create(); defer sandbox_destroy(&g); g.editor.palette=recipe_slot(.Stone)
 assert(editor_place(&g,{0,0},{0.8,0.8})); sandbox_toggle_editor(&g)
 id:=g.world.scene.subdivisions[0].id; body:=subdivision_body(&g.world.scene,id)
	b2.Body_SetTransform(body,to_b2(vsub(Vec2{0,YARD_FLOOR_BOTTOM-2.1},g.world.scene.subdivisions[g.world.scene.sub_rows[id]].rest_center)),b2.MakeRot(0))
	sandbox_tick(&g,0,false)
	testing.expect(t,!is_live_subdivision(&g.world.scene,id) && !b2.Body_IsValid(body),"A normal yard tick must clean up escaped bodies")
	expect_packed_storage(t,&g.world.scene)
}
@(test)
soak_rebuild_keeps_scene_world_stream_and_monotonic_ids :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	g:=soak_yard(); defer sandbox_destroy(&g)
	sandbox_fixture_mode(&g,.Falling_Bombs)
	world,base,player:=g.world.scene.physics.world,g.world.floor,g.world.players[0].body
	bomb_spawn(&g,{7,6})
	bomb:=g.world.bombs[0].body
	random,delay:=g.world.rain.random,g.world.rain.until_drop
	initial_regions,initial_links,initial_pieces:=counts_runtime(&g.world.scene)
	for _ in 0..<4 {
		sandbox_explode(&g,{0,0.6})
		old_ids: [dynamic]u64
		for sub in g.world.scene.subdivisions { append(&old_ids,sub.id) }
		last_id:=g.world.scene.next_id
		b2.Body_SetTransform(player,{0,-2},b2.MakeRot(0)); b2.Body_SetLinearVelocity(player,{2,-2})
		soak_rebuild_layout(&g)
		testing.expect(t,g.world.scene.physics.world==world && g.world.floor==base && g.world.players[0].body==player)
		testing.expect(t,g.world.rain.random==random && g.world.rain.until_drop==delay && g.world.bombs[0].body==bomb)
		testing.expect(t,len(g.world.scene.materials)==5 && len(g.layout.objects)==4 && g.world.scene.next_id>last_id)
		for id in old_ids { testing.expect(t,!is_live_subdivision(&g.world.scene,id)) }; delete(old_ids)
		for sub in g.world.scene.subdivisions { testing.expect(t,sub.id>last_id) }
		a,b,c:=counts_runtime(&g.world.scene)
		testing.expect(t,a==initial_regions && b==initial_links && c==initial_pieces)
		testing.expect(t,from_b2(b2.Body_GetPosition(player))==PLAYER_SPAWN && from_b2(b2.Body_GetLinearVelocity(player))==Vec2{})
		testing.expect(t,b2.World_GetCounters(world).bodyCount==i32(physics_body_count(&g.world.scene)+3))
		expect_packed_storage(t,&g.world.scene)
	}
}
@(test)
seeded_600_tick_replays_are_byte_identical_in_one_process :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	a,counts_a,next_a:=soak_replay_snapshot(); defer delete(a)
	b,counts_b,next_b:=soak_replay_snapshot(); defer delete(b)
	testing.expect(t,counts_a==counts_b && next_a==next_b && string(a)==string(b),"The same seeded tick/blast replay must reproduce geometry, graph, IDs and motion exactly")
}
