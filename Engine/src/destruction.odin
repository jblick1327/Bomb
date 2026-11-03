#+feature dynamic-literals
package main

import "core:math"

polygon_area :: proc(p: Polygon) -> f32 {
	a: f32
	for i in 0..<len(p.points) { a += vcross(p.points[i],p.points[(i+1)%len(p.points)]) }
	return math.abs(a)*0.5
}
clip_polygon :: proc(p: Polygon, axis: int, cut: f32, keep_low: bool) -> Polygon {
	points: [dynamic]Vec2
	defer delete(points)
	for i in 0..<len(p.points) {
		a,b := p.points[i],p.points[(i+1)%len(p.points)]
		av,bv := a.x-cut,b.x-cut
		if axis == 1 { av = a.y-cut; bv = b.y-cut }
		if !keep_low { av = -av; bv = -bv }
		inside_a, inside_b := av <= 0,bv <= 0
		if inside_a { append(&points,a) }
		if inside_a != inside_b {
			t := av/(av-bv)
			append(&points,vadd(a,vmul(vsub(b,a),t)))
		}
	}
	return make_polygon(points[:])
}
is_convex :: proc(p: Polygon) -> bool {
	if len(p.points) < 3 { return false }
	sign: f32
	for i in 0..<len(p.points) {
		cross := vcross(vsub(p.points[(i+1)%len(p.points)],p.points[i]),vsub(p.points[(i+2)%len(p.points)],p.points[(i+1)%len(p.points)]))
		if math.abs(cross) < 0.00001 { continue }
		if sign == 0 { sign = cross } else if cross*sign < 0 { return false }
	}
	return true
}
point_in_triangle :: proc(p,a,b,c: Vec2, orientation: f32, tolerance: f32 = 0.00001) -> bool {
	return vcross(vsub(b,a),vsub(p,a))*orientation >= -tolerance &&
	       vcross(vsub(c,b),vsub(p,b))*orientation >= -tolerance &&
	       vcross(vsub(a,c),vsub(p,c))*orientation >= -tolerance
}
triangulate_polygon :: proc(p: Polygon) -> [dynamic]Polygon {
 result: [dynamic]Polygon
 points: [dynamic]Vec2; indices: [dynamic]int
 defer delete(points); defer delete(indices)
 scale:=longest_dimension(p)
 duplicate_tolerance:=scale*0.0000001
 for point in p.points {
  if len(points)==0 || vlen(vsub(point,points[len(points)-1]))>duplicate_tolerance { append(&points,point) }
 }
 if len(points)>1 && vlen(vsub(points[0],points[len(points)-1]))<=duplicate_tolerance { resize(&points,len(points)-1) }
 if len(points)<3 { return result }
 signed:f64
 for point,i in points { signed+=polygon_turn(points[0],point,points[(i+1)%len(points)]) }
 orientation:=f64(1); if signed<0 { orientation=-1 }
 tolerance:=f64(scale)*f64(scale)*0.00000001
 for i in 0..<len(points) { append(&indices,i) }
 for len(indices)>3 {
  ear:=-1; fallback:=-1; largest:=f64(-1e300)
  for k in 0..<len(indices) {
   i,j,l:=indices[(k+len(indices)-1)%len(indices)],indices[k],indices[(k+1)%len(indices)]
   a,b,c:=points[i],points[j],points[l]
   turn:=polygon_turn(a,b,c)*orientation
   if turn>largest { largest=turn; fallback=k }
   if turn<=tolerance { continue }
   contains:=false
   for n in indices {
    if n==i || n==j || n==l { continue }
    point:=points[n]
    if polygon_turn(a,b,point)*orientation>= -tolerance && polygon_turn(b,c,point)*orientation>= -tolerance && polygon_turn(c,a,point)*orientation>= -tolerance { contains=true; break }
   }
   if !contains { ear=k; break }
  }
  // Roundoff or collinear boundary vertices must never truncate the fill.
  if ear<0 { ear=fallback }
  i,j,l:=indices[(ear+len(indices)-1)%len(indices)],indices[ear],indices[(ear+1)%len(indices)]
  append(&result,make_polygon([]Vec2{points[i],points[j],points[l]}))
  ordered_remove(&indices,ear)
 }
 append(&result,make_polygon([]Vec2{points[indices[0]],points[indices[1]],points[indices[2]]}))
 return result
}
// Straight cuts partition a shallow-concave outline directly. Collision convex
// decomposition is deliberately separate from logical fragment generation.
generate_children :: proc(parent: Polygon, recipe: Material, seed: u8, minimum_width: f32 = 0) -> [dynamic]Polygon {
 result: [dynamic]Polygon
 if seed==0 { return result }
 if recipe.triangulate { result=triangulate_polygon(parent) }
 else { append(&result,make_polygon(parent.points)) }
 for p in result {
  if !simple_polygon(p) || outline_width(p.points)<minimum_width {
   for child in result { delete(child.points) }; delete(result); return nil
  }
 }
 target:=max(recipe.generation_count,len(result))
 blocked:=make(map[int]bool); defer delete(blocked)
 for len(result)<target {
  chosen:=-1; largest:f32
  for p,i in result { area:=polygon_area(p); if !blocked[i] && area>largest { largest=area; chosen=i } }
  if chosen<0 || largest<0.0001 { break }
  p:=result[chosen]
  lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
  for point in p.points { lo={min(lo.x,point.x),min(lo.y,point.y)}; hi={max(hi.x,point.x),max(hi.y,point.y)} }
  axis:=0; width,height:=hi.x-lo.x,hi.y-lo.y
  if recipe.aspect_ratio<1 {
   if width>=height { if width/height<1/recipe.aspect_ratio { axis=1 } }
   else if height/width>=1/recipe.aspect_ratio { axis=1 }
  } else if width<height*recipe.aspect_ratio { axis=1 }
  fraction:=0.4+0.2*f32(derive_seed(seed,u64(len(result))))/255
  accepted:=false
  attempts:=2; if recipe.aspect_ratio<1 { attempts=1 }
  for attempt in 0..<attempts {
   cut_axis:=(axis+attempt)%2
   f:=fraction
   if recipe.aspect_ratio<1 {
    extent:=width; if cut_axis==1 { extent=height }
    low_fraction,high_fraction:=max(f32(0.4),minimum_width/extent),min(f32(0.6),1-minimum_width/extent)
    if low_fraction>high_fraction { break }
    f=clamp(f,low_fraction,high_fraction)
   }
   cut:=lo.x+(hi.x-lo.x)*f; if cut_axis==1 { cut=lo.y+(hi.y-lo.y)*f }
   low,high:=clip_polygon(p,cut_axis,cut,true),clip_polygon(p,cut_axis,cut,false)
   valid:=valid_partition_half(low,minimum_width) && valid_partition_half(high,minimum_width)
   valid=valid && math.abs(polygon_area(low)+polygon_area(high)-polygon_area(p))<=max(f32(0.0000002),polygon_area(p)*0.00002)
   if valid && recipe.triangulate {
    halves:=[2]Polygon{low,high}
    for half in halves {
     triangles:=triangulate_polygon(half)
     for triangle in triangles { valid=valid && valid_partition_half(triangle,minimum_width); delete(triangle.points) }
     delete(triangles)
    }
   }
   if valid {
    delete(p.points); result[chosen]=low; append(&result,high); accepted=true; break
   }
   delete(low.points); delete(high.points)
  }
  if !accepted { blocked[chosen]=true }
 }
 if !recipe.triangulate { displace_shared_boundaries(result[:],seed,minimum_width) }
 if recipe.triangulate {
  triangles: [dynamic]Polygon
  for polygon in result {
   parts:=triangulate_polygon(polygon)
   for part in parts { append(&triangles,part) }; delete(parts); delete(polygon.points)
  }
  delete(result); result=triangles
 }
 area:f32; genuine:=len(result)>=2; parent_area:=polygon_area(parent)
 for child in result {
  child_area:=polygon_area(child)
  genuine=genuine && valid_partition_half(child,minimum_width) && child_area<parent_area
  area+=child_area
 }
 if !genuine || math.abs(area-parent_area)>max(f32(0.000002),parent_area*0.0002) {
  for child in result { delete(child.points) }; delete(result); return nil
 }
 return result
}
valid_partition_half :: proc(p: Polygon,minimum_width: f32) -> bool {
 return len(p.points)>=3 && polygon_area(p)>=0.0001 && simple_polygon(p) && outline_width(p.points)>=minimum_width
}

