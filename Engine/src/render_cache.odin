package main
import "core:time"

import rl "vendor:raylib"
import "core:math"
import "core:slice"

SKIN_SPACING :: f32(0.1)
SKIN_RADIUS :: f32(0.5)
FILM_PX :: f32(3)
FILM_COLOR :: rl.Color{105,73,120,255}

Skin_Weight :: struct { id: u64, weight: f32 }
Skin_Cell :: struct { id: u64, outline: Polygon, lo,hi: Vec2, neighbours: [dynamic]int }
Skin_Pose :: struct { pose: Pose, rest_center: Vec2 }
Render_Cache :: struct {
	owner,revision: u64,
 anchored: bool,
	outline: Polygon,
	triangles: [dynamic]int,
 draw_edge: []bool,
	weights: [][dynamic]Skin_Weight,
 hub: Vec2,
 hub_weights: [dynamic]Skin_Weight,
 hub_fan: bool,
}
Render_Caches :: map[u64]Render_Cache
// Structural index of anchored pieces for presentation: no physics involved.
// Rebuilt whenever Scene.structure_revision changes.
STATIC_GRID :: f32(1)
Static_Index :: struct {
 valid: bool,
 revision: u64,
 anchored: map[u64]bool,
 grid: map[[2]i32][dynamic]u64,
 bounds: map[u64][4]f32,
}
static_index_release :: proc(idx: ^Static_Index) {
 delete(idx.anchored); delete(idx.bounds)
 for _,ids in idx.grid { delete(ids) }; delete(idx.grid)
 idx^={}
}
static_index_refresh :: proc(s: ^Scene,idx: ^Static_Index) {
 if idx.valid && idx.revision==s.structure_revision { return }
 static_index_release(idx)
 idx.anchored=make(map[u64]bool); idx.bounds=make(map[u64][4]f32); idx.grid=make(map[[2]i32][dynamic]u64)
 idx.valid=true; idx.revision=s.structure_revision
 for p in s.pieces { if p.live && piece_anchored(s,p.id,s.anchor_y) { idx.anchored[p.id]=true } }
 if len(idx.anchored)==0 { return }
 for sub in s.subdivisions {
  if !sub.live || !idx.anchored[sub.owner] { continue }
  lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
  for p in sub.outline.points { lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)} }
  idx.bounds[sub.id]={lo.x,lo.y,hi.x,hi.y}
  for gx in i32(math.floor(lo.x/STATIC_GRID))..=i32(math.floor(hi.x/STATIC_GRID)) {
   for gy in i32(math.floor(lo.y/STATIC_GRID))..=i32(math.floor(hi.y/STATIC_GRID)) {
    key:=[2]i32{gx,gy}; list:=idx.grid[key]; append(&list,sub.id); idx.grid[key]=list
   }
  }
 }
}
Render_Cache_State :: struct {
	cells: Render_Caches,
 statics: Static_Index,
 bands: map[u64]Rubber_Band,
	structure_revision,static_render_revision,static_render_signature: u64,
	initialized: bool,
}
release_render_caches :: proc(caches: ^Render_Cache_State) {
	for id in caches.cells { release_render_cache(&caches.cells[id]) }
 for id in caches.bands { release_rubber_band(&caches.bands[id]) }; delete(caches.bands)
	delete(caches.cells); static_index_release(&caches.statics); caches^={}
}
// This is the only phase that may insert cache entries. Complete it before
// taking any cache pointer: an insertion can move the map's value storage.
render_cache_prepass :: proc(s: ^Scene,caches: ^Render_Cache_State) {
 when BOM_FRAME_BENCH { frame_start:=time.tick_now(); defer { if frame_measuring { frame_cache_ms+=frame_ms(frame_start) } } }

	if !caches.initialized || caches.structure_revision!=s.structure_revision {
		when ODIN_TEST { render_signature_test_calls+=1 }
		// Same signature rule formerly used by physics_sync_structure.
		signature:=u64(0)
		static_index_refresh(s,&caches.statics)
		for p in s.pieces {
			if len(p.subdivisions)==0 { continue }
			if caches.statics.anchored[p.id] { signature+=p.id*0x9e3779b185ebca87+(p.render_revision+1)*0xc2b2ae3d27d4eb4f }
		}
		if signature!=caches.static_render_signature { caches.static_render_signature=signature; caches.static_render_revision+=1 }
		dead: [dynamic]u64
		for id in caches.cells { if !is_live_subdivision(s,id) { append(&dead,id) } }
		for id in dead { release_render_cache(&caches.cells[id]); delete_key(&caches.cells,id) }
		delete(dead)
  dead_bands:[dynamic]u64
  for id in caches.bands {
   row,exists:=s.piece_rows[id]
   if !exists || !s.pieces[row].live || s.materials[s.pieces[row].material].flexibility<=0 { append(&dead_bands,id) }
  }
  for id in dead_bands { release_rubber_band(&caches.bands[id]); delete_key(&caches.bands,id) }; delete(dead_bands)
		caches.structure_revision=s.structure_revision; caches.initialized=true
	}
	for sub in s.subdivisions { if sub.live { ensure_render_cache(s,caches,sub.id) } }
 // Cell-map insertions are complete before bands borrow any cell data.
 for piece in s.pieces {
  if piece.live && len(piece.subdivisions)>0 && s.materials[piece.material].flexibility>0 { ensure_rubber_band(s,caches,piece.id) }
 }
}
release_render_cache :: proc(cache: ^Render_Cache) {
	delete(cache.outline.points); delete(cache.triangles); delete(cache.draw_edge)
	for weights in cache.weights { delete(weights) }
	delete(cache.weights); delete(cache.hub_weights); cache^={}
}

