package main

import "core:math"
import "core:slice"
import rl "vendor:raylib"

Film_Vertex :: struct { cell: u64, index: int }
Film_Segment :: struct { a,b: Film_Vertex, span: bool }
Rubber_Band :: struct { revision: u64, hull: [dynamic]Vec2, segments: [dynamic]Film_Segment }
release_rubber_band :: proc(band: ^Rubber_Band) { delete(band.hull); delete(band.segments); band^={} }
film_rest :: proc(caches: ^Render_Cache_State,p: Film_Vertex) -> Vec2 { return caches.cells[p.cell].outline.points[p.index] }

// Monotone chain with duplicate and collinear points excluded. The hull and
// all film endpoints retain the original cache-outline coordinates.
rubber_rest_hull :: proc(points: []Vec2) -> [dynamic]Vec2 {
 sorted:=make([dynamic]Vec2); append(&sorted,..points); defer delete(sorted)
 slice.sort_by(sorted[:],proc(a,b: Vec2) -> bool { return a.x<b.x || a.x==b.x && a.y<b.y })
 unique:[dynamic]Vec2; defer delete(unique)
 for p in sorted { if len(unique)==0 || p!=unique[len(unique)-1] { append(&unique,p) } }
 hull:[dynamic]Vec2
 if len(unique)<3 { append(&hull,..unique[:]); return hull }
 for p in unique {
  for len(hull)>=2 && polygon_turn(hull[len(hull)-2],hull[len(hull)-1],p)<=0 { resize(&hull,len(hull)-1) }
  append(&hull,p)
 }
 lower:=len(hull)
 for i:=len(unique)-2; i>=0; i-=1 {
  p:=unique[i]
  for len(hull)>lower && polygon_turn(hull[len(hull)-2],hull[len(hull)-1],p)<=0 { resize(&hull,len(hull)-1) }
  append(&hull,p)
 }
 resize(&hull,len(hull)-1)
 return hull
}
rubber_on_segment :: proc(p,a,b: Vec2) -> bool {
 edge:=vsub(b,a); length:=vlen(edge)
 return length>0 && math.abs(vcross(edge,vsub(p,a)))<=1e-5*length && vdot(vsub(p,a),edge)>=-1e-5*length && vdot(vsub(p,b),edge)<=1e-5*length
}

ensure_rubber_band :: proc(s: ^Scene,caches: ^Render_Cache_State,owner: u64) {
 revision:=s.pieces[s.piece_rows[owner]].render_revision
 if band,ok:=caches.bands[owner]; ok && band.revision==revision { return }
 if caches.bands==nil { caches.bands=make(map[u64]Rubber_Band) }
 if _,exists:=caches.bands[owner]; !exists { caches.bands[owner]=Rubber_Band{} }
 band:=&caches.bands[owner]; release_rubber_band(band); band.revision=revision
 points:[dynamic]Vec2; defer delete(points)
 vertices:=make(map[Vec2]Film_Vertex); defer delete(vertices)
 film:[dynamic]Film_Segment; defer delete(film)
 ids:=sorted_ids(s.pieces[s.piece_rows[owner]].subdivisions[:]); defer delete(ids)
 for id in ids {
  if !is_live_subdivision(s,id) { continue }
  cache:=&caches.cells[id]
  for p,i in cache.outline.points {
   append(&points,p)
   if _,exists:=vertices[p]; !exists { vertices[p]={id,i} }
   if cache.draw_edge[i] { append(&film,Film_Segment{{id,i},{id,(i+1)%len(cache.outline.points)},false}) }
  }
 }
 band.hull=rubber_rest_hull(points[:])
 Contact :: struct { segment: Film_Segment, lo,hi: Film_Vertex, start,end: f32 }
 for a,i in band.hull {
  b:=band.hull[(i+1)%len(band.hull)]; edge:=vsub(b,a); length:=vlen(edge)
  contacts:[dynamic]Contact
  for segment in film {
   p,q:=film_rest(caches,segment.a),film_rest(caches,segment.b)
   if !rubber_on_segment(p,a,b) || !rubber_on_segment(q,a,b) { continue }
   lo,hi:=segment.a,segment.b
   start,end:=vdot(vsub(p,a),edge)/(length*length),vdot(vsub(q,a),edge)/(length*length)
   if start>end { start,end=end,start; lo,hi=hi,lo }
   append(&contacts,Contact{segment,lo,hi,start,end})
  }
  slice.sort_by(contacts[:],proc(a,b: Contact) -> bool {
   if a.start!=b.start { return a.start<b.start }
   if a.segment.a.cell!=b.segment.a.cell { return a.segment.a.cell<b.segment.a.cell }
   return a.segment.a.index<b.segment.a.index
  })
  cursor:=f32(0); endpoint:=vertices[a]; tolerance:=f32(1e-5)/length
  for contact in contacts {
   if contact.start>cursor+tolerance { append(&band.segments,Film_Segment{endpoint,contact.lo,true}) }
   // Keep every contact segment, its orientation, and its round joins exactly
   // as in the cell film. Only uncovered stretches become single spans.
   append(&band.segments,contact.segment)
   if contact.end>cursor { cursor=contact.end; endpoint=contact.hi }
  }
  if cursor<1-tolerance { append(&band.segments,Film_Segment{endpoint,vertices[b],true}) }
  delete(contacts)
 }
}

draw_rubber_bands :: proc(s: ^Scene,caches: ^Render_Cache_State,view: View,outlines: []Polygon,ids: []u64,selected: u64,width: f32) {
 rows:=make(map[u64]int); defer delete(rows)
 for id,i in ids { rows[id]=i }
 for piece in s.pieces {
  if !piece.live || s.materials[piece.material].flexibility<=0 { continue }
  band:=&caches.bands[piece.id]
  positions:=make(map[Vec2]Vec2)
  cells:=sorted_ids(piece.subdivisions[:])
  for id in cells {
   if !is_live_subdivision(s,id) { continue }
   cache:=&caches.cells[id]; outline:=outlines[rows[id]]
   for rest,i in cache.outline.points { if _,exists:=positions[rest]; !exists { positions[rest]=outline.points[i] } }
  }
  for segment in band.segments {
   color:=FILM_COLOR; if segment.a.cell==selected { color=rl.WHITE }
   draw_film_segment(view,positions[film_rest(caches,segment.a)],positions[film_rest(caches,segment.b)],color,width)
  }
  delete(cells); delete(positions)
 }
}
draw_film_segment :: proc(view: View,a,b: Vec2,color: rl.Color,width: f32) {
 pixels:=max(FILM_PX,width)
 p,q:=screen_point(view,a),screen_point(view,b)
 rl.DrawLineEx(p,q,pixels,color)
 rl.DrawCircleV(p,pixels*0.5,color); rl.DrawCircleV(q,pixels*0.5,color)
}
