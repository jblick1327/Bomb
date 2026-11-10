#+feature dynamic-literals
package shared

import slice "core:slice"
import time "core:time"
import math "core:math"
import mem "core:mem"

Cover_Edge :: struct { delta:Vec2, squared:f32 }

Cover_Cell :: struct { id,owner:u64, resistance:f32, points:[]Vec2, edges:[]Cover_Edge, lo,hi:Vec2 }

Cover_Cached :: struct { x,y,ox,oy:u32, owner:u64, distance:f32, used:bool }

Cover_Group :: struct { owner:u64, indices:[]int }

Cover_Grid_Entry :: struct { key:Cover_Key, owner:u64, index:int }

Cover_Key :: struct { x,y:int }

Cover :: struct {
 point_storage:[]Vec2, edge_storage:[]Cover_Edge,
 cells:[dynamic]Cover_Cell, owners:map[u64]u64,
 shadow:map[u64]bool,
 grid:map[Cover_Key][]Cover_Group,
 grid_indices:[]int, grid_groups:[dynamic]Cover_Group,
 seen:[]u32, epoch:u32,
 candidates:[dynamic]int, cuts:[dynamic]f32,
 shadow_points,shadow_hull:[dynamic]Vec2,
 clip_a,clip_b:[dynamic]Vec2,
 samples,fast_samples,cache_hits,upper_bound_skips:u64,
 cache:[]Cover_Cached,
 load_limit:f32,
 generation_arena:mem.Dynamic_Arena,
 unpartitionable:map[u64]bool, partition_cache_hits:u64,
 shape_queries:map[u64]Blast_Shape_Query, shape_hits,shape_misses:u64,
}

cover_key :: proc(p:Vec2) -> Cover_Key { return {int(math.floor(p.x)),int(math.floor(p.y))} }

cover_bounds_cross :: proc(a,b,lo,hi:Vec2) -> bool {
 d:=vsub(b,a); enter,exit:=f32(0),f32(1)
 for axis in 0..<2 {
  av,dv,lv,hv:=a.x,d.x,lo.x,hi.x
  if axis==1 { av=a.y; dv=d.y; lv=lo.y; hv=hi.y }
  if dv==0 { if av<lv || av>hv { return false }; continue }
  t,u:=(lv-av)/dv,(hv-av)/dv
  enter=max(enter,min(t,u)); exit=min(exit,max(t,u))
  if enter>exit { return false }
 }; return true
}

cover_candidates :: proc(c:^Cover,lo,hi:Vec2,owner:u64=0,ray:bool=false,origin:Vec2={},point:Vec2={}) {
 clear(&c.candidates)
 if c.grid==nil { for cell,i in c.cells { if cell.owner!=owner { append(&c.candidates,i) } }; return }
 c.epoch+=1
 a,b:=cover_key(lo),cover_key(hi)
 if !ray {
  for x in a.x..=b.x { for y in a.y..=b.y { cover_bucket(c,{x,y},lo,hi,owner,ray,origin,point) } }
 } else {
  key,last:=cover_key(origin),cover_key(point)
  dx,dy:=f64(point.x)-f64(origin.x),f64(point.y)-f64(origin.y)
  sx,sy:=1,1; if dx<0 { sx=-1 }; if dy<0 { sy=-1 }
  limit:=abs(last.x-key.x)+abs(last.y-key.y)+4
  for _ in 0..<limit {
   cover_bucket(c,key,lo,hi,owner,true,origin,point)
   if key==last { break }
   tx,ty:=f64(1e300),f64(1e300)
   if dx!=0 { boundary:=key.x; if sx>0 { boundary+=1 }; tx=(f64(boundary)-f64(origin.x))/dx }
   if dy!=0 { boundary:=key.y; if sy>0 { boundary+=1 }; ty=(f64(boundary)-f64(origin.y))/dy }
   if tx<ty { key.x+=sx } else if ty<tx { key.y+=sy } else {
    cover_bucket(c,{key.x+sx,key.y},lo,hi,owner,true,origin,point)
    cover_bucket(c,{key.x,key.y+sy},lo,hi,owner,true,origin,point)
    key.x+=sx; key.y+=sy
   }
  }
 }
 if ray { slice.sort(c.candidates[:]) }
}

cover_bucket :: proc(c:^Cover,key:Cover_Key,lo,hi:Vec2,owner:u64,ray:bool,origin,point:Vec2) {
 bucket,exists:=c.grid[key]; if !exists { return }
 for group in bucket {
  if group.owner==owner { continue }
  for index in group.indices {
   if c.seen[index]==c.epoch { continue }; c.seen[index]=c.epoch
   cell:=c.cells[index]
   if hi.x<cell.lo.x || lo.x>cell.hi.x || hi.y<cell.lo.y || lo.y>cell.hi.y { continue }
   if ray && !cover_bounds_cross(origin,point,cell.lo,cell.hi) { continue }
   append(&c.candidates,index)
  }
 }
}

