package shared
import t "core:testing"
import b2 "vendor:box2d"
import json "core:encoding/json"
import strings "core:strings"
import slice "core:slice"
import nc "../netcode"

@(test)
graze_exposed_annulus_includes_outer_boundary_keeps_lethal_and_outside_zones :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w);w.elimination_playing=true
 _=world_add_player(&w,2);_=world_add_player(&w,3)
 for x,i in ([4]f32{1.45,1.47,2.2+PLAYER_RADIUS,2.461}) {b2.Body_SetTransform(w.players[i].body,{x,1},b2.MakeRot(0))}
 events:Tick_Events;defer delete(events.explosions);world_explode(&w,{0,1},5,&events)
 t.expect(test,events.deaths==[MAX_PLAYERS]Round_Death{.Blast,.None,.None,.None})
 for count,i in ([4]u32{0,1,1,0}) {t.expect(test,w.players[i].graze_count==count)}
 t.expect(test,len(events.explosions)==1&&events.explosions[0].radius==5)
 // N2's lethal tangency remains harmless and is not outside the lethal zone.
 b2.Body_SetTransform(w.players[3].body,{1.2+PLAYER_RADIUS,1},b2.MakeRot(0))
 world_explode(&w,{0,1},5,&events)
 t.expect(test,events.deaths[3]==.None&&w.players[3].graze_count==0)
 t.expect(test,w.players[0].graze_count==0,"a pending lethal death cannot graze on another explosion")
}

@(test)
graze_full_cover_including_zero_resistance_protects_and_partial_exposure_counts :: proc(test:^t.T) {
 for partial in ([2]bool{false,true}) {
  w:=round_test_world();w.elimination_playing=true;_=world_remove_player(&w,1)
  b2.Body_SetTransform(w.players[0].body,{2.26,1},b2.MakeRot(0))
  top:=f32(3);if partial {top=1.1}
  _=owner_rule_rectangle(&w.scene,{.7,-1},{.8,top},.Indestructible,.Fixed,0)
  physics_sync_structure(&w.scene)
  events:Tick_Events;world_explode(&w,{0,1},5,&events)
  t.expect(test,w.players[0].graze_count==(partial?u32(1):0)&&events.deaths[0]==.None)
  delete(events.explosions);round_test_world_destroy(&w)
 }
}

@(test)
graze_cover_is_captured_before_the_detonation_destroys_it :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w);w.elimination_playing=true;_=world_remove_player(&w,1)
 b2.Body_SetTransform(w.players[0].body,{2.26,1},b2.MakeRot(0))
 wall:=owner_rule_rectangle(&w.scene,{.9,0},{1.1,3},.Destructible,.Fixed,.5);physics_sync_structure(&w.scene)
 events:Tick_Events;defer delete(events.explosions)
 world_explode(&w,{0,1},5,&events)
 t.expect(test,w.players[0].graze_count==0&&events.deaths[0]==.None&&!is_live_subdivision(&w.scene,wall))
 world_explode(&w,{0,1},5,&events)
 t.expect(test,w.players[0].graze_count==1&&events.deaths[0]==.None)
}

@(test)
graze_counts_once_per_explosion_dies_on_third_and_ignores_later_detonations :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w);w.elimination_playing=true;_=world_remove_player(&w,1)
 b2.Body_SetTransform(w.players[0].body,{2.26,1},b2.MakeRot(0))
 events:Tick_Events;defer delete(events.explosions)
 for count in u32(1)..=4 {
  world_explode(&w,{0,1},5,&events)
  t.expect(test,w.players[0].graze_count==min(count,u32(3)))
  t.expect(test,events.deaths[0]==(count<3?Round_Death.None:Round_Death.Blast))
  t.expect(test,len(events.explosions)==int(count),"damage never suppresses the actual explosion")
 }
}

@(test)
graze_sandbox_keeps_players_undamaged_at_lethal_and_graze_distances :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w)
 for x,i in ([2]f32{0,2.26}) {b2.Body_SetTransform(w.players[i].body,{x,1},b2.MakeRot(0))}
 events:Tick_Events;defer delete(events.explosions)
 for i in 0..<4 {world_explode(&w,{0,1},5,&events)}
 t.expect(test,events.deaths==[MAX_PLAYERS]Round_Death{}&&len(events.explosions)==4)
 for p in w.players[:2] {t.expect(test,p.active&&p.graze_count==0)}
}