apply_failures :: proc(s: ^Scene, failures: Failures) {
	if len(failures.subdivisions) == 0 && len(failures.connections) == 0 && len(failures.discard_subdivisions) == 0 { return }
	s.revision+=1
	affected := make(map[u64]bool)
	defer delete(affected)
	stage_failures(s,failures,&affected)
	rebuild_affected_pieces(s,affected)
	commit_structure(s)
}
// Reuse the existing one-wave graph update for physics and for each blast wave.
// Ownership, size filtering and engine handles are committed only at the end.
stage_failures :: proc(s: ^Scene, failures: Failures, affected: ^map[u64]bool, refine_only: bool = false, creation_size: f32 = 0) {
	replacements := make(map[u64][dynamic]u64)
	defer { for _,children in replacements { delete(children) }; delete(replacements) }
	failed_subs := sorted_ids(failures.subdivisions[:])
	for id in failures.discard_subdivisions { if !contains_id(failed_subs[:],id) { append(&failed_subs,id) } }
	sort_ids(failed_subs[:])
	failed_conns := sorted_ids(failures.connections[:])
	defer delete(failed_subs); defer delete(failed_conns)
	// Only attachments incident to failed endpoints can need inheritance.
	old_set:=make(map[u64]bool); defer delete(old_set)
	for id in failed_subs {
		if row,ok:=s.sub_rows[id]; ok { for connection in s.subdivisions[row].incident_links { old_set[connection]=true } }
	}
	old_connections: [dynamic]u64
	defer delete(old_connections)
	for id in old_set { append(&old_connections,id) }
	sort_ids(old_connections[:])
	for id in failed_subs {
		row, ok := s.sub_rows[id]
		if !ok || !s.subdivisions[row].live { continue }
		parent := s.subdivisions[row]
		seed := parent.seed
		if parent.width<=s.minimum_width && (creation_size==0 || longest_dimension(parent.outline)<=creation_size) || contains_id(failures.discard_subdivisions[:],id) { seed=0 }
		children := generate_children(parent.outline,s.materials[parent.material],seed,s.minimum_width)
		// Spatial refinement is not yet a centre-sampled failure. If the recipe
		// cannot partition this outline, retain it for the actual blast decision.
		if len(children)==0 {
   if !refine_only { s.subdivisions[row].seed=0 }
   discard:=contains_id(failures.discard_subdivisions[:],id)
   if refine_only || failures.impact && parent.width>s.minimum_width && !discard { continue }
  }
		affected[parent.owner] = true
		max_width,max_length: f32
		for outline,ordinal in children {
			center := centroid(outline)
			world_center := posed_point(parent,center)
			r := vsub(world_center,parent.pose.position)
			pose := Pose{position=world_center,angle=parent.pose.angle,velocity=vadd(parent.pose.velocity,Vec2{-parent.pose.angular_velocity*r.y,parent.pose.angular_velocity*r.x}),angular_velocity=parent.pose.angular_velocity}
			child := add_subdivision(s,parent.owner,outline,pose)
			child_row := s.sub_rows[child]
			// Parent context plus child ordinal is independent of other branches'
			// allocations. A deletion shortcut cannot perturb their future seeds.
			s.subdivisions[child_row].seed=derive_seed(parent.seed,u64(ordinal+1))
			max_width=max(max_width,s.subdivisions[child_row].width)
			max_length=max(max_length,longest_dimension(outline))
			delete(outline.points)
			child_ids := replacements[id]
			append(&child_ids,child)
			replacements[id] = child_ids
		}
		delete(children)
		// During creation, finish long thin cells before assigning the terminal batch.
		if max_width<=s.minimum_width && (creation_size==0 || max_length<=creation_size) {
			child_ids := replacements[id]
			for child in child_ids { s.subdivisions[s.sub_rows[child]].seed=0 }
		}
		s.subdivisions[row].live = false
	}
	for id in failed_conns {
		row, ok := s.conn_rows[id]
		if ok && s.connections[row].live {
			c := s.connections[row]
			affected[s.subdivisions[s.sub_rows[c.a]].owner] = true
			affected[s.subdivisions[s.sub_rows[c.b]].owner] = true
			s.connections[row].live = false
		}
	}
	for old_id in old_connections {
		i := s.conn_rows[old_id]
		c := s.connections[i]
		if !c.live { continue }
		a_dead := !s.subdivisions[s.sub_rows[c.a]].live
		b_dead := !s.subdivisions[s.sub_rows[c.b]].live
		if !a_dead && !b_dead { continue }
		s.connections[i].live = false
		left_default,right_default := [1]u64{c.a},[1]u64{c.b}
		left,right := left_default[:],right_default[:]
		if a_dead { left = replacements[c.a][:] }
		if b_dead { right = replacements[c.b][:] }
		old_a,old_b := s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
		old_length,_ := shared_boundary(old_a.outline,old_b.outline)
		if old_length <= 0 { continue }
		for a in left {
			for b in right {
				if inherits_old_boundary(s.subdivisions[s.sub_rows[a]].outline,s.subdivisions[s.sub_rows[b]].outline,old_a.outline,old_b.outline) { add_connection(s,a,b) }
			}
		}
	}
	// Impacts inherit outside attachments, but leave new siblings disconnected.
	if failures.impact { return }
	for id in failed_subs {
		children := replacements[id]
		for i in 0..<len(children) { for j in i+1..<len(children) { add_connection(s,children[i],children[j]) } }
	}
}
rebuild_affected_pieces :: proc(s: ^Scene, affected: map[u64]bool) {
	owners: [dynamic]u64
	defer delete(owners)
	for owner in affected { append(&owners,owner) }
	sort_ids(owners[:])
	for owner in owners { rebuild_piece(s,owner) }
}

