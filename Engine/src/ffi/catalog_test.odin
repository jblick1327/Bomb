package ffi
import t "core:testing"
import core "../shared"

@(test)
catalog_binding_view_is_sample_coherent_and_keeps_u64_ids_and_matrix_order :: proc(test:^t.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64;t.expect(test,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);t.expect(test,status==OK);context=s.ctx
 core.net_client_init(&s.client,1234,0);s.live=true;defer t.expect(test,bom_client_destroy(handle)==OK)
 layout,_,ok,reason:=core.decode_layout(transmute([]u8)#load("../presets/unity-policy-v4.json"));t.expect(test,ok,reason);if !ok {return};defer core.destroy_layout(&layout)
 w:=core.World{settings=core.DEFAULT_SANDBOX_SETTINGS};core.world_rebuild_layout(&w,&layout,false)
 core.scene_destroy(&s.client.rep.scene);s.client.rep.scene=w.scene;w.scene={};delete(w.bombs)
 s.client.rep.has_baseline=true;s.client.has_epoch=true;s.client.epoch=1;s.journal_epoch=1
 catalog:=BomCatalogInfo{struct_size=u32(size_of(BomCatalogInfo)),version=1}
 t.expect(test,bom_client_acquire_catalog(handle,1,&catalog)==BAD_ARGUMENT,"catalog pointers require an acquired sample")
 sample:=BomSample{struct_size=u32(size_of(BomSample)),version=1};t.expect(test,bom_client_acquire_sample(handle,&sample)==OK)
 t.expect(test,bom_client_acquire_catalog(handle,sample.sample_sequence+1,&catalog)==BAD_ARGUMENT)
 t.expect(test,bom_client_acquire_catalog(handle,sample.sample_sequence,&catalog)==OK)
 t.expect(test,catalog.epoch==sample.epoch&&catalog.flags==1&&catalog.source_count==1&&catalog.binding_count==sample.cell_count)
 source:=catalog.sources[0];t.expect(test,source.source_identity==9007199254741001&&string(source.asset_key[:source.asset_key_length])=="fixture")
 t.expect(test,source.m00== -2&&source.m11==3&&source.m22==.4&&source.m03==7&&source.m13== -2&&source.m23==4&&source.m33==1)
 t.expect(test,catalog.level.spawn0_x== -4&&catalog.level.spawn1_x==4&&catalog.level.flags==1&&catalog.level.move_speed==4)
 for binding in catalog.bindings[:catalog.binding_count] {t.expect(test,binding.source_identity==9007199254741001&&binding.source_part_id==9007199254742001&&binding.policy_flags&4!=0)}
 hash:=[32]u8{};t.expect(test,bom_client_expect_gameplay_manifest(handle,raw_data(hash[:]),32)==BUSY)
 t.expect(test,bom_client_release_sample(handle,sample.sample_sequence)==OK)
}
@(test)
expected_manifest_configuration_rejects_invalid_input_and_live_mutation :: proc(test:^t.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64;t.expect(test,bom_client_create(&info,&handle)==OK);defer t.expect(test,bom_client_destroy(handle)==OK)
 hash:[32]u8;hash[0]=1;t.expect(test,bom_client_expect_gameplay_manifest(handle,nil,32)==BAD_ARGUMENT&&bom_client_expect_gameplay_manifest(handle,raw_data(hash[:]),31)==BAD_ARGUMENT)
 t.expect(test,bom_client_expect_gameplay_manifest(handle,raw_data(hash[:]),32)==OK)
 s,_:=get_slot(handle);t.expect(test,s.has_expected_manifest&&s.expected_manifest==hash)
 t.expect(test,bom_client_expect_gameplay_manifest(handle,nil,0)==OK&&!s.has_expected_manifest)
}