@(test)
graze_uses_authored_threshold_and_radii_without_extending_small_explosions :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w);w.elimination_playing=true;_=world_remove_player(&w,1)
 w.scene.level_policy.active=true;w.scene.level_policy.config=DEFAULT_GAMEPLAY_CONFIG
 w.scene.level_policy.config.lethal_radius=.9;w.scene.level_policy.config.graze_radius=1.8;w.scene.level_policy.config.grazes_to_die=2
 b2.Body_SetTransform(w.players[0].body,{1.76,1},b2.MakeRot(0))
 events:Tick_Events;defer delete(events.explosions)
 world_explode(&w,{0,1},1,&events);t.expect(test,w.players[0].graze_count==0&&events.deaths[0]==.None)
 world_explode(&w,{0,1},5,&events);t.expect(test,w.players[0].graze_count==1&&events.deaths[0]==.None)
 world_explode(&w,{0,1},5,&events);t.expect(test,w.players[0].graze_count==2&&events.deaths[0]==.Blast)
}

graze_test_server :: proc()->Net_Server {
 ns:=round_test_server();ns.rounds.mode=.Elimination;_=round_begin(&ns.rounds)
 for i in 0..<2 {round_ready(&ns.rounds,i,ns.clients[i].incarnation,true)}
 round_server_prepare(&ns);ns.tick=ROUND_COUNTDOWN_TICKS;round_server_prepare(&ns)
 for x,i in ([2]f32{2.26,8}) {b2.Body_SetTransform(ns.game.world.players[i].body,{x,1},b2.MakeRot(0))}
 return ns
}

@(test)
graze_server_publishes_every_change_preserves_final_damage_and_resets_next_round :: proc(test:^t.T) {
 ns:=graze_test_server();defer net_server_destroy(&ns)
 t.expect(test,ns.rounds.state==.Playing)
 for count in u32(1)..=3 {
  ns.round_dirty=false
  events:Tick_Events;world_explode(&ns.game.world,{0,1},5,&events);round_server_finish(&ns,events);delete(events.explosions);ns.tick+=1
  snapshot:=round_snapshot(&ns)
  t.expect(test,ns.round_dirty&&snapshot.players[0].graze_count==count)
  t.expect(test,snapshot.players[0].alive==(count<3))
  t.expect(test,ns.rounds.state==(count<3?Round_State.Playing:Round_State.Finished))
 }
 t.expect(test,!ns.game.world.players[0].active&&ns.rounds.players[0].death==.Blast&&ns.rounds.winner==2)
 events:Tick_Events;world_explode(&ns.game.world,{0,1},5,&events);defer delete(events.explosions)
 t.expect(test,round_snapshot(&ns).players[0].graze_count==3,"a dead participant keeps their final count")
 old_id:=ns.rounds.id;restart:=[2]u8{NET_APP_HOST_COMMAND,NET_HOST_RESET}
 t.expect(test,net_host_apply_command(&ns,0,restart[:])==""&&ns.rounds.id==old_id+1)
 for p in round_snapshot(&ns).players {t.expect(test,p.graze_count==0)}
 for p in ns.game.world.players {t.expect(test,p.graze_count==0)}
}

@(test)
graze_simultaneous_third_hits_draw_and_disconnect_retains_previous_damage :: proc(test:^t.T) {
 ns:=graze_test_server();defer net_server_destroy(&ns)
 for &p,i in ns.game.world.players[:2] {p.graze_count=2;b2.Body_SetTransform(p.body,{i==0?f32(2.26):-2.26,1},b2.MakeRot(0))}
 events:Tick_Events;defer delete(events.explosions);world_explode(&ns.game.world,{0,1},5,&events);round_server_finish(&ns,events)
 t.expect(test,ns.rounds.state==.Finished&&ns.rounds.draw&&ns.rounds.winner==0)
 for p in ns.rounds.players[:2] {t.expect(test,!p.alive&&p.graze_count==3&&p.death==.Blast)}
 other:=graze_test_server();defer net_server_destroy(&other)
 other.game.world.players[0].graze_count=2;round_server_finish(&other,{})
 round_disconnect(&other.rounds,0);round_server_sync_bodies(&other);round_server_finish(&other,{})
 t.expect(test,other.rounds.players[0].graze_count==2&&other.rounds.players[0].death==.Disconnect)
}

