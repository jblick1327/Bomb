package main

import nc "netcode"
import b2 "vendor:box2d"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:sync"
import "core:testing"

scenes_equal :: proc(a,b: ^Scene) -> bool {
 x:=canonical_encode(a); y:=canonical_encode(b); defer { delete(x); delete(y) }
 return slice.equal(x,y)
}
// ---------------------------------------------------------------- lockstep
@(test)
replication_lockstep_two_minute_soak :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 // 7300 ticks: just over two minutes, so it includes the first refill (tick 7201).
 sc:=Scenario{label="unit",ticks=7300,bots=4,blasting=true,falling_bombs=true,refill=true,lockstep=true,join_tick=3600,seed=1234}
 result:=run_scenario(sc); defer scenario_result_destroy(&result)
 testing.expectf(t,result.first_mismatch==0,"lockstep mismatch at tick %d",result.first_mismatch)
 testing.expectf(t,result.join_mismatch==0,"late-join mismatch at tick %d",result.join_mismatch)
 testing.expect(t,result.ticks==7300 && result.deltas>50 && result.blast_events>40)
 testing.expect(t,result.join_ticks_verified>3000)
 testing.expect(t,result.largest_part<=REPL_PART_LIMIT+16)
 fmt.printf("Replication unit soak: ticks=%d deltas=%d blasts=%d largest_message=%d join_verified=%d\n",result.ticks,result.deltas,result.blast_events,result.largest_message,result.join_ticks_verified)
}
@(test)
replication_parts_split_and_apply_atomically :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 // A tiny limit forces every message through many parts.
 sc:=Scenario{label="split",ticks=900,bots=4,blasting=true,falling_bombs=true,lockstep=true,part_limit=400,seed=7}
 result:=run_scenario(sc); defer scenario_result_destroy(&result)
 testing.expectf(t,result.first_mismatch==0,"mismatch at %d",result.first_mismatch)
 testing.expect(t,result.max_parts>5 && result.largest_part<=400+16)
 // Incomplete messages are not applied.
 g:=soak_yard(); defer sandbox_destroy(&g)
 srv:Repl_Server; defer repl_server_destroy(&srv)
 rep:Replica; replica_init(&rep); defer replica_destroy(&rep)
 first:=repl_server_update(&srv,&g.world.scene,0,1500); defer repl_output_destroy(&first)
 testing.expect(t,first.kind==.Baseline && len(first.parts)>2)
 for part in first.parts[:len(first.parts)-1] {
  applied,err:=replica_receive(&rep,part); testing.expect(t,!applied && err=="")
 }
 testing.expect(t,!rep.has_baseline && len(rep.scene.subdivisions)==0,"A partial message must not be applied")
 applied,err:=replica_receive(&rep,first.parts[len(first.parts)-1]); testing.expect(t,applied && err=="" && rep.has_baseline)
 testing.expect(t,scenes_equal(&g.world.scene,&rep.scene))
}
@(test)
replication_epochs_and_stale_deltas_are_errors :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 srv:Repl_Server; defer repl_server_destroy(&srv)
 rep:Replica; replica_init(&rep); defer replica_destroy(&rep)
 base:=repl_server_update(&srv,&g.world.scene,0); defer repl_output_destroy(&base)
 testing.expect(t,repl_apply_output(&rep,&base)=="")
 epoch:=g.world.scene.epoch
 testing.expect(t,sandbox_fixture_blast(&g,{-4.3,1}))
 d1:=repl_server_update(&srv,&g.world.scene,1); defer repl_output_destroy(&d1)
 testing.expect(t,d1.kind==.Delta)
 sandbox_explode(&g,{2.5,1})
 d2:=repl_server_update(&srv,&g.world.scene,2); defer repl_output_destroy(&d2)
 testing.expect(t,d2.kind==.Delta)
 // Skipping d1 is a from_revision error and changes nothing.
 before:=canonical_encode(&rep.scene); defer delete(before)
 testing.expect(t,repl_apply_output(&rep,&d2)=="delta from_revision does not match")
 now:=canonical_encode(&rep.scene); defer delete(now)
 testing.expect(t,slice.equal(before,now))
 testing.expect(t,repl_apply_output(&rep,&d1)=="" && repl_apply_output(&rep,&d2)=="")
 testing.expect(t,scenes_equal(&g.world.scene,&rep.scene))
 // Re-applying an old delta fails too.
 testing.expect(t,repl_apply_output(&rep,&d1)=="delta from_revision does not match")
 // A rebuild (reset) starts a new epoch with a Baseline; a delta from the old epoch is an error.
 sandbox_explode(&g,{4.3,2.4})
 stale:=repl_server_update(&srv,&g.world.scene,3); defer repl_output_destroy(&stale)
 sandbox_reset(&g)
 testing.expect(t,g.world.scene.epoch==epoch+1)
 fresh:=repl_server_update(&srv,&g.world.scene,4); defer repl_output_destroy(&fresh)
 testing.expect(t,fresh.kind==.Baseline)
 testing.expect(t,repl_apply_output(&rep,&fresh)=="" && rep.scene.epoch==epoch+1 && rep.rebuilt)
 testing.expect(t,repl_apply_output(&rep,&stale)=="delta from another epoch")
 testing.expect(t,scenes_equal(&g.world.scene,&rep.scene))
 // Snapshot load is a rebuild as well.
 data,ok:=encode_world_snapshot(&g.world); testing.expect(t,ok); defer delete(data)
 loaded,lok:=decode_world_snapshot(data,g.world.scene.epoch+1); testing.expect(t,lok)
 defer { scene_destroy(&loaded.scene); delete(loaded.bombs) }
 loaded_out:=repl_server_update(&srv,&loaded.scene,5); defer repl_output_destroy(&loaded_out)
 testing.expect(t,loaded_out.kind==.Baseline)
 testing.expect(t,repl_apply_output(&rep,&loaded_out)=="" && scenes_equal(&loaded.scene,&rep.scene))
 // A joining client gets a Baseline at the current revision and then follows deltas.
 join:=repl_server_baseline(&srv,&loaded.scene,5); defer repl_output_destroy(&join)
 other:Replica; replica_init(&other); defer replica_destroy(&other)
 testing.expect(t,repl_apply_output(&other,&join)=="")
 testing.expect(t,scenes_equal(&loaded.scene,&other.scene))
}