cover_polygons_overlap :: proc(a,b:[]Vec2) -> bool {
 for p,i in a { e:=vsub(a[(i+1)%len(a)],p); any_inside:=false
  for q in b { if vcross(e,vsub(q,p))>0 { any_inside=true; break } }
  if !any_inside { return false }
 }
 left,right:[dynamic]Vec2
 if active_cover!=nil { left=active_cover.clip_a; right=active_cover.clip_b }
 defer { if active_cover!=nil { active_cover.clip_a=left; active_cover.clip_b=right } else { delete(left); delete(right) } }
 clear(&left); append(&left,..b)
 for p,i in a {
  clear(&right); e:=vsub(a[(i+1)%len(a)],p)
  for q,j in left {
   r:=left[(j+1)%len(left)]; dq,dr:=vcross(e,vsub(q,p)),vcross(e,vsub(r,p))
   if dq>=0 { append(&right,q) }
   if (dq>0 && dr<0) || (dq<0 && dr>0) { append(&right,vadd(q,vmul(vsub(r,q),dq/(dq-dr)))) }
  }
  left,right=right,left
  if len(left)<3 { return false }
 }
 area:f64
 for p,i in left { q:=left[(i+1)%len(left)]; area+=f64(p.x)*f64(q.y)-f64(p.y)*f64(q.x) }
 return area!=0
}

cover_shadow :: proc(sub:Subdivision,origin:Vec2) -> bool {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(16,started) }
 c:=active_cover; if c==nil { return false }
 if result,ok:=c.shadow[sub.id]; ok { return result }
 points:=c.shadow_points; hull:=c.shadow_hull
 clear(&points); clear(&hull); append(&points,origin)
 lo,hi:=origin,origin
 for p in sub.outline.points { q:=posed_point(sub,p); append(&points,q); lo={min(lo.x,q.x),min(lo.y,q.y)}; hi={max(hi.x,q.x),max(hi.y,q.y)} }
 slice.sort_by(points[:],proc(a,b:Vec2)->bool { return a.x<b.x || a.x==b.x && a.y<b.y })
 for p in points { for len(hull)>=2 && vcross(vsub(hull[len(hull)-1],hull[len(hull)-2]),vsub(p,hull[len(hull)-1]))<=0 { resize(&hull,len(hull)-1) }; append(&hull,p) }
 upper:=len(hull)+1
 for i:=len(points)-2; i>=0; i-=1 { p:=points[i]; for len(hull)>=upper && vcross(vsub(hull[len(hull)-1],hull[len(hull)-2]),vsub(p,hull[len(hull)-1]))<=0 { resize(&hull,len(hull)-1) }; append(&hull,p) }
 if len(hull)>1 { resize(&hull,len(hull)-1) }
 c.shadow_points=points; c.shadow_hull=hull
 owner:=c.owners[sub.id]; cover_candidates(c,lo,hi,owner); result:=false
 for index in c.candidates { cell:=c.cells[index]; if cell.owner!=owner && cover_polygons_overlap(hull[:],cell.points) { result=true; break } }
 c.shadow[sub.id]=result
 return result
}

@(thread_local) active_cover:^Cover

