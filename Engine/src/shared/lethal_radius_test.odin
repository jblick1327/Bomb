package shared
import t "core:testing"
import b2 "vendor:box2d"
import math "core:math"
import json "core:encoding/json"
import strings "core:strings"
import nc "../netcode"

@(test)
lethal_radius_separates_capsule_death_from_full_crater_and_graze_zone :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w);w.elimination_playing=true
 _=world_add_player(&w,2);_=world_add_player(&w,3)
 // Distances to the capsule surface: 1.19, 1.21, 2.0 and 4.0.
 for x,i in ([4]f32{1.45,1.47,2.26,4.26}) {b2.Body_SetTransform(w.players[i].body,{x,1},b2.MakeRot(0))}
 target:=owner_rule_rectangle(&w.scene,{3,-.2},{3.2,.2},.Destructible,.Fixed,.5)
 physics_sync_structure(&w.scene)
 events:Tick_Events;defer delete(events.explosions)
 world_explode(&w,{0,1},5,&events)
 t.expect(test,events.deaths==[MAX_PLAYERS]Round_Death{.Blast,.None,.None,.None},"only capsules inside 1.2 die; grazes await N3")
 t.expect(test,!is_live_subdivision(&w.scene,target),"destruction beyond both damage zones still receives the full radius")
 t.expect(test,len(events.explosions)==1&&events.explosions[0].radius==5,"presentation retains the crater radius")
}

@(test)
lethal_radius_uses_authored_config_and_never_extends_a_smaller_explosion :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w);w.elimination_playing=true
 w.scene.level_policy.active=true;w.scene.level_policy.config=DEFAULT_GAMEPLAY_CONFIG
 w.scene.level_policy.config.lethal_radius=.7
 b2.Body_SetTransform(w.players[0].body,{.95,1},b2.MakeRot(0))
 b2.Body_SetTransform(w.players[1].body,{.97,1},b2.MakeRot(0))
 events:Tick_Events;defer delete(events.explosions)
 world_explode(&w,{0,1},5,&events)
 t.expect(test,events.deaths[0]==.Blast&&events.deaths[1]==.None,"authored .7 overrides default 1.2")
 events.deaths={};world_explode(&w,{0,1},.5,&events)
 t.expect(test,events.deaths==[MAX_PLAYERS]Round_Death{},"a .5 blast cannot inherit the larger configured lethal zone")
 w.elimination_playing=false;world_explode(&w,{.95,1},5,&events)
 t.expect(test,events.deaths==[MAX_PLAYERS]Round_Death{},"Sandbox still has no elimination deaths")
}

@(test)
lethal_radius_keeps_full_zero_resistance_cover_and_partial_capsule_visibility :: proc(test:^t.T) {
 for partial in ([2]bool{false,true}) {
  w:=round_test_world();w.elimination_playing=true
  b2.Body_SetTransform(w.players[0].body,{1.4,1},b2.MakeRot(0));_=world_remove_player(&w,1)
  top:=f32(3);if partial {top=1.1}
  _=owner_rule_rectangle(&w.scene,{.7,-1},{.8,top},.Indestructible,.Fixed,0)
  physics_sync_structure(&w.scene)
  events:Tick_Events;world_explode(&w,{0,1},5,&events)
  t.expect(test,events.deaths[0]==(partial?Round_Death.Blast:Round_Death.None),"full cover protects; an exposed capsule tip inside lethal radius counts")
  delete(events.explosions);round_test_world_destroy(&w)
 }
}

@(test)
lethal_radius_round_snapshot_reports_effective_damage_radius_without_layout_change :: proc(test:^t.T) {
 ns:Net_Server;ns.game.world.settings=DEFAULT_SANDBOX_SETTINGS
 ns.game.world.settings.blast_radius=5
 result:=round_snapshot(&ns);t.expect(test,result.lethal_radius==1.2&&result.rules_version==2)
 ns.game.world.scene.level_policy.active=true;ns.game.world.scene.level_policy.config=DEFAULT_GAMEPLAY_CONFIG
 ns.game.world.scene.level_policy.config.lethal_radius=.9
 result=round_snapshot(&ns);t.expect(test,result.lethal_radius==.9)
 ns.game.world.settings.blast_radius=.5
 result=round_snapshot(&ns);t.expect(test,result.lethal_radius==.5)
 writer:nc.Writer;nc.writer_init(&writer);defer nc.writer_destroy(&writer);round_encode(&writer,result)
 copy,ok:=round_decode(writer.data[:]);t.expect(test,ok&&copy.lethal_radius==result.lethal_radius)
}

