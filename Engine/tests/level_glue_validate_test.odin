package main

import "core:testing"
import "core:sync"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import shared "shared"

// Builds a version 4 layout of axis-aligned tiles {x0,y0,x1,y1}; tile i is part i%per_source+1 of source i/per_source+1.
glue_test_level :: proc(tiles:[][4]f32,links:[][2]int,per_source:int=1,bounds:[2]f32={20,30}) -> string {
 b:strings.Builder
 fmt.sbprintf(&b,`{{"kind":"bom-layout","version":4,"seed":42,"next_identity":%d,"level_id":"glue-test","gameplay_config_id":"bom-default-v5","catalog_id":"glue-test",`,len(tiles)+10)
 fmt.sbprintf(&b,`"simulation_bounds":{{"lo":{{"x":-%v,"y":-3}},"hi":{{"x":%v,"y":%v}}}},"kill_bounds":{{"lo":{{"x":-%v,"y":-4}},"hi":{{"x":%v,"y":%v}}}},`,bounds.x,bounds.x,bounds.y,bounds.x+1,bounds.x+1,bounds.y+1)
 fmt.sbprintf(&b,`"camera_bounds":{{"lo":{{"x":-%v,"y":-4}},"hi":{{"x":%v,"y":%v}}}},"aim_bounds":{{"lo":{{"x":-%v,"y":-3}},"hi":{{"x":%v,"y":%v}}}},`,bounds.x+1,bounds.x+1,bounds.y+1,bounds.x,bounds.x,bounds.y)
 fmt.sbprintf(&b,`"fragment_cull_bounds":{{"lo":{{"x":-%v,"y":-10}},"hi":{{"x":%v,"y":%v}}}},`,bounds.x+10,bounds.x+10,bounds.y+10)
 fmt.sbprintf(&b,`"spawns":[{{"x":-4,"y":%v}},{{"x":4,"y":%v}},{{"x":-2,"y":%v}},{{"x":6,"y":%v}}],`,bounds.y-1,bounds.y-1,bounds.y-1,bounds.y-1)
 fmt.sbprintf(&b,`"bombs":{{"spawn_x":{{"x":-9,"y":9}},"spawn_height":9,"cleanup_bounds":{{"lo":{{"x":-%v,"y":-4}},"hi":{{"x":%v,"y":%v}}}}}},"sources":[`,bounds.x+2,bounds.x+2,bounds.y+2)
 sources:=(len(tiles)+per_source-1)/per_source
 for source in 0..<sources {
  if source>0 { strings.write_string(&b,",") }
  fmt.sbprintf(&b,`{{"identity":%d,"asset_key":"tile-%d","visual_hash":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","group_to_rest":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"depth":{{"x":-0.3,"y":0.3}},"cap_key":"stone","motion":"dynamic","damage":"destructible","parts":[`,source+1,source+1)
  for i in source*per_source..<min(len(tiles),(source+1)*per_source) {
   t:=tiles[i]
   if i>source*per_source { strings.write_string(&b,",") }
   fmt.sbprintf(&b,`{{"part_id":%d,"material":"stone","outline":[{{"x":%v,"y":%v}},{{"x":%v,"y":%v}},{{"x":%v,"y":%v}},{{"x":%v,"y":%v}}],"anchors":[]}}`,i%per_source+1,t[0],t[1],t[2],t[1],t[2],t[3],t[0],t[3])
  }
  strings.write_string(&b,"]}")
 }
 strings.write_string(&b,`],"glue":[`)
 for l,i in links {
  if i>0 { strings.write_string(&b,",") }
  fmt.sbprintf(&b,`{{"a":{{"source_identity":%d,"part_id":%d}},"b":{{"source_identity":%d,"part_id":%d}}}}`,l[0]/per_source+1,l[0]%per_source+1,l[1]/per_source+1,l[1]%per_source+1)
 }
 strings.write_string(&b,`]}`)
 return strings.to_string(b)
}

glue_test_world :: proc(t:^testing.T,json_text:string) -> (layout:shared.Layout,w:shared.World,ok:bool) {
 seed:u8;reason:string
 layout,seed,ok,reason=shared.decode_layout(transmute([]u8)json_text);testing.expect(t,ok,reason);if !ok { return }
 w=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;shared.world_rebuild_layout(&w,&layout,false)
 return
}

glue_test_grid :: proc(columns,rows:int) -> (tiles:[dynamic][4]f32,links:[dynamic][2]int) {
 for r in 0..<rows { for c in 0..<columns {
  x,y:=f32(c)*0.6-7.2,f32(r)*0.45
  append(&tiles,[4]f32{x,y,x+0.6,y+0.45})
  if c>0 { append(&links,[2]int{r*columns+c-1,r*columns+c}) }
  if r>0 { append(&links,[2]int{(r-1)*columns+c,r*columns+c}) }
 } }
 return
}

