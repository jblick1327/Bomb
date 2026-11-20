package shared
import t "core:testing"
import b2 "vendor:box2d"
import math "core:math"
import slice "core:slice"
import nc "../netcode"

ITEM_TEST_DT :: f32(1.0/60.0)

item_test_world :: proc(players:int=1) -> World {
 w:=round_test_world();w.elimination_playing=true
 for i in players..<MAX_PLAYERS {_=world_remove_player(&w,i)}
 return w
}

@(test)
item_schedule_is_seeded_deterministic_and_uses_darryn_intervals :: proc(test:^t.T) {
 a:=item_test_world(0);defer round_test_world_destroy(&a)
 b:=item_test_world(0);defer round_test_world_destroy(&b)
 t.expect(test,a.items.until_spawn>=180&&a.items.until_spawn<=480,"first item 3..8 s after the round starts")
 spawns:[dynamic]u64;defer delete(spawns)
 for tick in u64(1)..=3600 {
  last:=a.items.next_id
  ea:=world_tick(&a,{},ITEM_TEST_DT);delete(ea.explosions)
  eb:=world_tick(&b,{},ITEM_TEST_DT);delete(eb.explosions)
  t.expect(test,a.items==b.items,"same seed, same items, bit for bit")
  t.expect(test,a.items.count<=2,"lifetime 15 s and interval >=12 s keep at most two items")
  if a.items.next_id!=last {
   append(&spawns,tick);item:=a.items.items[a.items.count-1]
   t.expect(test,item.id==a.items.next_id&&item.kind!=.None&&item.position.x>=-7&&item.position.x<=8)
  }
 }
 t.expect(test,len(spawns)>=3,"a minute of play spawns several items")
 t.expect(test,spawns[0]>=180&&spawns[0]<=480)
 for i in 1..<len(spawns) {gap:=spawns[i]-spawns[i-1];t.expect(test,gap>=720&&gap<=1200,"12..20 s between items")}
 c:=round_test_world();defer round_test_world_destroy(&c);c.settings.seed=43;item_rain_reset(&c.items,c.settings.seed)
 d:=round_test_world();defer round_test_world_destroy(&d);item_rain_reset(&d.items,42)
 t.expect(test,c.items.random!=d.items.random,"the stream is seeded by the world seed")
 // Items only advance while an Elimination round is playing.
 e:=item_test_world(0);defer round_test_world_destroy(&e);e.elimination_playing=false;before:=e.items
 for _ in 0..<600 {ev:=world_tick(&e,{},ITEM_TEST_DT);delete(ev.explosions)}
 t.expect(test,e.items==before)
}

@(test)
item_kinds_follow_darryn_chances :: proc(test:^t.T) {
 rain:Item_Rain;item_rain_reset(&rain,7)
 counts:[Item_Kind]int;n:=40000
 for _ in 0..<n {counts[item_pick_kind(&rain)]+=1}
 expected:=[Item_Kind]f64{.None=0,.Silver_Coin=.25,.Gold_Coin=.15,.Invincibility=.2,.Slow=.2,.Speed_Boost=.2}
 for kind in Item_Kind {t.expect(test,math.abs(f64(counts[kind])/f64(n)-expected[kind])<.01)}
}

