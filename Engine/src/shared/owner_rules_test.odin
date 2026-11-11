#+feature dynamic-literals
package shared
import t "core:testing"
import math "core:math"
import b2 "vendor:box2d"
import nc "../netcode"

owner_rule_rectangle :: proc(s:^Scene,lo,hi:Vec2,damage:Damage_Policy=.Indestructible,motion:Motion_Policy=.Fixed,resistance:f32=3) -> u64 {
 material:=editor_material(.Glass);material.blast_resistance=resistance
 mi:=add_material(s,material);owner:=add_piece(s,mi,0)
 points:=[4]Vec2{{lo.x,lo.y},{hi.x,lo.y},{hi.x,hi.y},{lo.x,hi.y}};outline:=Polygon{points[:]}
 id:=add_subdivision(s,owner,outline,Pose{position=centroid(outline)})
 s.subdivisions[s.sub_rows[id]].provenance={SOURCE_DIAGNOSTIC,owner,motion,damage,motion==.Fixed}
 return id
}

@(test)
owner_capsule_visibility_respects_intact_cover_partial_exposure_and_actual_radius :: proc(test:^t.T) {
 s:=new_scene(0);defer scene_destroy(&s)
 _=owner_rule_rectangle(&s,{1,-1},{1.2,3})
 full:=cover_begin(&s,5,true);defer cover_destroy(&full)
 t.expect(test,!blast_capsule_visible(&full,{3,1},Blast{{0,1},5}),"intact wall blocks the whole capsule")
 t.expect(test,!blast_capsule_visible(&full,{3,1},Blast{{3,3},.5}),"the real small radius does not inherit 2.2-unit lethality")
 clear_scene:=new_scene(0);defer scene_destroy(&clear_scene)
 clear_cover:=cover_begin(&clear_scene,5,true);defer cover_destroy(&clear_cover)
 t.expect(test,blast_capsule_visible(&clear_cover,{3,1},Blast{{0,1},5}),"exposure beyond the former 2.2-unit radius is lethal within the actual radius")
 t.expect(test,!blast_capsule_visible(&clear_cover,{3,1},Blast{{0,1},2}),"outside the actual blast remains safe")
 partial:=new_scene(0);defer scene_destroy(&partial)
 _=owner_rule_rectangle(&partial,{1,-1},{1.2,1.1})
 partial_cover:=cover_begin(&partial,5,true);defer cover_destroy(&partial_cover)
 t.expect(test,cover_ray_occluded(&partial_cover,{0,1},{3,1}),"center is covered")
 t.expect(test,blast_capsule_visible(&partial_cover,{3,1},Blast{{0,1},5}),"exposed upper capsule is reached even though its center is covered")
}

@(test)
owner_capsule_visibility_detects_narrow_slit_without_fixed_sample_points :: proc(test:^t.T) {
 s:=new_scene(0);defer scene_destroy(&s)
 // A .001-thick wall leaves a real line through the .0001-high slit. The
 // former .01 thickness blocked every downward ray across the wall's depth.
 _=owner_rule_rectangle(&s,{1,-1},{1.001,.96})
 _=owner_rule_rectangle(&s,{1,.9601},{1.001,3})
 cover:=cover_begin(&s,5,true);defer cover_destroy(&cover)
 t.expect(test,cover_ray_occluded(&cover,{0,1},{3,1}))
 t.expect(test,blast_capsule_visible(&cover,{3,1},Blast{{0,1},5}),"angular intervals find the small exposed part through the slit")
}

@(test)
owner_zero_resistance_solid_blocks_players_without_changing_destruction_attenuation :: proc(test:^t.T) {
 s:=new_scene(0);defer scene_destroy(&s)
 _=owner_rule_rectangle(&s,{1,-1},{1.2,3},.Indestructible,.Fixed,0)
 damage_cover:=cover_begin(&s,5);defer cover_destroy(&damage_cover)
 active_cover=&damage_cover;defer {active_cover=nil}
 t.expect(test,cover_distance({3,1},{0,1},0)==3&&len(damage_cover.cells)==0,"the original zero-resistance destruction query is unchanged")
 player_cover:=cover_begin(&s,5,true);defer cover_destroy(&player_cover)
 t.expect(test,!blast_capsule_visible(&player_cover,{3,1},Blast{{0,1},5}),"a physical solid still blocks player lethality")
}