BLAST_LOAD_MULTIPLIER :: f32(10)
BLAST_IMPULSE_SCALE :: f32(0.2)
blast_load :: proc(distance,radius: f32) -> f32 {
	if radius <= 0 || distance >= radius { return 0 }
	return BLAST_LOAD_MULTIPLIER*max(f32(0),radius-distance)
}
fails :: proc(load,strength: f32) -> bool { return load > 0 && load >= strength }
evaluate_blast :: proc(s: ^Scene, blast: Blast, first_subdivision: int = 0, first_connection: int = 0) -> Failures {
	f := Failures{}
	regions,links: [dynamic]u64
	defer delete(regions); defer delete(links)
	if first_subdivision==0 && first_connection==0 {
		regions=blast_regions(s,blast)
		links=blast_connections(s,regions[:])
	} else {
		for i in first_subdivision..<len(s.subdivisions) { if s.subdivisions[i].live { append(&regions,s.subdivisions[i].id) } }
		for i in first_connection..<len(s.connections) { if s.connections[i].live { append(&links,s.connections[i].id) } }
	}
	for id in regions {
		sub:=s.subdivisions[s.sub_rows[id]]
		load:=blast_load(vlen(vsub(subdivision_sample(sub),blast.position)),blast.radius)
		if fails(load,s.materials[sub.material].subdivision_strength) { append(&f.subdivisions,id) }
	}
	for id in links {
		c:=s.connections[s.conn_rows[id]]
		a:=s.subdivisions[s.sub_rows[c.a]]
		load:=blast_load(vlen(vsub(connection_sample(s,c),blast.position)),blast.radius)
		if fails(load,s.materials[a.material].connection_strength) { append(&f.connections,id) }
	}
	return f
}
// Descendants partition the outline, inherit its material and keep its rigid
// transform during this event. Their samples lie in the posed convex hull.
// Outward rounding and a strict load margin avoid pruning borderline failures.
blast_erases_descendants :: proc(sub: Subdivision, blast: Blast, strength: f32) -> bool {
	if !finite(strength) || !finite(blast.radius) || !valid_vec(blast.position) { return false }
	farthest: f32
	for point in sub.outline.points {
		distance := vlen(vsub(posed_point(sub,point),blast.position))
		if !finite(distance) { return false }
		farthest=max(farthest,distance)
	}
	farthest=math.nextafter(farthest,math.inf_f32(1))
	return blast_load(farthest,blast.radius)>strength+0.0001
}
// Refine every cell reached by the blast's destructive core, on every object,
// down to the minimum width. Fully doomed cells can use ordinary blast deletion;
// terminal or unpartitionable cells remain for the actual failure decision.
// Preserve birth contexts and inherited connections, and defer final bodies and
// the survivor impulse until the enclosing blast pass finishes.
refine_blast_reach :: proc(s: ^Scene,blast: Blast) -> bool {
 // Reach-only attempts are not failures; retain their local skip set.
 unrefinable:=make(map[u64]bool); defer delete(unrefinable)
	affected:=make(map[u64]bool)
	defer delete(affected)
	changed:=false
	candidates:=blast_regions(s,blast); defer delete(candidates)
	for {
		failures:=Failures{}
		for id in candidates {
			sub:=s.subdivisions[s.sub_rows[id]]
			if !sub.live || sub.seed==0 || sub.width<=s.minimum_width || unrefinable[sub.id] { continue }
			strength:=s.materials[sub.material].subdivision_strength
			if fails(blast_load(vlen(vsub(sub.pose.position,blast.position)),blast.radius),strength) {
				extent:=f32(0)
				for point in sub.outline.points { extent=max(extent,vlen(vsub(point,sub.rest_center))) }
				if extent<=blast.radius-strength/BLAST_LOAD_MULTIPLIER || blast_erases_descendants(sub,blast,strength) { continue }
			}
			distance:=f32(1e30)
			if point_in_subdivision(sub,blast.position) { distance=0 }
			else {
				for rest,i in sub.outline.points {
					a,b:=posed_point(sub,rest),posed_point(sub,sub.outline.points[(i+1)%len(sub.outline.points)])
					edge:=vsub(b,a); squared:=vdot(edge,edge)
					if squared<=0 { continue }
					t:=clamp(vdot(vsub(blast.position,a),edge)/squared,f32(0),f32(1))
					distance=min(distance,vlen(vsub(blast.position,vadd(a,vmul(edge,t)))))
				}
			}
			if fails(blast_load(distance,blast.radius),strength) { append(&failures.subdivisions,sub.id) }
		}
		if len(failures.subdivisions)==0 { break }
		first_child:=len(s.subdivisions)
		stage_failures(s,failures,&affected,true)
		for id in failures.subdivisions {
			if s.subdivisions[s.sub_rows[id]].live { unrefinable[id]=true } else { changed=true }
		}
		delete(failures.subdivisions)
		clear(&candidates)
		for i in first_child..<len(s.subdivisions) { if s.subdivisions[i].live { append(&candidates,s.subdivisions[i].id) } }
	}
	if changed { rebuild_affected_pieces(s,affected) }
	return changed
}