@(test)
item_falls_lands_resumes_after_a_detonation_and_expires_after_fifteen_seconds :: proc(test:^t.T) {
 w:=item_test_world(0);defer round_test_world_destroy(&w)
 w.items.until_spawn=1
 ev:=world_tick(&w,{},ITEM_TEST_DT);delete(ev.explosions)
 t.expect(test,w.items.count==1&&!w.items.items[0].landed&&w.items.items[0].ticks_left==ITEM_TUNING.lifetime_ticks-1)
 w.items.until_spawn=100000
 spawn_y:=BOMB_SKY_HEIGHT;t.expect(test,w.items.items[0].position.y<spawn_y,"falls from the bomb spawn height")
 ticks:=1
 for !w.items.items[0].landed && ticks<300 {ev=world_tick(&w,{},ITEM_TEST_DT);delete(ev.explosions);ticks+=1}
 item:=w.items.items[0];t.expect(test,item.landed&&item.position.y>-3&&item.position.y<1,"lands on the ground")
 for _ in 0..<30 {ev=world_tick(&w,{},ITEM_TEST_DT);delete(ev.explosions)}
 t.expect(test,w.items.items[0].position==item.position&&w.items.items[0].landed,"a landed item stays put")
 // A detonation resumes the fall in the same tick, exactly like Darryn's ResumeFalling.
 world_bomb_spawn(&w,{item.position.x>0?item.position.x-3:item.position.x+3,1})
 exploded:=false
 for _ in 0..<600 {
  ev=world_tick(&w,{},ITEM_TEST_DT);count:=len(ev.explosions);delete(ev.explosions)
  if count>0 {exploded=true;break}
 }
 t.expect(test,exploded&&w.items.count==1&&!w.items.items[0].landed)
 for w.items.count>0 && ticks<2000 {ev=world_tick(&w,{},ITEM_TEST_DT);delete(ev.explosions);ticks+=1}
 // Lifetime counts world ticks since spawn, whether falling or landed.
 t.expect(test,w.items.count==0)
 w2:=item_test_world(0);defer round_test_world_destroy(&w2);w2.items.until_spawn=1
 present:=0
 for _ in 0..<1000 {ev=world_tick(&w2,{},ITEM_TEST_DT);delete(ev.explosions);w2.items.until_spawn=max(w2.items.until_spawn,2);if w2.items.count>0 {present+=1}}
 t.expect(test,present==int(ITEM_TUNING.lifetime_ticks),"present for exactly 15 s")
}

item_place :: proc(w:^World,kind:Item_Kind,position:Vec2) {
 w.items.next_id+=1;w.items.items[w.items.count]=Item{id=w.items.next_id,kind=kind,position=position,landed=true,ticks_left=900};w.items.count+=1
}

@(test)
item_pickup_is_capsule_overlap_coins_add_and_invincibility_blocks_lethal_and_graze_for_ten_seconds :: proc(test:^t.T) {
 w:=item_test_world(1);defer round_test_world_destroy(&w)
 w.items.until_spawn=100000
 b2.Body_SetTransform(w.players[0].body,{2,1},b2.MakeRot(0));b2.Body_SetLinearVelocity(w.players[0].body,{})
 events:Tick_Events
 item_place(&w,.Silver_Coin,{2.62,1});item_rain_step(&w,ITEM_TEST_DT,&events)
 t.expect(test,w.items.count==1&&w.players[0].coins==0,"0.62 from the capsule axis: no overlap (reach 0.61)")
 w.items.items[0].position={2.6,1};item_rain_step(&w,ITEM_TEST_DT,&events)
 t.expect(test,w.items.count==0&&w.players[0].coins==10,"silver coin +10 on overlap")
 item_place(&w,.Gold_Coin,{2,1.8});item_rain_step(&w,ITEM_TEST_DT,&events)
 t.expect(test,w.items.count==0&&w.players[0].coins==60,"gold coin +50; 0.5 above the capsule segment top")
 // Lower player index wins a tie on the same tick.
 w2:=item_test_world(2);defer round_test_world_destroy(&w2);w2.items.until_spawn=100000
 for i in 0..<2 {b2.Body_SetTransform(w2.players[i].body,{2,1},b2.MakeRot(0))}
 item_place(&w2,.Gold_Coin,{2,1});item_rain_step(&w2,ITEM_TEST_DT,&events)
 t.expect(test,w2.players[0].coins==50&&w2.players[1].coins==0)
 events.deaths[0]=.Blast;item_place(&w2,.Gold_Coin,{2,1});item_rain_step(&w2,ITEM_TEST_DT,&events)
 t.expect(test,w2.players[0].coins==50&&w2.players[1].coins==50,"a player already dead this tick collects nothing")
 events.deaths={}
 item_place(&w,.Invincibility,{2,1});item_rain_step(&w,ITEM_TEST_DT,&events)
 t.expect(test,w.players[0].invincible_ticks==600&&w.players[0].speed_effect==.None)
 defer delete(events.explosions)
 // Ten seconds of protection from both damage zones, counted in world ticks.
 for tick in 1..=601 {
  center:=from_b2(b2.Body_GetPosition(w.players[0].body))
  protected:=tick<=600
  world_explode(&w,{center.x-2.26,center.y},5,&events)
  t.expect(test,w.players[0].graze_count==(protected?u32(0):1)&&events.deaths[0]==.None)
  if !protected {world_explode(&w,center,5,&events);t.expect(test,events.deaths[0]==.Blast,"lethal again once the effect ends")}
  ev:=world_tick(&w,{},ITEM_TEST_DT);delete(ev.explosions)
  if tick==600 {t.expect(test,w.players[0].invincible_ticks==0)}
 }
}

