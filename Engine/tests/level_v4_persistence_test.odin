package main
import t "core:testing"
import sync "core:sync"
import strings "core:strings"
import shared "shared"

@(test)
authored_level_snapshot_preserves_catalog_bounds_high_ids_and_pins :: proc(test:^t.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 data:=#load("presets/unity-policy-v4.json")
 layout,seed,ok,reason:=decode_layout(transmute([]u8)data);t.expect(test,ok,reason);if !ok { return };defer destroy_layout(&layout)
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false);defer scene_destroy(&w.scene);defer delete(w.bombs)
 bytes,encoded:=encode_world_snapshot(&w);defer delete(bytes);t.expect(test,encoded&&strings.contains(string(bytes),"9007199254741001"))
 restored,decoded:=decode_world_snapshot(bytes,7);t.expect(test,decoded);if !decoded { return };defer scene_destroy(&restored.scene);defer delete(restored.bombs)
 t.expect(test,restored.scene.level_policy.active&&restored.scene.level_policy.spawns==w.scene.level_policy.spawns&&restored.scene.level_json==w.scene.level_json&&restored.scene.epoch==7)
 t.expect(test,len(restored.scene.subdivisions)==len(w.scene.subdivisions))
 for sub in restored.scene.subdivisions {
  t.expect(test,sub.provenance.source_identity==9007199254741001&&sub.provenance.source_part_id==9007199254742001)
  t.expect(test,sub.provenance==w.scene.subdivisions[w.scene.sub_rows[sub.id]].provenance)
 }
 again,valid:=encode_world_snapshot(&restored);defer delete(again);t.expect(test,valid&&string(again)==string(bytes),"v4-authored world snapshot round-trips exactly")
}
@(test)
source_keys_survive_repeated_refinement_regroup_and_scene_snapshot :: proc(test:^t.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 s:=make_wall(42,.01);defer scene_destroy(&s)
 for &sub,i in s.subdivisions { sub.provenance={source_identity=9007199254741001+u64(i%2),source_part_id=9007199254742001,motion=.Fixed,pinned=true} }
 for iteration in 0..<3 {
  candidate:=u64(0);for sub in s.subdivisions { if sub.live&&sub.seed!=0 { candidate=sub.id;break } };t.expect(test,candidate!=0);if candidate==0 { break }
  failure:=failure_for(candidate);apply_failures(&s,failure);free_failures(&failure)
  for sub in s.subdivisions { t.expect(test,(sub.provenance.source_identity==9007199254741001||sub.provenance.source_identity==9007199254741002)&&sub.provenance.source_part_id==9007199254742001&&sub.provenance.pinned&&sub.provenance.motion==.Fixed) }
 }
 bytes,encoded:=encode_snapshot(&s);defer delete(bytes);t.expect(test,encoded)
 loaded,ok:=decode_snapshot(bytes);t.expect(test,ok);if !ok { return };defer scene_destroy(&loaded)
 for sub in loaded.subdivisions { t.expect(test,sub.provenance==s.subdivisions[s.sub_rows[sub.id]].provenance) }
}
@(test)
odin_editor_preserves_unity_authored_metadata_and_stays_read_only :: proc(test:^t.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create();defer sandbox_destroy(&g)
 data:=#load("presets/unity-policy-v4.json");t.expect(test,sandbox_load_layout_data(&g,transmute([]u8)data)&&g.layout.level!=nil&&!g.editor.editing)
 before:=shared.level_gameplay_hash(g.layout.level);sandbox_toggle_editor(&g);t.expect(test,!g.editor.editing&&strings.contains(g.status,"read-only"))
 bytes,encoded:=encode_layout(&g.layout,g.world.settings.seed);defer delete(bytes);t.expect(test,encoded)
 restored,_,ok,reason:=decode_layout(bytes);t.expect(test,ok,reason);if !ok {return};defer destroy_layout(&restored)
 t.expect(test,restored.level!=nil&&shared.level_gameplay_hash(restored.level)==before&&restored.level.sources[0].identity==9007199254741001)
}