@(test)
graze_config_v4_migration_preserves_every_authored_value_through_level_loading :: proc(test:^t.T) {
 legacy_json :: `{"version":4,"gravity":{"x":1,"y":-12},"player":{"speed":6,"acceleration":50,"jump_speed":9,"coyote_time":0.2,"jump_buffer":0.3,"gravity_scale":1.75},"bomb_fuse":2,"bomb_drop_min":1.2,"bomb_drop_max":3,"bomb_radius":4,"lethal_radius":0.8,"graze_radius":1.8,"elimination_start_interval":{"x":2,"y":3},"elimination_end_interval":{"x":0.5,"y":1.5},"elimination_ramp_seconds":120}`
 old:Gameplay_Config;t.expect(test,json.unmarshal(transmute([]u8)string(legacy_json),&old)==nil)
 expected:=old;expected.version=5;expected.grazes_to_die=3
 current:=gameplay_config_upgrade(old)
 t.expect(test,current==expected&&gameplay_config_valid(current)&&gameplay_config_upgrade(current)==current)
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_level_layout(&level)
 level.gameplay_config=old
 bytes,encoded:=exact_json_encode(level,false);t.expect(test,encoded);defer delete(bytes)
 copy,valid,problem:=decode_level_layout(bytes);t.expect(test,valid,problem);if !valid {return};defer destroy_level_layout(&copy)
 t.expect(test,copy.gameplay_config==expected)
}

@(test)
graze_config_validates_threshold_hashes_it_and_preserves_catalog_state :: proc(test:^t.T) {
 for count in ([3]u32{0,256,max(u32)}) {config:=DEFAULT_GAMEPLAY_CONFIG;config.grazes_to_die=count;t.expect(test,!gameplay_config_valid(config))}
 for count in ([3]u32{1,3,255}) {config:=DEFAULT_GAMEPLAY_CONFIG;config.grazes_to_die=count;t.expect(test,gameplay_config_valid(config))}
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_level_layout(&level)
 original:=level_gameplay_hash(&level);hash:=gameplay_config_hash(level.gameplay_config);level.gameplay_config.grazes_to_die=7
 t.expect(test,gameplay_config_hash(level.gameplay_config)!=hash&&level_gameplay_hash(&level)!=original)
 scene:=new_scene(0);defer scene_destroy(&scene);scene_apply_level(&scene,&level)
 copy:=new_scene(0);defer scene_destroy(&copy);t.expect(test,scene_restore_catalog_data(&copy,scene.level_json,scene.source_parts[:]))
 t.expect(test,copy.level_policy.config==level.gameplay_config&&copy.config_hash==scene.config_hash&&copy.gameplay_manifest==scene.gameplay_manifest)
 level.gameplay_config.grazes_to_die=0
 bytes,encoded:=exact_json_encode(level,false);defer delete(bytes);t.expect(test,encoded)
 bad,valid,_:=decode_level_layout(bytes);t.expect(test,!valid,"v5 must reject a missing threshold, not silently repair it");if valid {destroy_level_layout(&bad)}
 fixture,_:=strings.replace_all(string(LEVEL_V4_TEST),"bom-default-v1","bom-default-v5",context.temp_allocator)
 omitted,loaded,why:=decode_level_layout(transmute([]u8)fixture);t.expect(test,loaded,why)
 if loaded {t.expect(test,omitted.gameplay_config==DEFAULT_GAMEPLAY_CONFIG);destroy_level_layout(&omitted)}
}

@(test)
graze_round_wire_has_versioned_exact_offsets_roundtrip_and_byte_identity :: proc(test:^t.T) {
 snapshot:=Round_Snapshot{rules_version=ROUND_RULES_VERSION,mode=.Elimination,state=.Playing,epoch=9,id=9007199254741001,lethal_radius=1.2}
 for i in 0..<MAX_PLAYERS {snapshot.players[i]={session_id=u64(i+1),generation=u64(i+7),slot=i,alive=i<3,graze_count=u32(i)}}
 writer:nc.Writer;nc.writer_init(&writer);defer nc.writer_destroy(&writer);round_encode(&writer,snapshot)
 t.expect(test,GAME_PROTOCOL_VERSION==9&&ROUND_RULES_VERSION==4&&len(writer.data)==533+8+MAX_PLAYERS*21)
 for i in 0..<MAX_PLAYERS {
  offset:=73+i*55+19
  t.expect(test,writer.data[offset]==u8(i)&&writer.data[offset+1]==0&&writer.data[offset+2]==0&&writer.data[offset+3]==0,"each new count occupies its fixed little-endian u32 position")
 }
 copy,ok:=round_decode(writer.data[:]);t.expect(test,ok&&copy==snapshot)
 second:nc.Writer;nc.writer_init(&second);defer nc.writer_destroy(&second);round_encode(&second,copy)
 t.expect(test,slice.equal(writer.data[:],second.data[:]))
 for length in 0..<len(writer.data) {_,valid:=round_decode(writer.data[:length]);t.expect(test,!valid)}
 writer.data[5]=2;_,old:=round_decode(writer.data[:]);t.expect(test,!old,"old round format cannot be accepted as the new layout")
 client:Net_Client;round_client_accept(&client,second.data[:]);t.expect(test,client.has_round&&client.round_snapshot.players[2].graze_count==2)
}