@(test)
item_speed_effects_scale_only_the_movement_target_replace_each_other_and_expire :: proc(test:^t.T) {
 w:=item_test_world(1);defer round_test_world_destroy(&w);p:=&w.players[0]
 item_apply(p,.Speed_Boost);t.expect(test,p.speed_effect==.Boost&&p.speed_ticks==600&&player_speed_scale(p)==1.5)
 b2.Body_SetLinearVelocity(p.body,{10,0});player_movement_from_support(p,1,false,ITEM_TEST_DT)
 t.expect(test,from_b2(b2.Body_GetLinearVelocity(p.body)).x==10.5,"boost target 7 x 1.5")
 item_apply(p,.Invincibility);t.expect(test,p.speed_effect==.Boost&&p.speed_ticks==599&&p.invincible_ticks==600,"effects coexist")
 item_apply(p,.Slow);t.expect(test,p.speed_effect==.Slow&&p.speed_ticks==600,"a new speed item replaces the old one and restarts 10 s")
 b2.Body_SetLinearVelocity(p.body,{3,0});player_movement_from_support(p,1,false,ITEM_TEST_DT)
 t.expect(test,from_b2(b2.Body_GetLinearVelocity(p.body)).x==3.5,"slow target 7 x 0.5")
 p.grounded=true;p.coyote=.1;player_movement_from_support(p,0,true,ITEM_TEST_DT)
 t.expect(test,from_b2(b2.Body_GetLinearVelocity(p.body)).y==PLAYER_TUNING.jump_speed,"jump is unchanged")
 for _ in 0..<597 {player_movement_from_support(p,1,false,ITEM_TEST_DT)}
 t.expect(test,p.speed_ticks==1&&p.speed_effect==.Slow)
 player_movement_from_support(p,1,false,ITEM_TEST_DT);t.expect(test,p.speed_ticks==0&&p.speed_effect==.None&&player_speed_scale(p)==1)
 b2.Body_SetLinearVelocity(p.body,{10,0});player_movement_from_support(p,1,false,ITEM_TEST_DT)
 t.expect(test,from_b2(b2.Body_GetLinearVelocity(p.body)).x==10-PLAYER_TUNING.acceleration*ITEM_TEST_DT,"normal target again")
}

