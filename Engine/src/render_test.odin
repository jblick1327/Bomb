package main

import "core:testing"
import "core:math"
import "core:sync"
import b2 "vendor:box2d"

render_test_cross :: proc(a,b,c: Vec2) -> f64 {
	return (f64(b.x)-f64(a.x))*(f64(c.y)-f64(a.y))-(f64(b.y)-f64(a.y))*(f64(c.x)-f64(a.x))
}

@(test)
wood_render_cache_covers_refined_polygons :: proc(t: ^testing.T) {
	for seed in 1..=32 {
		s:=new_scene(0.1)
		m:=add_material(&s,editor_material(.Wood))
		p:=add_piece(&s,m,u8(seed))
		points:=[4]Vec2{{0,0},{6,0},{6,4},{0,4}}
		add_subdivision(&s,p,Polygon{points=points[:]},Pose{position={3,2}})
		blasts:=[3]Blast{{{-0.1,2},5},{{3,4.1},4},{{6.1,1},4}}
		for blast in blasts {
			blast_pass(&s,blast)
			for sub in s.subdivisions {
				cache:=ensure_render_cache(&s,sub.id)
				area:=f64(0)
				for i:=0; i+2<len(cache.triangles); i+=3 {
					a,b,c:=cache.outline.points[cache.triangles[i]],cache.outline.points[cache.triangles[i+1]],cache.outline.points[cache.triangles[i+2]]
					area+=math.abs(render_test_cross(a,b,c))*0.5
				}
				expected:=f64(0)
				for point,i in cache.outline.points { expected+=render_test_cross(cache.outline.points[0],point,cache.outline.points[(i+1)%len(cache.outline.points)])*0.5 }
				expected=math.abs(expected)
				// Ignore differences smaller than a fraction of one screen pixel;
				// seed 13 previously lost up to a quarter of a visible fragment.
				testing.expectf(t,math.abs(area-expected)<max(f64(0.000025),expected*0.0001),"Wood seed %d sub %d: filled %.9f / %.9f",seed,sub.id,area,expected)
			}
		}
		scene_destroy(&s)
	}
}

@(test)
piece_outline_flags_hide_only_live_bonds_and_leave_cracks :: proc(t: ^testing.T) {
 s:=new_scene(0.1); defer scene_destroy(&s)
 m:=add_material(&s,editor_material(.Wood)); owner:=add_piece(&s,m,0)
 ids:[4]u64
 for i in 0..<4 {
  x,y:=f32(i%2),f32(i/2)
  vertices:=[4]Vec2{{x,y},{x+1,y},{x+1,y+1},{x,y+1}}; p:=Polygon{points=vertices[:]}
  ids[i]=add_subdivision(&s,owner,p,Pose{position=centroid(p)})
 }
 for a in 0..<4 { for b in a+1..<4 { add_connection(&s,ids[a],ids[b]) } }
 before,ok:=encode_snapshot(&s); defer delete(before); testing.expect(t,ok)
 hidden,visible:=0,0
 poses:=make(map[u64]Pose); defer delete(poses)
 for id in ids {
  cache:=ensure_render_cache(&s,id)
  for draw in cache.draw_edge { if draw { visible+=1 } else { hidden+=1 } }
  sub:=s.subdivisions[s.sub_rows[id]]
  raw:=render_outline(&s,sub,poses,false); surface:=render_outline(&s,sub,poses,true)
  testing.expect(t,len(raw.points)==len(cache.outline.points) && len(surface.points)==len(cache.outline.points))
  delete(raw.points); delete(surface.points)
 }
 testing.expect(t,hidden==8 && visible==8)
 after,encoded:=encode_snapshot(&s); defer delete(after); testing.expect(t,encoded && string(before)==string(after))
 // Breaking an internal bond of a rigid cycle cannot open a physical crack.
 f:=Failures{}; append(&f.connections,s.connection_pairs[pair_key(ids[0],ids[1])])
 apply_failures(&s,f); free_failures(&f)
 testing.expect(t,len(s.pieces)==1)
 hidden,visible=0,0
 for id in ids { cache:=ensure_render_cache(&s,id); for draw in cache.draw_edge { if draw { visible+=1 } else { hidden+=1 } } }
 testing.expect(t,hidden==8 && visible==8)
}

