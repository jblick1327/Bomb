#+feature dynamic-literals
package main

import "core:math"
import "core:testing"
import "core:encoding/json"
import "core:fmt"

@(test)
child_width_guard_rejects_thin_batches_and_keeps_legacy_terminals :: proc(t: ^testing.T) {
 s:=make_wall(42,0.75); defer scene_destroy(&s)
 parent:=s.subdivisions[1].id
 f:=failure_for(parent); apply_failures(&s,f); free_failures(&f)
 testing.expect(t,!is_live_subdivision(&s,parent) && len(s.subdivisions)==2,"Neither half can meet the cutoff; a failed unpartitionable region is removed")
 expect_valid(t,&s)
 r:=make_wall(42); defer scene_destroy(&r)
 r.materials[0].generation_count=3
 original:=r.subdivisions[1]
 preview:=generate_children(original.outline,r.materials[0],original.seed)
 lo,hi:=f32(1e30),f32(0)
 for polygon in preview { width:=outline_width(polygon.points); lo=min(lo,width); hi=max(hi,width); delete(polygon.points) }; delete(preview)
 testing.expect(t,hi>lo && hi<original.width)
 r.minimum_width=(lo+hi)*0.5
 f=failure_for(original.id); apply_failures(&r,f); free_failures(&f)
 for sub in r.subdivisions { testing.expect(t,sub.width>=r.minimum_width,"Every new child must meet the thickness cutoff") }
 expect_valid(t,&r)
 // Seed-zero existing geometry remains live until failure, then cannot refine.
 legacy:=r.subdivisions[0].id; r.subdivisions[0].seed=0
 before:=len(r.subdivisions)
 f=failure_for(legacy); apply_failures(&r,f); free_failures(&f)
 testing.expect(t,len(r.subdivisions)==before-1 && !is_live_subdivision(&r,legacy))
}

@(test)
recursive_failure_terminates_without_a_width_cutoff :: proc(t: ^testing.T) {
	s:=new_scene(0); defer scene_destroy(&s)
	m:=add_material(&s,make_material(impact_scale=1,name="tiny",subdivision_strength=1,connection_strength=1,generation_count=4,aspect_ratio=1))
	p:=add_piece(&s,m,42)
	points:=[4]Vec2{{0,0},{0.03,0},{0.03,0.01},{0,0.01}}
	outline:=Polygon{points=points[:]}
	id:=add_subdivision(&s,p,outline,Pose{position=centroid(outline)})

	blast:=Blast{position={-0.1,0},radius=1}
	blast_pass(&s,blast,false)
	a,b,c:=counts(&s)
	testing.expect(t,a==0 && b==0 && c==0 && len(s.subdivisions)==0 && s.next_id==5,"The first genuine split is followed by direct removal when area limits prevent another")
	last_id:=s.next_id
	for _ in 0..<4 { blast_pass(&s,blast,false) }
	testing.expect(t,s.next_id==last_id && s.revision==1)
	expect_valid(t,&s)
}

@(test)
blast_deletion_bound_is_conservative :: proc(t: ^testing.T) {
	s:=make_wall(42); defer scene_destroy(&s)
	sub:=s.subdivisions[0]
	farthest:=vlen(Vec2{1,1})
	// At equality the ordinary test fails, but the shortcut must decline:
	// outward distance rounding and its strict 1e-4 load margin are intentional.
	blast:=Blast{position={0,0},radius=farthest+0.6}
	testing.expect(t,!blast_erases_descendants(sub,blast,6))
	blast.radius+=0.000001
	testing.expect(t,!blast_erases_descendants(sub,blast,6))
	blast.radius+=0.01
	testing.expect(t,blast_erases_descendants(sub,blast,6))
	testing.expect(t,!blast_erases_descendants(sub,blast,math.inf_f32(1)))
	testing.expect(t,!blast_erases_descendants(sub,blast,math.nan_f32()))
	testing.expect(t,!blast_erases_descendants(sub,Blast{position={0,0},radius=math.inf_f32(1)},6))
	sub.pose.angle=0.7
	sub.pose.position={8,-3}
	posed_blast:=Blast{position=posed_point(sub,Vec2{}),radius=blast.radius}
	testing.expect(t,blast_erases_descendants(sub,posed_blast,6),"The bound uses the posed outline")
}

