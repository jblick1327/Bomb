package shared
import os "core:os"
import fmt "core:fmt"

level_hash_text :: proc(hash:[32]u8) -> string { bytes:=make([]u8,64);digits:="0123456789abcdef";for byte,i in hash {bytes[i*2]=digits[byte>>4];bytes[i*2+1]=digits[byte&15]};return transmute(string)bytes }
Level_Source_Report :: struct {identity:u64,parts,cells,pinned_cells:int,area:f64,matrix_probe:[3]f32}
Level_Validation_Report :: struct {
 status,level_id,gameplay_manifest_hash,gameplay_config_hash,catalog_hash:string,
 game_protocol:u32,canonical_version:u8,
 source_count,part_count,cell_count,fixture_count:int,
 bounds:Resolved_Level_Policy,
 sources:[dynamic]Level_Source_Report,
}
level_validate_cli :: proc(input,report_path:string) -> bool {
 data,err:=os.read_entire_file(input,context.allocator);if err!=nil {fmt.eprintln("Cannot read layout:",input);return false};defer delete(data)
 layout,seed,valid,reason:=decode_layout(data);if !valid {fmt.eprintln("Invalid exported layout:",reason);return false};defer destroy_layout(&layout)
 if layout.level==nil {fmt.eprintln("This export validator requires layout v4; the server still loads legacy layouts normally");return false}
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};w.settings.seed=seed;world_rebuild_layout(&w,&layout,false);defer scene_destroy(&w.scene);defer delete(w.bombs)
 manifest:=level_hash_text(w.scene.gameplay_manifest);config:=level_hash_text(w.scene.config_hash);catalog:=level_hash_text(level_sha256(transmute([]u8)w.scene.level_json));defer delete(manifest);defer delete(config);defer delete(catalog)
 report:=Level_Validation_Report{status="passed",level_id=layout.level.level_id,gameplay_manifest_hash=manifest,gameplay_config_hash=config,catalog_hash=catalog,game_protocol=GAME_PROTOCOL_VERSION,canonical_version=REPL_CANON_VERSION,source_count=len(layout.level.sources),cell_count=len(w.scene.subdivisions),bounds=w.scene.level_policy};defer delete(report.sources)
 for source in layout.level.sources {
  row:=Level_Source_Report{identity=source.identity,parts=len(source.parts),matrix_probe=level_matrix_point(source.group_to_rest,{1,2,3})};report.part_count+=len(source.parts)
  for sub in w.scene.subdivisions {
   if sub.provenance.source_identity!=source.identity {continue};row.cells+=1;row.area+=f64(polygon_area(sub.outline));if sub.provenance.pinned {row.pinned_cells+=1}
   if sub.fixture_count==0 {fmt.eprintln("Source has a cell without collision geometry:",source.identity);return false};report.fixture_count+=sub.fixture_count
  };append(&report.sources,row)
 }
 encoded,encoded_ok:=exact_json_encode(report,true);defer delete(encoded)
 if !encoded_ok||os.write_entire_file(report_path,encoded)!=nil {fmt.eprintln("Cannot write validation report:",report_path);return false}
 normalized:=fmt.aprintf("%s.layout.json",report_path);defer delete(normalized)
 if os.write_entire_file(normalized,transmute([]u8)w.scene.level_json)!=nil {fmt.eprintln("Cannot write normalized catalog:",normalized);return false}
 fmt.printf("LEVEL PASS sources=%d parts=%d cells=%d fixtures=%d gameplay=%s catalog=%s\n",report.source_count,report.part_count,report.cell_count,report.fixture_count,manifest,catalog)
 return true
}