// Independent pairwise edge predicate (no shared generation-validity code).
expect_simple_outline :: proc(t: ^testing.T,p: Polygon,id: u64) {
 for a,i in p.points {
  b:=p.points[(i+1)%len(p.points)]
  testing.expectf(t,a!=b,"Region %d has a duplicate edge",id)
  for j in i+1..<len(p.points) {
   if j==i+1 || i==0 && j==len(p.points)-1 { continue }
   c,d:=p.points[j],p.points[(j+1)%len(p.points)]
   ac,ad,ca,cb:=render_test_cross(a,b,c),render_test_cross(a,b,d),render_test_cross(c,d,a),render_test_cross(c,d,b)
   crossing:=(ac>0 && ad<0 || ac<0 && ad>0) && (ca>0 && cb<0 || ca<0 && cb>0)
   pairs:=[4][3]Vec2{{a,b,c},{a,b,d},{c,d,a},{c,d,b}}
   for pair in pairs { x,y,q:=pair[0],pair[1],pair[2]; if render_test_cross(x,y,q)==0 && q.x>=min(x.x,y.x) && q.x<=max(x.x,y.x) && q.y>=min(x.y,y.y) && q.y<=max(x.y,y.y) { crossing=true } }
   testing.expectf(t,!crossing,"Region %d edges %d and %d cross/touch: %v",id,i,j,p.points)
  }
 }
}
expect_sound_live_geometry :: proc(t: ^testing.T,s: ^Scene) {
 for sub in s.subdivisions {
  testing.expectf(t,sub.width>=s.minimum_width,"Region %d width %.9f < %.9f",sub.id,sub.width,s.minimum_width)
  expect_simple_outline(t,sub.outline,sub.id)
  testing.expectf(t,sub.fixture_count>0 && len(sub.shapes)>0,"Region %d lacks collision",sub.id)
  cache:=ensure_render_cache(s,sub.id)
  area:f32
  for i:=0; i+2<len(cache.triangles); i+=3 {
   a,b,c:=fill_point(cache.outline,cache.hub,cache.triangles[i]),fill_point(cache.outline,cache.hub,cache.triangles[i+1]),fill_point(cache.outline,cache.hub,cache.triangles[i+2])
   area+=math.abs(vcross(vsub(b,a),vsub(c,a)))*0.5
  }
  expected:=f32(partition_area(sub.outline.points))
  testing.expectf(t,math.abs(area-expected)<=max(f32(0.0000005),expected*0.00002),"Region %d f32 render fill %.9f / outline %.9f",sub.id,area,expected)
 }
}

@(test)
all_palette_and_floor_geometry_stays_sound_across_32_seeds :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 for seed in 1..=32 {
  for choice in Palette {
   g:=sandbox_editor_create(); g.applied.seed=u8(seed); g.editor.palette=choice
   testing.expect(t,editor_place(&g,{0,0},{2.4,1.2})); sandbox_toggle_editor(&g)
   expect_sound_live_geometry(t,&g.scene)
   moved:=make(map[b2.BodyId]bool)
   height:=f32(2.1); if choice==.Rubber { height=3.6 }
   for sub in g.scene.subdivisions { if sub.material==0 || moved[sub.body] { continue }; moved[sub.body]=true; p:=b2.Body_GetPosition(sub.body); p.y+=height; b2.Body_SetTransform(sub.body,p,b2.MakeRot(0)); b2.Body_SetAwake(sub.body,true) }
   delete(moved)
   for _ in 0..<150 { sandbox_tick(&g,0,false) }
   expect_sound_live_geometry(t,&g.scene)
   blasts:=[3]Vec2{{-0.1,0.2},{3,0.2},{6.5,0.2}}
   for pos in blasts { sandbox_explode(&g,pos); expect_sound_live_geometry(t,&g.scene) }
   expect_valid(t,&g.scene); sandbox_destroy(&g)
  }
 }
}

