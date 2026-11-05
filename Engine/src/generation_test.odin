package main

import "core:math"
import "core:sync"
import "core:testing"

// Independent double-precision area and triangle intersection checks catch
// compensating gaps/overlaps that a sum of the generator's f32 areas can miss.
Partition_Point :: struct { x,y: f64 }
partition_area :: proc(points: []Vec2) -> f64 {
	area: f64
	for p,i in points {
		q:=points[(i+1)%len(points)]
		area+=(f64(p.x)-f64(points[0].x))*(f64(q.y)-f64(points[0].y))-(f64(p.y)-f64(points[0].y))*(f64(q.x)-f64(points[0].x))
	}
	return math.abs(area)*0.5
}
partition_side :: proc(a,b,p: Partition_Point) -> f64 { return (b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x) }
partition_triangle_overlap :: proc(a,b: Polygon) -> f64 {
	points: [12]Partition_Point
	for p,i in a.points { points[i]={f64(p.x),f64(p.y)} }
	count:=len(a.points)
	clip: [3]Partition_Point
	for p,i in b.points { clip[i]={f64(p.x),f64(p.y)} }
	orientation:=f64(1)
	if partition_side(clip[0],clip[1],clip[2])<0 { orientation=-1 }
	for edge in 0..<3 {
		next: [12]Partition_Point
		next_count:=0
		for i in 0..<count {
			p,q:=points[i],points[(i+1)%count]
			ps:=orientation*partition_side(clip[edge],clip[(edge+1)%3],p)
			qs:=orientation*partition_side(clip[edge],clip[(edge+1)%3],q)
			if ps>=0 { next[next_count]=p; next_count+=1 }
			if (ps>=0)!=(qs>=0) {
				fraction:=ps/(ps-qs)
				next[next_count]={p.x+(q.x-p.x)*fraction,p.y+(q.y-p.y)*fraction}; next_count+=1
			}
		}
		points=next; count=next_count
	}
	area: f64
	for i in 0..<count { area+=partition_side(points[0],points[i],points[(i+1)%count]) }
	return math.abs(area)*0.5
}
expect_generation_partition :: proc(t: ^testing.T,parent: Polygon,children: []Polygon) {
	testing.expect(t,len(children)>=2)
	parent_area:=partition_area(parent.points)
	tolerance:=max(f64(0.00000005),parent_area*0.00005)
	parent_triangles:=triangulate_polygon(parent)
	defer { for triangle in parent_triangles { delete(triangle.points) }; delete(parent_triangles) }
	triangles: [dynamic][dynamic]Polygon
	defer { for batch in triangles { for triangle in batch { delete(triangle.points) }; delete(batch) }; delete(triangles) }
	area: f64
	for child in children {
		child_area:=partition_area(child.points)
		area+=child_area
		testing.expect(t,child_area>0 && child_area<parent_area)
		parts:=triangulate_polygon(child)
		inside: f64
		for part in parts { for triangle in parent_triangles { inside+=partition_triangle_overlap(part,triangle) } }
		testing.expectf(t,math.abs(inside-child_area)<=tolerance,"Every child must stay within its parent, including displaced seams: area %.8f, clipped %.8f, points %v",child_area,inside,child.points)
		append(&triangles,parts)
	}
	testing.expect(t,math.abs(area-parent_area)<=tolerance,"The partition must preserve its parent's area")
	for i in 0..<len(triangles) {
		for j in i+1..<len(triangles) {
			overlap: f64
			for a in triangles[i] { for b in triangles[j] { overlap+=partition_triangle_overlap(a,b) } }
			testing.expect(t,overlap<=tolerance,"Sibling interiors must not overlap")
		}
	}
	// Each child edge must be covered by the parent boundary or an exact sibling
	// seam. T junctions may split one side into several collinear segments.
	for child,i in children {
		perimeter,covered:=f32(0),f32(0)
		boundaries: [dynamic]Polygon
		append(&boundaries,parent)
		for other,j in children { if i!=j { append(&boundaries,other) } }
		for p,k in child.points {
			q:=child.points[(k+1)%len(child.points)]
			length:=vlen(vsub(q,p)); perimeter+=length
			if length==0 { continue }
			unit:=vmul(vsub(q,p),1/length)
			intervals: [dynamic][2]f32
			for other in boundaries {
				for a,j in other.points {
					b:=other.points[(j+1)%len(other.points)]
                    // Exact micro-edges are valid boundaries even below the
                    // production attachment cutoff used by segment_overlap.
                    if p==a && q==b || p==b && q==a {
                        append(&intervals,[2]f32{0,length})
                    } else if seam,ok:=segment_overlap(Segment{p,q},Segment{a,b}); ok {
						lo,hi:=vdot(vsub(seam.a,p),unit),vdot(vsub(seam.b,p),unit)
						append(&intervals,[2]f32{max(f32(0),min(lo,hi)),min(length,max(lo,hi))})
					}
				}
			}
			for j in 1..<len(intervals) {
				n:=j
				for n>0 && intervals[n][0]<intervals[n-1][0] { intervals[n],intervals[n-1]=intervals[n-1],intervals[n]; n-=1 }
			}
			// Measure the union: tolerance-near seams can overlap, and a duplicate
			// match must neither fail coverage nor cancel a real gap elsewhere.
			end:=f32(0)
			for interval in intervals {
				if interval[1]>end { covered+=interval[1]-max(end,interval[0]); end=interval[1] }
			}
			delete(intervals)
		}
		delete(boundaries)
		testing.expectf(t,math.abs(covered-perimeter)<0.0001,"Every generated edge must retain a matching shared boundary: perimeter %.8f, coverage %.8f, points %v",perimeter,covered,child.points)
	}
}

