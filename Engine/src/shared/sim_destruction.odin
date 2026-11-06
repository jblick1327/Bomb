#+feature dynamic-literals
package shared

import time "core:time"
import fmt "core:fmt"
import math "core:math"
import mem "core:mem"

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

generate_children :: proc(parent: Polygon, recipe: Material, seed: u8, minimum_width: f32 = 0,creation: bool = false) -> [dynamic]Polygon {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(9,started) }
 if active_cover==nil || seed==0 { return generate_children_impl(parent,recipe,seed,minimum_width,creation) }
 arena:=&active_cover.generation_arena
 if arena.block_allocator.procedure==nil { mem.dynamic_arena_init(arena,block_size=65536,out_band_size=32768,alignment=64) }
 original_allocator:=context.allocator
 context.allocator=mem.dynamic_arena_allocator(arena)
 blast_scratch_active=true
 temporary:=generate_children_impl(parent,recipe,seed,minimum_width,creation)
 context.allocator=original_allocator
 blast_scratch_active=false
 result:[dynamic]Polygon
 for polygon in temporary { append(&result,make_polygon(polygon.points)) }
 mem.dynamic_arena_reset(arena)
 return result
}

generate_children_impl :: proc(parent: Polygon, recipe: Material, seed: u8, minimum_width: f32 = 0,creation: bool = false) -> [dynamic]Polygon {

 if recipe.aspect_ratio<1 { return generate_grained_children(parent,recipe,seed,minimum_width,creation) }
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
 blocked_inline:[8]bool; blocked:=blocked_inline[:]
 if target>len(blocked_inline) { blocked=make([]bool,target) }
 defer { if target>len(blocked_inline) { delete(blocked) } }
 for len(result)<target {
  chosen:=-1; largest:f32
  for p,i in result { area:=polygon_area(p); if !blocked[i] && area>largest { largest=area; chosen=i } }
  if chosen<0 || largest<0.0001 { break }
  p:=result[chosen]
  lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
  for point in p.points { lo={min(lo.x,point.x),min(lo.y,point.y)}; hi={max(hi.x,point.x),max(hi.y,point.y)} }
  axis:=0; width,height:=hi.x-lo.x,hi.y-lo.y
  if width<height*recipe.aspect_ratio { axis=1 }
  fraction:=0.4+0.2*f32(derive_seed(seed,u64(len(result))))/255
  accepted:=false
  for attempt in 0..<2 {
   cut_axis:=(axis+attempt)%2
   f:=fraction
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
 shock:=shock_begin_impact(s,failures); defer shock_destroy(&shock)
	stage_failures(s,failures,&affected,false,0,&shock,true)
 _=shock_apply(s,&shock,&affected,true)
	rebuild_affected_pieces(s,affected)
	commit_structure(s)
}

stage_failures :: proc(s: ^Scene, failures: Failures, affected: ^map[u64]bool, refine_only: bool = false, creation_size: f32 = 0,shock: ^Shock_Transaction = nil,direct: bool = false) {
 if creation_size==0 { scene_finish_references(s) }
	replacements := make(map[u64][dynamic]u64)
	defer { for _,children in replacements { delete(children) }; delete(replacements) }
	failed_subs := sorted_ids(failures.subdivisions[:])
 failed_set:=make(map[u64]bool); defer delete(failed_set)
 discard_set:=make(map[u64]bool); defer delete(discard_set)
 for id in failed_subs { failed_set[id]=true }
 for id in failures.discard_subdivisions { discard_set[id]=true }
	for id in failures.discard_subdivisions { if !failed_set[id] { append(&failed_subs,id); failed_set[id]=true } }
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
  if !refine_only && s.materials[parent.material].name=="wood" { cover_wood_failures+=1 }
  if direct { shock_mark_direct(shock,id) }
		seed := parent.seed
		grained:=s.materials[parent.material].aspect_ratio<1
		if !grained && parent.width<=s.minimum_width && (creation_size==0 || frame_longest(parent.outline,parent.frame)<=creation_size) || discard_set[id] { seed=0 }
  when BOM_PROFILE { if blast_profile!=nil { if direct { blast_profile.counts[0]+=1 } } }
		children: [dynamic]Polygon
  cacheable:=active_cover!=nil && seed==parent.seed && seed!=0 && creation_size==0
  if cacheable && active_cover.unpartitionable[id] {
   active_cover.partition_cache_hits+=1
  } else {
   children=generate_framed(parent.outline,s.materials[parent.material],seed,s.minimum_width,creation_size>0,parent.frame)
   // During a blast, this cell's rest outline, recipe and minimum width do
   // not change. Do not repeat a failed partition during direct staging.
   if cacheable && len(children)==0 { active_cover.unpartitionable[id]=true }
  }
		// Spatial refinement is not yet a centre-sampled failure. If the recipe
		// cannot partition this outline, retain it for the actual blast decision.
		if len(children)==0 {
   if !refine_only { s.subdivisions[row].seed=0 }
   discard:=discard_set[id]
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
   when BOM_PROFILE { if blast_profile!=nil { blast_profile.counts[7]+=1 } }
			child_row := s.sub_rows[child]
   s.subdivisions[child_row].frame=parent.frame
   shock_inherit(shock,id,child)
   if active_cover!=nil { active_cover.owners[child]=active_cover.owners[id]; if flag,ok:=active_cover.shadow[id]; ok { active_cover.shadow[child]=flag } }
			// Parent context plus child ordinal is independent of other branches'
			// allocations. A deletion shortcut cannot perturb their future seeds.
			s.subdivisions[child_row].seed=derive_seed(parent.seed,u64(ordinal+1))
			max_width=max(max_width,s.subdivisions[child_row].width)
			max_length=max(max_length,frame_longest(outline,parent.frame))
			delete(outline.points)
			child_ids := replacements[id]
			append(&child_ids,child)
			replacements[id] = child_ids
		}
		delete(children)
		// During creation, finish long thin cells before assigning the terminal batch.
		if !grained && max_width<=s.minimum_width && (creation_size==0 || max_length<=creation_size) {
			child_ids := replacements[id]
			for child in child_ids { s.subdivisions[s.sub_rows[child]].seed=0 }
		}
		s.subdivisions[row].live = false
	}
	for id in failed_conns {
		row, ok := s.conn_rows[id]
		if ok && s.connections[row].live {
			c := s.connections[row]
   if c.mortar { path:=string("blast");if failures.impact { path="force" };seam_diagnostic_death(s,c,path);s.connections[row].live=false; continue }
			affected[s.subdivisions[s.sub_rows[c.a]].owner] = true
			affected[s.subdivisions[s.sub_rows[c.b]].owner] = true
			s.connections[row].live = false
		}
	}
 when BOM_PROFILE { inheritance_start:=time.tick_now() }
	for old_id in old_connections {
		i := s.conn_rows[old_id]
		c := s.connections[i]
		if !c.live { continue }
		a_dead := !s.subdivisions[s.sub_rows[c.a]].live
		b_dead := !s.subdivisions[s.sub_rows[c.b]].live
		if !a_dead && !b_dead { continue }
  if c.mortar { seam_diagnostic_death(s,c,"endpoint replacement/deletion") }
		s.connections[i].live = false
		left_default,right_default := [1]u64{c.a},[1]u64{c.b}
		left,right := left_default[:],right_default[:]
		if a_dead { left = replacements[c.a][:] }
		if b_dead { right = replacements[c.b][:] }
		if len(c.glue)>0 { inherit_glue(s,c,left,right);continue }
  old_a,old_b := s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
  // Rest outlines are immutable, and these cached boundaries remain owned
  // by the old connection until commit. Reuse them during inheritance.
  old_segments:=c.rest_segments[:]
  old_owned:[dynamic]Segment
  if old_segments==nil {
   old_length,_:=shared_boundary(old_a.outline,old_b.outline)
   if old_length<=0 { continue }
   old_owned=shared_segments(old_a.outline,old_b.outline); old_segments=old_owned[:]
  }
  for a in left { for b in right {
   sa,sb:=s.subdivisions[s.sub_rows[a]],s.subdivisions[s.sub_rows[b]]
   if !inheritance_bounds_overlap(sa.outline,sb.outline) { continue }
   current:=shared_segments(sa.outline,sb.outline)
   if len(current)>0 && inherits_old_boundary(sa.outline,sb.outline,old_a.outline,old_b.outline,old_segments,current[:]) { add_connection(s,a,b,c.mortar,current[:]) }
   delete(current)
  } }
  delete(old_owned)
	}
 when BOM_PROFILE { profile_add(10,inheritance_start) }
	// Impacts inherit outside attachments, but leave new siblings disconnected.
	if failures.impact || failures.no_sibling_bonds { return }
 when BOM_PROFILE { sibling_start:=time.tick_now(); defer profile_add(11,sibling_start) }
	for id in failed_subs {
		children := replacements[id]
		for i in 0..<len(children) { for j in i+1..<len(children) { add_connection(s,children[i],children[j]) } }
	}
}

rebuild_affected_pieces :: proc(s: ^Scene, affected: map[u64]bool) {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(5,started) }

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

COVER_REACH_SHORTCUTS :: #config(COVER_REACH_SHORTCUTS,true)

COVER_DELETE_SHORTCUTS :: #config(COVER_DELETE_SHORTCUTS,true)

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
		load:=blast_load(cover_failure_distance(sub,subdivision_sample(sub),blast,s.materials[sub.material].subdivision_strength),blast.radius)
		if fails(load,s.materials[sub.material].subdivision_strength) { append(&f.subdivisions,id) }
	}
	for id in links {
		c:=s.connections[s.conn_rows[id]]
		a:=s.subdivisions[s.sub_rows[c.a]]
  strength:=s.materials[a.material].connection_strength
  sample:=connection_blast_sample(s,c,blast.position)
  if c.mortar {
   b:=s.subdivisions[s.sub_rows[c.b]]
   strength=min(strength,s.materials[b.material].connection_strength)
   sample=connection_sample(s,c)
  }
  load:=blast_load(cover_failure_distance(a,sample,blast,strength),blast.radius)
  if fails(load,strength) { append(&f.connections,id) }
	}
	return f
}

