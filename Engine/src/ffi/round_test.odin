package ffi
import t "core:testing"
import core "../shared"

@(test)
round_abi_requires_sample_lease_and_exposes_only_copied_bounded_rosters :: proc(test:^t.T) {
 create:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&create,&handle)==OK);defer bom_client_destroy(handle)
 t.expect(test,bom_client_set_join_options(handle,1)==OK && bom_client_set_join_options(handle,2)==BAD_ARGUMENT)
 slot,_:=get_slot(handle);slot.client.has_round=true
 slot.client.round_snapshot=core.Round_Snapshot{mode=.Elimination,id=9007199254741001,epoch=4,lethal_radius=5}
 for i in 0..<core.MAX_PLAYERS {slot.client.round_snapshot.players[i]={session_id=9007199254741009+u64(i),slot=i,alive=true}}
 info:=BomRoundInfo{struct_size=u32(size_of(BomRoundInfo)),version=1}
 t.expect(test,bom_client_get_round(handle,0,&info)==BAD_ARGUMENT)
 sample:=BomSample{struct_size=u32(size_of(BomSample)),version=1}
 t.expect(test,bom_client_acquire_sample(handle,&sample)==OK)
 t.expect(test,bom_client_set_join_options(handle,0)==BUSY)
 t.expect(test,bom_client_get_round(handle,sample.sample_sequence+1,&info)==BAD_ARGUMENT)
 t.expect(test,bom_client_get_round(handle,sample.sample_sequence,&info)==OK && info.round_id==9007199254741001 && info.player_count==4 && info.connection_count==4)
 t.expect(test,info.players[0].session_id==9007199254741009 && info.players[0].alive==1)
 t.expect(test,info.players[3].session_id==9007199254741012&&info.players[3].slot==3)
 t.expect(test,bom_client_release_sample(handle,sample.sample_sequence)==OK)
 t.expect(test,bom_client_get_round(handle,sample.sample_sequence,&info)==BAD_ARGUMENT)
}