@(test)
triangulation_keeps_small_valid_corners_from_refined_ground :: proc(t: ^testing.T) {
	a:=[8]Vec2{{4.5152297,-0.4394615},{4.5316315,-0.7697342},{4.5756717,-0.84055817},{4.6283793,-0.9051913},{4.6355357,-0.6723415},{4.6283793,-0.43949175},{4.6283793,-0.4394615},{4.5718045,-0.44398749}}
	b:=[7]Vec2{{4.7738128,-0.43949175},{4.757686,0},{4.6283793,0},{4.6197467,-0.21973075},{4.6283793,-0.4394615},{4.6283793,-0.43949175},{4.701096,-0.43367442}}
	fixtures:=[2]Polygon{{points=a[:]},{points=b[:]}}
	for parent in fixtures {
		parts:=triangulate_polygon(parent)
		defer { for part in parts { delete(part.points) }; delete(parts) }
		testing.expect(t,len(parts)==len(parent.points)-2,"Every ear of these simple outlines must be retained")
		expect_generation_partition(t,parent,parts[:])
	}
}

@(test)
concave_nontriangular_parents_are_cut_directly :: proc(t: ^testing.T) {
 points:=[5]Vec2{{0,0},{2,0},{2,1},{1,0.98},{0,1}}
 parent:=Polygon{points=points[:]}
 choices:=[2]Recipe{.Wood,.Stone}
 for choice in choices {
  recipe:=editor_material(choice)
  for seed in 1..=32 {
   children:=generate_children(parent,recipe,u8(seed),0.1)
   testing.expectf(t,len(children)==recipe.generation_count,"%v seed %d direct cuts %d",choice,seed,len(children))
   expect_generation_partition(t,parent,children[:])
   for child in children { testing.expect(t,simple_polygon(child) && outline_width(child.points)>=0.1); delete(child.points) }; delete(children)
  }
 }
}

@(test)
triangulated_generation_skips_jitter_and_preserves_partitions :: proc(t: ^testing.T) {
	points:=[4]Vec2{{1.5,0},{2.35,0},{2.35,0.85},{1.5,0.85}}
	parent:=Polygon{points=points[:]}
	recipe:=test_recipe(2)
	children:=generate_children(parent,recipe,42)
	defer { for child in children { delete(child.points) }; delete(children) }
	// This square's straight cuts yield ten triangles. Displaced seams used
	// to multiply the same seed and recipe into 32 logical subdivisions.
	testing.expect(t,len(children)==10,"Triangulated generation must not add bent-seam vertices")
	expect_generation_partition(t,parent,children[:])
	refined:=0
	for child,i in children {
		testing.expect(t,len(child.points)==3,"Shards must retain deliberate triangulation")
		if outline_width(child.points)<=0.1 { continue }
		grandchildren:=generate_children(child,recipe,derive_seed(42,u64(i+1)))
		defer { for grandchild in grandchildren { delete(grandchild.points) }; delete(grandchildren) }
		expect_generation_partition(t,child,grandchildren[:])
		for grandchild in grandchildren { testing.expect(t,len(grandchild.points)==3) }
		refined+=1
	}
	testing.expect(t,refined>0,"Exercise a subsequent generation with inherited birth contexts")
}


@(test)
editor_roots_get_distinct_deterministic_generation_contexts :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 assert(editor_place(&g,{0,0},{0.8,0.8})); assert(editor_place(&g,{1,0},{1.8,0.8})); sandbox_toggle_editor(&g)
 a,b:=g.world.scene.subdivisions[0],g.world.scene.subdivisions[1]
 testing.expect(t,a.seed!=0 && b.seed!=0 && a.seed!=b.seed)
 sandbox_reset(&g)
 testing.expect(t,g.world.scene.subdivisions[0].seed==a.seed && g.world.scene.subdivisions[1].seed==b.seed)
}