blast_pass :: proc(s: ^Scene, blast: Blast, deletion_shortcut: bool = true) {
	physics_read_motion(s)
	revision:=s.revision
	refined:=refine_blast_reach(s,blast)
	physics_read_motion(s)
	affected := make(map[u64]bool)
	defer delete(affected)
	f := evaluate_blast(s,blast)
	changed := false
	for len(f.subdivisions)>0 || len(f.connections)>0 {
		changed=true
		if deletion_shortcut {
			for id in f.subdivisions {
				sub := s.subdivisions[s.sub_rows[id]]
				if sub.seed!=0 && sub.width>s.minimum_width && blast_erases_descendants(sub,blast,s.materials[sub.material].subdivision_strength) { append(&f.discard_subdivisions,id) }
			}
		}
		first_subdivision,first_connection := len(s.subdivisions),len(s.connections)
		stage_failures(s,f,&affected)
		delete(f.subdivisions); delete(f.connections); delete(f.discard_subdivisions)
		// Earlier survivors have unchanged samples. Only children and new links
		// need this blast again; failed old links are already excluded from inheritance.
		f=evaluate_blast(s,blast,first_subdivision,first_connection)
	}
	delete(f.subdivisions); delete(f.connections); delete(f.discard_subdivisions)
	if changed { s.revision+=1; rebuild_affected_pieces(s,affected) }
	commit_structure(s)
	physics_sync_structure(s)
	final_regions:=blast_regions(s,blast); defer delete(final_regions)
	for id in final_regions {
		sub := &s.subdivisions[s.sub_rows[id]]
		offset := vsub(subdivision_sample(sub^),blast.position)
		distance := vlen(offset)
		load := blast_load(distance,blast.radius)
		if load>0 && distance>0.00001 { apply_blast_motion(s,sub,vmul(offset,1/distance),load) }
	}
	physics_read_motion(s)
	if refined && s.revision==revision { s.revision+=1 }
}