same_outline :: proc(a,b: Polygon) -> bool {
	if len(a.points)!=len(b.points) { return false }
	for p,i in a.points { if p!=b.points[i] { return false } }
	return true
}
// Allocation IDs intentionally differ when a dead subtree is skipped. Compare
// the observable graph by exact retained outlines, seeds, motion and membership.
expect_same_blast_result :: proc(t: ^testing.T, a,b: ^Scene) {
	expect_valid(t,a); expect_valid(t,b)
	as,ac,ap:=counts(a); bs,bc,bp:=counts(b)
	testing.expect(t,as==bs && ac==bc && ap==bp)
	matches:=make(map[u64]u64); defer delete(matches)
	used:=make(map[u64]bool); defer delete(used)
	for x in a.subdivisions {
		if !x.live { continue }
		found:=false
		for y in b.subdivisions {
			if !y.live || used[y.id] || !same_outline(x.outline,y.outline) { continue }
			matches[x.id]=y.id; used[y.id]=true; found=true
			testing.expect(t,x.seed==y.seed && x.material==y.material && x.width==y.width && close_vec(x.pose.position,y.pose.position) && close_vec(x.pose.velocity,y.pose.velocity) && close(x.pose.angle,y.pose.angle) && close(x.pose.angular_velocity,y.pose.angular_velocity))
			left,right:=a.pieces[a.piece_rows[x.owner]],b.pieces[b.piece_rows[y.owner]]
			testing.expect(t,left.seed==right.seed && len(left.subdivisions)==len(right.subdivisions) && len(left.connections)==len(right.connections))
			break
		}
		testing.expect(t,found,"A retained outline differs between recursive and shortcut evaluation")
	}
	if len(matches)!=as { return }
	for c in a.connections {
		if !c.live { continue }
		found:=false
		for d in b.connections {
			if d.live && ((d.a==matches[c.a] && d.b==matches[c.b]) || (d.b==matches[c.a] && d.a==matches[c.b])) {
				found=true
				testing.expect(t,close_vec(connection_sample(a,c),connection_sample(b,d)))
				break
			}
		}
		testing.expect(t,found,"A surviving inherited or internal link differs")
	}
	for p in a.pieces {
		if !p.live { continue }
		owner:=b.subdivisions[b.sub_rows[matches[p.subdivisions[0]]]].owner
		for id in p.subdivisions { testing.expect(t,b.subdivisions[b.sub_rows[matches[id]]].owner==owner,"Retained memberships differ") }
	}

}

@(test)
deletion_shortcut_agrees_with_recursive_blasts :: proc(t: ^testing.T) {
	for pattern in 0..<3 {
		for whole in 0..<2 {
			a:=make_wall(42,0.08); defer scene_destroy(&a)
			b:=make_wall(42,0.08); defer scene_destroy(&b)
			scenes:=[2]^Scene{&a,&b}
			for s in scenes {
				s.materials[0]=test_recipe(pattern)
				s.materials[0].subdivision_strength=6
				s.materials[0].connection_strength=4
				for &sub in s.subdivisions {
					sub.pose.position=vadd(Vec2{2,-1},vrotate(sub.rest_center,0.7))
					sub.pose.angle=0.7
					sub.pose.velocity=vadd(Vec2{1,2},Vec2{-2*sub.pose.position.y,2*sub.pose.position.x})
					sub.pose.angular_velocity=2
				}
			}
			blast:=Blast{position=vadd(Vec2{2,-1},vrotate(Vec2{-1,0.25},0.7)),radius=3.5}
			if whole==1 { blast.radius=10 }
			blast_pass(&a,blast,true); blast_pass(&b,blast,false)
			testing.expect(t,a.next_id<b.next_id,"The proven deletion must avoid actual generation work")
			expect_same_blast_result(t,&a,&b)
			if whole==0 {
				remaining,_,_:=counts(&a)
				testing.expect(t,remaining>0)
				// Future events must also agree: a skipped earlier branch cannot
				// shift seeds through IDs, piece regrouping or an RNG stream.
				next:=Blast{position=vadd(Vec2{2,-1},vrotate(Vec2{3.3,-0.2},0.7)),radius=1.7}
				blast_pass(&a,next,true); blast_pass(&b,next,false)
				expect_same_blast_result(t,&a,&b)
			}
		}
	}
}

