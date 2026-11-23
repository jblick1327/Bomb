package ffi
import t "core:testing"
import core "../shared"
import nc "../netcode"

@(test)
items_abi_exposes_graze_zone_item_state_and_item_actors_from_copied_native_state :: proc(test:^t.T) {
 snapshot:=core.Round_Snapshot{rules_version=core.ROUND_RULES_VERSION,mode=.Elimination,state=.Playing,lethal_radius=1.2,graze_radius=2.2,grazes_to_die=3}
 for i in 0..<core.MAX_PLAYERS {snapshot.players[i]={session_id=u64(i+1),generation=1,slot=i,alive=true,coins=u32(10*i)}}
 snapshot.players[1].effects=core.ROUND_EFFECT_INVINCIBLE|core.ROUND_EFFECT_SLOW;snapshot.players[1].invincible_end_tick=700;snapshot.players[1].speed_end_tick=650
 writer:nc.Writer;nc.writer_init(&writer);defer nc.writer_destroy(&writer);core.round_encode(&writer,snapshot)
 decoded,ok:=core.round_decode(writer.data[:]);t.expect(test,ok)
 create:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&create,&handle)==OK);defer bom_client_destroy(handle)
 slot,_:=get_slot(handle);slot.client.has_round=true;slot.client.round_snapshot=decoded
 { // the copied client state belongs to the handle's allocator
  context=slot.ctx
  slot.client.drawn[core.ent_key(.Item,7)]=core.Net_Drawn{x=1,y=2,landed=true,item=u8(core.Item_Kind.Gold_Coin)}
  slot.client.drawn[core.ent_key(.Bomb,7)]=core.Net_Drawn{x=3,y=4,fuse=1}
 }
 sample:=BomSample{struct_size=u32(size_of(BomSample)),version=1}
 t.expect(test,bom_client_acquire_sample(handle,&sample)==OK)
 info:=BomRoundInfo{struct_size=u32(size_of(BomRoundInfo)),version=1}
 t.expect(test,bom_client_get_round(handle,sample.sample_sequence,&info)==OK&&info.rules_version==4)
 t.expect(test,info.lethal_radius==1.2&&info.graze_radius==2.2&&info.grazes_to_die==3,"Unity can draw both rings from native state")
 for i in 0..<4 {t.expect(test,info.players[i].coins==u32(10*i))}
 p:=info.players[1]
 t.expect(test,p.effects==u32(core.ROUND_EFFECT_INVINCIBLE|core.ROUND_EFFECT_SLOW)&&p.invincible_end_tick==700&&p.speed_end_tick==650)
 found_item,found_bomb:=false,false
 for pose in sample.poses[:sample.pose_count] {
  if pose.kind==u32(core.Ent_Kind.Item) {found_item=pose.id==7&&pose.flags==1|u32(core.Item_Kind.Gold_Coin)<<8&&pose.x==1&&pose.y==2}
  if pose.kind==u32(core.Ent_Kind.Bomb) {found_bomb=pose.id==7&&pose.flags==0}
 }
 t.expect(test,found_item&&found_bomb,"items are kind 4 actors; flags bit 0 landed, bits 8..15 item kind")
 shape:=BomActorShapeInfo{struct_size=u32(size_of(BomActorShapeInfo)),version=1}
 t.expect(test,bom_actor_shape_info(&shape)==OK&&shape.item_radius==core.ITEM_RADIUS&&shape.bomb_radius==core.BOMB_RADIUS)
 t.expect(test,BOM_ABI_MINOR==7&&size_of(BomRoundPlayer)==88&&offset_of(BomRoundPlayer,graze_count)==28&&offset_of(BomRoundPlayer,coins)==64)
 t.expect(test,offset_of(BomRoundInfo,connections)+8==offset_of(BomRoundInfo,graze_radius),"graze_radius is appended; existing offsets are unchanged")
 t.expect(test,bom_client_release_sample(handle,sample.sample_sequence)==OK)
}
