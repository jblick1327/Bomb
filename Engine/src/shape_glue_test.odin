package main
import "core:testing"
import "core:fmt"
import "core:math"
import "core:sync"

shape_direct_scene :: proc(recipe:Recipe,angle:f32=0,wedge:bool=false)->Scene {
 s:=new_scene(WOOD_MINIMUM_WIDTH);add_material(&s,editor_material(recipe));seed:=u8(42);if recipe==.Rubber { seed=0 };owner:=add_piece(&s,0,seed)
 size:=Vec2{3,0.8};if recipe==.Rubber { size={1.6,0.8} }
 r:=Authored_Shape{lo=vmul(size,-0.5),hi=vmul(size,0.5),angle=angle}
 if wedge { r.lo={-1,-0.5};r.hi={1,0.5};r.shape=.Wedge }
 build_shaped_object(&s,r,owner);return s
}
scene_live_area :: proc(s:^Scene)->(count:int,area:f32) {
 for sub in s.subdivisions { if sub.live { count+=1;area+=polygon_area(sub.outline) } };return
}
@(test)
shape_frame_equivalence :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 for recipe in Recipe {
  a,b:=shape_direct_scene(recipe),shape_direct_scene(recipe,30);defer scene_destroy(&a);defer scene_destroy(&b)
  ca,aa:=scene_live_area(&a);cb,ab:=scene_live_area(&b);error:=f32(0)
  testing.expect(t,ca==cb,fmt.tprintf("%v counts %d/%d",recipe,ca,cb))
  for sub in a.subdivisions { if !sub.live { continue };row,ok:=b.sub_rows[sub.id];if !ok { testing.expect(t,false,"missing paired cell");continue };other:=b.subdivisions[row]
   testing.expect(t,len(sub.outline.points)==len(other.outline.points));for p,i in sub.outline.points { if i<len(other.outline.points) { error=max(error,vlen(vsub(vrotate(p,math.PI/6),other.outline.points[i]))) } }
  }
  testing.expect(t,error<=1e-4,fmt.tprintf("%v vertex error %f",recipe,error))
  radius:=f32(5);if recipe==.Glass { radius=2 };if recipe==.Rubber { radius=6 }
  blast:=Blast{{-1.55,0},radius};blast_pass(&a,blast);blast.position=vrotate(blast.position,math.PI/6);blast_pass(&b,blast)
  na,ar:=scene_live_area(&a);nb,br:=scene_live_area(&b);lost_a,lost_b:=aa-ar,ab-br
  fmt.printf("Frame %v built=%d/%d error=%.9f blast cells=%d/%d lost=%.9f/%.9f\n",recipe,ca,cb,error,na,nb,lost_a,lost_b)
  testing.expect(t,na==nb && math.abs(lost_a-lost_b)<=max(f32(1e-5),max(lost_a,lost_b)*0.01))
 }
}
@(test)
shape_wedges_validate :: proc(t:^testing.T) {
 for recipe in Recipe {
  s:=shape_direct_scene(recipe,0,true);count,area:=scene_live_area(&s);valid,why:=validate_scene(&s);testing.expect(t,valid,why)
  minimum:=f32(1e30);for sub in s.subdivisions { if sub.live { minimum=min(minimum,sub.width) } }
  fmt.printf("Wedge %v cells=%d area=%.9f minimum_width=%.9f\n",recipe,count,area,minimum)
  testing.expect(t,math.abs(area-1)<=1e-5);if recipe==.Rubber { testing.expect(t,minimum>=WOOD_MINIMUM_WIDTH-1e-6) };scene_destroy(&s)
 }
}
glue_test_length :: proc(a,b:Authored_Shape)->f32 {
 pa,pb:=shape_polygon(a),shape_polygon(b);defer delete(pa.points);defer delete(pb.points)
 samples:=glue_samples(pa,pb);defer delete(samples);length:f32;for sample in samples { length+=sample.w };return length
}
@(test)
shape_glue_lengths :: proc(t:^testing.T) {
 a:=Authored_Shape{lo={0,0},hi={1,1}};b:=a;b.lo.y=1;b.hi.y=2
 flush:=glue_test_length(a,b);testing.expect(t,math.abs(flush-1)<1e-5)
 b.lo.y+=0.0005;b.hi.y+=0.0005;near:=glue_test_length(a,b);testing.expect(t,math.abs(near-1)<=0.05)
 a.angle=30;b=a;b.lo=vadd(a.lo,vrotate({0,1},math.PI/6));b.hi=vadd(a.hi,vrotate({0,1},math.PI/6))
 rotated:=glue_test_length(a,b);testing.expect(t,math.abs(rotated-1)<=0.05)
 wall:=Authored_Shape{lo={0,0},hi={0.5,3}}
 for angle in ([2]f32{60,30}) {
  beam:=Authored_Shape{lo={0,0},hi={3,0.3},angle=180-angle}
  poly:=shape_polygon(beam);corner:=poly.points[2];delete(poly.points)
  move:=vsub(Vec2{0.5,2},corner);beam.lo=vadd(beam.lo,move);beam.hi=vadd(beam.hi,move)
  length:=glue_test_length(wall,beam);expected:=f32(0.45);if angle==30 { expected=0.35 }
  fmt.printf("Glue lean %.0f length=%.6f\n",angle,length);testing.expect(t,math.abs(length-expected)<=0.05)
 }
 fmt.printf("Glue flush=%.6f rotated=%.6f gap0.0005=%.6f\n",flush,rotated,near)
}