@(test)
new_blast_connections_fail_before_further_inheritance :: proc(t: ^testing.T) {
	s:=make_wall(42,0.08); defer scene_destroy(&s)
	s.materials[0].subdivision_strength=4.5
	s.materials[0].connection_strength=0
	broken:=Failures{connections=[dynamic]u64{s.connections[0].id}}; defer free_failures(&broken)
	apply_failures(&s,broken)
	left:=s.subdivisions[0].id
	blast:=Blast{position={1.5,0.5},radius=0.8}
	// Verify an actual newborn link fails; packed storage no longer retains its corpse.
	bytes,encoded:=encode_snapshot(&s); defer delete(bytes); testing.expect(t,encoded)
	probe,decoded:=decode_snapshot(bytes); defer scene_destroy(&probe); testing.expect(t,decoded)
	wave:=evaluate_blast(&probe,blast); defer free_failures(&wave)
	first_sub,first_link:=len(probe.subdivisions),len(probe.connections)
	affected:=make(map[u64]bool); defer delete(affected)
	stage_failures(&probe,wave,&affected)
	testing.expect(t,len(probe.connections)>first_link,"Failure must create an internal attachment")
	new_wave:=evaluate_blast(&probe,blast,first_sub,first_link); defer free_failures(&new_wave)
	testing.expect(t,len(new_wave.connections)>0,"That new attachment must fail in its birth blast")
	blast_pass(&s,blast,false)
	for c in s.connections {
		if !c.live { continue }
		testing.expect(t,c.a!=left && c.b!=left,"The earlier broken boundary must stay broken")
		testing.expect(t,!fails(blast_load(vlen(vsub(connection_sample(&s,c),blast.position)),blast.radius),0),"New connections are evaluated by the same blast")
	}
	testing.expect(t,len(s.connections)==0,"All newly created links lie within this blast and must be removed")
	expect_valid(t,&s)
}

@(test)
birth_context_survives_snapshots_and_legacy_loads :: proc(t: ^testing.T) {
	s:=make_wall(42,0.08); defer scene_destroy(&s)
	s.materials[0].subdivision_strength=4.5
	blast_pass(&s,Blast{position={1.5,0.5},radius=0.8})
	bytes,ok:=encode_snapshot(&s); defer delete(bytes)
	testing.expect(t,ok)
	r,decoded:=decode_snapshot(bytes); defer scene_destroy(&r)
	testing.expect(t,decoded)
	if !decoded { return }
	next:=Blast{position={2.5,-0.1},radius=1.5}
	blast_pass(&s,next); blast_pass(&r,next)
	expected,actual:=read_state(&s),read_state(&r)
	defer release_state_view(&expected); defer release_state_view(&actual)
	// Eight-decimal JSON coordinates can shift later cut vertices by one ULP.
	// Bound that geometry/centroid/velocity error explicitly; keep topology,
	// birth contexts, IDs, ownership, graph and angular motion byte-exact.
	max_vertex,max_position,max_velocity:=f32(0),f32(0),f32(0)
	for &sub in actual.subdivisions {
		row,exists:=s.sub_rows[sub.id]; testing.expect(t,exists)
		if !exists { continue }
		original:=s.subdivisions[row]
  max_position=max(max_position,vlen(vsub(sub.pose.position,original.pose.position))); max_velocity=max(max_velocity,vlen(vsub(sub.pose.velocity,original.pose.velocity)))
		testing.expect(t,vlen(vsub(sub.rest_center,original.rest_center))<0.000001)
		testing.expect(t,vlen(vsub(sub.pose.velocity,original.pose.velocity))<0.000005)
		testing.expect(t,vlen(vsub(sub.pose.position,original.pose.position))<0.000002)
  testing.expect(t,len(sub.outline.points)==len(original.outline.points))
  for &point,i in sub.outline.points { max_vertex=max(max_vertex,vlen(vsub(point,original.outline.points[i]))); testing.expect(t,vlen(vsub(point,original.outline.points[i]))<0.0000001); point=original.outline.points[i] }
  sub.rest_center=original.rest_center; sub.pose.velocity=original.pose.velocity; sub.pose.position=original.pose.position
	}
	fmt.printf("Snapshot decimal round-trip: max vertex %.9f position %.9f velocity %.9f\n",max_vertex,max_position,max_velocity)
	a,a_err:=json.marshal(expected,{pretty=true}); defer delete(a)
	b,b_err:=json.marshal(actual,{pretty=true}); defer delete(b)
	testing.expect(t,a_err==nil && b_err==nil && string(a)==string(b),"Future refinement must use the transmitted birth contexts")

	old:=make_wall(42); defer scene_destroy(&old)
	view:=read_state(&old); defer release_state_view(&view)
	view.version=1
	for &sub in view.subdivisions { sub.seed=0 }
	legacy,err:=json.marshal(view); defer delete(legacy)
	testing.expect(t,err==nil)
	loaded,accepted:=decode_snapshot(legacy); defer scene_destroy(&loaded)
	testing.expect(t,accepted)
	if accepted { for sub in loaded.subdivisions { testing.expect(t,sub.seed==42 && sub.width>0,"Legacy snapshots inherit their original piece context") } }
}
