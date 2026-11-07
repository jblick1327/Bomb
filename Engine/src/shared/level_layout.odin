package shared

import json "core:encoding/json"
import mem "core:mem"
import math "core:math"

// Version 4 authoring data is separate from legacy editor rectangles. The
// application loader will opt into it only with the coordinated wire change.
SOURCE_RESERVED_START :: u64(0xffffffffffffff00)
Level_Bounds :: struct { lo,hi:Vec2 }
Level_Bomb_Settings :: struct { spawn_x:Vec2, spawn_height:f32, cleanup_bounds:Level_Bounds }
Level_Part :: struct { part_id:u64, material:string, outline:[dynamic]Vec2, anchors:[dynamic]Segment }
Level_Source :: struct {
 identity:u64,
 asset_key,visual_hash,cap_key:string,
 group_to_rest:[16]f32,
 depth:Vec2,
 motion,damage:string,
 parts:[dynamic]Level_Part,
}
Level_Part_Key :: struct { source_identity,part_id:u64 }
Level_Glue :: struct { a,b:Level_Part_Key }
Level_Layout :: struct {
 kind:string, version:int, seed:u64, next_identity:u64,
 level_id,gameplay_config_id,catalog_id:string,
 gameplay_config:Gameplay_Config,
 simulation_bounds,kill_bounds,camera_bounds,aim_bounds,fragment_cull_bounds:Level_Bounds,
 spawns:[dynamic]Vec2,
 bombs:Level_Bomb_Settings,
 materials:[dynamic]Wire_Custom_Material,
 sources:[dynamic]Level_Source,
 glue:[dynamic]Level_Glue,
}
destroy_level_layout :: proc(level:^Level_Layout) {
 delete(level.kind);delete(level.level_id);delete(level.gameplay_config_id);delete(level.catalog_id)
 delete(level.spawns);delete(level.glue)
 for m in level.materials { delete(m.name);delete(m.base) };delete(level.materials)
 for source in level.sources {
  delete(source.asset_key);delete(source.visual_hash);delete(source.cap_key);delete(source.motion);delete(source.damage)
  for part in source.parts { delete(part.material);delete(part.outline);delete(part.anchors) };delete(source.parts)
 };delete(level.sources);level^={}
}
level_bounds_valid :: proc(bounds:Level_Bounds) -> bool {
 return valid_vec(bounds.lo)&&valid_vec(bounds.hi)&&bounds.hi.x-bounds.lo.x>=.01&&bounds.hi.y-bounds.lo.y>=.01&&
  math.abs(bounds.lo.x)<=10000&&math.abs(bounds.lo.y)<=10000&&math.abs(bounds.hi.x)<=10000&&math.abs(bounds.hi.y)<=10000
}
level_bounds_contains :: proc(bounds:Level_Bounds,p:Vec2) -> bool { return valid_vec(p)&&p.x>=bounds.lo.x&&p.x<=bounds.hi.x&&p.y>=bounds.lo.y&&p.y<=bounds.hi.y }
level_matrix_valid :: proc(m:[16]f32) -> bool {
 for v in m { if !finite(v) { return false } }
 if math.abs(m[3])>1e-6||math.abs(m[7])>1e-6||math.abs(m[11])>1e-6||math.abs(m[15]-1)>1e-6 { return false }
 determinant:=f64(m[0])*(f64(m[5])*f64(m[10])-f64(m[9])*f64(m[6]))-
  f64(m[4])*(f64(m[1])*f64(m[10])-f64(m[9])*f64(m[2]))+f64(m[8])*(f64(m[1])*f64(m[6])-f64(m[5])*f64(m[2]))
 return math.abs(determinant)>=1e-8
}
level_matrix_point :: proc(m:[16]f32,p:[3]f32) -> [3]f32 {
 return {m[0]*p[0]+m[4]*p[1]+m[8]*p[2]+m[12],m[1]*p[0]+m[5]*p[1]+m[9]*p[2]+m[13],m[2]*p[0]+m[6]*p[1]+m[10]*p[2]+m[14]}
}
level_polygon_problem :: proc(points:[]Vec2,bounds:Level_Bounds) -> string {
 if len(points)<3||len(points)>128 { return "Part outlines require 3..128 vertices" }
 signed:f64
 for p,i in points {
  if !level_bounds_contains(bounds,p) { return "Proxy vertex outside simulation bounds" }
  q:=points[(i+1)%len(points)]
  if vlen(vsub(p,q))<.001 { return "Proxy edges must be at least 0.001 units" }
  signed+=f64(p.x)*f64(q.y)-f64(p.y)*f64(q.x)
 }
 if signed<.0002 { return "Proxy outlines must be CCW with area at least 0.0001" }
 if !simple_polygon(Polygon{points=points}) { return "Proxy outline self-intersects" }
 return ""
}
level_parts_overlap :: proc(a,b:[]Vec2) -> bool {
 aa:=convex_decomposition(Polygon{points=a});bb:=convex_decomposition(Polygon{points=b})
 defer { for p in aa { delete(p.points) };delete(aa);for p in bb { delete(p.points) };delete(bb) }
 for x in aa { for y in bb { intersection:=convex_intersection(x,y);area:=polygon_area(intersection);delete(intersection.points);if area>1e-6 { return true } } }
 return false
}
level_layout_problem :: proc(level:^Level_Layout) -> string {
 if level.kind!="bom-layout"||level.version!=4 { return "Not a version 4 bom-layout" }
 if len(level.level_id)<1||len(level.level_id)>128||len(level.gameplay_config_id)<1||len(level.gameplay_config_id)>128||len(level.catalog_id)<1||len(level.catalog_id)>128 { return "Level/config/catalog identifiers require 1..128 bytes" }
 if level.seed>255 { return "Seed must be between 0 and 255" }
 if !gameplay_config_valid(level.gameplay_config) { return "Invalid versioned gameplay configuration" }
 for bounds in ([6]Level_Bounds{level.simulation_bounds,level.kill_bounds,level.camera_bounds,level.aim_bounds,level.fragment_cull_bounds,level.bombs.cleanup_bounds}) { if !level_bounds_valid(bounds) { return "Invalid level bounds" } }
 if len(level.spawns)!=4 { return "Exactly four explicit spawn points are required" }
 for spawn in level.spawns { if !level_bounds_contains(level.simulation_bounds,spawn)||!level_bounds_contains(level.kill_bounds,spawn) { return "Spawn outside simulation/kill bounds" } }
 if !valid_vec(level.bombs.spawn_x)||!finite(level.bombs.spawn_height)||level.bombs.spawn_x.y<level.bombs.spawn_x.x||level.bombs.spawn_x.x<level.simulation_bounds.lo.x||level.bombs.spawn_x.y>level.simulation_bounds.hi.x||level.bombs.spawn_height<level.simulation_bounds.lo.y||level.bombs.spawn_height>level.simulation_bounds.hi.y { return "Invalid bomb spawn limits" }
 if len(level.sources)>512||len(level.materials)>4||len(level.glue)>1024 { return "Level record count exceeds limits" }
 palette:Layout;defer { for &m in palette.materials { m.name="" };destroy_layout(&palette) }
 for m in level.materials {
  base,known:=material_base_name(m.base);if !known { return "Unknown custom material base" }
  if problem:=material_name_problem(&palette,m.name);problem!="" { return problem }
  custom:=custom_from_wire(m,base);if problem:=custom_problem(custom);problem!="" { return problem }
  // The validation palette borrows names owned by the parsed level.
  custom.name="";append(&palette.materials,custom)
  palette.materials[len(palette.materials)-1].name=m.name
 }

 sources:=make(map[u64]bool);defer delete(sources)
 parts:=make(map[Level_Part_Key]bool);defer delete(parts)
 maximum:u64;count:=0;construction_budget:=f64(0)
 for source in level.sources {
  if source.identity==0||source.identity>=SOURCE_RESERVED_START||sources[source.identity] { return "Source identity is zero, duplicate or reserved" };sources[source.identity]=true;maximum=max(maximum,source.identity)
  if len(source.asset_key)<1||len(source.asset_key)>256||len(source.visual_hash)!=64||len(source.cap_key)>256 { return "Invalid visual catalog binding" }
  for c in source.visual_hash { if !(c>='0'&&c<='9'||c>='a'&&c<='f') { return "Visual content hash must be lowercase SHA256" } }
  if !level_matrix_valid(source.group_to_rest)||!valid_vec(source.depth)||source.depth.y-source.depth.x<.001 { return "Invalid nonsingular affine transform or depth interval" }
  if source.motion!="dynamic"&&source.motion!="fixed"&&source.motion!="anchored" { return "Unknown motion policy" }
  if source.damage!="destructible"&&source.damage!="indestructible" { return "Unknown damage policy" }
  if len(source.parts)<1||len(source.parts)>64 { return "A source requires 1..64 physics parts" }
  anchor_count:=0
  for part,index in source.parts {
   count+=1;if count>1024 { return "Maximum 1024 physics parts" }
   key:=Level_Part_Key{source.identity,part.part_id};if part.part_id==0||part.part_id==max(u64)||parts[key] { return "Part identity is zero, duplicate or exhausted" };parts[key]=true
   known:=false;for slot in 0..<palette_count(&palette) { if layout_material(&palette,Slot(slot)).name==part.material { known=true;break } };if !known { return "Unknown physics material" }
   if problem:=level_polygon_problem(part.outline[:],level.simulation_bounds);problem!="" { return problem }
   lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30};for p in part.outline { lo={min(lo.x,p.x),min(lo.y,p.y)};hi={max(hi.x,p.x),max(hi.y,p.y)} }
   construction_budget+=math.ceil(f64(hi.x-lo.x)/.1)*math.ceil(f64(hi.y-lo.y)/.1)*f64(len(part.outline)-2)
   if construction_budget>100000 { return "Proxy construction budget exceeds 100000 conservative grid-triangle units; split/simplify the authored level" }
   if len(part.anchors)>128 { return "Too many anchor segments" }
   for anchor in part.anchors {
    if !valid_vec(anchor.a)||!valid_vec(anchor.b)||vlen(vsub(anchor.b,anchor.a))<.001 { return "Invalid anchor segment" }
    overlap:=false
    for p,i in part.outline { if _,matches:=segment_overlap(anchor,Segment{p,part.outline[(i+1)%len(part.outline)]});matches { overlap=true;break } }
    if !overlap { return "Anchor segment has no matching proxy boundary interval" }
   }
   anchor_count+=len(part.anchors)
   for earlier in source.parts[:index] { if level_parts_overlap(part.outline[:],earlier.outline[:]) { return "Compound physics parts overlap" } }
  }
  if source.motion=="anchored"&&anchor_count==0 { return "Anchored sources require explicit boundary segments" }
 }
 if level.next_identity<=maximum||level.next_identity>=SOURCE_RESERVED_START { return "next_identity must exceed every source and avoid the reserved range" }
 links:=make(map[[2]Level_Part_Key]bool);defer delete(links)
 for link in level.glue {
  if link.a==link.b||!parts[link.a]||!parts[link.b] { return "Glue refers to missing or identical parts" }
  if links[{link.a,link.b}]||links[{link.b,link.a}] { return "Duplicate glue link" };links[{link.a,link.b}]=true
 }
 return ""
}
decode_level_layout :: proc(data:[]u8) -> (level:Level_Layout,ok:bool,problem:string) {
 if len(data)==0||len(data)>NET_APP_MAX_LAYOUT { return {},false,"Version 4 layout exceeds the 200000-byte upload bound" }
 // Failed and malformed parses share one bounded scratch lifetime, including
 // partially allocated nested JSON records. Persistent data is allocated only
 // after every count/geometry/policy check succeeds.
 storage:=make([]u8,16*1024*1024);defer delete(storage)
 arena:mem.Arena;mem.arena_init(&arena,storage)
 wire:Level_Layout
 if json.unmarshal(data,&wire,allocator=mem.arena_allocator(&arena))!=nil { return {},false,"Invalid version 4 layout JSON" }
 if wire.gameplay_config.version==0&&wire.gameplay_config_id=="bom-default-v1" { wire.gameplay_config=DEFAULT_GAMEPLAY_CONFIG }
 if reason:=level_layout_problem(&wire);reason!="" { return {},false,reason }
 canonical,err:=json.marshal(wire);defer delete(canonical)
 if err!=nil||len(canonical)>NET_APP_MAX_LAYOUT { return {},false,"Canonical level catalog exceeds the 200000-byte upload bound" }
 if json.unmarshal(data,&level)!=nil { destroy_level_layout(&level);return {},false,"Cannot retain validated level layout" }
 if level.gameplay_config.version==0 { level.gameplay_config=wire.gameplay_config }
 return level,true,""
}
