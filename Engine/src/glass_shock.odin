package main
import "core:time"

// Ephemeral damage transaction. Its lineage survives spatial refinement and
// provisional regrouping; no shock values or hit sources persist in the World.
Shock_Cell :: struct { group: int, direct,reached: bool, load: f32 }
Shock_Source :: struct { group,material: int, point: Vec2, load: f32 }
Shock_Transaction :: struct {
 groups: map[u64]int,
 cells: map[u64]Shock_Cell,
 sources: [dynamic]Shock_Source,
}
shock_destroy :: proc(shock: ^Shock_Transaction) { delete(shock.groups); delete(shock.cells); delete(shock.sources); shock^={} }
shock_group :: proc(shock: ^Shock_Transaction,s: ^Scene,piece: Piece) -> int {
 if group,ok:=shock.groups[piece.id]; ok { return group }
 if shock.groups==nil { shock.groups=make(map[u64]int); shock.cells=make(map[u64]Shock_Cell) }
 group:=len(shock.groups); shock.groups[piece.id]=group
 for id in piece.subdivisions { if is_live_subdivision(s,id) { shock.cells[id]={group=group} } }
 return group
}
shock_rest_point :: proc(sub: Subdivision,point: Vec2) -> Vec2 { return vadd(sub.rest_center,vrotate(vsub(point,sub.pose.position),-sub.pose.angle)) }
shock_nearest_segment :: proc(point,a,b: Vec2) -> Vec2 {
 edge:=vsub(b,a); squared:=vdot(edge,edge)
 if squared<=0 { return a }
 return vadd(a,vmul(edge,clamp(vdot(vsub(point,a),edge)/squared,f32(0),f32(1))))
}
shock_rest_distance :: proc(point: Vec2,outline: Polygon) -> f32 {
 inside:=false; distance:=f32(1e30)
 for a,i in outline.points {
  b:=outline.points[(i+1)%len(outline.points)]
  distance=min(distance,vlen(vsub(point,shock_nearest_segment(point,a,b))))
  if (a.y>point.y)!=(b.y>point.y) && point.x<(b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x { inside=!inside }
 }
 if inside { return 0 }; return distance
}
shock_begin_blast :: proc(s: ^Scene,blast: Blast) -> Shock_Transaction {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(2,started) }

 shock:=Shock_Transaction{}
 owners:[dynamic]u64; defer delete(owners)
 for p in s.pieces { if p.live && s.materials[p.material].shock_loss>0 { append(&owners,p.id) } }; sort_ids(owners[:])
 for owner in owners {
  piece:=s.pieces[s.piece_rows[owner]]; material:=s.materials[piece.material]
  ids:=sorted_ids(piece.subdivisions[:])
  distance:=f32(1e30); point,rest:Vec2
  for id in ids {
   sub:=s.subdivisions[s.sub_rows[id]]; if !sub.live { continue }
   if point_in_subdivision(sub,blast.position) { point=blast.position; rest=shock_rest_point(sub,point); distance=0; break }
   for a,i in sub.outline.points {
    q:=shock_nearest_segment(blast.position,posed_point(sub,a),posed_point(sub,sub.outline.points[(i+1)%len(sub.outline.points)]))
    d:=vlen(vsub(blast.position,q))
    if d<distance { distance=d; point=q; rest=shock_rest_point(sub,q) }
   }
  }
  delete(ids)
  if blast_load(distance,blast.radius)<material.connection_strength || blast_load(distance,blast.radius)<=0 { continue }
  load:=blast_load(cover_distance(point,blast.position,owner),blast.radius)
  if load<material.connection_strength || load<=0 { continue }
  group:=shock_group(&shock,s,piece)
  append(&shock.sources,Shock_Source{group,piece.material,rest,load})
 }
 return shock
}
shock_begin_impact :: proc(s: ^Scene,failures: Failures) -> Shock_Transaction {
 shock:=Shock_Transaction{}
 if !failures.impact || len(failures.impact_sources)==0 { return shock }
 ids:[dynamic]u64; defer delete(ids)
 sources:=make(map[u64]Impact_Shock_Source); defer delete(sources)
 for source in failures.impact_sources { sources[source.cell]=source; append(&ids,source.cell) }; sort_ids(ids[:])
 for id in ids {
  if !is_live_subdivision(s,id) { continue }
  sub:=s.subdivisions[s.sub_rows[id]]; material:=s.materials[sub.material]; source:=sources[id]
  if material.shock_loss<=0 || source.load<material.connection_strength { continue }
  group:=shock_group(&shock,s,s.pieces[s.piece_rows[sub.owner]])
  append(&shock.sources,Shock_Source{group,sub.material,shock_rest_point(sub,source.point),source.load})
 }
 return shock
}
shock_mark_direct :: proc(shock: ^Shock_Transaction,id: u64) {
 if shock==nil { return }
 if cell,ok:=shock.cells[id]; ok { cell.direct=true; shock.cells[id]=cell }
}
shock_inherit :: proc(shock: ^Shock_Transaction,parent,child: u64) {
 if shock==nil { return }
 // A new child has not itself failed directly. Only its ancestry and any
 // already-computed shock travel with it; the shock failure pass is one wave.
 if cell,ok:=shock.cells[parent]; ok { cell.direct=false; shock.cells[child]=cell }
}