fill_point :: proc(outline: Polygon,hub: Vec2,index: int) -> Vec2 {
 if index==len(outline.points) { return hub }
 return outline.points[index]
}
fill_cross :: proc(a,b,c: Vec2) -> f64 {
 return (f64(b.x)-f64(a.x))*(f64(c.y)-f64(a.y))-(f64(b.y)-f64(a.y))*(f64(c.x)-f64(a.x))
}
skin_hub_fan_valid :: proc(outline: Polygon,hub: Vec2) -> bool {
 orientation:f64
 for a,i in outline.points { orientation+=fill_cross(outline.points[0],a,outline.points[(i+1)%len(outline.points)]) }
 if orientation==0 { return false }
 for a,i in outline.points {
  if fill_cross(hub,a,outline.points[(i+1)%len(outline.points)])*orientation<=0 { return false }
 }
 return true
}
skin_render_point :: proc(rest: Vec2,weights: []Skin_Weight,candidates: map[u64]Skin_Pose) -> Vec2 {
 point:=Vec2{}
 for weight in weights {
  candidate:=candidates[weight.id]
  posed:=vadd(candidate.pose.position,vrotate(vsub(rest,candidate.rest_center),candidate.pose.angle))
  point=vadd(point,vmul(posed,weight.weight))
 }
 return point
}

skin_outline :: proc(outline: Polygon) -> Polygon {
 points:[dynamic]Vec2; defer delete(points)
 for a,i in outline.points {
  b:=outline.points[(i+1)%len(outline.points)]
  lo,hi:=a,b; forward:=a.x<b.x || a.x==b.x && a.y<b.y
  if !forward { lo,hi=b,a }
  n:=max(1,int(math.ceil(vlen(vsub(hi,lo))/SKIN_SPACING)))
  append(&points,a)
  for k in 1..<n {
   index:=k; if !forward { index=n-k }
   append(&points,vadd(lo,vmul(vsub(hi,lo),f32(index)/f32(n))))
  }
 }
 return make_polygon(points[:])
}

// Candidates depend only on the piece's live rest geometry, in cell-ID order.
skin_cells :: proc(s: ^Scene,owner: u64) -> [dynamic]Skin_Cell {
 ids:=sorted_ids(s.pieces[s.piece_rows[owner]].subdivisions[:]); defer delete(ids)
 cells:[dynamic]Skin_Cell
 for id in ids {
  if !is_live_subdivision(s,id) { continue }
  sub:=s.subdivisions[s.sub_rows[id]]
  lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
  for p in sub.outline.points { lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)} }
  append(&cells,Skin_Cell{id=id,outline=sub.outline,lo=vsub(lo,{SKIN_RADIUS,SKIN_RADIUS}),hi=vadd(hi,{SKIN_RADIUS,SKIN_RADIUS})})
 }
 rows:=make(map[u64]int); defer delete(rows)
 for cell,i in cells { rows[cell.id]=i }
 for &cell in cells {
  for id in s.subdivisions[s.sub_rows[cell.id]].incident_links {
   link:=s.connections[s.conn_rows[id]]; if !link.live || link.mortar { continue }
   other:=link.a; if other==cell.id { other=link.b }
   if row,ok:=rows[other]; ok { append(&cell.neighbours,row) }
  }
  slice.sort(cell.neighbours[:])
 }
 return cells
}
release_skin_cells :: proc(cells: [dynamic]Skin_Cell) {
 for cell in cells { delete(cell.neighbours) }; delete(cells)
}

