package shared
import t "core:testing"
import b2 "vendor:box2d"
import strings "core:strings"
import nc "../netcode"
import math "core:math"
import json "core:encoding/json"

@(test)
gameplay_manifest_excludes_visual_content_and_includes_authoritative_config_and_geometry :: proc(test:^t.T) {
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_level_layout(&level)
 original:=level_gameplay_hash(&level)
 old:=level.sources[0].visual_hash;level.sources[0].visual_hash=strings.clone("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
 t.expect(test,level_gameplay_hash(&level)==original);delete(level.sources[0].visual_hash);level.sources[0].visual_hash=old
 level.sources[0].group_to_rest[12]+=1;t.expect(test,level_gameplay_hash(&level)==original,"art transform is separate from explicit world-rest gameplay proxies")
 level.gameplay_config.player.speed+=1;t.expect(test,level_gameplay_hash(&level)!=original)
 level.gameplay_config.player.speed-=1;level.sources[0].parts[0].outline[0].x+=.01;t.expect(test,level_gameplay_hash(&level)!=original)
}
@(test)
configured_player_motion_and_owner_restore_use_shared_tuning :: proc(test:^t.T) {
 s:=new_scene(0);defer scene_destroy(&s);s.level_policy.active=true;s.level_policy.config=DEFAULT_GAMEPLAY_CONFIG;s.level_policy.config.player={7,100,9,.4,.3,1.75}
 prediction:Static_Prediction;t.expect(test,prediction_static_build(&prediction,&s,true));defer prediction_static_destroy(&prediction)
 player:=&prediction.player;player.grounded=true;player_movement_from_support(player,1,true,1.0/60)
 t.expect(test,b2.Body_GetGravityScale(player.body)==1.75)
 velocity:=from_b2(b2.Body_GetLinearVelocity(player.body));t.expect(test,velocity.x>1.6&&velocity.y==9)
 o:=Owner_State{identity={1,1,1},position={0,3},coyote=.4,buffered_jump=.3,teleport_serial=1}
 t.expect(test,owner_state_restore(prediction.scene.physics.world,player,o)&&player.tuning.speed==7&&player.coyote==.4&&player.buffered_jump==.3)
 t.expect(test,b2.Body_GetGravityScale(player.body)==1.75,"rewinding must recreate the configured player gravity")
}
@(test)
known_wrong_gameplay_manifest_rejects_before_adding_player :: proc(test:^t.T) {
 ns,ok:=net_real_create_server("");t.expect(test,ok);if !ok {return};defer net_server_destroy(&ns);ns.real_gate=true;ns.real_logging=false
 w:nc.Writer;nc.writer_init(&w);defer nc.writer_destroy(&w)
 wrong:[32]u8;wrong[0]=1
 net_app_write_hello(&w,GAME_PROTOCOL_VERSION,GAME_BUILD_ID,"",wrong[:]);net_app_server_hello(&ns,0,w.data[:],1)
 t.expect(test,!ns.clients[0].active&&!ns.game.world.players[0].active&&ns.real_reject_at[0]>0)
 nc.writer_reset(&w);net_app_write_hello(&w,GAME_PROTOCOL_VERSION,GAME_BUILD_ID,"");net_app_server_hello(&ns,1,w.data[:],1)
 t.expect(test,ns.clients[1].active&&ns.game.world.players[1].active,"missing local art/manifest may use authoritative server data")
}
@(test)
known_manifest_mismatch_after_level_change_never_reaches_presented_topology :: proc(test:^t.T) {
 c:Net_Client;net_client_init(&c,1234,0);defer net_client_destroy(&c);c.has_expected_manifest=true
 legacy:=test_prediction_static_scene();defer scene_destroy(&legacy)
 server:Repl_Server;defer repl_server_destroy(&server)
 first:=repl_server_baseline(&server,&legacy,0);defer repl_output_destroy(&first)
 for part in first.parts {net_client_on_reliable(&c,part)}
 t.expect(test,c.rep.has_baseline&&c.rep.scene.epoch==1&&c.real_reason=="")
 layout,seed,ok,reason:=decode_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_layout(&layout)
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false);w.scene.epoch=2;defer scene_destroy(&w.scene);defer delete(w.bombs)
 next:=repl_server_baseline(&server,&w.scene,1);defer repl_output_destroy(&next)
 for part in next.parts {net_client_on_reliable(&c,part)}
 t.expect(test,c.real_reason!=""&&c.rep.scene.epoch==1&&c.received.scene.epoch==2&&len(c.queue)==0,"incompatible catalog must not become visible or queued")
}
@(test)
catalog_roundtrip_preserves_tiny_config_and_matrix_float_bits_and_gameplay_fingerprint :: proc(test:^t.T) {
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_level_layout(&level)
 level.gameplay_config.player.jump_buffer=1.2345678e-9;level.gameplay_config.player.gravity_scale=1.2345678;level.sources[0].group_to_rest[4]=1.2345678e-9
 scene:=new_scene(0);defer scene_destroy(&scene);scene_apply_level(&scene,&level)
 t.expect(test,scene.catalog!=nil&&transmute(u32)scene.catalog.gameplay_config.player.jump_buffer==transmute(u32)level.gameplay_config.player.jump_buffer&&transmute(u32)scene.catalog.sources[0].group_to_rest[4]==transmute(u32)level.sources[0].group_to_rest[4])
 copy:=new_scene(0);defer scene_destroy(&copy);t.expect(test,scene_restore_catalog_data(&copy,scene.level_json,scene.source_parts[:]))
 t.expect(test,copy.gameplay_manifest==scene.gameplay_manifest&&copy.config_hash==scene.config_hash,"catalog text may not round tuning and invalidate a legitimate bundled manifest")
 t.expect(test,transmute(u32)copy.level_policy.config.player.gravity_scale==transmute(u32)level.gameplay_config.player.gravity_scale)
}