@(test)
owner_detonation_uses_cover_before_damage_and_only_the_next_blast_can_reach_player :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w);w.elimination_playing=true
 b2.Body_SetTransform(w.players[0].body,{1.4,1},b2.MakeRot(0));_=world_remove_player(&w,1)
 wall:=owner_rule_rectangle(&w.scene,{.9,0},{1.1,3},.Destructible,.Fixed,.5)
 physics_sync_structure(&w.scene)
 events:Tick_Events;defer delete(events.explosions)
 world_explode(&w,{0,1},3,&events)
 t.expect(test,events.deaths[0]==.None,"the blast cannot retroactively kill through the wall it just destroyed")
 t.expect(test,!is_live_subdivision(&w.scene,wall),"fixture blast actually removes the shielding wall")
 world_explode(&w,{0,1},3,&events)
 t.expect(test,events.deaths[0]==.Blast,"a later explosion sees the now-open path")
}

@(test)
owner_cleanup_removes_dynamic_indestructible_cells_and_pieces_but_keeps_fixed_and_anchored_sources :: proc(test:^t.T) {
 w:World;w.scene=new_scene(.1);defer scene_destroy(&w.scene)
 w.scene.level_policy.active=true;w.scene.level_policy.fragment_cull={{-2,-2},{2,2}}
 dynamic_cell:=owner_rule_rectangle(&w.scene,{10,10},{11,11},.Indestructible,.Dynamic)
 damaged:=owner_rule_rectangle(&w.scene,{12,10},{13,11},.Destructible,.Dynamic)
 fixed:=owner_rule_rectangle(&w.scene,{14,10},{15,11},.Indestructible,.Fixed)
 anchored:=owner_rule_rectangle(&w.scene,{16,10},{17,11},.Destructible,.Anchored)
 dynamic_owner:=w.scene.subdivisions[w.scene.sub_rows[dynamic_cell]].owner
 t.expect(test,world_remove_out_of_bounds(&w))
 t.expect(test,!is_live_subdivision(&w.scene,dynamic_cell)&&!is_live_subdivision(&w.scene,damaged))
 owner_row,owner_exists:=w.scene.piece_rows[dynamic_owner]
 t.expect(test,!owner_exists||!w.scene.pieces[owner_row].live,"empty dynamic piece is removed as well as its cell")
 t.expect(test,w.scene.subdivisions[w.scene.sub_rows[fixed]].live&&w.scene.subdivisions[w.scene.sub_rows[anchored]].live)
}

