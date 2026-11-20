package main


import shared "shared"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"
import b2 "vendor:box2d"

Soak_Timing :: struct { total_ms, max_ms: f64, count: int }
soak_sample :: proc(t: ^Soak_Timing,start: time.Tick) {
	ms:=f64(time.tick_diff(start,time.tick_now()))/f64(time.Millisecond)
	t.total_ms+=ms; t.max_ms=max(t.max_ms,ms); t.count+=1
}
soak_mean :: proc(t: Soak_Timing) -> f64 { if t.count==0 { return 0 }; return t.total_ms/f64(t.count) }

// One repeatable editor layout, shared by the soak and equivalence checks.
soak_yard :: proc() -> Sandbox {
	g:=sandbox_editor_create()
	positions:=[4]f32{-7.2,-3,0,3.5}
	for material in Recipe {
		x:=positions[int(material)]; g.editor.palette=recipe_slot(material)
		assert(editor_place(&g,{x,0},{x+1.6,2}))
	}
	sandbox_toggle_editor(&g)
	return g
}
soak_rebuild_layout :: proc(g: ^Sandbox) {
 soak_rebuild_world(&g.world,&g.layout)
 g.selected=0; sandbox_clear_input(g)
}
soak_rebuild_headless :: proc(g: ^Headless_Game) { soak_rebuild_world(&g.world,&g.layout) }
soak_rebuild_world :: proc(w: ^World,layout: ^Layout) {
	s:=&w.scene
	f:=Failures{}
	for sub in s.subdivisions { if sub.live { append(&f.discard_subdivisions,sub.id) } }
	revision:=s.revision
	apply_failures(s,f); delete(f.discard_subdivisions)
	// Keep the world, base, buffers, IDs, material table and bomb stream running.
	assert(len(s.materials)==5)
	materials:=[8]int{1,2,3,4,0,0,0,0}
	objects: [dynamic]Built_Object; defer delete(objects)
 layout_build_rectangles(w,layout,false,materials,&objects)
 ground:=sandbox_add_ground(s,0,w.settings.seed)
 build_mortar(s,objects[:],ground)
	if s.revision==revision { s.revision+=1 }
	physics_sync_structure(s)
	for &player in w.players { if player.active { player_respawn(&player) } }
}
run_soak :: proc(minutes: int = 20) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track,context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator=mem.tracking_allocator(&track)
	g:=soak_yard()
	defer {
		sandbox_destroy(&g)
		fmt.printf("after_destroy_odin_bytes=%d,after_destroy_box2d_bytes=%d\n",track.current_memory_allocated,b2.GetByteCount())
		assert(track.current_memory_allocated==0,"Soak scene allocations must be released")
	}
	sandbox_fixture_mode(&g,.Falling_Bombs)
	blasts:=Soak_Timing{}; g.blast_timing=&blasts
	fmt.println("seed=42 dt=1/60 substeps=4; four 1.6x2 materials; idle player; radius=5; same-scene refill every 2 minutes; allocation tracking enabled")
	fmt.println("minute,cycle,tick_mean_ms,tick_max_ms,blast_mean_ms,blast_max_ms,blasts,live_regions,live_links,live_pieces,stored_regions,stored_links,stored_pieces,sub_map,link_map,piece_map,vertices,odin_bytes,box2d_bytes,allocated_bytes,box2d_bodies,box2d_joints,next_id,peak_regions,peak_links,peak_pieces")
	for minute in 1..=minutes {
		ticks:=Soak_Timing{}; blasts={}
		peak_regions,peak_links,peak_pieces:=0,0,0
		for tick in 0..<3600 {
			start:=time.tick_now()
			// Replenishment is included in that tick's timing. Sample the exhausted
			// cycle at each even minute before replenishing on the next tick.
			if tick==0 && minute>1 && minute%2==1 { soak_rebuild_layout(&g) }
   when BOM_PROFILE { shared.profile_tick=u64((minute-1)*3600+tick+1) }
			sandbox_tick(&g,0,false); soak_sample(&ticks,start)
			peak_regions=max(peak_regions,len(g.world.scene.subdivisions)); peak_links=max(peak_links,len(g.world.scene.connections)); peak_pieces=max(peak_pieces,len(g.world.scene.pieces))
		}
		a,b,c:=counts_runtime(&g.world.scene)
		counters:=b2.World_GetCounters(g.world.scene.physics.world)
		odin_bytes,box2d_bytes:=track.current_memory_allocated,i64(b2.GetByteCount())
		fmt.printf("%d,%d,%.6f,%.6f,%.6f,%.6f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",minute,(minute+1)/2,soak_mean(ticks),ticks.max_ms,soak_mean(blasts),blasts.max_ms,blasts.count,a,b,c,len(g.world.scene.subdivisions),len(g.world.scene.connections),len(g.world.scene.pieces),len(g.world.scene.sub_rows),len(g.world.scene.conn_rows),len(g.world.scene.piece_rows),vertex_count(&g.world.scene),odin_bytes,box2d_bytes,odin_bytes+box2d_bytes,counters.bodyCount,counters.jointCount,g.world.scene.next_id,peak_regions,peak_links,peak_pieces)
		valid,message:=validate_scene(&g.world.scene); assert(valid,message)
	}
	assert(save_world_snapshot(&g.world,"output/soak-final.json"))
}
// Each call finishes and destroys its world before the next replay is started.
soak_replay_snapshot :: proc(tuning:Player_Tuning=PLAYER_TUNING) -> ([]byte,[3]int,u64) {
	g:=soak_yard(); defer sandbox_destroy(&g)
 sandbox_fixture_player_tuning(&g,tuning)
	positions:=[3]Vec2{{-6.6,1},{0,0.6},{5.8,1.2}}
	for position in positions {
		for _ in 0..<120 { sandbox_tick(&g,0,false) }
		sandbox_explode(&g,position)
	}
	for _ in 0..<240 { sandbox_tick(&g,0,false) }
	valid,message:=validate_scene(&g.world.scene); assert(valid,message)
	bytes,ok:=encode_world_snapshot(&g.world); assert(ok)
	a,b,c:=counts_runtime(&g.world.scene)
	return bytes,{a,b,c},g.world.scene.next_id
}
run_soak_fixtures :: proc(prefix: string) {
	positions:=[3]Vec2{{-6.6,1},{0,0.6},{5.8,1.2}}
	g:=soak_yard(); defer sandbox_destroy(&g)
	for position in positions { sandbox_explode(&g,position) }
	path:=fmt.aprintf("%s-blasts.json",prefix); defer delete(path)
	assert(save_world_snapshot(&g.world,path))
	ok,message:=validate_scene(&g.world.scene); assert(ok,message)
	fmt.println("Blast fixture:",counts_runtime(&g.world.scene),"next ID:",g.world.scene.next_id)
	first,counts,next_id:=soak_replay_snapshot(); defer delete(first)
	second,_,_:=soak_replay_snapshot(); defer delete(second)
	assert(string(first)==string(second),"600-tick replay snapshots must be byte-identical in one process")
	path2:=fmt.aprintf("%s-ticked.json",prefix); defer delete(path2)
	assert(os.write_entire_file(path2,first)==nil)
	fmt.println("600-tick fixture:",counts,"next ID:",next_id,"| two same-process replays are byte-identical")
}
