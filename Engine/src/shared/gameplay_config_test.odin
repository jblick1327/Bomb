package shared
import t "core:testing"
import b2 "vendor:box2d"
import strings "core:strings"
import nc "../netcode"

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
 s:=new_scene(0);defer scene_destroy(&s);s.level_policy.active=true;s.level_policy.config=DEFAULT_GAMEPLAY_CONFIG;s.level_policy.config.player={7,100,9,.4,.3}
 prediction:Static_Prediction;t.expect(test,prediction_static_build(&prediction,&s,true));defer prediction_static_destroy(&prediction)
 player:=&prediction.player;player.grounded=true;player_movement_from_support(player,1,true,1.0/60)
 velocity:=from_b2(b2.Body_GetLinearVelocity(player.body));t.expect(test,velocity.x>1.6&&velocity.y==9)
 o:=Owner_State{identity={1,1,1},position={0,3},coyote=.4,buffered_jump=.3,teleport_serial=1}
 t.expect(test,owner_state_restore(prediction.scene.physics.world,player,o)&&player.tuning.speed==7&&player.coyote==.4&&player.buffered_jump==.3)
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
