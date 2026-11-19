package shared
import os "core:os"
import fmt "core:fmt"

level_hash_text :: proc(hash:[32]u8) -> string { bytes:=make([]u8,64);digits:="0123456789abcdef";for byte,i in hash {bytes[i*2]=digits[byte>>4];bytes[i*2+1]=digits[byte&15]};return transmute(string)bytes }
Level_Source_Report :: struct {identity:u64,identity_text:string,initial_cell_ids:[dynamic]string,parts,cells,pinned_cells:int,area:f64,matrix_probe:[3]f32}
Level_Glue_Report :: struct {source_a,source_b:u64,part_a,part_b:u64,name_a,name_b:string,samples:int,gap:f32}
level_glue_part :: proc(level:^Level_Layout,key:Level_Part_Key) -> (name:string,outline:[]Vec2) {
 for source in level.sources { if source.identity!=key.source_identity { continue };for part in source.parts { if part.part_id==key.part_id { return source.asset_key,part.outline[:] } } }
 return "",nil
}
// One row per authored glue link: samples that take effect, and the gap between the two proxies.
level_glue_report :: proc(s:^Scene,level:^Level_Layout) -> [dynamic]Level_Glue_Report {
 rows:[dynamic]Level_Glue_Report
 index:=level_part_cell_index(s);defer level_part_cell_index_destroy(&index)
 for link in level.glue {
  name_a,out_a:=level_glue_part(level,link.a);name_b,out_b:=level_glue_part(level,link.b)
  gap,_:=polygon_contact(Polygon{out_a},Polygon{out_b})
  append(&rows,Level_Glue_Report{link.a.source_identity,link.b.source_identity,link.a.part_id,link.b.part_id,name_a,name_b,level_glue_link(s,&index,link,false),gap})
 }
 return rows
}
level_glue_failure :: proc(row:Level_Glue_Report) -> string {
 return fmt.aprintf("Glue link never takes effect (0 samples): source %d \"%s\" part %d / source %d \"%s\" part %d, gap %.4f (glue reaches %.2f)",row.source_a,row.name_a,row.part_a,row.source_b,row.name_b,row.part_b,row.gap,GLUE_FILLET)
}
Level_Validation_Report :: struct {
 status,level_id,gameplay_manifest_hash,gameplay_config_hash,catalog_hash:string,
 game_protocol:u32,canonical_version:u8,
 source_count,part_count,cell_count,fixture_count:int,
 bounds:Resolved_Level_Policy,
 sources:[dynamic]Level_Source_Report,
 glue_link_count,glue_zero_sample_links:int,
 glue:[dynamic]Level_Glue_Report,
 settle:Level_Settle_Report,
}
level_validate_cli :: proc(input,report_path:string,settle_ticks:int=0,settle_window:int=120,settle_options:=Level_Settle_Options{}) -> bool {
 if settle_ticks<0 || settle_window<0 || (settle_ticks>0 && settle_ticks<=settle_window) {fmt.eprintln("Settle ticks must exceed the nonnegative settle window");return false}
 data,err:=os.read_entire_file(input,context.allocator);if err!=nil {fmt.eprintln("Cannot read layout:",input);return false};defer delete(data)
 layout,seed,valid,reason:=decode_layout(data);if !valid {fmt.eprintln("Invalid exported layout:",reason);return false};defer destroy_layout(&layout)
 if layout.level==nil {fmt.eprintln("This export validator requires layout v4; the server still loads legacy layouts normally");return false}
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false);defer scene_destroy(&w.scene);defer delete(w.bombs)
 manifest:=level_hash_text(w.scene.gameplay_manifest);config:=level_hash_text(w.scene.config_hash);catalog:=level_hash_text(level_sha256(transmute([]u8)w.scene.level_json));defer delete(manifest);defer delete(config);defer delete(catalog)
 report:=Level_Validation_Report{status="passed",level_id=layout.level.level_id,gameplay_manifest_hash=manifest,gameplay_config_hash=config,catalog_hash=catalog,game_protocol=GAME_PROTOCOL_VERSION,canonical_version=REPL_CANON_VERSION,source_count=len(layout.level.sources),cell_count=len(w.scene.subdivisions),bounds=w.scene.level_policy};defer {delete(report.glue);for row in report.sources {delete(row.identity_text);for id in row.initial_cell_ids {delete(id)};delete(row.initial_cell_ids)};delete(report.sources)}
 for source in layout.level.sources {
  append(&report.sources,Level_Source_Report{identity=source.identity,identity_text=fmt.aprintf("%d",source.identity),parts=len(source.parts),matrix_probe=level_matrix_point(source.group_to_rest,{1,2,3})});row:=&report.sources[len(report.sources)-1];report.part_count+=len(source.parts)
  for sub in w.scene.subdivisions {
   if sub.provenance.source_identity!=source.identity {continue};row.cells+=1;append(&row.initial_cell_ids,fmt.aprintf("%d",sub.id));row.area+=f64(polygon_area(sub.outline));if sub.provenance.pinned {row.pinned_cells+=1}
   if sub.fixture_count==0 {fmt.eprintln("Source has a cell without collision geometry:",source.identity);return false};report.fixture_count+=sub.fixture_count
  }
 }
 report.glue=level_glue_report(&w.scene,layout.level)
 report.glue_link_count=len(report.glue)
 for row in report.glue { if row.samples==0 { report.glue_zero_sample_links+=1 } }
 if report.glue_zero_sample_links>0 { report.status="failed" }
 if settle_ticks>0 {report.settle=level_settle_run(&w,layout.level,settle_ticks,settle_window,settle_options)}
 defer level_settle_destroy(&report.settle)
 encoded,encoded_ok:=exact_json_encode(report,true);defer delete(encoded)
 if !encoded_ok||os.write_entire_file(report_path,encoded)!=nil {fmt.eprintln("Cannot write validation report:",report_path);return false}
 normalized:=fmt.aprintf("%s.layout.json",report_path);defer delete(normalized)
 if os.write_entire_file(normalized,transmute([]u8)w.scene.level_json)!=nil {fmt.eprintln("Cannot write normalized catalog:",normalized);return false}
 if report.glue_zero_sample_links>0 {
  for row in report.glue { if row.samples==0 { message:=level_glue_failure(row);fmt.eprintln("LEVEL FAIL",message);delete(message) } }
  return false
 }
 fmt.printf("LEVEL PASS sources=%d parts=%d cells=%d fixtures=%d gameplay=%s catalog=%s\n",report.source_count,report.part_count,report.cell_count,report.fixture_count,manifest,catalog)
 return true
}