blast_erases_descendants :: proc(sub: Subdivision, blast: Blast, strength: f32) -> bool {
 if cover_external(sub,blast.position) { return false }
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

refine_blast_reach :: proc(s: ^Scene,blast: Blast,shock: ^Shock_Transaction = nil) -> bool {
 when BOM_PROFILE { started:=time.tick_now(); defer profile_add(0,started) }

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
			if !sub.live || sub.seed==0 || sub.width<=s.minimum_width && s.materials[sub.material].aspect_ratio>=1 || unrefinable[sub.id] { continue }
			strength:=s.materials[sub.material].subdivision_strength
			if (COVER_REACH_SHORTCUTS || !cover_foreign_any(sub)) && fails(blast_load(cover_failure_distance(sub,sub.pose.position,blast,strength),blast.radius),strength) {
				extent:=f32(0)
				for point in sub.outline.points { extent=max(extent,vlen(vsub(point,sub.rest_center))) }
				// Extent alone is a legacy reach heuristic, not a whole-core proof.
    // Newly enabled cases require the farthest-point proof below.
    if !cover_external(sub,blast.position) && !cover_foreign_any(sub) && extent<=blast.radius-strength/BLAST_LOAD_MULTIPLIER || blast_erases_descendants(sub,blast,strength) { continue }
			}
			distance:=f32(1e30)
			if point_in_subdivision(sub,blast.position) { distance=0 }
			else {
				for rest,i in sub.outline.points {
					a,b:=posed_point(sub,rest),posed_point(sub,sub.outline.points[(i+1)%len(sub.outline.points)])
					edge:=vsub(b,a); squared:=vdot(edge,edge)
					if squared<=0 { continue }
					t:=clamp(vdot(vsub(blast.position,a),edge)/squared,f32(0),f32(1))
					distance=min(distance,cover_failure_distance(sub,vadd(a,vmul(edge,t)),blast,strength))
				}
			}
			if fails(blast_load(distance,blast.radius),strength) { append(&failures.subdivisions,sub.id) }
		}
		if len(failures.subdivisions)==0 { break }
		first_child:=len(s.subdivisions)
		stage_failures(s,failures,&affected,true,0,shock)
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
 when BOM_PROFILE {
  profile:=Profile{start=time.tick_now(),before={len(s.subdivisions),len(s.connections)}}; blast_profile=&profile
  defer { fmt.printf("PROFILE,%d,%.6f,%v,%v,%v,%d,%d\n",profile_tick,f64(time.tick_diff(profile.start,time.tick_now()))/f64(time.Millisecond),profile.ms,profile.counts,profile.before,len(s.subdivisions),len(s.connections)); blast_profile=nil }
 }
	physics_read_motion(s)
 cover:=cover_begin(s,blast.radius); active_cover=&cover; defer { when BOM_PROFILE { fmt.printf("COVER,%d,%d,%d,%d,%d,%d,%d,%d\n",profile_tick,cover.samples,cover.fast_samples,cover.cache_hits,cover.upper_bound_skips,cover.shape_hits,cover.shape_misses,cover.partition_cache_hits) }; active_cover=nil; cover_destroy(&cover) }
 shock:=shock_begin_blast(s,blast); defer shock_destroy(&shock)
	revision:=s.revision
	refined:=refine_blast_reach(s,blast,&shock)
	physics_read_motion(s)
	affected := make(map[u64]bool)
	defer delete(affected)
 when BOM_PROFILE { direct_start:=time.tick_now() }
	f := evaluate_blast(s,blast)
	changed := false
	for len(f.subdivisions)>0 || len(f.connections)>0 {
		changed=true
		if deletion_shortcut {
			for id in f.subdivisions {
				sub := s.subdivisions[s.sub_rows[id]]
				if (COVER_DELETE_SHORTCUTS || !cover_foreign_any(sub)) && sub.seed!=0 && sub.width>s.minimum_width && blast_erases_descendants(sub,blast,s.materials[sub.material].subdivision_strength) { append(&f.discard_subdivisions,id) }
			}
		}
		first_subdivision,first_connection := len(s.subdivisions),len(s.connections)
		stage_failures(s,f,&affected,false,0,&shock,true)
		delete(f.subdivisions); delete(f.connections); delete(f.discard_subdivisions)
		// Earlier survivors have unchanged samples. Only children and new links
		// need this blast again; failed old links are already excluded from inheritance.
		f=evaluate_blast(s,blast,first_subdivision,first_connection)
	}
	delete(f.subdivisions); delete(f.connections); delete(f.discard_subdivisions)
 when BOM_PROFILE { profile_add(1,direct_start) }
 if shock_apply(s,&shock,&affected,false) { changed=true }
	if changed { s.revision+=1; rebuild_affected_pieces(s,affected) }
	commit_structure(s)
	physics_sync_structure(s)
 when BOM_PROFILE { impulse_start:=time.tick_now(); defer profile_add(8,impulse_start) }
	final_regions:=blast_regions(s,blast); defer delete(final_regions)
	for id in final_regions {
		sub := &s.subdivisions[s.sub_rows[id]]
		offset := vsub(subdivision_sample(sub^),blast.position)
		distance := vlen(offset)
		load := blast_load(cover_sample_distance(sub^,subdivision_sample(sub^),blast.position),blast.radius)
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

presplit_piece :: proc(s: ^Scene,owner: u64,size: f32 = PRESPLIT_SIZE) {
 affected:=make(map[u64]bool); defer delete(affected)
 candidates:=sorted_ids(s.pieces[s.piece_rows[owner]].subdivisions[:]); defer delete(candidates)
 for len(candidates)>0 {
  f:=Failures{}
  for id in candidates {
   sub:=s.subdivisions[s.sub_rows[id]]
   needed:=frame_longest(sub.outline,sub.frame)>size+0.00001
   if s.materials[sub.material].aspect_ratio<1 { local:=frame_polygon(sub.outline,sub.frame); needed,_=grain_cut_kind(local,s.minimum_width,true,s.materials[sub.material].strip_thickness);delete(local.points) }
   if sub.live && sub.seed!=0 && needed { append(&f.subdivisions,id) }
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