// block_lo/block_hi optionally add a free, unbonded Stone block (identity 3), e.g. one resting on the tip.
glue_cantilever :: proc(glued:bool,block_lo:Vec2={},block_hi:Vec2={})->Sandbox {
 g:=sandbox_editor_create()
 append(&g.layout.objects,Authored_Shape{identity=1,material=recipe_slot(.Stone),lo={0,0},hi={0.5,3},mortar=true})
 append(&g.layout.objects,Authored_Shape{identity=2,material=recipe_slot(.Stone),lo={0.5,2.1},hi={2.5,2.4}})
 g.layout.next_identity=3
 if block_hi.x>block_lo.x { append(&g.layout.objects,Authored_Shape{identity=3,material=recipe_slot(.Stone),lo=block_lo,hi=block_hi});g.layout.next_identity=4 }
 if glued { append(&g.layout.glue,Glue_Link{1,2}) }
 sandbox_toggle_editor(&g)
 // Isolate glue from the automatic wall-to-beam mortar created by the wall flag.
 s:=&g.world.scene;f:=Failures{};left,right:[dynamic]u64
 for sub in s.subdivisions { if sub.rest_center.y<=0 || sub.rest_center.x>=0.5 && sub.rest_center.y>2.4 { continue };if sub.rest_center.x<0.5 { append(&left,sub.id) } else { append(&right,sub.id) } }
 for c in s.connections { if c.mortar && (contains_id(left[:],c.a) && contains_id(right[:],c.b) || contains_id(right[:],c.a) && contains_id(left[:],c.b)) { append(&f.connections,c.id) } }
 apply_failures(s,f);free_failures(&f)
 if glued { a,b:=shape_polygon(g.layout.objects[0]),shape_polygon(g.layout.objects[1]);samples:=glue_samples(a,b);assign_glue(s,samples[:],left[:],right[:]);delete(samples);delete(a.points);delete(b.points) }
 delete(left);delete(right);physics_sync_structure(s);return g
}
@(test)
shape_glue_holds_breaks :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 for glued in ([2]bool{true,false}) {
  g:=glue_cantilever(glued);s:=&g.world.scene
  starts:=make(map[u64]Vec2);links:[dynamic]u64
  for sub in s.subdivisions { if sub.rest_center.x>0.5 && sub.rest_center.y>1 { starts[sub.id]=sub.pose.position } }
  for c in s.connections { if len(c.glue)>0 { append(&links,c.id) } }
  maximum:=f32(0)
  for _ in 0..<600 { sandbox_tick(&g,0,false);for id,p in starts { if is_live_subdivision(s,id) { maximum=max(maximum,vlen(vsub(s.subdivisions[s.sub_rows[id]].pose.position,p))) } } }
  fmt.printf("Cantilever glued=%v max600=%.9f members=%d\n",glued,maximum,len(links))
  if glued {
   testing.expect(t,maximum<=0.05 && len(links)>0)
   survivors:=0;for id in links { if row,ok:=s.conn_rows[id];ok && s.connections[row].live { survivors+=1 } };testing.expect(t,survivors==len(links))
   tick:=g.world.tick;blast_pass(s,Blast{{0.5,3.8},5})
   remain:=0;for id in links { if row,ok:=s.conn_rows[id];ok && s.connections[row].live { remain+=1 } }
   fmt.printf("Glue blast tick=%d broken=%d/%d\n",tick,len(links)-remain,len(links));testing.expect(t,remain==0 && g.world.tick==tick)
  } else { testing.expect(t,maximum>0.5) }
  delete(starts);delete(links);sandbox_destroy(&g)
 }
}
@(test)
shape_contact_snap_and_layout :: proc(t:^testing.T) {
 l:=Layout{next_identity=3};defer destroy_layout(&l)
 wall:=Authored_Shape{identity=1,material=recipe_slot(.Stone),lo={0,0},hi={0.5,3}}
 append(&l.objects,wall)
 for gap in ([2]f32{0.2,0.4}) {
  beam:=Authored_Shape{identity=2,lo={0,0},hi={2,0.3},angle=30}
  p:=shape_polygon(beam);low:=f32(1e30);for v in p.points { low=min(low,v.x) };delete(p.points)
  shift:=Vec2{0.5+gap-low,1.5};beam.lo=vadd(beam.lo,shift);beam.hi=vadd(beam.hi,shift)
  snapped:=shape_snap(&l,beam);a,b:=shape_polygon(snapped),shape_polygon(wall);distance,_:=polygon_contact(a,b);delete(a.points);delete(b.points)
  testing.expect(t,!shape_overlap(snapped,wall))
  if gap<0.3 { testing.expect(t,distance<=1e-5) } else { testing.expect(t,snapped==beam) }
  fmt.printf("Snap gap=%.1f final_distance=%.9f unchanged=%v\n",gap,distance,snapped==beam)
 }
 wedge:=Authored_Shape{identity=2,material=recipe_slot(.Wood),shape=.Wedge,angle=90,lo={2,1},hi={4,2}}
 append(&l.objects,wedge)
 data,ok:=encode_layout(&l,42);defer delete(data);testing.expect(t,ok)
 decoded,seed,valid,why:=decode_layout(data);defer destroy_layout(&decoded);testing.expect(t,valid,why)
 again,eok:=encode_layout(&decoded,seed);defer delete(again);testing.expect(t,eok && string(data)==string(again))
 testing.expect(t,decoded.objects[1]==wedge)
}
@(test)
shape_near_glue_snapshot :: proc(t:^testing.T) {
 s:=new_scene(0.1);defer scene_destroy(&s);add_material(&s,editor_material(.Stone))
 ids:[2]u64
 for i in 0..<2 { owner:=add_piece(&s,0,0);y:=f32(i)*1.0005;p:=shape_polygon(Authored_Shape{lo={0,y},hi={1,y+1}});ids[i]=add_subdivision(&s,owner,p,Pose{position=centroid(p)});delete(p.points) }
 a,b:=s.subdivisions[s.sub_rows[ids[0]]],s.subdivisions[s.sub_rows[ids[1]]]
 samples:=glue_samples(a.outline,b.outline);defer delete(samples);glue_add(&s,ids[0],ids[1],samples[:])
 valid,why:=validate_scene(&s);testing.expect(t,valid,why)
 length,_:=seam_geometry(s.connections[0]);testing.expect(t,math.abs(length-1)<=0.05)
 data,ok:=encode_snapshot(&s);defer delete(data);testing.expect(t,ok)
 decoded,loaded:=decode_snapshot(data);testing.expect(t,loaded)
 if loaded { defer scene_destroy(&decoded);again,eok:=encode_snapshot(&decoded);defer delete(again);testing.expect(t,eok && string(data)==string(again)) }
 for mutation in 0..<7 {
  view:=read_state(&s);samples_copy:=make([]Glue_Sample,len(view.connections[0].glue));copy(samples_copy,view.connections[0].glue);view.connections[0].glue=samples_copy
  switch mutation {
  case 0:samples_copy[0].w=0
  case 1:samples_copy[0].w=math.nan_f32()
  case 2:samples_copy[0].p.y-=0.01
  case 3:samples_copy[0].q.y+=0.01
  case 4:samples_copy[0].q.x+=0.3
  case 5:view.connections[0].mortar=false
  case 6:view.subdivisions[0].frame=math.nan_f32()
  }
  invalid,accepted:=decode_scene_state(&view);testing.expect(t,!accepted);if accepted { scene_destroy(&invalid) }
  delete(samples_copy);release_state_view(&view)
 }
 fmt.printf("Near-contact gap=.0005 L=%.6f snapshot_exact=%v invalid_samples/frame_rejected=7/7\n",length,loaded)
}