skin_weights :: proc(p: Vec2,cells: []Skin_Cell) -> [dynamic]Skin_Weight {
 weights:[dynamic]Skin_Weight; total:f32
 distances:=make([]f32,len(cells)); defer delete(distances)
 visited:=make([]bool,len(cells)); defer delete(visited)
 frontier,next:[dynamic]int; defer delete(frontier); defer delete(next)
 for cell,row in cells {
  distances[row]=1e30
  if p.x<cell.lo.x || p.x>cell.hi.x || p.y<cell.lo.y || p.y>cell.hi.y { continue }
  inside:=false; distance:=f32(1e30)
  for a,i in cell.outline.points {
   b:=cell.outline.points[(i+1)%len(cell.outline.points)]; edge:=vsub(b,a)
   relative:=vsub(p,a); projection:=vdot(relative,edge)
   t:=clamp(projection/max(vdot(edge,edge),f32(1e-20)),f32(0),f32(1))
   distance=min(distance,vlen(vsub(p,vadd(a,vmul(edge,t)))))
   if vcross(edge,relative)==0 && projection>=0 && projection<=vdot(edge,edge) { distance=0 }
   if (a.y>p.y)!=(b.y>p.y) && p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x { inside=!inside }
  }
  if inside { distance=0 }
  distances[row]=distance
  // All containing cells seed the same search, including shared boundaries.
  if distance==0 { visited[row]=true; append(&frontier,row) }
 }
 for len(frontier)>0 {
  for row in frontier { for neighbour in cells[row].neighbours {
   if !visited[neighbour] && distances[neighbour]<SKIN_RADIUS {
    visited[neighbour]=true; append(&next,neighbour)
   }
  } }
  slice.sort(next[:]); frontier,next=next,frontier; clear(&next)
 }
 // Preserve the original ID-ordered weight arithmetic and normalization.
 for cell,row in cells {
  if !visited[row] { continue }; distance:=distances[row]
  w:=1-distance/SKIN_RADIUS; w*=w
  append(&weights,Skin_Weight{cell.id,w}); total+=w
 }
 assert(total>0,"A skin vertex must be supported by its own rest cell")
 for &weight in weights { weight.weight/=total }
 return weights
}