// ---------------------------------------------------------------- presentation without Box2D
@(test)
piece_anchored_matches_static_bodies :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 sandbox_fixture_mode(&g,.Falling_Bombs)
 checked,static_pieces:=0,0
 for tick in 0..<1500 {
  sandbox_tick(&g,0,false)
  if tick%250!=0 { continue }
  s:=&g.world.scene
  for p in s.pieces {
   if !p.live || len(p.subdivisions)==0 { continue }
   first:=s.subdivisions[s.sub_rows[p.subdivisions[0]]]
   is_static:=first.body!=b2.nullBodyId && b2.Body_GetType(first.body)==.staticBody
   testing.expectf(t,is_static==piece_anchored(s,p.id,s.anchor_y),"piece %d anchored mismatch",p.id)
   checked+=1; if is_static { static_pieces+=1 }
  }
 }
 testing.expect(t,checked>0 && static_pieces>0)
}
// The previous implementation, kept as the oracle: a Box2D overlap query.
oracle_static :: proc(sub: Subdivision) -> bool { return sub.body!=b2.nullBodyId && b2.Body_GetType(sub.body)==.staticBody }
oracle_neighbours :: proc(s: ^Scene,sub: Subdivision) -> [dynamic]u64 {
 candidates: [dynamic]u64
 if s.materials[sub.material].flexibility>0 && !oracle_static(sub) {
  for link in sub.incident_links {
   c:=s.connections[s.conn_rows[link]]
   if !c.live || c.mortar { continue }
   other:=c.a; if c.a==sub.id { other=c.b }
   if is_live_subdivision(s,other) { append(&candidates,other) }
  }
 } else if s.physics.active {
  lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
  for rest in sub.outline.points { p:=posed_point(sub,rest); lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)} }
  query:=Blast_Query{ids=make(map[u64]bool)}; defer delete(query.ids)
  box:=b2.AABB{lowerBound={lo.x-0.05,lo.y-0.05},upperBound={hi.x+0.05,hi.y+0.05}}
  _=b2.World_OverlapAABB(s.physics.world,box,b2.DefaultQueryFilter(),blast_query_shape,&query)
  for id in query.ids { if is_live_subdivision(s,id) { append(&candidates,id) } }
 } else { for id in s.pieces[s.piece_rows[sub.owner]].subdivisions { append(&candidates,id) } }
 result:[dynamic]u64
 for id in candidates {
  if id==sub.id { continue }
  other:=s.subdivisions[s.sub_rows[id]]
  together:=sub.owner==other.owner && s.materials[sub.material].flexibility==0
  together=together || oracle_static(sub) && oracle_static(other)
  if c,ok:=s.connection_pairs[pair_key(sub.id,id)]; ok { together=together || (s.connections[s.conn_rows[c]].live && !s.connections[s.conn_rows[c]].mortar) }
  if !together { continue }
  boundaries:=shared_segments(sub.outline,other.outline)
  if len(boundaries)>0 { append(&result,id) }; delete(boundaries)
 }
 delete(candidates); sort_ids(result[:]); return result
}
// Compares every live cell's neighbour list and draw_edge flags against the oracle.
compare_render_structure :: proc(t: ^testing.T,s: ^Scene,caches: ^Render_Cache_State,label: string) -> (cells,mismatches: int) {
 render_cache_prepass(s,caches)
 for sub in s.subdivisions {
  if !sub.live { continue }
  cells+=1
  expected:=oracle_neighbours(s,sub); defer delete(expected)
  actual:=render_together_neighbours(s,sub,&caches.statics); defer delete(actual)
  if !slice.equal(expected[:],actual[:]) { mismatches+=1; testing.expectf(t,false,"%s: cell %d neighbours differ: %v vs %v",label,sub.id,expected[:],actual[:]); continue }
  // draw_edge for rigid and anchored cells is a pure function of the neighbour list.
  cache:=caches.cells[sub.id]
  if cache.anchored!=oracle_static(sub) { mismatches+=1; testing.expectf(t,false,"%s: cell %d anchored flag differs",label,sub.id); continue }
  outline:=make_polygon(sub.outline.points); defer delete(outline.points)
  for other in expected { for rest in s.subdivisions[s.sub_rows[other]].outline.points { insert_boundary_endpoint(&outline,rest) } }
  flexible:=s.materials[sub.material].flexibility>0 && !cache.anchored
  if flexible { skinned:=skin_outline(outline); delete(outline.points); outline=skinned }
  if len(outline.points)!=len(cache.draw_edge) { mismatches+=1; testing.expectf(t,false,"%s: cell %d outline length differs",label,sub.id); continue }
  for a,i in outline.points {
   b:=outline.points[(i+1)%len(outline.points)]
   draw:=true
   for other in expected {
    neighbour:=s.subdivisions[s.sub_rows[other]]
    if point_on_boundary(vmul(vadd(a,b),0.5),sub.outline,neighbour.outline) { draw=false; break }
   }
   if draw!=cache.draw_edge[i] { mismatches+=1; testing.expectf(t,false,"%s: cell %d draw_edge[%d] differs",label,sub.id,i); break }
  }
 }
 return
}
@(test)
render_caches_match_physics_oracle_on_soak_world :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 sandbox_fixture_mode(&g,.Falling_Bombs)
 team:Bot_Team; bot_team_init(&team,4,true,55)
 for i in 1..<4 { world_add_player(&g.world,i) }
 caches:Render_Cache_State; defer release_render_caches(&caches)
 total_cells,total_bad:=0,0
 for tick in 0..<2400 {
  move,jump:=bot_team_step(&team,&g); sandbox_tick(&g,move,jump)
  if tick==0 || tick==300 || tick==900 || tick==1500 || tick==2399 {
   cells,bad:=compare_render_structure(t,&g.world.scene,&caches,fmt.tprintf("tick %d",tick))
   total_cells+=cells; total_bad+=bad
  }
 }
 testing.expect(t,total_cells>1000 && total_bad==0)
 fmt.printf("Render structure equivalence: %d cell comparisons, %d mismatches\n",total_cells,total_bad)
}