@(test)
shape_glue_inheritance :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 s:=new_scene(0.1);defer scene_destroy(&s)
 add_material(&s,editor_material(.Stone));add_material(&s,editor_material(.Wood))
 shapes:=[2]Authored_Shape{{identity=1,lo={-0.5,0},hi={0,3}},{identity=2,lo={0,2},hi={2,2.3}}}
 objects:[dynamic]Built_Object;defer delete(objects)
 for r,i in shapes { first:=s.next_id+1;owner:=add_piece(&s,i,42);build_shaped_object(&s,r,owner);append(&objects,built_object(r,first,s.next_id+1)) }
 links:=[1]Glue_Link{{1,2}};build_glue(&s,links[:],objects[:],{})
 original:[dynamic]Glue_Sample;defer delete(original)
 parent:=u64(0);for c in s.connections { if len(c.glue)>0 { append(&original,..c.glue[:]);parent=c.b } }
 before:=f32(0);for sample in original { before+=sample.w };testing.expect(t,before>0)
 blast_pass(&s,Blast{{2.8,2.15},4.7})
 after,deleted:f32;members:=0
 for c in s.connections { if len(c.glue)>0 { members+=1;for sample in c.glue { after+=sample.w } } }
 for sample in original {
  a,b:=false,false
  for sub in s.subdivisions { if !sub.live { continue };if sub.material==0 { a=a || vlen(vsub(sample.p,boundary_nearest(sub.outline,sample.p)))<1e-4 } else { b=b || vlen(vsub(sample.q,boundary_nearest(sub.outline,sample.q)))<1e-4 } }
  if !a || !b { deleted+=sample.w }
 }
 fmt.printf("Glue inheritance before=%.9f deleted=%.9f after=%.9f members=%d parent_split=%v\n",before,deleted,after,members,!is_live_subdivision(&s,parent))
 testing.expect(t,!is_live_subdivision(&s,parent) && members>0 && math.abs(after-(before-deleted))<1e-5)
 valid,why:=validate_scene(&s);testing.expect(t,valid,why)
 // A deliberate endpoint discard separately exercises removal of samples.
 // Keep the blast fixture's inherited geometry and strengths unchanged.
 victim:=u64(0);expected_loss:=f32(0)
 for c in s.connections { if len(c.glue)>0 { victim=c.b;break } }
 for c in s.connections { if c.a==victim || c.b==victim { for sample in c.glue { expected_loss+=sample.w } } }
 f:=Failures{};append(&f.discard_subdivisions,victim);apply_failures(&s,f);free_failures(&f)
 retained:=f32(0);for c in s.connections { for sample in c.glue { retained+=sample.w } }
 fmt.printf("Glue deleted endpoint id=%d before=%.9f deleted=%.9f after=%.9f\n",victim,after,expected_loss,retained)
 testing.expect(t,expected_loss>0 && retained>0 && math.abs(retained-(after-expected_loss))<1e-5)
 final_valid,final_reason:=validate_scene(&s);testing.expect(t,final_valid,final_reason)
}

