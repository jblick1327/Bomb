package shared
import nc "../netcode"
import sha2 "core:crypto/sha2"
import strings "core:strings"

level_catalog_parts_match :: proc(s:^Scene,level:^Level_Layout) -> bool {
 count:=0;for source in level.sources { for part in source.parts {
  count+=1;matched:=false
  for record in s.source_parts {
   if record.source_identity!=source.identity||record.source_part_id!=part.part_id { continue }
   if len(record.segments)!=len(part.anchors) { return false }
   for segment,i in record.segments { if segment!=part.anchors[i] { return false } };matched=true;break
  };if !matched { return false }
 } };return count==len(s.source_parts)
}
scene_restore_catalog_data :: proc(s:^Scene,text:string,parts:[]Source_Part_Anchors) -> bool {
 if len(parts)>1024||len(text)>NET_APP_MAX_LAYOUT { return false }
 seen:=make(map[Level_Part_Key]bool);defer delete(seen)
 for part in parts {
  key:=Level_Part_Key{part.source_identity,part.source_part_id}
  if seen[key]||key.source_identity==0||key.part_id==0||len(part.segments)>128 { return false };seen[key]=true
  for segment in part.segments { if !valid_vec(segment.a)||!valid_vec(segment.b)||vlen(vsub(segment.b,segment.a))<.001 { return false } }
  copy:=Source_Part_Anchors{source_identity=part.source_identity,source_part_id=part.source_part_id};append(&copy.segments,..part.segments[:]);append(&s.source_parts,copy)
 }
 if text!="" {
  level,ok,_:=decode_level_layout(transmute([]u8)text);if !ok { return false };defer destroy_level_layout(&level)
  if !level_catalog_parts_match(s,&level) { return false };s.level_policy=level_resolve_policy(&level);s.gameplay_manifest=level_gameplay_hash(&level);s.config_hash=gameplay_config_hash(level.gameplay_config)
 };s.level_json=strings.clone(text);return true
}

level_sha256 :: proc(data:[]u8) -> [32]u8 { ctx:sha2.Context_256;sha2.init_256(&ctx);sha2.update(&ctx,data);out:[32]u8;sha2.final(&ctx,out[:]);return out }
repl_write_catalog :: proc(w:^nc.Writer,s:^Scene) {
 hash:=level_sha256(transmute([]u8)s.level_json);nc.write_raw(w,hash[:]);nc.write_string(w,s.level_json)
 nc.write_varint(w,u64(len(s.source_parts)))
 for part in s.source_parts {
  nc.write_u64(w,part.source_identity);nc.write_u64(w,part.source_part_id);nc.write_varint(w,u64(len(part.segments)))
  for segment in part.segments { nc.write_f32(w,segment.a.x);nc.write_f32(w,segment.a.y);nc.write_f32(w,segment.b.x);nc.write_f32(w,segment.b.y) }
 }
}
repl_read_catalog :: proc(r:^nc.Reader,s:^Scene) -> string {
 expected:[32]u8;for &byte in expected { byte=nc.read_u8(r) }
 text:=nc.read_string(r)
 if !r.ok||len(text)>NET_APP_MAX_LAYOUT||level_sha256(transmute([]u8)text)!=expected { return "invalid catalog size/hash" }
 level:Level_Layout;defer destroy_level_layout(&level)
 if len(text)>0 {
  decoded,ok,reason:=decode_level_layout(transmute([]u8)text);if !ok { return reason };level=decoded
  s.level_policy=level_resolve_policy(&level)
  s.gameplay_manifest=level_gameplay_hash(&level);s.config_hash=gameplay_config_hash(level.gameplay_config)
 }
 s.level_json=strings.clone(text)
 count:=nc.read_varint(r);if !r.ok||count>1024 { return "too many source part bindings" }
 seen:=make(map[Level_Part_Key]bool);defer delete(seen)
 for _ in 0..<count {
  part:=Source_Part_Anchors{source_identity=nc.read_u64(r),source_part_id=nc.read_u64(r)}
  key:=Level_Part_Key{part.source_identity,part.source_part_id}
  n:=nc.read_varint(r);if !r.ok||n>128||n>u64(nc.reader_remaining(r))/16||key.source_identity==0||key.part_id==0||seen[key] { return "invalid source part anchors" };seen[key]=true
  for _ in 0..<n {
   segment:=Segment{{nc.read_f32(r),nc.read_f32(r)},{nc.read_f32(r),nc.read_f32(r)}}
   if !valid_vec(segment.a)||!valid_vec(segment.b)||vlen(vsub(segment.b,segment.a))<.001 { delete(part.segments);return "invalid source anchor geometry" }
   append(&part.segments,segment)
  };append(&s.source_parts,part)
 }
 if !r.ok { return "truncated catalog" }
 if len(text)>0&&!level_catalog_parts_match(s,&level) { return "catalog/source-part metadata mismatch" };return ""
}