@(test)
triangulation_scales_cleans_duplicates_and_never_truncates :: proc(t: ^testing.T) {
 scales:=[3]f32{0.0001,1,10000}
 for scale in scales {
  source:=[7]Vec2{{0,0},{2,0},{2,0},{2,1},{1,0.99},{0,1},{0,0}}
  for &point in source { point=vmul(point,scale) }
  p:=Polygon{points=source[:]}; triangles:=triangulate_polygon(p)
  testing.expect(t,len(triangles)==3,"Five distinct vertices must produce three triangles at every scale")
  area:f64
  for triangle in triangles { area+=partition_area(triangle.points); delete(triangle.points) }; delete(triangles)
  testing.expect(t,math.abs(area-partition_area(p.points))<=partition_area(p.points)*0.000001)
 }
 // Former self-crossing hairline input must still complete, though generation
 // rejects such outlines before they can become live regions.
 points:=[4]Vec2{{0,0},{2,1},{0,1},{2,0}}
 p:=Polygon{points=points[:]}; triangles:=triangulate_polygon(p)
 testing.expect(t,len(triangles)==2)
 for triangle in triangles { delete(triangle.points) }; delete(triangles)
}

@(test)
unbonded_render_boundaries_remain_independent :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=new_scene(0.1); defer scene_destroy(&s)
 m:=add_material(&s,editor_material(.Wood)); left:=add_piece(&s,m,0); right:=add_piece(&s,m,0)
 bounds:=[3][4]Vec2{{{0,0},{1,0},{1,2},{0,2}},{{1,0},{2,0},{2,1},{1,1}},{{1,1},{2,1},{2,2},{1,2}}}
 ids:[3]u64
 for points,i in bounds { vertices:=points; p:=Polygon{points=vertices[:]}; owner:=left; if i>0 { owner=right }; ids[i]=add_subdivision(&s,owner,p,Pose{position=centroid(p)}) }
 add_connection(&s,ids[1],ids[2]); physics_init(&s)
 before,ok:=encode_snapshot(&s); defer delete(before); testing.expect(t,ok)
 cache:=ensure_render_cache(&s,ids[0]); testing.expect(t,len(cache.outline.points)==4,"Unbonded neighbours must not add cached endpoints")
 for draw in cache.draw_edge { testing.expect(t,draw,"No bond means no hidden outline edge") }
 after,encoded:=encode_snapshot(&s); defer delete(after); testing.expect(t,encoded && string(before)==string(after),"Render caching must leave simulation bytes unchanged")
 poses:=make(map[u64]Pose); defer delete(poses)
 body:=s.subdivisions[s.sub_rows[ids[1]]].body
 b2.Body_SetTransform(body,{0.2,0},b2.MakeRot(0)); physics_read_motion(&s)
 a:=render_outline(&s,s.subdivisions[s.sub_rows[ids[0]]],poses,true)
 b:=render_outline(&s,s.subdivisions[s.sub_rows[ids[1]]],poses,true)
 max_left,min_right:=f32(-1e30),f32(1e30)
 for point in a.points { max_left=max(max_left,point.x) }; for point in b.points { min_right=min(min_right,point.x) }
 testing.expect(t,min_right-max_left>0.19,"Collinear endpoint insertion must preserve separation after the pieces move")
 delete(a.points); delete(b.points)
}

@(test)
subpixel_strokes_use_alpha_with_one_pixel_geometry :: proc(t: ^testing.T) {
 widths:=[5]f32{0,0.3,0.7,1,2}
 for width in widths {
  pixels,color:=stroke_style(width,{10,20,30,200})
  expected:=width; if width>0 && width<1 { expected=1 }
  testing.expect(t,pixels==expected && color.r==10 && color.g==20 && color.b==30)
  alpha:=u8(200); if width>0 && width<1 { alpha=u8(200*width) }
  testing.expect(t,color.a==alpha)
 }
}

