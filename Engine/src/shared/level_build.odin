package shared
import json "core:encoding/json"
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
 return layout,u8(level.seed),true,""
}
scene_apply_level :: proc(s:^Scene,level:^Level_Layout) {
 s.level_policy=level_resolve_policy(level)
 s.gameplay_manifest=level_gameplay_hash(level);s.config_hash=gameplay_config_hash(level.gameplay_config)
 bytes,err:=json.marshal(level^);assert(err==nil);assert(len(bytes)<=NET_APP_MAX_LAYOUT)
 s.level_json=transmute(string)bytes
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
  motion:=Motion_Policy.Dynamic;if source.motion=="fixed" { motion=.Fixed };if source.motion=="anchored" { motion=.Anchored }
  damage:=Damage_Policy.Destructible;if source.damage=="indestructible" { damage=.Indestructible }
  for &sub in s.subdivisions { if sub.id<first_id { continue };sub.provenance={source.identity,part.part_id,motion,damage,false};cell_resolve_pin(s,sub.id) }
 } }
 for link in level.glue {
  for a in s.subdivisions {
   if !a.live||a.provenance.source_identity!=link.a.source_identity||a.provenance.source_part_id!=link.a.part_id { continue }
   for b in s.subdivisions {
    if !b.live||b.provenance.source_identity!=link.b.source_identity||b.provenance.source_part_id!=link.b.part_id { continue }
    samples:=glue_samples(a.outline,b.outline);_=glue_add(s,a.id,b.id,samples[:]);delete(samples)
   }
  }
 }
}