@(test)
shape_blasted_world_snapshot :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create();defer sandbox_destroy(&g)
 l:=shape_demo_layout();data,ok:=encode_layout(&l,42);defer delete(data);destroy_layout(&l);testing.expect(t,ok)
 testing.expect(t,sandbox_load_layout_data(&g,data),g.status)
 sandbox_toggle_editor(&g)
 valid_initial,initial_reason:=validate_scene(&g.world.scene);testing.expect(t,valid_initial,initial_reason)
 sandbox_fixture_radius(&g,4);sandbox_explode(&g,{-3.8,0.5})
 for _ in 0..<15 { sandbox_tick(&g,0,false) }
 valid_now,reason_now:=validate_scene(&g.world.scene);testing.expect(t,valid_now,reason_now)
 rotated,wedge,glue:=false,false,false
 for sub in g.world.scene.subdivisions { rotated=rotated || math.abs(sub.frame-math.PI/6)<1e-5;wedge=wedge || math.abs(sub.frame-math.PI/2)<1e-5 }
 for c in g.world.scene.connections { glue=glue || len(c.glue)>0 };testing.expect(t,rotated && wedge && glue)
 bytes,encoded:=encode_world_snapshot(&g.world);defer delete(bytes);testing.expect(t,encoded)
 restored,loaded:=decode_world_snapshot(bytes);testing.expect(t,loaded)
 if loaded {
  defer { scene_destroy(&restored.scene);delete(restored.bombs) }
  again,eok:=encode_world_snapshot(&restored);defer delete(again)
  testing.expect(t,eok && string(bytes)==string(again));valid,why:=validate_scene(&restored.scene);testing.expect(t,valid,why)
 }
 fmt.printf("Blasted rotated/wedge/glue World exact=%v bytes=%d\n",loaded,len(bytes))
}