@(test)
lethal_radius_config_v3_json_migration_preserves_authored_fields_and_adds_damage_zones :: proc(test:^t.T) {
 legacy_json :: `{"version":3,"gravity":{"x":0,"y":-12},"player":{"speed":6,"acceleration":50,"jump_speed":9,"coyote_time":0.2,"jump_buffer":0.3,"gravity_scale":1.75},"bomb_fuse":2,"bomb_drop_min":1.2,"bomb_drop_max":3,"bomb_radius":4,"elimination_start_interval":{"x":2,"y":3},"elimination_end_interval":{"x":0.5,"y":1.5},"elimination_ramp_seconds":120}`
 old:Gameplay_Config;t.expect(test,json.unmarshal(transmute([]u8)string(legacy_json),&old)==nil)
 expected:=old;expected.version=4;expected.lethal_radius=1.2;expected.graze_radius=2.2
 current:=gameplay_config_upgrade(old)
 t.expect(test,current==expected&&gameplay_config_valid(current)&&gameplay_config_upgrade(current)==current)
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_level_layout(&level)
 level.gameplay_config=old
 bytes,encoded:=exact_json_encode(level,false);t.expect(test,encoded);defer delete(bytes)
 copy,valid,problem:=decode_level_layout(bytes);t.expect(test,valid,problem);if !valid {return};defer destroy_level_layout(&copy)
 t.expect(test,copy.gameplay_config==expected,"explicit v3 levels use migrated authoritative rules")
 for id in ([4]string{"bom-default-v1","bom-default-v2","bom-default-v3","bom-default-v4"}) {
  fixture,_:=strings.replace_all(string(LEVEL_V4_TEST),"bom-default-v1",id,context.temp_allocator)
  omitted,loaded,why:=decode_level_layout(transmute([]u8)fixture);t.expect(test,loaded,why)
  if loaded {t.expect(test,omitted.gameplay_config==DEFAULT_GAMEPLAY_CONFIG);destroy_level_layout(&omitted)}
 }
}

@(test)
lethal_radius_config_validation_hashing_and_catalog_preserve_both_zones :: proc(test:^t.T) {
 for invalid in ([7]f32{0,-1,.099,6.001,math.nan_f32(),math.inf_f32(1),math.inf_f32(-1)}) {
  config:=DEFAULT_GAMEPLAY_CONFIG;config.lethal_radius=invalid;t.expect(test,!gameplay_config_valid(config))
  config=DEFAULT_GAMEPLAY_CONFIG;config.graze_radius=invalid;t.expect(test,!gameplay_config_valid(config))
 }
 config:=DEFAULT_GAMEPLAY_CONFIG;config.graze_radius=1.19;t.expect(test,!gameplay_config_valid(config))
 config.lethal_radius=.1;config.graze_radius=.1;t.expect(test,gameplay_config_valid(config))
 config.lethal_radius=6;config.graze_radius=6;t.expect(test,gameplay_config_valid(config),"damage radii are independent of the destruction radius")
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok {return};defer destroy_level_layout(&level)
 original:=level_gameplay_hash(&level);hash:=gameplay_config_hash(level.gameplay_config)
 for graze in ([2]bool{false,true}) {
  level.gameplay_config=DEFAULT_GAMEPLAY_CONFIG
  if graze {level.gameplay_config.graze_radius=2.2345678}else{level.gameplay_config.lethal_radius=1.2345678}
  t.expect(test,level_gameplay_hash(&level)!=original&&gameplay_config_hash(level.gameplay_config)!=hash)
  scene:=new_scene(0);scene_apply_level(&scene,&level)
  copy:=new_scene(0);t.expect(test,scene_restore_catalog_data(&copy,scene.level_json,scene.source_parts[:]))
  t.expect(test,copy.level_policy.config==level.gameplay_config&&copy.gameplay_manifest==scene.gameplay_manifest&&copy.config_hash==scene.config_hash,"both zone fields retain exact float bits through the catalog")
  scene_destroy(&copy);scene_destroy(&scene)
 }
 level.gameplay_config=DEFAULT_GAMEPLAY_CONFIG;level.gameplay_config.lethal_radius=0
 bytes,encoded:=exact_json_encode(level,false);t.expect(test,encoded);defer delete(bytes)
 bad,valid,_:=decode_level_layout(bytes);t.expect(test,!valid,"v4 must reject missing damage zones rather than silently migrating them");if valid {destroy_level_layout(&bad)}
}
