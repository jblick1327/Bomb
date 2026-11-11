package ffi
import t "core:testing"
import core "../shared"
import nc "../netcode"

@(test)
graze_abi_exposes_decoded_counts_in_copied_sample_roster_and_preserves_stride :: proc(test:^t.T) {
 snapshot:=core.Round_Snapshot{rules_version=core.ROUND_RULES_VERSION,mode=.Elimination,state=.Playing,lethal_radius=1.2}
 for i in 0..<core.MAX_PLAYERS {snapshot.players[i]={session_id=u64(i+1),generation=1,slot=i,alive=i<3,graze_count=u32(i)}}
 writer:nc.Writer;nc.writer_init(&writer);defer nc.writer_destroy(&writer);core.round_encode(&writer,snapshot)
 decoded,ok:=core.round_decode(writer.data[:]);t.expect(test,ok)
 create:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&create,&handle)==OK);defer bom_client_destroy(handle)
 slot,_:=get_slot(handle);slot.client.has_round=true;slot.client.round_snapshot=decoded
 sample:=BomSample{struct_size=u32(size_of(BomSample)),version=1}
 t.expect(test,bom_client_acquire_sample(handle,&sample)==OK)
 info:=BomRoundInfo{struct_size=u32(size_of(BomRoundInfo)),version=1}
 t.expect(test,bom_client_get_round(handle,sample.sample_sequence,&info)==OK&&info.player_count==4&&info.rules_version==3)
 for i in 0..<4 {t.expect(test,info.players[i].graze_count==u32(i)&&info.players[i].alive==(i<3?u32(1):0))}
 slot.client.round_snapshot.players[1].graze_count=99
 t.expect(test,info.players[1].graze_count==1,"borrowed ABI roster is copied native snapshot state")
 t.expect(test,BOM_ABI_MINOR==5&&size_of(BomRoundPlayer)==64&&offset_of(BomRoundPlayer,graze_count)==28)
 t.expect(test,bom_client_release_sample(handle,sample.sample_sequence)==OK)
 t.expect(test,bom_client_get_round(handle,sample.sample_sequence,&info)==BAD_ARGUMENT)
}