triangle_indices :: proc(outline: Polygon,fan: bool = false) -> [dynamic]int {
	result: [dynamic]int
 // Keep every subdivided boundary vertex, including collinear rest points.
 if fan { for i in 1..<len(outline.points)-1 { append(&result,0,i,i+1) }; return result }
	triangles:=triangulate_polygon(outline)
	for triangle in triangles {
		for point in triangle.points {
			for vertex,i in outline.points { if point==vertex { append(&result,i); break } }
		}
		delete(triangle.points)
	}
	delete(triangles)
	return result
}
render_static :: proc(s: ^Scene,statics: ^Static_Index,sub: Subdivision) -> bool {
 if statics!=nil { static_index_refresh(s,statics); return statics.anchored[sub.owner] }
 return piece_anchored(s,sub.owner,s.anchor_y)
}
// Structural candidates only: the cell's piece, live non-mortar links and, for an
// anchored cell, cells of other anchored pieces near its rest bounds.
render_together_neighbours :: proc(s: ^Scene,sub: Subdivision,statics_in: ^Static_Index = nil) -> [dynamic]u64 {
 local:Static_Index
 statics:=statics_in
 if statics==nil { statics=&local }
 defer static_index_release(&local)
 static_index_refresh(s,statics)
 anchored:=statics.anchored[sub.owner]
 candidates: [dynamic]u64
 seen:=make(map[u64]bool); defer delete(seen)
 add_candidate :: proc(candidates: ^[dynamic]u64,seen: ^map[u64]bool,s: ^Scene,id: u64) {
  if seen[id] { return }
  seen[id]=true
  if is_live_subdivision(s,id) { append(candidates,id) }
 }
 for link in sub.incident_links {
  c:=s.connections[s.conn_rows[link]]
  if !c.live || c.mortar { continue }
  other:=c.a; if c.a==sub.id { other=c.b }
  add_candidate(&candidates,&seen,s,other)
 }
 if s.materials[sub.material].flexibility<=0 || anchored {
  for id in s.pieces[s.piece_rows[sub.owner]].subdivisions { add_candidate(&candidates,&seen,s,id) }
 }
 if anchored {
  lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
  for p in sub.outline.points { lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)} }
  lo=vsub(lo,{0.05,0.05}); hi=vadd(hi,{0.05,0.05})
  for gx in i32(math.floor(lo.x/STATIC_GRID))..=i32(math.floor(hi.x/STATIC_GRID)) {
   for gy in i32(math.floor(lo.y/STATIC_GRID))..=i32(math.floor(hi.y/STATIC_GRID)) {
    list,found:=statics.grid[[2]i32{gx,gy}]
    if !found { continue }
    for id in list {
     if seen[id] { continue }
     box:=statics.bounds[id]
     if box[2]<lo.x || box[0]>hi.x || box[3]<lo.y || box[1]>hi.y { continue }
     add_candidate(&candidates,&seen,s,id)
    }
   }
  }
 }
 result:[dynamic]u64
 for id in candidates {
  if id==sub.id { continue }
  other:=s.subdivisions[s.sub_rows[id]]
  together:=sub.owner==other.owner && s.materials[sub.material].flexibility==0
  together=together || anchored && statics.anchored[other.owner]
  if c,ok:=s.connection_pairs[pair_key(sub.id,id)]; ok { together=together || (s.connections[s.conn_rows[c]].live && !s.connections[s.conn_rows[c]].mortar) }
  if !together { continue }
  boundaries:=shared_segments(sub.outline,other.outline)
  if len(boundaries)>0 { append(&result,id) }; delete(boundaries)
 }
 delete(candidates); sort_ids(result[:]); return result
}
ensure_render_cache :: proc(s: ^Scene,caches: ^Render_Cache_State,id: u64) -> ^Render_Cache {
	when ODIN_TEST { render_ensure_test_calls+=1 }
	sub:=&s.subdivisions[s.sub_rows[id]]
	if caches.cells==nil { caches.cells=make(Render_Caches) }
	if _,exists:=caches.cells[id]; !exists { caches.cells[id]=Render_Cache{} }
	cache:=&caches.cells[id]
	revision:=s.pieces[s.piece_rows[sub.owner]].render_revision
	static_index_refresh(s,&caches.statics)
	anchored:=render_static(s,&caches.statics,sub^)
 if anchored { revision=caches.static_render_revision }
 if cache.owner==sub.owner && cache.revision==revision && cache.anchored==anchored { return cache }
	release_render_cache(cache)
	cache.owner=sub.owner; cache.revision=revision; cache.anchored=anchored
	cache.outline=make_polygon(sub.outline.points)
 neighbours:=render_together_neighbours(s,sub^,&caches.statics); defer delete(neighbours)
 for other in neighbours { for rest in s.subdivisions[s.sub_rows[other]].outline.points { insert_boundary_endpoint(&cache.outline,rest) } }
 flexible:=s.materials[sub.material].flexibility>0 && !anchored
 if flexible {
  outline:=skin_outline(cache.outline); delete(cache.outline.points); cache.outline=outline
  cells:=skin_cells(s,sub.owner); defer release_skin_cells(cells)
  cache.weights=make([][dynamic]Skin_Weight,len(cache.outline.points))
  for rest,i in cache.outline.points { cache.weights[i]=skin_weights(rest,cells[:]) }
  cache.hub=sub.rest_center
  cache.hub_weights=skin_weights(cache.hub,cells[:])
  cache.hub_fan=skin_hub_fan_valid(cache.outline,cache.hub)
 }
 if cache.hub_fan {
  for i in 0..<len(cache.outline.points) { append(&cache.triangles,len(cache.outline.points),i,(i+1)%len(cache.outline.points)) }
 } else { cache.triangles=triangle_indices(cache.outline,flexible) }
 cache.draw_edge=make([]bool,len(cache.outline.points))
 for a,i in cache.outline.points {
  b:=cache.outline.points[(i+1)%len(cache.outline.points)]
  cache.draw_edge[i]=true
  for other in neighbours {
   neighbour:=s.subdivisions[s.sub_rows[other]]
   if point_on_boundary(vmul(vadd(a,b),0.5),sub.outline,neighbour.outline) { cache.draw_edge[i]=false; break }
  }
 }
	return cache
}
render_outline :: proc(s: ^Scene,caches: ^Render_Cache_State,sub: Subdivision,poses: map[u64]Pose,surface: bool,frames: map[u64]Pose = nil,hub: ^Vec2 = nil) -> Polygon {
	cache:=&caches.cells[sub.id]
 outline:=make_polygon(cache.outline.points)
 if s.materials[sub.material].flexibility==0 {
  frame:=rigid_render_frame(s,sub,poses,frames)
  for rest,i in cache.outline.points { outline.points[i]=rigid_render_point(frame,rest) }
  return outline
 }
 if surface && len(cache.weights)>0 {
  // Resolve each candidate once; retain only the fields needed to pose a point.
  candidates:=make(map[u64]Skin_Pose); defer delete(candidates)
  for weights in cache.weights { for weight in weights {
   if _,found:=candidates[weight.id]; found { continue }
   posed:=render_subdivision(s,s.subdivisions[s.sub_rows[weight.id]],poses)
   candidates[weight.id]={posed.pose,posed.rest_center}
  } }
  for weight in cache.hub_weights {
   if _,found:=candidates[weight.id]; found { continue }
   posed:=render_subdivision(s,s.subdivisions[s.sub_rows[weight.id]],poses)
   candidates[weight.id]={posed.pose,posed.rest_center}
  }
  for rest,i in cache.outline.points {
   outline.points[i]=skin_render_point(rest,cache.weights[i][:],candidates)
  }
  if hub!=nil { hub^=skin_render_point(cache.hub,cache.hub_weights[:],candidates) }
  return outline
 }
 posed:=render_subdivision(s,sub,poses)
 if hub!=nil { hub^=posed_point(posed,cache.hub) }
 for rest,i in cache.outline.points {
  outline.points[i]=posed_point(posed,rest)
 }
 return outline
}
draw_cached_fill :: proc(view: View,outline: Polygon,color: rl.Color,cache: ^Render_Cache,hub: Vec2 = {}) {
	indices:=cache.triangles[:]
	for i:=0; i+2<len(indices); i+=3 {
		a,b,c:=screen_point(view,fill_point(outline,hub,indices[i])),screen_point(view,fill_point(outline,hub,indices[i+1])),screen_point(view,fill_point(outline,hub,indices[i+2]))
		// Near-collinear triangles can flip orientation after screen rounding.
		cross:=(f64(b.x)-f64(a.x))*(f64(c.y)-f64(a.y))-(f64(b.y)-f64(a.y))*(f64(c.x)-f64(a.x))
		if cross<0 { rl.DrawTriangle(a,b,c,color) }
		else { rl.DrawTriangle(c,b,a,color) }
	}
 // Only exposed/cracked boundaries get a fill-coloured seal, even in F3.
 draw_cached_strokes(view,outline,color,1,cache,false)
}
stroke_style :: proc(width: f32,color: rl.Color) -> (f32,rl.Color) {
 if width<=0 { return 0,color }
 if width<1 { tint:=color; tint.a=u8(f32(color.a)*width); return 1,tint }
 return width,color
}
draw_cached_strokes :: proc(view: View,outline: Polygon,color: rl.Color,width: f32,cache: ^Render_Cache,region_outlines: bool) {
 pixels,tint:=stroke_style(width,color)
 if pixels==0 { return }
 for point,i in outline.points {
  if region_outlines || cache.draw_edge[i] { rl.DrawLineEx(screen_point(view,point),screen_point(view,outline.points[(i+1)%len(outline.points)]),pixels,tint) }
 }
}

draw_cached_film :: proc(view: View,outline: Polygon,color: rl.Color,width: f32,cache: ^Render_Cache) {
 pixels:=max(FILM_PX,width)
 for draw,i in cache.draw_edge {
  if !draw { continue }
  a,b:=screen_point(view,outline.points[i]),screen_point(view,outline.points[(i+1)%len(outline.points)])
  rl.DrawLineEx(a,b,pixels,color)
  rl.DrawCircleV(a,pixels*0.5,color); rl.DrawCircleV(b,pixels*0.5,color)
 }
}