Shock_Queue_Entry :: struct { cost: f32, id: u64 }
shock_before :: proc(a,b: Shock_Queue_Entry) -> bool { return a.cost<b.cost || a.cost==b.cost && a.id<b.id }
shock_queue_push :: proc(queue: ^[dynamic]Shock_Queue_Entry,item: Shock_Queue_Entry) {
 append(queue,item); i:=len(queue^)-1
 for i>0 { parent:=(i-1)/2; if !shock_before(queue^[i],queue^[parent]) { break }; queue^[i],queue^[parent]=queue^[parent],queue^[i]; i=parent }
}
shock_queue_pop :: proc(queue: ^[dynamic]Shock_Queue_Entry) -> Shock_Queue_Entry {
 item:=queue^[0]; queue^[0]=queue^[len(queue^)-1]; resize(queue,len(queue^)-1); i:=0
 for {
  child:=i*2+1; if child>=len(queue^) { break }
  if child+1<len(queue^) && shock_before(queue^[child+1],queue^[child]) { child+=1 }
  if !shock_before(queue^[child],queue^[i]) { break }
  queue^[i],queue^[child]=queue^[child],queue^[i]; i=child
 }
 return item
}
shock_travel :: proc(s: ^Scene,shock: ^Shock_Transaction,source: Shock_Source) {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(2,started) }

 ids:[dynamic]u64; defer delete(ids)
 distances:=make(map[u64]f32); defer delete(distances)
 nearest:=f32(1e30)
 for id,cell in shock.cells {
  if cell.group!=source.group || !is_live_subdivision(s,id) { continue }
  sub:=s.subdivisions[s.sub_rows[id]]; if sub.material!=source.material { continue }
  distance:=shock_rest_distance(source.point,sub.outline); distances[id]=distance
  append(&ids,id); nearest=min(nearest,distance)
 }
 sort_ids(ids[:])
 costs:=make(map[u64]f32); defer delete(costs)
 queue:[dynamic]Shock_Queue_Entry; defer delete(queue)
 for id in ids {
  sub:=s.subdivisions[s.sub_rows[id]]
  if distances[id]<=nearest+0.5 {
   cost:=vlen(vsub(source.point,sub.rest_center)); costs[id]=cost; shock_queue_push(&queue,Shock_Queue_Entry{cost,id})
  }
 }
 for len(queue)>0 {
  entry:=shock_queue_pop(&queue)
  if costs[entry.id]!=entry.cost { continue }
  sub:=s.subdivisions[s.sub_rows[entry.id]]
  cell:=shock.cells[entry.id]; load:=source.load-s.materials[source.material].shock_loss*entry.cost
  if !cell.reached || load>cell.load { cell.reached=true; cell.load=load; shock.cells[entry.id]=cell }
  links:=sorted_ids(sub.incident_links[:])
  for id in links {
   link:=s.connections[s.conn_rows[id]]; if !link.live || link.mortar { continue }
   other:=link.a; if other==sub.id { other=link.b }
   next,ok:=shock.cells[other]
   if !ok || next.group!=source.group || !is_live_subdivision(s,other) { continue }
   neighbour:=s.subdivisions[s.sub_rows[other]]; if neighbour.material!=source.material { continue }
   cost:=entry.cost+vlen(vsub(sub.rest_center,neighbour.rest_center))
   if previous,seen:=costs[other]; !seen || cost<previous { costs[other]=cost; shock_queue_push(&queue,Shock_Queue_Entry{cost,other}) }
  }
  delete(links)
 }
}
shock_apply :: proc(s: ^Scene,shock: ^Shock_Transaction,affected: ^map[u64]bool,impact: bool) -> bool {
 if len(shock.sources)==0 { return false }
 for source in shock.sources { shock_travel(s,shock,source) }
 ids:[dynamic]u64; defer delete(ids)
 for id in shock.cells { if is_live_subdivision(s,id) { append(&ids,id) } }; sort_ids(ids[:])
 failures:=Failures{impact=impact,no_sibling_bonds=true}; defer free_failures(&failures)
 for id in ids {
  cell:=shock.cells[id]; sub:=s.subdivisions[s.sub_rows[id]]
  if cell.reached && !cell.direct && fails(cell.load,s.materials[sub.material].subdivision_strength) { append(&failures.subdivisions,id) }
 }
 when BOM_PROFILE { if blast_profile!=nil { blast_profile.counts[1]+=len(failures.subdivisions) } }
 changed:=len(failures.subdivisions)>0
 // One wave only. Children inherit their parent's load and lineage, but are
 // never submitted to a second shock failure or a direct-blast recursion.
 when BOM_PROFILE { staging_start:=time.tick_now() }
 stage_failures(s,failures,affected,false,0,shock)
 when BOM_PROFILE { profile_add(3,staging_start); bond_start:=time.tick_now(); defer profile_add(4,bond_start) }
 clear(&ids)
 links:=make(map[u64]bool); defer delete(links)
 for id,cell in shock.cells { if cell.reached && is_live_subdivision(s,id) { for link in s.subdivisions[s.sub_rows[id]].incident_links { links[link]=true } } }
 for id in links { if s.connections[s.conn_rows[id]].live { append(&ids,id) } }; sort_ids(ids[:])
 for id in ids {
  c:=s.connections[s.conn_rows[id]]; if c.mortar { continue }; a,a_ok:=shock.cells[c.a]; b,b_ok:=shock.cells[c.b]
  if !a_ok || !b_ok || !a.reached || !b.reached || a.group!=b.group { continue }
  left,right:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
  if !left.live || !right.live || left.material!=right.material || s.materials[left.material].shock_loss<=0 { continue }
  if fails(min(a.load,b.load),s.materials[left.material].connection_strength) {
   s.connections[s.conn_rows[id]].live=false; affected^[left.owner]=true; changed=true
  }
 }
 return changed
}