PRESPLIT_SIZE :: f32(1)
longest_dimension :: proc(p: Polygon) -> f32 {
 lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
 for v in p.points { lo={min(lo.x,v.x),min(lo.y,v.y)}; hi={max(hi.x,v.x),max(hi.y,v.y)} }
 return max(hi.x-lo.x,hi.y-lo.y)
}
// Creation-only refinement: inherit seams and birth contexts exactly as damage
// does, but keep unpartitionable live geometry instead of treating it as failed.
presplit_piece :: proc(s: ^Scene,owner: u64,size: f32 = PRESPLIT_SIZE) {
 affected:=make(map[u64]bool); defer delete(affected)
 candidates:=sorted_ids(s.pieces[s.piece_rows[owner]].subdivisions[:]); defer delete(candidates)
 for len(candidates)>0 {
  f:=Failures{}
  for id in candidates {
   sub:=s.subdivisions[s.sub_rows[id]]
   if sub.live && sub.seed!=0 && longest_dimension(sub.outline)>size+0.00001 { append(&f.subdivisions,id) }
  }
  if len(f.subdivisions)==0 { delete(f.subdivisions); break }
  first:=len(s.subdivisions)
  stage_failures(s,f,&affected,true,size); delete(f.subdivisions)
  clear(&candidates)
  for i in first..<len(s.subdivisions) { if s.subdivisions[i].live { append(&candidates,s.subdivisions[i].id) } }
 }
 rebuild_affected_pieces(s,affected)
 commit_structure(s)
}