@(test)
item_speed_effect_prediction_replays_the_server_kernel_including_expiry :: proc(test:^t.T) {
 source:=test_prediction_static_scene();defer scene_destroy(&source)
 predicted:Static_Prediction;defer prediction_static_destroy(&predicted)
 t.expect(test,prediction_static_build(&predicted,&source))
 def:=b2.DefaultWorldDef();def.gravity={0,-9.8};world:=b2.CreateWorld(def);defer b2.DestroyWorld(world)
 bd:=b2.DefaultBodyDef();bd.position={.5,-1.5};ground:=b2.CreateBody(world,bd)
 _=b2.CreatePolygonShape(ground,physics_shape_def(200),b2.MakeBox(8.5,1.5))
 player:=player_create(world)
 player.speed_effect=.Boost;player.speed_ticks=80 // picked up before tick 1; expires mid-run
 id:=Input_Identity{9007199254740999,1,9007199254741001}
 history:Command_History;command_history_begin(&history,{id,1,9007199254742001})
 schedule:=Input_Schedule{identity=id,synchronized=true}
 owners:[256]Owner_State
 future:[256]Vec2;future_valid:[256]bool
 max_error:f32;compared:=0;fastest:f32
 for tick in u64(1)..=240 {
  for history.next_tick<=tick+3 {
   target:=history.next_tick;move:=target%80<40?i8(127):i8(-127)
   edge:=target==30 || target==150?target:u64(0)
   _,ok:=command_history_push(&history,move,edge);t.expect(test,ok)
  }
  command:=history.slots[tick%INPUT_HISTORY].command
  player_before_step(&player,move_dequantize(command.move),command.jump_edge!=0,f32(NET_STEP_DT))
  b2.World_Step(world,f32(NET_STEP_DT),PHYSICS_SUBSTEPS);player_after_movement_step(&player)
  fastest=max(fastest,math.abs(from_b2(b2.Body_GetLinearVelocity(player.body)).x))
  schedule.finalized_through=tick;schedule.last_applied_sequence=command.sequence
  if command.jump_edge!=0 { schedule.last_jump_edge=command.jump_edge }
  owners[tick%256]=owner_state_capture(&player,&schedule,tick,1)
  t.expect(test,owners[tick%256].speed_ticks==(tick<80?u32(80-tick):0))
  if future_valid[tick%256] { max_error=max(max_error,vlen(vsub(future[tick%256],player.pose.position)));compared+=1 }
  if tick>6 {
   owner:=owners[(tick-6)%256]
   t.expect(test,prediction_static_replay(&predicted,owner,&history))
   t.expect(test,predicted.state_tick==tick+3 && predicted.reason==.None)
   future[predicted.state_tick%256]=predicted.player.pose.position;future_valid[predicted.state_tick%256]=true
   t.expect(test,command_history_finalize(&history,id,owner.finalized_through))
  }
 }
 t.expect(test,fastest>10.4,"the boost was actually exercised")
 t.expect(test,compared>200 && max_error<.03,"prediction replays boost and expiry from the owner state")
}

@(test)
item_round_server_publishes_coins_and_effects_awards_coins_and_clears_effects_on_death :: proc(test:^t.T) {
 ns:=graze_test_server();defer net_server_destroy(&ns)
 body:=&ns.game.world.players[0]
 item_apply(body,.Gold_Coin);item_apply(body,.Invincibility);item_apply(body,.Speed_Boost)
 ns.round_dirty=false;round_server_finish(&ns,{})
 end:=ns.tick+1+600
 p:=round_snapshot(&ns).players[0]
 t.expect(test,ns.round_dirty&&p.coins==50&&p.effects==ROUND_EFFECT_INVINCIBLE|ROUND_EFFECT_SPEED_BOOST&&p.invincible_end_tick==end&&p.speed_end_tick==end)
 // One simulated tick later the remaining counts fall but the end ticks hold: no resend.
 body.invincible_ticks-=1;body.speed_ticks-=1;ns.tick+=1;ns.round_dirty=false;round_server_finish(&ns,{})
 t.expect(test,!ns.round_dirty&&round_snapshot(&ns).players[0].invincible_end_tick==end)
 body.invincible_ticks=0;body.speed_ticks-=1;ns.tick+=1;round_server_finish(&ns,{})
 p=round_snapshot(&ns).players[0]
 t.expect(test,ns.round_dirty&&p.effects==ROUND_EFFECT_SPEED_BOOST&&p.invincible_end_tick==0&&p.speed_end_tick==end)
 item_apply(body,.Slow);ns.tick+=1;round_server_finish(&ns,{})
 p=round_snapshot(&ns).players[0];t.expect(test,p.effects==ROUND_EFFECT_SLOW&&p.speed_end_tick==ns.tick+1+600)
 item_apply(&ns.game.world.players[1],.Speed_Boost);item_apply(&ns.game.world.players[1],.Silver_Coin)
 events:Tick_Events;events.deaths[0]=.Blast;ns.tick+=1;round_server_finish(&ns,events)
 t.expect(test,ns.rounds.state==.Finished&&ns.rounds.winner==2)
 final:=round_snapshot(&ns);for q in final.players[:2] {t.expect(test,q.effects==0&&q.invincible_end_tick==0&&q.speed_end_tick==0,"no effects once dead or after the round")}
 dead:=ns.rounds.players[0];winner:=ns.rounds.players[1]
 t.expect(test,dead.coins==50&&dead.xp_gained==50+dead.bombs_faced*10+dead.alive_ticks/60,"coins join the round award")
 t.expect(test,winner.coins==10&&winner.xp_gained==10+winner.bombs_faced*10+winner.alive_ticks/60)
 s:=round_find_session(&ns.rounds,dead.session_id);t.expect(test,s!=nil&&s.total_xp==dead.xp_gained)
 old_id:=ns.rounds.id;restart:=[2]u8{NET_APP_HOST_COMMAND,NET_HOST_RESET}
 t.expect(test,net_host_apply_command(&ns,0,restart[:])==""&&ns.rounds.id==old_id+1)
 for q in round_snapshot(&ns).players {t.expect(test,q.coins==0&&q.effects==0)}
 for q in ns.game.world.players {t.expect(test,q.coins==0&&q.invincible_ticks==0&&q.speed_ticks==0)}
 t.expect(test,ns.game.world.items.count==0)
}

