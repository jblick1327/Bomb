package shared
import strings "core:strings"
import math "core:math"

Resolved_Level_Policy :: struct {
 active:bool,
 simulation,kill,camera,aim,fragment_cull:Level_Bounds,
 spawns:[4]Vec2,
 bombs:Level_Bomb_Settings,
 config:Gameplay_Config,
}
level_resolve_policy :: proc(level:^Level_Layout) -> Resolved_Level_Policy {
 out:=Resolved_Level_Policy{active=true,simulation=level.simulation_bounds,kill=level.kill_bounds,camera=level.camera_bounds,aim=level.aim_bounds,fragment_cull=level.fragment_cull_bounds,bombs=level.bombs}
 out.config=level.gameplay_config;copy(out.spawns[:],level.spawns[:]);return out
}
decode_unity_layout :: proc(data:[]u8) -> (layout:Layout,seed:u8,ok:bool,problem:string) {
 level,valid,reason:=decode_level_layout(data);if !valid { return {},0,false,reason }
 layout.level=new(Level_Layout);layout.level^=level;layout.next_identity=level.next_identity
 for m in level.materials { base,_:=material_base_name(m.base);custom:=custom_from_wire(m,base);custom.name=strings.clone(m.name);append(&layout.materials,custom) }
 // Construct and bound the deterministic geometry before accepting an upload
 // or creating a physics world. The old world survives a rejected layout.
 preview:=World{scene=new_scene(WOOD_MINIMUM_WIDTH),settings=DEFAULT_SANDBOX_SETTINGS};preview.settings.seed=u8(level.seed)
 world_build_level(&preview,&layout,false);defer scene_destroy(&preview.scene)
 if preview.rebuild_error!="" { reason:=preview.rebuild_error;destroy_layout(&layout);return {},0,false,reason }
 return layout,u8(level.seed),true,""
}
scene_apply_level :: proc(s:^Scene,level:^Level_Layout) {
 s.level_policy=level_resolve_policy(level)
 s.gameplay_manifest=level_gameplay_hash(level);s.config_hash=gameplay_config_hash(level.gameplay_config)
 bytes,encoded:=exact_json_encode(level^,false);assert(encoded);assert(len(bytes)<=NET_APP_MAX_LAYOUT)
 s.level_json=transmute(string)bytes
 copy,valid,_:=decode_level_layout(bytes);assert(valid);s.catalog=new(Level_Layout);s.catalog^=copy
 for source in level.sources { for part in source.parts {
  anchors:=Source_Part_Anchors{source_identity=source.identity,source_part_id=part.part_id};append(&anchors.segments,..part.anchors[:]);append(&s.source_parts,anchors)
 } }
}
level_part_material :: proc(layout:^Layout,key:string) -> Slot { for i in 0..<palette_count(layout) { if layout_material(layout,Slot(i)).name==key { return Slot(i) } };panic("Unvalidated level material") }
build_level_part :: proc(s:^Scene,outline:Polygon,owner:u64,rubber:bool) {
 if !rubber { _=add_subdivision(s,owner,outline,Pose{position=centroid(outline)});presplit_piece(s,owner);return }
 lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30};for p in outline.points { lo={min(lo.x,p.x),min(lo.y,p.y)};hi={max(hi.x,p.x),max(hi.y,p.y)} }
 nx,ny:=max(1,int(math.ceil((hi.x-lo.x)/RUBBER_CELL_SIZE))),max(1,int(math.ceil((hi.y-lo.y)/RUBBER_CELL_SIZE)))
 assert(nx*ny<=100000)
 convex:=convex_decomposition(outline);defer { for p in convex { delete(p.points) };delete(convex) }
 ids:[dynamic]u64;defer delete(ids)
 for row in 0..<ny { for col in 0..<nx {
  x0,x1:=lo.x+(hi.x-lo.x)*f32(col)/f32(nx),lo.x+(hi.x-lo.x)*f32(col+1)/f32(nx)
  y0,y1:=lo.y+(hi.y-lo.y)*f32(row)/f32(ny),lo.y+(hi.y-lo.y)*f32(row+1)/f32(ny)
  vertices:=[4]Vec2{{x0,y0},{x1,y0},{x1,y1},{x0,y1}}
  cells:[dynamic]Polygon
  for piece in convex { clipped:=convex_intersection(Polygon{vertices[:]},piece);if len(clipped.points)>=3&&polygon_area(clipped)>1e-8 { append(&cells,clipped) }else{delete(clipped.points)} }
  for {
   joined:=false
   for i in 0..<len(cells) { for j in i+1..<len(cells) {
    if length,_:=shared_boundary(cells[i],cells[j]);length<=.00001 { continue }
    merged:=polygon_union_touching(cells[i],cells[j]);delete(cells[i].points);delete(cells[j].points);cells[i]=merged;ordered_remove(&cells,j);joined=true;break
   };if joined { break } };if !joined { break }
  }
  for cell in cells { id:=add_subdivision(s,owner,cell,Pose{position=centroid(cell)});for other in ids { _=add_connection(s,other,id) };append(&ids,id);delete(cell.points) };delete(cells)
 } }
}
world_build_level :: proc(w:^World,layout:^Layout,editing:bool) {
 s:=&w.scene;level:=layout.level;scene_apply_level(s,level)
 materials:[8]int;for i in 0..<palette_count(layout) { material:=layout_material(layout,Slot(i));material.name=strings.clone(material.name);append(&s.owned_names,material.name);materials[i]=add_material(s,material) }
 if editing { return }
 for source in level.sources { for part in source.parts {
  slot:=level_part_material(layout,part.material);rubber:=layout_base(layout,slot)==.Rubber
  seed:=derive_seed(w.settings.seed,source.identity~part.part_id);if rubber { seed=0 }
  owner:=add_piece(s,materials[int(slot)],seed);first_id:=s.next_id+1
  build_level_part(s,Polygon{part.outline[:]},owner,rubber)
  if len(s.subdivisions)>REPL_MAX_CELLS {w.rebuild_error="Constructed level exceeds the unchanged 100000-cell native capacity";return}
  motion:=Motion_Policy.Dynamic;if source.motion=="fixed" { motion=.Fixed };if source.motion=="anchored" { motion=.Anchored }
  damage:=Damage_Policy.Destructible;if source.damage=="indestructible" { damage=.Indestructible }
  for &sub in s.subdivisions { if sub.id<first_id { continue };sub.provenance={source.identity,part.part_id,motion,damage,false};cell_resolve_pin(s,sub.id) }
 } }
 index:=level_part_cell_index(s);defer level_part_cell_index_destroy(&index)
 for link in level.glue { _=level_glue_link(s,&index,link,true) }
}
Level_Part_Cell_Index :: map[Level_Part_Key][dynamic]int
// Row numbers of the live cells of each authored part, in scene order (same order a full scan would visit).
level_part_cell_index :: proc(s:^Scene) -> Level_Part_Cell_Index {
 index:Level_Part_Cell_Index
 for sub,row in s.subdivisions {
  if !sub.live { continue }
  key:=Level_Part_Key{sub.provenance.source_identity,sub.provenance.source_part_id}
  rows:=index[key];append(&rows,row);index[key]=rows
 }
 return index
}
level_part_cell_index_destroy :: proc(index:^Level_Part_Cell_Index) { for _,rows in index { delete(rows) };delete(index^) }
// Applies (add) or only counts (!add) the glue samples of one authored link.
// A link joins every cell of part A to every touching cell of part B; the
// returned total is the number of samples that actually took effect.
// P1 (2026-11-24): a pair whose bounding boxes are further apart than GLUE_FILLET can produce no sample
// (glue_side only hits within GLUE_FILLET of a sample point on the boundary), so it is skipped before
// glue_samples. Same samples, same order, same connection ids; round restarts no longer test every cell pair.
LEVEL_GLUE_REACH :: GLUE_FILLET+0.05
level_glue_link :: proc(s:^Scene,index:^Level_Part_Cell_Index,link:Level_Glue,add:bool) -> int {
 total:=0
 rows_b:=index[link.b]
 bounds_b:=make([][2]Vec2,len(rows_b));defer delete(bounds_b)
 for row_b,i in rows_b { lo,hi:=mortar_bounds(s.subdivisions[row_b].outline);bounds_b[i]={lo,hi} }
 for row_a in index[link.a] {
  a:=s.subdivisions[row_a]
  alo,ahi:=mortar_bounds(a.outline)
  for row_b,i in rows_b {
   blo,bhi:=bounds_b[i][0],bounds_b[i][1]
   if blo.x>ahi.x+LEVEL_GLUE_REACH || alo.x>bhi.x+LEVEL_GLUE_REACH || blo.y>ahi.y+LEVEL_GLUE_REACH || alo.y>bhi.y+LEVEL_GLUE_REACH { continue }
   b:=s.subdivisions[row_b]
   samples:=glue_samples(a.outline,b.outline);total+=len(samples)
   if add { _=glue_add(s,a.id,b.id,samples[:]) }
   delete(samples)
  }
 }
 return total
}