// ---------------------------------------------------------------- players
@(test)
players_do_not_collide_and_commands_are_per_player :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 sandbox_toggle_editor(&g)
 for i in 1..<MAX_PLAYERS { testing.expect(t,world_add_player(&g.world,i)) }
 testing.expect(t,!world_add_player(&g.world,2) && !world_add_player(&g.world,MAX_PLAYERS))
 for player in g.world.players { testing.expect(t,player.active && player.blast_radius==g.world.settings.blast_radius && player.pose.position==PLAYER_SPAWN) }
 for _ in 0..<30 { sandbox_tick(&g,0,false) }
 // Only players 1 and 2 walk; player 1 starts inside player 0 and walks through player 3's column.
 for _ in 0..<40 {
  commands:Tick_Commands
  commands.players[1].move=1; commands.players[2].move=-1
  events:=world_tick(&g.world,commands,1.0/60); delete(events.explosions)
 }
 x:[MAX_PLAYERS]f32
 for player,i in g.world.players { x[i]=player.pose.position.x }
 testing.expect(t,x[0]==x[3] && x[1]>x[0]+1 && x[2]<x[0]-1,"Players must pass through each other")
 // Walking players skim the floor; only the idle ones are required to report grounded.
 testing.expect(t,g.world.players[0].grounded && g.world.players[3].grounded)
 // The mirrored pose equals the body.
 for player in g.world.players { state:=read_body_state(player.body).pose; testing.expect(t,state==player.pose) }
 // Inactive players ignore commands; a removed player stays removed.
 testing.expect(t,world_remove_player(&g.world,3) && !g.world.players[3].active && !world_remove_player(&g.world,3))
 commands:Tick_Commands
 commands.players[3].move=1; append(&commands.players[3].blasts,Vec2{0,5}); commands.players[3].radius=f32(2)
 events:=world_tick(&g.world,commands,1.0/60)
 testing.expect(t,len(events.explosions)==0 && !events.blast_rejected[3])
 delete(events.explosions); delete(commands.players[3].blasts)
}
@(test)
blasts_apply_in_player_order_with_player_radius :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 for i in 1..<MAX_PLAYERS { world_add_player(&g.world,i) }
 g.world.settings.blast_radius=5
 commands:Tick_Commands
 defer { for &p in commands.players { delete(p.blasts) } }
 // Player 3 queues first in the array order of arguments, but index order decides.
 append(&commands.players[3].blasts,Vec2{6.2,1}); commands.players[3].radius=f32(1)
 append(&commands.players[1].blasts,Vec2{-4.3,1},Vec2{-0.7,1}); commands.players[1].radius=f32(2)
 append(&commands.players[0].blasts,Vec2{2.5,1}); commands.players[0].radius=f32(3)
 append(&commands.players[2].blasts,Vec2{0,5}) // Empty air: all five blasts are valid, so order is unambiguous.
 commands.bomb_radius=f32(4)
 events:=world_tick(&g.world,commands,1.0/60); defer delete(events.explosions)
 radii:[dynamic]f32; defer delete(radii)
 for e in events.explosions { append(&radii,e.radius) }
 testing.expectf(t,slice.equal(radii[:],[]f32{3,2,2,5,1}),"explosion radii %v",radii[:])
 expected:=[5]Vec2{{2.5,1},{-4.3,1},{-0.7,1},{0,5},{6.2,1}}
 if len(events.explosions)==len(expected) { for event,i in events.explosions { testing.expect(t,event.position==expected[i]) } }
 testing.expect(t,g.world.settings.blast_radius==4,"bomb_radius sets the falling-bomb radius")
 testing.expect(t,g.world.players[0].blast_radius==3 && g.world.players[1].blast_radius==2 && g.world.players[3].blast_radius==1 && g.world.players[2].blast_radius==5)
}
@(test)
local_sandbox_radius_reaches_player_zero_and_bombs :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 sandbox_toggle_editor(&g)
 sandbox_set_radius(&g,2.5)
 testing.expect(t,sandbox_radius(&g)==2.5)
 q0,qb:=g.queued.players[0].radius.(f32),g.queued.bomb_radius.(f32)
 testing.expect(t,q0==2.5 && qb==2.5)
 sandbox_tick(&g,0,false)
 testing.expect(t,g.world.settings.blast_radius==2.5 && g.world.players[0].blast_radius==2.5 && sandbox_radius(&g)==2.5)
}
@(test)
world_snapshot_v4_roundtrips_players :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 for i in 1..<MAX_PLAYERS { world_add_player(&g.world,i) }
 world_remove_player(&g.world,2)
 g.world.players[1].blast_radius=2.25; g.world.players[3].blast_radius=0.75
 g.world.players[3].coyote=0.031; g.world.players[1].buffered_jump=0.017
 for i in 0..<120 {
  commands:Tick_Commands
  commands.players[1].move=1; commands.players[3].move=-1; commands.players[0].jump=i==10
  events:=world_tick(&g.world,commands,1.0/60); delete(events.explosions)
 }
 data,ok:=encode_world_snapshot(&g.world); testing.expect(t,ok); defer delete(data)
 restored,decoded:=decode_world_snapshot(data); testing.expect(t,decoded)
 defer { scene_destroy(&restored.scene); delete(restored.bombs) }
 if !decoded { return }
 for i in 0..<MAX_PLAYERS {
  a,b:=g.world.players[i],restored.players[i]
  testing.expect(t,a.active==b.active)
  if !a.active { continue }
  testing.expect(t,a.pose==b.pose && a.blast_radius==b.blast_radius && a.coyote==b.coyote && a.buffered_jump==b.buffered_jump)
  testing.expect(t,read_body_state(b.body).pose==b.pose,"mirrors are refreshed after snapshot load")
 }
 again,encoded:=encode_world_snapshot(&restored); defer delete(again)
 testing.expect(t,encoded && string(data)==string(again),"v4 round-trips exactly")
}
@(test)
bots_are_deterministic_and_valid :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 blasts:[2][dynamic]Vec2; defer { delete(blasts[0]); delete(blasts[1]) }
 for run in 0..<2 {
  g:=soak_yard()
  for i in 1..<MAX_PLAYERS { world_add_player(&g.world,i) }
  team:Bot_Team; bot_team_init(&team,4,true,321)
  for _ in 0..<2400 {
   move,jump:=bot_team_step(&team,&g)
   for i in 0..<4 { append(&blasts[run],..g.queued.players[i].blasts[:]) }
   sandbox_tick(&g,move,jump)
  }
  sandbox_destroy(&g)
 }
 testing.expect(t,len(blasts[0])>=4 && slice.equal(blasts[0][:],blasts[1][:]))
}

