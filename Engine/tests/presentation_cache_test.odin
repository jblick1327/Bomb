package main

import "core:testing"
import "core:sync"
import "core:fmt"
import "core:mem"
import b2 "vendor:box2d"

when ODIN_TEST {
	@(thread_local) render_ensure_test_calls: u64
	@(thread_local) render_signature_test_calls: u64
}

when ODIN_TEST {
@(test)
headless_world_does_no_render_cache_work :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	render_ensure_test_calls=0
	g:=soak_yard(); defer sandbox_destroy(&g)
	build:=render_ensure_test_calls
	ticks,explodes:=u64(0),u64(0)
	positions:=[3]Vec2{{-6.6,1},{0,0.6},{5.8,1.2}}
	for point in positions {
		before:=render_ensure_test_calls
		for _ in 0..<120 { sandbox_tick(&g,0,false) }
		ticks+=render_ensure_test_calls-before
		before=render_ensure_test_calls
		sandbox_explode(&g,point)
		explodes+=render_ensure_test_calls-before
	}
	before:=render_ensure_test_calls
	for _ in 0..<240 { sandbox_tick(&g,0,false) }
	ticks+=render_ensure_test_calls-before
	data,ok:=encode_world_snapshot(&g.world); testing.expect(t,ok); defer delete(data)
	before=render_ensure_test_calls
	w,loaded:=decode_world_snapshot(data); testing.expect(t,loaded)
	defer { scene_destroy(&w.scene); delete(w.bombs) }
	loads:=render_ensure_test_calls-before
	fmt.printf("Cache check 1: build=%d tick=%d explode=%d total600=%d load=%d ensure_calls\n",build,ticks,explodes,build+ticks+explodes,loads)
	testing.expect(t,build+ticks+explodes+loads==0,"Headless simulation must never ensure a render cache")
}

@(test)
notices_expire_in_edit_and_paused_modes :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	g:=sandbox_editor_create(); defer sandbox_destroy(&g)
	failures:=0
	for mode in 0..<3 {
		if mode==1 { sandbox_set_panel(&g,true) }
		if mode==2 { sandbox_set_panel(&g,false); sandbox_toggle_editor(&g); sandbox_set_panel(&g,true) }
		sandbox_notice(&g,"Expires in every mode")
		sandbox_advance(&g,3,{})
		fmt.printf("Cache check 2: mode=%d remaining_notice_seconds=%.1f\n",mode,g.status_time)
		if g.status_time>0 { failures+=1 }
	}
	fmt.printf("Cache check 2: unexpired notices=%d/3\n",failures)
	testing.expect(t,failures==0,"Edit and paused notices must expire after three seconds")
}

@(test)
presentation_cache_prunes_live_keys_and_releases_after_scene :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track,context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator=mem.tracking_allocator(&track)
	box2d_before:=b2.GetByteCount()
	g:=soak_yard()
	caches:=Render_Cache_State{}
	positions:=[3]Vec2{{-6.6,1},{0,0.6},{5.8,1.2}}
	for stage in 0..<4 {
		if stage>0 {
			for _ in 0..<120 { sandbox_tick(&g,0,false) }
			sandbox_explode(&g,positions[stage-1])
		}
		before,ok:=encode_world_snapshot(&g.world); testing.expect(t,ok)
		render_cache_prepass(&g.world.scene,&caches)
		signature_calls:=render_signature_test_calls
		render_cache_prepass(&g.world.scene,&caches)
		testing.expect(t,render_signature_test_calls==signature_calls,"Unchanged structure must not rescan the static signature")
		live:=0
		for sub in g.world.scene.subdivisions {
			if !sub.live { continue }; live+=1
			cache,found:=caches.cells[sub.id]
			testing.expect(t,found && cache.owner==sub.owner && cache.anchored==render_static(&g.world.scene,&caches.statics,sub))
			revision:=g.world.scene.pieces[g.world.scene.piece_rows[sub.owner]].render_revision
			if cache.anchored { revision=caches.static_render_revision }
			testing.expect(t,cache.revision==revision)
		}
		stale:=0
		for id in caches.cells { if !is_live_subdivision(&g.world.scene,id) { stale+=1 } }
		testing.expect(t,len(caches.cells)==live && stale==0)
		after,encoded:=encode_world_snapshot(&g.world)
		testing.expect(t,encoded && string(before)==string(after),"Cache pre-pass changed the World")
		delete(before); delete(after)
		fmt.printf("Cache check 3: stage=%d live=%d cached=%d stale=%d\n",stage,live,len(caches.cells),stale)
	}
	scene_destroy(&g.world.scene)
	render_cache_prepass(&g.world.scene,&caches)
	testing.expect(t,len(caches.cells)==0,"Destroyed scene must prune every cache")
	release_render_caches(&caches)
	sandbox_destroy(&g)
	fmt.printf("Cache check 3 teardown: Odin bytes=%d Box2D delta=%d\n",track.current_memory_allocated,b2.GetByteCount()-box2d_before)
	testing.expect(t,track.current_memory_allocated==0 && b2.GetByteCount()==box2d_before)
}
}