@(test)
rigid_render_vertices_share_frame_bit_for_bit :: proc(t: ^testing.T) {
 s:=new_scene(0.1); defer scene_destroy(&s)
 m:=add_material(&s,editor_material(.Wood)); owner:=add_piece(&s,m,42)
 bounds:=[3][4]Vec2{{{0,0},{1,0},{1,2},{0,2}},{{1,0},{2,0},{2,1},{1,1}},{{1,1},{2,1},{2,2},{1,2}}}
 ids:[3]u64
 poses:=make(map[u64]Pose); defer delete(poses)
 previous:=make(map[u64]Pose); defer delete(previous)
 for vertices,i in bounds {
  points:=vertices; p:=Polygon{points=points[:]}
  ids[i]=add_subdivision(&s,owner,p,Pose{position=centroid(p)})
  sub:=&s.subdivisions[s.sub_rows[ids[i]]]
  old:=Pose{position=vadd(Vec2{1.137,-0.372},vrotate(sub.rest_center,0.271)),angle=0.271}
  sub.pose=Pose{position=vadd(Vec2{1.231,-0.314},vrotate(sub.rest_center,0.397)),angle=0.397}
  previous[sub.id]=old
  poses[sub.id]=interpolate_region_pose(&s,sub^,old,0.37)
 }
 for i in 1..<3 { add_connection(&s,ids[0],ids[i]) }
 before,ok:=encode_snapshot(&s); defer delete(before); testing.expect(t,ok)
 frames:=render_piece_frames(&s,poses,previous,0.37); defer delete(frames)
 testing.expect(t,len(frames)==1)
 seen:=make(map[Vec2]u64); defer delete(seen)
 repeats:=0
 modes:=[2]bool{false,true}
 for surface in modes { for id in ids {
  sub:=s.subdivisions[s.sub_rows[id]]; cache:=ensure_render_cache(&s,id)
  outline:=render_outline(&s,sub,poses,surface,frames)
  for rest,i in cache.outline.points {
   point:=outline.points[i]; bits:=transmute(u64)point
   if previous,found:=seen[rest]; found { testing.expect(t,bits==previous,"Shared rest vertices must have identical rendered bits"); repeats+=1 }
   else { seen[rest]=bits }
  }
  center:=render_subdivision(&s,sub,poses,frames).pose.position
  testing.expect(t,center==rigid_render_point(frames[owner],sub.rest_center))
  delete(outline.points)
 } }
 testing.expect(t,repeats>5)
 after,encoded:=encode_snapshot(&s); defer delete(after)
 testing.expect(t,encoded && string(before)==string(after))
}

@(test)
borders_follow_rigid_groups_flexible_bonds_and_static_neighbours :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=msaa_border_scene(); defer scene_destroy(&s)
 static_hidden:=0
 for sub in s.subdivisions { if !render_static(sub) { continue }; others:=render_together_neighbours(&s,sub)
  for id in others { other:=s.subdivisions[s.sub_rows[id]]; if other.owner!=sub.owner { static_hidden+=1 } }; delete(others)
 }
 testing.expect(t,static_hidden>0,"Separate anchored pieces share bare fill boundaries")
 // Free one anchored piece without changing rest geometry: its split gets borders.
 old_revision:=s.static_render_revision
 body:=s.pieces[0].body; b2.Body_SetType(body,.dynamicBody)
 for sub in s.subdivisions { if sub.body!=body { continue }; others:=render_together_neighbours(&s,sub)
  for id in others { testing.expect(t,s.subdivisions[s.sub_rows[id]].owner==sub.owner) }; delete(others)
 }
 testing.expect(t,old_revision>0)
 // Existing rigid-cycle test covers a broken bond inside the same body.
 // The same missing bond in flexible material must be exposed.
 for &m in s.materials { if m.name=="wood" { m.flexibility=0.5 } }
 hidden:f32
 for sub in s.subdivisions {
  if s.materials[sub.material].name!="wood" { continue }
  release_render_cache(&s.subdivisions[s.sub_rows[sub.id]].render); cache:=ensure_render_cache(&s,sub.id)
  for draw,i in cache.draw_edge { if !draw { hidden+=vlen(vsub(cache.outline.points[(i+1)%len(cache.outline.points)],cache.outline.points[i])) } }
 }
 testing.expect(t,math.abs(hidden-6)<=1e-4)
}