owner_four_player_round :: proc(count:int=4) -> Round_Controller {
 r:=Round_Controller{mode=.Elimination};_=round_begin(&r)
 for i in 0..<count {_=round_connect(&r,i,u64(100+i),u64(i+1));round_ready(&r,i,u64(i+1),true)}
 round_prepare_tick(&r,1);round_prepare_tick(&r,181);return r
}
@(test)
owner_countdown_admits_existing_loading_players_but_fences_new_connections_and_generations :: proc(test:^t.T) {
 r:=Round_Controller{mode=.Elimination};_=round_begin(&r)
 for i in 0..<MAX_PLAYERS {_=round_connect(&r,i,u64(100+i),u64(i+1))}
 round_ready(&r,0,1,true);round_ready(&r,1,2,true);round_prepare_tick(&r,10)
 t.expect(test,r.state==.Countdown&&r.start_tick==190&&r.players[2].session_id==0)
 round_ready(&r,2,3,true);round_prepare_tick(&r,11)
 round_ready(&r,3,4,true);round_prepare_tick(&r,12)
 t.expect(test,r.players[2].session_id==102&&r.players[3].session_id==103&&r.start_tick==190)
 round_prepare_tick(&r,190)
 for p in r.players {t.expect(test,p.alive&&p.session_id!=0)}
 r=Round_Controller{mode=.Elimination};_=round_begin(&r)
 for i in 0..<3 {_=round_connect(&r,i,u64(100+i),u64(i+1))}
 round_ready(&r,0,1,true);round_ready(&r,1,2,true);round_prepare_tick(&r,10)
 round_disconnect(&r,2);_=round_connect(&r,2,102,99);round_ready(&r,2,99,true)
 _=round_connect(&r,3,103,4);round_ready(&r,3,4,true);round_prepare_tick(&r,11)
 t.expect(test,r.players[2].session_id==0&&r.players[3].session_id==0,"resumed generations and new connections after countdown stay spectators")
 round_disconnect(&r,1);round_prepare_tick(&r,12)
 t.expect(test,r.state==.Waiting&&r.start_tick==0,"a selected participant dropping still cancels countdown")
}
@(test)
owner_four_player_round_waits_for_last_survivor_and_awards_each_participant_once :: proc(test:^t.T) {
 r:=owner_four_player_round();t.expect(test,r.state==.Playing)
 for victim in 0..<3 {
  deaths:[MAX_PLAYERS]Round_Death;deaths[victim]=.Blast
  round_finish_tick(&r,u64(182+victim),deaths,1)
  t.expect(test,r.state==(victim<2?Round_State.Playing:Round_State.Finished))
 }
 t.expect(test,r.winner==103&&!r.draw&&r.sessions[3].wins==1)
 before:=r.sessions;round_award(&r);t.expect(test,r.sessions==before,"all four awards are idempotent")
 for p in r.players {t.expect(test,p.session_id!=0&&round_find_session(&r,p.session_id).awarded_round==r.id)}
}
@(test)
owner_two_three_four_player_rounds_draw_when_the_last_survivors_die_together :: proc(test:^t.T) {
 for count in 2..=4 {
  r:=owner_four_player_round(count);t.expect(test,r.state==.Playing)
  deaths:[MAX_PLAYERS]Round_Death
  for i in 0..<count {deaths[i]=.Blast}
  round_finish_tick(&r,182,deaths,2)
  t.expect(test,r.state==.Finished&&r.draw&&r.winner==0)
 }
}
@(test)
owner_four_player_round_wire_keeps_all_participants_and_configured_blast_radius :: proc(test:^t.T) {
 r:=Round_Snapshot{rules_version=ROUND_RULES_VERSION,mode=.Elimination,state=.Playing,lethal_radius=5}
 for i in 0..<MAX_PLAYERS {r.players[i]={session_id=u64(100+i),generation=u64(i+1),slot=i,alive=true}}
 writer:nc.Writer;nc.writer_init(&writer);defer nc.writer_destroy(&writer);round_encode(&writer,r)
 decoded,ok:=round_decode(writer.data[:]);t.expect(test,ok&&decoded.players==r.players&&decoded.lethal_radius==5)
}
@(test)
owner_elimination_bomb_pacing_is_tick_based_bounded_seeded_and_resets :: proc(test:^t.T) {
 config:=DEFAULT_GAMEPLAY_CONFIG
 t.expect(test,elimination_bomb_interval(config,0)==Vec2{1,2.5})
 middle:=elimination_bomb_interval(config,2700)
 t.expect(test,math.abs(middle.x-.7)<1e-6&&math.abs(middle.y-1.75)<1e-6)
 t.expect(test,elimination_bomb_interval(config,5400)==Vec2{.4,1}&&elimination_bomb_interval(config,999999)==Vec2{.4,1})
 a,b:Bomb_Rain;bomb_rain_reset(&a,42,config,true);bomb_rain_reset(&b,42,config,true)
 first:=a.until_drop;t.expect(test,first==b.until_drop)
 for tick in u64(0)..<1000 {
  aa:=bomb_drop_delay_round(&a,config,true,tick*7);bb:=bomb_drop_delay_round(&b,config,true,tick*7);interval:=elimination_bomb_interval(config,tick*7)
  t.expect(test,aa==bb&&aa>=interval.x&&aa<=interval.y)
 }
 bomb_rain_reset(&a,42,config,true);t.expect(test,a.until_drop==first,"new round starts with the same seed and start interval")
 bomb_rain_reset(&a,42,config);bomb_rain_reset(&b,42,config)
 for i in 0..<64 {t.expect(test,bomb_drop_delay_round(&a,config,false,u64(i)*10000)==bomb_drop_delay_config(&b,config),"Sandbox retains the fixed range and independent random sequence")}
}
@(test)
owner_config_migrates_old_tuning_and_fingerprints_pacing_and_radius :: proc(test:^t.T) {
 legacy:=DEFAULT_GAMEPLAY_CONFIG;legacy.version=1;legacy.player.speed=7;legacy.bomb_drop_min=1.2
 upgraded:=gameplay_config_upgrade(legacy);t.expect(test,upgraded.version==4&&upgraded.player.speed==7&&upgraded.player.gravity_scale==1&&upgraded.bomb_drop_min==1.2&&gameplay_config_valid(upgraded))
 original:=gameplay_config_hash(upgraded);upgraded.bomb_radius=4;t.expect(test,gameplay_config_hash(upgraded)!=original)
 upgraded=gameplay_config_upgrade(legacy);upgraded.elimination_ramp_seconds=60;t.expect(test,gameplay_config_hash(upgraded)!=original)
 upgraded=gameplay_config_upgrade(legacy);upgraded.elimination_end_interval.x=.5;t.expect(test,gameplay_config_hash(upgraded)!=original)
 upgraded.elimination_start_interval.x=0;t.expect(test,!gameplay_config_valid(upgraded))
}