@(test)
gameplay_config_v2_json_migration_preserves_authored_rules_and_unit_gravity :: proc(test:^t.T) {
 legacy_json :: `{"version":2,"gravity":{"x":0,"y":-12},"player":{"speed":4,"acceleration":32,"jump_speed":6.3,"coyote_time":0.2,"jump_buffer":0.3},"bomb_fuse":2,"bomb_drop_min":1.2,"bomb_drop_max":3,"bomb_radius":4,"elimination_start_interval":{"x":2,"y":3},"elimination_end_interval":{"x":0.5,"y":1.5},"elimination_ramp_seconds":120}`
 legacy:Gameplay_Config;t.expect(test,json.unmarshal(transmute([]u8)string(legacy_json),&legacy)==nil)
 t.expect(test,legacy.player.gravity_scale==0&&!gameplay_config_valid(legacy))
 expected:=legacy;expected.version=4;expected.player.gravity_scale=1;expected.lethal_radius=1.2;expected.graze_radius=2.2
 upgraded:=gameplay_config_upgrade(legacy)
 t.expect(test,upgraded==expected&&gameplay_config_valid(upgraded),"v2 migration must preserve every existing authored field")
 t.expect(test,gameplay_config_upgrade(upgraded)==upgraded,"migration must be idempotent")
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_level_layout(&level)
 level.gameplay_config=legacy
 bytes,encoded:=exact_json_encode(level,false);t.expect(test,encoded);defer delete(bytes)
 copy,valid,problem:=decode_level_layout(bytes);t.expect(test,valid,problem);if !valid {return};defer destroy_level_layout(&copy)
 t.expect(test,copy.gameplay_config==expected,"level loading must migrate explicit config v2")
}

@(test)
gameplay_config_validates_and_fingerprints_player_gravity :: proc(test:^t.T) {
 config:=DEFAULT_GAMEPLAY_CONFIG
 t.expect(test,config.version==4&&gameplay_config_valid(config)&&gameplay_config_upgrade(config)==config)
 for scale in ([7]f32{0,-1,.099,10.001,math.nan_f32(),math.inf_f32(1),math.inf_f32(-1)}) {
  config.player.gravity_scale=scale;t.expect(test,!gameplay_config_valid(config))
 }
 for scale in ([3]f32{.1,1,10}) {config.player.gravity_scale=scale;t.expect(test,gameplay_config_valid(config))}
 config=DEFAULT_GAMEPLAY_CONFIG;config.version=5;t.expect(test,!gameplay_config_valid(gameplay_config_upgrade(config)))
 config=DEFAULT_GAMEPLAY_CONFIG;hash:=gameplay_config_hash(config);config.player.gravity_scale=1
 t.expect(test,gameplay_config_hash(config)!=hash,"gravity changes must invalidate gameplay config manifests")
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_level_layout(&level)
 original:=level_gameplay_hash(&level);level.gameplay_config.player.gravity_scale=1
 t.expect(test,level_gameplay_hash(&level)!=original,"gravity changes must invalidate the level handshake manifest")
 level.gameplay_config.player.gravity_scale=0
 bytes,encoded:=exact_json_encode(level,false);t.expect(test,encoded);defer delete(bytes)
 bad,valid,_:=decode_level_layout(bytes);t.expect(test,!valid,"current config cannot silently migrate a missing or zero scale");if valid {destroy_level_layout(&bad)}
}

@(test)
validation_report_serializes_double_precision_area :: proc(test:^t.T) {
 report:=Level_Source_Report{identity=9007199254741001,area=1.23456789012345e-9}
 encoded,ok:=exact_json_encode(report,false);defer delete(encoded)
 t.expect(test,ok&&strings.contains(string(encoded),"1.23456789012345e-09"),"reports must preserve f64 values instead of failing serialization")
}