cover_begin :: proc(s:^Scene,load_limit:f32=0,include_zero_resistance_solids:bool=false) -> Cover {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(17,started) }
 c:=Cover{unpartitionable=make(map[u64]bool),load_limit=load_limit,owners=make(map[u64]u64),shadow=make(map[u64]bool),grid=make(map[Cover_Key][]Cover_Group)}
 ids:[dynamic]u64; defer delete(ids)
 for sub in s.subdivisions { if sub.live { append(&ids,sub.id) } }; sort_ids(ids[:])
 total_points:=0
 for id in ids { sub:=s.subdivisions[s.sub_rows[id]]; if include_zero_resistance_solids||s.materials[sub.material].blast_resistance!=0 { total_points+=len(sub.outline.points) } }
 c.point_storage=make([]Vec2,total_points); c.edge_storage=make([]Cover_Edge,total_points); cursor:=0
 for id in ids {
  sub:=s.subdivisions[s.sub_rows[id]]; c.owners[id]=sub.owner
  resistance:=s.materials[sub.material].blast_resistance; if resistance==0&&!include_zero_resistance_solids { continue }
  cell:=Cover_Cell{id=id,owner=sub.owner,resistance=resistance,points=c.point_storage[cursor:cursor+len(sub.outline.points)],edges=c.edge_storage[cursor:cursor+len(sub.outline.points)],lo={1e30,1e30},hi={-1e30,-1e30}}
  for p,i in sub.outline.points { q:=posed_point(sub,p); cell.points[i]=q; cell.lo={min(cell.lo.x,q.x),min(cell.lo.y,q.y)}; cell.hi={max(cell.hi.x,q.x),max(cell.hi.y,q.y)} }
  for a,i in cell.points { edge:=vsub(cell.points[(i+1)%len(cell.points)],a); cell.edges[i]={edge,vdot(edge,edge)} }
  cursor+=len(cell.points)
  append(&c.cells,cell)
 }
 max_points:=0; for sub in s.subdivisions { if sub.live { max_points=max(max_points,len(sub.outline.points)) } }
 c.candidates=make([dynamic]int,0,len(c.cells)); c.cuts=make([dynamic]f32,0,max_points+2)
 c.shadow_points=make([dynamic]Vec2,0,max_points+1); c.shadow_hull=make([dynamic]Vec2,0,2*(max_points+1))
 c.clip_a=make([dynamic]Vec2,0,2*max_points*(max_points+2)+16); c.clip_b=make([dynamic]Vec2,0,2*max_points*(max_points+2)+16)
 c.cache=make([]Cover_Cached,8192)
 c.seen=make([]u32,len(c.cells))
 entries:[dynamic]Cover_Grid_Entry; defer delete(entries)
 for cell,index in c.cells { a,b:=cover_key(cell.lo),cover_key(cell.hi)
  for x in a.x..=b.x { for y in a.y..=b.y { append(&entries,Cover_Grid_Entry{{x,y},cell.owner,index}) } }
 }
 slice.sort_by(entries[:],proc(a,b:Cover_Grid_Entry)->bool {
  if a.key.x!=b.key.x { return a.key.x<b.key.x }; if a.key.y!=b.key.y { return a.key.y<b.key.y }
  if a.owner!=b.owner { return a.owner<b.owner }; return a.index<b.index
 })
 c.grid_indices=make([]int,len(entries)); c.grid_groups=make([dynamic]Cover_Group,0,len(entries))
 for entry,i in entries { c.grid_indices[i]=entry.index }
 start:=0
 for start<len(entries) {
  finish:=start+1
  for finish<len(entries) && entries[finish].key==entries[start].key && entries[finish].owner==entries[start].owner { finish+=1 }
  append(&c.grid_groups,Cover_Group{entries[start].owner,c.grid_indices[start:finish]}); start=finish
 }
 start=0; entry_row:=0
 for start<len(c.grid_groups) {
  key:=entries[entry_row].key; finish:=start
  for finish<len(c.grid_groups) && entries[entry_row].key==key {
   entry_row+=len(c.grid_groups[finish].indices); finish+=1
   if entry_row==len(entries) { break }
  }
  c.grid[key]=c.grid_groups[start:finish]; start=finish
 }

 return c
}

cover_destroy :: proc(c:^Cover) { delete(c.point_storage); delete(c.edge_storage); delete(c.cells); delete(c.owners); delete(c.shadow); delete(c.grid_indices); delete(c.grid_groups); delete(c.grid); delete(c.seen); delete(c.candidates); delete(c.cuts); delete(c.shadow_points); delete(c.shadow_hull); delete(c.clip_a); delete(c.clip_b); delete(c.cache); for _,entry in c.shape_queries { delete(entry.points) }; delete(c.shape_queries); delete(c.unpartitionable); if c.generation_arena.block_allocator.procedure!=nil { mem.dynamic_arena_destroy(&c.generation_arena) } }

cover_distance :: proc(point,origin:Vec2,owner:u64,count_sample:bool=true) -> f32 {
 if count_sample && active_cover!=nil { active_cover.samples+=1 }
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(15,started) }
 delta:=vsub(point,origin); distance:=vlen(delta); ray_length:=distance
 if active_cover==nil || distance==0 { return distance }
 // All resistance is nonnegative. Further cover cannot change a zero load.
 if active_cover.load_limit>0 && distance>=active_cover.load_limit { return distance }
 lo:=Vec2{min(point.x,origin.x),min(point.y,origin.y)}; hi:=Vec2{max(point.x,origin.x),max(point.y,origin.y)}
 c:=active_cover
 cache_slot:=-1
 if len(c.cache)>0 {
  x,y,ox,oy:=transmute(u32)point.x,transmute(u32)point.y,transmute(u32)origin.x,transmute(u32)origin.y
  hash:=u64(x)*0x9e3779b1+u64(y)*0x85ebca77+owner*0xc2b2ae3d+u64(ox)*0x27d4eb2f+u64(oy)
  for probe in 0..<8 {
   slot:=int((hash+u64(probe))&u64(len(c.cache)-1)); entry:=&c.cache[slot]
   if !entry.used { cache_slot=slot; break }
   if entry.x==x && entry.y==y && entry.ox==ox && entry.oy==oy && entry.owner==owner { c.cache_hits+=1; return entry.distance }
  }
 }
 cover_candidates(c,lo,hi,owner,true,origin,point)
 cuts:=c.cuts; defer { c.cuts=cuts }
 for index in c.candidates {
  cell:=c.cells[index]
  if cell.owner==owner || hi.x<cell.lo.x || lo.x>cell.hi.x || hi.y<cell.lo.y || lo.y>cell.hi.y { continue }
  fraction:=cover_ray_fraction(cell,origin,point,&cuts)
  distance+=cell.resistance*ray_length*fraction
  if c.load_limit>0 && distance>=c.load_limit { break }
 }
 if cache_slot>=0 { c.cache[cache_slot]={transmute(u32)point.x,transmute(u32)point.y,transmute(u32)origin.x,transmute(u32)origin.y,owner,distance,true} }
 return distance
}