@(test)
validator_reports_glue_samples_and_names_a_link_that_never_takes_effect :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 // tile-1|tile-2 gap 0.05 (inside the 0.2 fillet), tile-2|tile-3 gap 1.0 (outside it).
 text:=glue_test_level({{0,0,1,1},{1.05,0,2,1},{3,0,4,1}},{{0,1},{1,2}});defer delete(text)
 layout,w,ok:=glue_test_world(t,text);if !ok { return };defer shared.destroy_layout(&layout);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
 rows:=shared.level_glue_report(&w.scene,layout.level);defer delete(rows)
 testing.expect_value(t,len(rows),2)
 testing.expect(t,rows[0].samples>0,"a 0.05 gap is glued")
 testing.expect(t,rows[0].gap>0.049&&rows[0].gap<0.051)
 testing.expect_value(t,rows[1].samples,0)
 testing.expect(t,rows[1].gap>0.99&&rows[1].gap<1.01)
 message:=shared.level_glue_failure(rows[1]);defer delete(message)
 testing.expect(t,strings.contains(message,`source 2 "tile-2"`)&&strings.contains(message,`source 3 "tile-3"`)&&strings.contains(message,"gap 1.0000"),message)
 // The count is the effect: a passing link's samples equal what the connections actually carry.
 carried:=0;for c in w.scene.connections { if c.live { carried+=len(c.glue) } }
 testing.expect_value(t,carried,rows[0].samples)
}

@(test)
validate_layout_cli_fails_on_zero_sample_link_and_passes_when_fixed :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 bad:=glue_test_level({{0,0,1,1},{1.5,0,2.5,1}},{{0,1}});defer delete(bad)
 good:=glue_test_level({{0,0,1,1},{1.1,0,2.1,1}},{{0,1}});defer delete(good)
 input,report:="build/glue-validate-input.json","build/glue-validate-report.json"
 defer { os.remove(input);os.remove(report);os.remove("build/glue-validate-report.json.layout.json") }
 testing.expect(t,os.write_entire_file(input,transmute([]u8)bad)==nil)
 testing.expect(t,!shared.level_validate_cli(input,report),"zero-sample glue must fail validation")
 data,err:=os.read_entire_file(report,context.allocator);defer delete(data)
 testing.expect(t,err==nil&&strings.contains(string(data),`"status": "failed"`)&&strings.contains(string(data),`"samples": 0`),string(data))
 testing.expect(t,os.write_entire_file(input,transmute([]u8)good)==nil)
 testing.expect(t,shared.level_validate_cli(input,report),"a link inside the glue fillet passes")
 data2,err2:=os.read_entire_file(report,context.allocator);defer delete(data2)
 testing.expect(t,err2==nil&&strings.contains(string(data2),`"status": "passed"`)&&strings.contains(string(data2),`"glue_link_count": 1`))
}

@(test)
glue_budget_accepts_more_than_1024_links_and_stops_at_2048 :: proc(t:^testing.T) {
 // The part count stays at the wire-catalog bound of 1024; the glue count is a validator bound. The 200000-byte layout bound still applies.
 tiles,links:=glue_test_grid(24,24);defer delete(tiles);defer delete(links)
 testing.expect_value(t,len(links),1104)
 text:=glue_test_level(tiles[:],links[:],64);defer delete(text)
 level,ok,problem:=shared.decode_level_layout(transmute([]u8)text);testing.expect(t,ok,problem);if !ok { return };defer shared.destroy_level_layout(&level)
 testing.expect_value(t,len(level.glue),1104)
 for len(level.glue)<shared.LEVEL_MAX_GLUE_LINKS { append(&level.glue,level.glue[0]) }
 testing.expect_value(t,shared.level_layout_problem(&level),"Duplicate glue link")
 append(&level.glue,level.glue[0])
 testing.expect_value(t,shared.level_layout_problem(&level),"Level record count exceeds limits")
}

@(test)
glue_budget_cost_with_1104_links_is_measured :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 tiles,links:=glue_test_grid(24,24);defer delete(tiles);defer delete(links)
 text:=glue_test_level(tiles[:],links[:],64);defer delete(text)
 start:=time.now()
 layout,w,ok:=glue_test_world(t,text);if !ok { return };defer shared.destroy_layout(&layout);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
 build_ms:=time.duration_milliseconds(time.since(start))
 glue_samples,live:=0,0;for c in w.scene.connections { if c.live&&c.mortar { live+=1;glue_samples+=len(c.glue) } }
 start=time.now();rows_report:=shared.level_glue_report(&w.scene,layout.level);defer delete(rows_report)
 report_ms:=time.duration_milliseconds(time.since(start))
 zero:=0;for row in rows_report { if row.samples==0 { zero+=1 } }
 fmt.printfln("GLUE BUDGET parts=%d links=%d cells=%d glue_connections=%d glue_samples=%d zero_links=%d build_ms=%.0f report_ms=%.0f layout_bytes=%d",len(tiles),len(links),len(w.scene.subdivisions),live,glue_samples,zero,build_ms,report_ms,len(text))
 testing.expect_value(t,zero,0)
 testing.expect(t,live>=len(links),"every authored link produced at least one glue connection")
}
