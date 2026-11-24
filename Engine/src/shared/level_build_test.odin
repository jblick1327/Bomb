package shared
import t "core:testing"
import math "core:math"
import b2 "vendor:box2d"
import nc "../netcode"

@(test)
unity_level_build_has_exact_provenance_area_explicit_spawns_and_no_implicit_floor :: proc(test:^t.T) {
 layout,seed,ok,reason:=decode_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok { return };defer destroy_layout(&layout)
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;defer scene_destroy(&w.scene);defer delete(w.bombs)
 world_rebuild_layout(&w,&layout,false)
 t.expect(test,w.scene.level_policy.active&&w.floor==b2.nullBodyId&&w.scene.anchor_y== -1e30)
 area:f32;for sub in w.scene.subdivisions {
  t.expect(test,sub.provenance.source_identity==9007199254741001&&sub.provenance.source_part_id==9007199254742001&&sub.provenance.motion==.Anchored&&sub.provenance.damage==.Indestructible)
  area+=polygon_area(sub.outline)
 };t.expect(test,math.abs(area-5)<.00001)
 t.expect(test,w.players[0].pose.position==Vec2{-4,1});t.expect(test,world_add_player(&w,1)&&w.players[1].pose.position==Vec2{4,1})
 before:=w.players[0].pose.position.y
 for tick in 0..<20 { events:=world_tick(&w,Tick_Commands{},1.0/60);delete(events.explosions) }
 t.expect(test,w.players[0].pose.position.y<before-.1,"empty space at a negative X must not acquire legacy ground")
 // A complete reliable baseline carries matching metadata and every cell key.
 server:Repl_Server;defer repl_server_destroy(&server)
 baseline:=repl_server_baseline(&server,&w.scene,20);defer repl_output_destroy(&baseline)
 rep:Replica;replica_init(&rep);defer replica_destroy(&rep)
 for part in baseline.parts { _,problem:=replica_receive(&rep,part);t.expect_value(test,problem,"") }
 t.expect(test,rep.has_baseline&&rep.scene.level_json==w.scene.level_json&&rep.scene.level_policy.spawns[1]==Vec2{4,1})
 original:=canonical_encode(&w.scene);copy:=canonical_encode(&rep.scene);defer delete(original);defer delete(copy)
 t.expect(test,repl_hash(original)==repl_hash(copy))
 for sub in rep.scene.subdivisions { t.expect(test,sub.provenance.source_identity==9007199254741001&&sub.provenance.source_part_id==9007199254742001) }
 world_rebuild_layout(&w,&layout,false);t.expect(test,w.scene.epoch==2&&w.players[0].pose.position==Vec2{-4,1})
}
@(test)
catalog_hash_and_source_policy_corruption_fail_before_presentation :: proc(test:^t.T) {
 s,_,_,_:=test_policy_scene(.Fixed,.Indestructible);defer scene_destroy(&s)
 w:nc.Writer;nc.writer_init(&w);defer nc.writer_destroy(&w);repl_write_catalog(&w,&s)
 w.data[0]~=1
 destination:=new_scene(0);defer scene_destroy(&destination)
 r:nc.Reader;nc.reader_init(&r,w.data[:]);t.expect(test,repl_read_catalog(&r,&destination)!="")
 _,valid:=cell_policy_decode(9007199254741001,9007199254742001,0xffffffff);t.expect(test,!valid)
 _,valid=cell_policy_decode(1,1,u32(Motion_Policy.Fixed));t.expect(test,!valid,"fixed without pin must fail validation")
}
