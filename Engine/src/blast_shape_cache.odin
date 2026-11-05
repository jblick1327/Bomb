package main
@(thread_local) blast_scratch_active:bool
// Validation repeatedly asks the same pure questions while generating, staging
// and installing one polygon. Cache exact ordered f32 inputs for this blast only.
Blast_Shape_Query :: struct {
 points:[]Vec2,
 width:f32,
 width_known,simple_known,simple:bool,
}
blast_shape_key :: proc(points:[]Vec2) -> u64 {
 hash:=u64(14695981039346656037)
 for p in points { hash=(hash~u64(transmute(u32)p.x))*1099511628211; hash=(hash~u64(transmute(u32)p.y))*1099511628211 }
 return hash~u64(len(points))
}
blast_shape_entry :: proc(points:[]Vec2) -> (u64,Blast_Shape_Query) {
 c:=active_cover
 if c.shape_queries==nil { c.shape_queries=make(map[u64]Blast_Shape_Query) }
 key:=blast_shape_key(points); entry,ok:=c.shape_queries[key]
 if ok && len(entry.points)==len(points) {
  equal:=true
  for p,i in points { q:=entry.points[i]; if transmute(u32)p.x!=transmute(u32)q.x || transmute(u32)p.y!=transmute(u32)q.y { equal=false; break } }
  if equal { return key,entry }
 }
 if ok { delete(entry.points) }
 clone:=make([]Vec2,len(points)); copy(clone,points)
 return key,Blast_Shape_Query{points=clone}
}
blast_cached_width :: proc(points:[]Vec2) -> f32 {
 key,entry:=blast_shape_entry(points)
 if entry.width_known { active_cover.shape_hits+=1; return entry.width }
 active_cover.shape_misses+=1; entry.width=outline_width_uncached(points); entry.width_known=true
 active_cover.shape_queries[key]=entry; return entry.width
}
blast_cached_simple :: proc(p:Polygon) -> bool {
 key,entry:=blast_shape_entry(p.points)
 if entry.simple_known { active_cover.shape_hits+=1; return entry.simple }
 active_cover.shape_misses+=1; entry.simple=simple_polygon_uncached(p); entry.simple_known=true
 active_cover.shape_queries[key]=entry; return entry.simple
}