// Glue seams inherit samples in place (glue_add with inherit): that path must bump the revision,
// or a replica keeps the old samples. The glue demo exercises it under blasts.
@(test)
replication_lockstep_glue_demo_under_blasts :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=seam_demo_game(); defer sandbox_destroy(&g)
 srv:Repl_Server; defer repl_server_destroy(&srv)
 rep:Replica; replica_init(&rep); defer replica_destroy(&rep)
 first:=repl_server_update(&srv,&g.world.scene,0); defer repl_output_destroy(&first)
 testing.expect(t,repl_apply_output(&rep,&first)=="")
 blasts:=[?]Vec2{{-3.8,0.5},{-4.4,1.5},{0.2,1.2},{-1.5,2.2},{1.5,0.7},{-4.6,2.7},{-2.2,3.2}}
 radii:=[?]f32{4,3,2.5,3,2,2.8,3.6}
 deltas,mismatches:=0,0
 x:Repl_Scratch; y:Repl_Scratch; defer { repl_scratch_destroy(&x); repl_scratch_destroy(&y) }
 a,b:nc.Writer; nc.writer_init(&a); nc.writer_init(&b); defer { nc.writer_destroy(&a); nc.writer_destroy(&b) }
 for tick in 1..=700 {
  if tick%90==5 {
   i:=(tick/90)%len(blasts)
   if sandbox_valid_aim(&g.world.scene,blasts[i]) { sandbox_fixture_radius(&g,radii[i]); sandbox_explode(&g,blasts[i]) }
  }
  sandbox_tick(&g,0,false)
  out:=repl_server_update(&srv,&g.world.scene,u64(tick)); defer repl_output_destroy(&out)
  if out.kind==.Delta { deltas+=1 }
  testing.expect(t,repl_apply_output(&rep,&out)=="")
  clear(&a.data); clear(&b.data)
  canonical_encode_into(&a,&g.world.scene,&x); canonical_encode_into(&b,&rep.scene,&y)
  if !bytes_equal(a.data[:],b.data[:]) { mismatches+=1; testing.expectf(t,false,"glue demo lockstep mismatch at tick %d",tick); break }
 }
 testing.expect(t,deltas>0 && mismatches==0)
 fmt.printf("Glue demo lockstep: deltas=%d mismatches=%d\n",deltas,mismatches)
}