@(test)
shape_layout_rejections_atomic :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create();defer sandbox_destroy(&g);testing.expect(t,editor_place(&g,{4,0},{5,1}));sandbox_toggle_editor(&g)
 original,lok:=encode_layout(&g.layout,42);world,wok:=encode_world_snapshot(&g.world);defer delete(original);defer delete(world);testing.expect(t,lok && wok)
 prefix:=`{"kind":"bom-layout","version":3,"seed":42,"next_identity":3,"objects":[{"identity":1,"material":"stone","lo":{"x":0,"y":0},"hi":{"x":1,"y":1}},`
 adjacent ::`{"identity":2,"material":"wood","lo":{"x":1,"y":0},"hi":{"x":2,"y":1}}]`
 cases:=[5]string{
  `{"identity":2,"material":"wood","lo":{"x":1.3,"y":0},"hi":{"x":2.3,"y":1}}],"glue":[{"a":1,"b":2}]}`,
  adjacent+`,"glue":[{"a":1,"b":9}]}`,
  adjacent+`,"glue":[{"a":1,"b":2},{"a":1,"b":2}]}`,
  `{"identity":2,"material":"wood","angle":1e999,"lo":{"x":2,"y":0},"hi":{"x":3,"y":1}}]}`,
  `{"identity":2,"material":"wood","shape":"wedge","lo":{"x":0.5,"y":0},"hi":{"x":1.5,"y":1}}]}`,
 }
 for data,i in cases {
  bytes:=fmt.aprintf("%s%s",prefix,data);accepted:=sandbox_load_layout_data(&g,transmute([]byte)bytes);delete(bytes)
  a,aok:=encode_layout(&g.layout,42);b,bok:=encode_world_snapshot(&g.world)
  testing.expect(t,!accepted && aok && bok && string(a)==string(original) && string(b)==string(world));delete(a);delete(b)
  fmt.printf("Shape rejection %d accepted=%v notice=%s unchanged=true\n",i,accepted,g.status)
 }
}