@(test)
item_round_wire_format_4_appends_graze_zone_and_item_state :: proc(test:^t.T) {
 snapshot:=Round_Snapshot{rules_version=ROUND_RULES_VERSION,mode=.Elimination,state=.Playing,epoch=9,id=9007199254741001,lethal_radius=1.2,graze_radius=2.2,grazes_to_die=3}
 effects:=[4]u8{0,ROUND_EFFECT_INVINCIBLE,ROUND_EFFECT_SPEED_BOOST,ROUND_EFFECT_INVINCIBLE|ROUND_EFFECT_SLOW}
 for i in 0..<MAX_PLAYERS {
  p:=&snapshot.players[i];p^={session_id=u64(i+1),generation=u64(i+7),slot=i,alive=true,graze_count=u32(i),coins=u32(10*i+1),effects=effects[i]}
  if effects[i]&ROUND_EFFECT_INVINCIBLE!=0 {p.invincible_end_tick=9007199254741000+u64(i)}
  if effects[i]&(ROUND_EFFECT_SPEED_BOOST|ROUND_EFFECT_SLOW)!=0 {p.speed_end_tick=9007199254742000+u64(i)}
 }
 writer:nc.Writer;nc.writer_init(&writer);defer nc.writer_destroy(&writer);round_encode(&writer,snapshot)
 t.expect(test,GAME_PROTOCOL_VERSION==9&&ROUND_RULES_VERSION==4&&len(writer.data)==533+8+MAX_PLAYERS*21)
 for i in 0..<MAX_PLAYERS {offset:=73+i*55+19;t.expect(test,writer.data[offset]==u8(i),"format-3 offsets are unchanged")}
 t.expect(test,transmute(f32)(u32(writer.data[533])|u32(writer.data[534])<<8|u32(writer.data[535])<<16|u32(writer.data[536])<<24)==2.2&&writer.data[537]==3)
 for i in 0..<MAX_PLAYERS {offset:=541+i*21;t.expect(test,writer.data[offset]==u8(10*i+1)&&writer.data[offset+4]==effects[i])}
 copy,ok:=round_decode(writer.data[:]);t.expect(test,ok&&copy==snapshot)
 second:nc.Writer;nc.writer_init(&second);defer nc.writer_destroy(&second);round_encode(&second,copy)
 t.expect(test,slice.equal(writer.data[:],second.data[:]))
 for length in 0..<len(writer.data) {_,valid:=round_decode(writer.data[:length]);t.expect(test,!valid)}
 bad:=[?]u8{ROUND_EFFECT_SPEED_BOOST|ROUND_EFFECT_SLOW,8,ROUND_EFFECT_INVINCIBLE|ROUND_EFFECT_SPEED_BOOST,0}
 for value in bad {
  // Player 1 has only an invincible end tick: each value breaks one invariant.
  data:=slice.clone(writer.data[:]);defer delete(data);data[541+21+4]=value
  _,valid:=round_decode(data);t.expect(test,!valid)
 }
 data:=slice.clone(writer.data[:]);defer delete(data);data[5]=3;_,old:=round_decode(data);t.expect(test,!old,"format 3 is rejected")
}