@(test)
reset_keeps_the_active_player_set :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 world_add_player(&g.world,2); g.world.players[2].blast_radius=1.5
 world_remove_player(&g.world,0)
 epoch:=g.world.scene.epoch
 sandbox_reset(&g)
 testing.expect(t,g.world.scene.epoch==epoch+1)
 testing.expect(t,!g.world.players[0].active && g.world.players[2].active && g.world.players[2].blast_radius==1.5 && !g.world.players[1].active && !g.world.players[3].active)
 testing.expect(t,b2.Body_IsValid(g.world.players[2].body) && g.world.players[2].pose.position==PLAYER_SPAWN)
}

@(test)
replication_glue_append_emits_a_delta :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 s:=new_scene(0.1);defer scene_destroy(&s)
 add_material(&s,editor_material(.Stone))
 a_owner,b_owner:=add_piece(&s,0,42),add_piece(&s,0,42)
 pa,pb:=shape_polygon(Authored_Shape{lo={0,0},hi={1,1}}),shape_polygon(Authored_Shape{lo={0,1},hi={1,2}})
 a:=add_subdivision(&s,a_owner,pa,Pose{position=centroid(pa)});b:=add_subdivision(&s,b_owner,pb,Pose{position=centroid(pb)})
 samples:=glue_samples(pa,pb);delete(pa.points);delete(pb.points);defer delete(samples)
 testing.expect(t,len(samples)>=4)
 middle:=len(samples)/2;id:=glue_add(&s,a,b,samples[:middle])
 srv:Repl_Server;defer repl_server_destroy(&srv)
 rep:Replica;replica_init(&rep);defer replica_destroy(&rep)
 baseline:=repl_server_update(&srv,&s,0);defer repl_output_destroy(&baseline)
 testing.expect(t,repl_apply_output(&rep,&baseline)=="")
 revision:=s.structure_revision
 testing.expect(t,glue_add(&s,a,b,samples[middle:],true)==id && s.structure_revision>revision)
 delta:=repl_server_update(&srv,&s,1);defer repl_output_destroy(&delta)
 testing.expect(t,delta.kind==.Delta && repl_apply_output(&rep,&delta)=="" && scenes_equal(&s,&rep.scene))
 testing.expect(t,len(rep.scene.connections[rep.scene.conn_rows[id]].glue)==len(samples))
 fmt.printf("Glue append revision: %d -> %d, Delta applied, samples=%d\n",revision,s.structure_revision,len(samples))
}