// Shared geometric chord calculation. Destruction continues to multiply the
// exact same fraction by material resistance; player visibility only asks
// whether a positive interior chord exists. Boundary-only contact is unchanged.
cover_ray_fraction :: proc(cell:Cover_Cell,origin,point:Vec2,scratch:^[dynamic]f32) -> f32 {
 cuts:=scratch^;defer {scratch^=cuts}
 delta:=vsub(point,origin)
 clear(&cuts); append(&cuts,0,1)
 for a,i in cell.points {
  b:=cell.points[(i+1)%len(cell.points)]; edge:=vsub(b,a); if len(cell.edges)>0 { edge=cell.edges[i].delta }; den:=vcross(delta,edge)
  if den==0 { continue }
  t:=vcross(vsub(a,origin),edge)/den; u:=vcross(vsub(a,origin),delta)/den
  if t>0 && t<1 && u>=0 && u<=1 { append(&cuts,t) }
 }
 for i in 1..<len(cuts) { value:=cuts[i]; j:=i; for j>0 && cuts[j-1]>value { cuts[j]=cuts[j-1]; j-=1 }; cuts[j]=value }
 fraction:f32
 for i in 0..<len(cuts)-1 {
  mid:=vadd(origin,vmul(delta,(cuts[i]+cuts[i+1])*0.5)); inside:=false; boundary:=false
  for a,j in cell.points { b:=cell.points[(j+1)%len(cell.points)]; e:=vsub(b,a); squared:=vdot(e,e); if len(cell.edges)>0 { e=cell.edges[j].delta; squared=cell.edges[j].squared }; m:=vsub(mid,a); if vcross(e,m)==0 && vdot(m,e)>=0 && vdot(m,e)<=squared { boundary=true }; if (a.y>mid.y)!=(b.y>mid.y) && mid.x<(b.x-a.x)*(mid.y-a.y)/(b.y-a.y)+a.x { inside=!inside } }
  if inside && !boundary { fraction+=cuts[i+1]-cuts[i] }
 }
 return fraction
}

cover_ray_occluded :: proc(c:^Cover,origin,point:Vec2) -> bool {
 lo:=Vec2{min(point.x,origin.x),min(point.y,origin.y)};hi:=Vec2{max(point.x,origin.x),max(point.y,origin.y)}
 cover_candidates(c,lo,hi,0,true,origin,point)
 for index in c.candidates {if cover_ray_fraction(c.cells[index],origin,point,&c.cuts)>0 {return true}}
 return false
}

cover_sample_distance :: proc(sub:Subdivision,point,origin:Vec2) -> f32 {
 owner:=sub.owner
 if active_cover!=nil {
  active_cover.samples+=1
  geometric:=vlen(vsub(point,origin))
  if active_cover.load_limit>0 && geometric>=active_cover.load_limit { if !cover_shadow(sub,origin) { active_cover.fast_samples+=1 }; return geometric }
  owner=active_cover.owners[sub.id]
  if !cover_shadow(sub,origin) { active_cover.fast_samples+=1; return vlen(vsub(point,origin)) }
 }
 return cover_distance(point,origin,owner,false)
}

cover_external :: proc(sub:Subdivision,origin:Vec2) -> bool {
 return cover_shadow(sub,origin)
}

cover_foreign_any :: proc(sub:Subdivision) -> bool {
 if active_cover==nil { return false }
 owner:=active_cover.owners[sub.id]
 for cell in active_cover.cells { if cell.owner!=owner { return true } }; return false
}

cover_failure_distance :: proc(sub:Subdivision,point:Vec2,blast:Blast,strength:f32) -> f32 {
 distance:=vlen(vsub(point,blast.position))
 if !fails(blast_load(distance,blast.radius),strength) {
  if active_cover!=nil { active_cover.samples+=1; active_cover.upper_bound_skips+=1; if !cover_shadow(sub,blast.position) { active_cover.fast_samples+=1 } }
  return distance
 }
 return cover_sample_distance(sub,point,blast.position)
}