@(test)
item_owner_wire_carries_the_speed_effect_and_rejects_inconsistent_state :: proc(test:^t.T) {
 o:=Owner_State{identity={9007199254740999,7,4294967301},state_tick=9007199254742001,topology_revision=3,finalized_through=9007199254742001,
  position={1,2},teleport_serial=1,speed_effect=.Slow,speed_ticks=321}
 w:nc.Writer;nc.writer_init(&w,256);defer nc.writer_destroy(&w);owner_state_encode(&w,o)
 decoded,ok:=owner_state_decode(w.data[:]);t.expect(test,ok&&decoded==o)
 for size in 0..<len(w.data) {_,valid:=owner_state_decode(w.data[:size]);t.expect(test,!valid)}
 w.data[len(w.data)-5]=3;_,ok=owner_state_decode(w.data[:]);t.expect(test,!ok,"unknown speed effect")
 for bad in ([3]Owner_State{{speed_effect=.None,speed_ticks=1},{speed_effect=.Boost,speed_ticks=0},{speed_effect=.Boost,speed_ticks=601}}) {
  x:=o;x.speed_effect=bad.speed_effect;x.speed_ticks=bad.speed_ticks;t.expect(test,!owner_state_valid(x))
 }
 // Restoring for prediction carries the effect into the shared kernel.
 def:=b2.DefaultWorldDef();world:=b2.CreateWorld(def);defer b2.DestroyWorld(world)
 player:=player_create(world);t.expect(test,owner_state_restore(world,&player,o)&&player.speed_effect==.Slow&&player.speed_ticks==321)
}

@(test)
item_frame_entries_carry_kind_and_leave_bomb_keys_unchanged :: proc(test:^t.T) {
 t.expect(test,ent_key(.Bomb,5)==(u64(3)<<62|5)&&key_kind(ent_key(.Bomb,5))==.Bomb&&key_id(ent_key(.Bomb,5))==5)
 key:=ent_key(.Item,5);t.expect(test,key!=ent_key(.Bomb,5)&&key_kind(key)==.Item&&key_id(key)==5&&key>ent_key(.Bomb,1<<40))
 bomb:=Pose_State{x=10,y=20,a=30,landed=true,fuse=99}
 item:=Pose_State{x=-100,y=400,landed=true,item=u8(Item_Kind.Gold_Coin)}
 entries:=[?]Frame_Entry{{ent_key(.Player,1),{x=1,y=2}},{ent_key(.Bomb,3),bomb},{key,item},{ent_key(.Item,9),{x=5,y=6,item=u8(Item_Kind.Speed_Boost)}}}
 parts:[dynamic][]u8;defer {for p in parts {delete(p)};delete(parts)}
 frame_encode(1,10,false,0,0,nil,entries[:],{},&parts);t.expect(test,len(parts)==1)
 part,ok:=frame_decode_part(parts[0],nil);defer frame_part_destroy(&part)
 t.expect(test,ok&&slice.equal(part.entries[:],entries[:]),"absolute rows round trip")
 base:=make(Pose_Table);defer delete(base);for e in entries {base[e.key]=e.state}
 moved:=entries;moved[2].state.y=300;moved[2].state.landed=false
 delta:[dynamic][]u8;defer {for p in delta {delete(p)};delete(delta)}
 frame_encode(1,11,true,10,0,&base,moved[2:3],{},&delta)
 next,good:=frame_decode_part(delta[0],&base);defer frame_part_destroy(&next)
 t.expect(test,good&&len(next.entries)==1&&next.entries[0]==moved[2],"delta rows round trip")
 corrupt:=slice.clone(parts[0]);defer delete(corrupt);corrupt[len(corrupt)-1]=0
 bad,valid:=frame_decode_part(corrupt,nil);t.expect(test,!valid);frame_part_destroy(&bad)
 corrupt[len(corrupt)-1]=u8(max(Item_Kind))+1
 bad2,valid2:=frame_decode_part(corrupt,nil);t.expect(test,!valid2);frame_part_destroy(&bad2)
}