@(test)
replication_default_limit_splits_large_baseline :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 s:=new_scene(0.1);defer scene_destroy(&s);add_material(&s,editor_material(.Stone))
 for i in 0..<6000 {
  owner:=add_piece(&s,0,42);x,y:=f32(i%100),f32(i/100)
  p:=shape_polygon(Authored_Shape{lo={x,y},hi={x+1,y+1}})
  add_subdivision(&s,owner,p,Pose{position=centroid(p)});delete(p.points)
 }
 srv:Repl_Server;defer repl_server_destroy(&srv)
 rep:Replica;replica_init(&rep);defer replica_destroy(&rep)
 baseline:=repl_server_update(&srv,&s,0);defer repl_output_destroy(&baseline)
 testing.expect(t,baseline.message_bytes>REPL_PART_LIMIT && len(baseline.parts)>1)
 largest:=0
 for part,i in baseline.parts {
  largest=max(largest,len(part));testing.expect(t,len(part)<=REPL_PART_LIMIT+16 && len(part)<=255_000)
  applied,err:=replica_receive(&rep,part);testing.expect(t,err=="")
  if i<len(baseline.parts)-1 { testing.expect(t,!applied && !rep.has_baseline && len(rep.scene.subdivisions)==0) }
  else { testing.expect(t,applied && rep.has_baseline && scenes_equal(&s,&rep.scene)) }
 }
 fmt.printf("Large Baseline: %d bytes, parts=%d largest=%d, applied atomically\n",baseline.message_bytes,len(baseline.parts),largest)
}

@(test)
replication_material_append_without_cells_emits_delta :: proc(t:^testing.T) {
 s:=new_scene(0.1);defer scene_destroy(&s);add_material(&s,editor_material(.Stone))
 srv:Repl_Server;defer repl_server_destroy(&srv)
 rep:Replica;replica_init(&rep);defer replica_destroy(&rep)
 base:=repl_server_update(&srv,&s,0);defer repl_output_destroy(&base)
 testing.expect(t,repl_apply_output(&rep,&base)=="")
 revision:=s.structure_revision;add_material(&s,editor_material(.Glass))
 testing.expect(t,s.structure_revision>revision)
 delta:=repl_server_update(&srv,&s,1);defer repl_output_destroy(&delta)
 testing.expect(t,delta.kind==.Delta && repl_apply_output(&rep,&delta)=="" && scenes_equal(&s,&rep.scene) && len(rep.scene.materials)==2)
}
