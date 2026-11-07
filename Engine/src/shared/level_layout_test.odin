package shared
import t "core:testing"
import json "core:encoding/json"
import math "core:math"

LEVEL_V4_TEST :: `{"kind":"bom-layout","version":4,"seed":42,"next_identity":9007199254741002,
"level_id":"unit-level","gameplay_config_id":"bom-default-v1","catalog_id":"unit-catalog",
"simulation_bounds":{"lo":{"x":-10,"y":-3},"hi":{"x":10,"y":12}},
"kill_bounds":{"lo":{"x":-11,"y":-4},"hi":{"x":11,"y":13}},
"camera_bounds":{"lo":{"x":-11,"y":-4},"hi":{"x":11,"y":13}},
"aim_bounds":{"lo":{"x":-10,"y":-3},"hi":{"x":10,"y":12}},
"fragment_cull_bounds":{"lo":{"x":-20,"y":-10},"hi":{"x":20,"y":20}},
"spawns":[{"x":-4,"y":1},{"x":4,"y":1},{"x":-2,"y":1},{"x":2,"y":1}],
"bombs":{"spawn_x":{"x":-9,"y":9},"spawn_height":9,"cleanup_bounds":{"lo":{"x":-12,"y":-4},"hi":{"x":12,"y":14}}},
"sources":[{"identity":9007199254741001,"asset_key":"fixture","visual_hash":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
"group_to_rest":[-2,0,0,0,0,3,0,0,0,0,0.4,0,7,-2,4,1],"depth":{"x":-0.3,"y":0.3},"cap_key":"stone",
"motion":"anchored","damage":"indestructible","parts":[{"part_id":9007199254742001,"material":"stone",
"outline":[{"x":0,"y":0},{"x":3,"y":0},{"x":3,"y":1},{"x":1,"y":1},{"x":1,"y":3},{"x":0,"y":3}],
"anchors":[{"a":{"x":0,"y":0},"b":{"x":3,"y":0}}]}]}]}`

@(test)
level_v4_exact_ids_roundtrip_transform_and_concave_coverage :: proc(test:^t.T) {
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok { return };defer destroy_level_layout(&level)
 t.expect(test,level.sources[0].identity==9007199254741001&&level.sources[0].parts[0].part_id==9007199254742001&&level.next_identity==9007199254741002)
 p:=level_matrix_point(level.sources[0].group_to_rest,{1,2,3});t.expect(test,p==[3]f32{5,4,5.2})
 outline:=Polygon{points=level.sources[0].parts[0].outline[:]}
 pieces:=convex_decomposition(outline);defer { for piece in pieces { delete(piece.points) };delete(pieces) }
 area:f32;for piece in pieces { area+=polygon_area(piece);t.expect(test,len(piece.points)<=8&&is_convex(piece)) };t.expect(test,math.abs(area-5)<1e-6)
 encoded,err:=json.marshal(level);t.expect(test,err==nil);defer delete(encoded)
 copy,valid,problem:=decode_level_layout(encoded);t.expect(test,valid,problem);if valid { defer destroy_level_layout(&copy);t.expect(test,copy.sources[0].identity==level.sources[0].identity&&copy.sources[0].parts[0].part_id==level.sources[0].parts[0].part_id) }
}
@(test)
level_v4_rejects_invalid_bounds_ids_geometry_and_transform :: proc(test:^t.T) {
 level,ok,reason:=decode_level_layout(transmute([]u8)string(LEVEL_V4_TEST));t.expect(test,ok,reason);if !ok { return };defer destroy_level_layout(&level)
 source:=&level.sources[0];id:=source.identity;source.identity=0;t.expect(test,level_layout_problem(&level)!="");source.identity=id
 source.group_to_rest[0]=0;t.expect(test,level_layout_problem(&level)!="");source.group_to_rest[0]=-2
 next:=level.next_identity;level.next_identity=id;t.expect(test,level_layout_problem(&level)!="");level.next_identity=next
 spawn:=level.spawns[0];level.spawns[0]={1000,0};t.expect(test,level_layout_problem(&level)!="");level.spawns[0]=spawn
 part:=&source.parts[0];point:=part.outline[1];part.outline[1]=part.outline[0];t.expect(test,level_layout_problem(&level)!="");part.outline[1]=point
 anchor:=part.anchors[0];part.anchors[0]={{1,1},{2,2}};t.expect(test,level_layout_problem(&level)!="");part.anchors[0]=anchor
 for size in ([5]int{0,1,15,100,len(LEVEL_V4_TEST)-1}) { bad,valid,_:=decode_level_layout((transmute([]u8)string(LEVEL_V4_TEST))[:size]);t.expect(test,!valid);if valid { destroy_level_layout(&bad) } }
 t.expect_value(test,level_layout_problem(&level),"")
}
@(test)
level_v4_compound_hole_stays_empty_and_overlaps_are_detected :: proc(test:^t.T) {
 bottom:=[4]Vec2{{0,0},{4,0},{4,1},{0,1}};top:=[4]Vec2{{0,3},{4,3},{4,4},{0,4}}
 left:=[4]Vec2{{0,1},{1,1},{1,3},{0,3}};right:=[4]Vec2{{3,1},{4,1},{4,3},{3,3}}
 hole:=[4]Vec2{{1,1},{3,1},{3,3},{1,3}};overlap:=[4]Vec2{{.5,.5},{1.5,.5},{1.5,1.5},{.5,1.5}}
 parts:=[4][]Vec2{bottom[:],top[:],left[:],right[:]};area:f32
 for part,i in parts { t.expect_value(test,level_polygon_problem(part,Level_Bounds{{-1,-1},{5,5}}),"");area+=polygon_area(Polygon{part});t.expect(test,!level_parts_overlap(part,hole[:]));for other in parts[:i] { t.expect(test,!level_parts_overlap(part,other)) } }
 t.expect(test,math.abs(area-12)<1e-6&&level_parts_overlap(bottom[:],overlap[:]))
}
