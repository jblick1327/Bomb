package main
import rl "vendor:raylib"
import gl "vendor:raylib/rlgl"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import b2 "vendor:box2d"

texture_check_scene :: proc(recipe:Recipe,size:Vec2,floor:bool=false)->Scene {
 g:=Sandbox{world=World{scene=new_scene(0.1),settings=DEFAULT_SANDBOX_SETTINGS}}
 if !floor { append(&g.layout.objects,Authored_Shape{lo={0,0},hi=size,material=recipe_slot(recipe),identity=1}) }
 editor_build_objects(&g)
 if floor { sandbox_add_ground(&g.world.scene,int(recipe),42) }
 destroy_layout(&g.layout); return g.world.scene
}
texture_window_image :: proc(s:^Scene,caches:^Render_Cache_State,view:View,r:Authored_Shape,index:int,whole:bool)->rl.Image {
 rl.BeginDrawing(); rl.ClearBackground({19,28,42,255})
 ui_text(.Body,"Texture continuity / actual 4x MSAA",12,12,YARD_INK)
 poses:=make(map[u64]Pose)
 if whole { texture_begin(); texture_rectangle(view,r,s.materials[index]); texture_end() }
 else { draw_scene(s,caches,view,poses,0,true,false,false,true,0) }
 delete(poses); gl.DrawRenderBatchActive(); image:=rl.LoadImageFromScreen(); rl.EndDrawing(); return image
}
texture_compare_cells :: proc() {
 total:=0
 for recipe in Recipe {
  size:=Vec2{6,0.8}; floor:=false
  switch recipe { case .Glass:size={5,2.5};case .Rubber:size={1.6,0.8};case .Stone:size={17,3};floor=true;case .Wood: }
  s:=texture_check_scene(recipe,size,floor); caches:=Render_Cache_State{}
  r:=Authored_Shape{lo={0,0},hi=size}; view:=View{offset={80,650},scale=128}
  if floor { r.lo={-8,-3};r.hi={9,0};view={offset={576,350},scale=64} }
  a:=texture_window_image(&s,&caches,view,r,int(recipe),false); b:=texture_window_image(&s,&caches,view,r,int(recipe),true)
  dpi:=f32(a.width)/f32(rl.GetScreenWidth()); bad,checked,maximum:=0,0,0
  for y in 0..<a.height { for x in 0..<a.width {
   p:=world_point(view,{(f32(x)+0.5)/dpi,(f32(y)+0.5)/dpi})
   margin:=f32(2.1)/(view.scale*dpi)
   if p.x<r.lo.x+margin || p.x>r.hi.x-margin || p.y<r.lo.y+margin || p.y>r.hi.y-margin { continue }
   border:=false
   for sub in s.subdivisions { cache:=&caches.cells[sub.id]; for draw,i in cache.draw_edge {
    if !draw { continue }; edge:=Segment{cache.outline.points[i],cache.outline.points[(i+1)%len(cache.outline.points)]}
    if msaa_edge_distance(p,edge.a,edge.b)<margin { border=true; break }
   }; if border { break } }
   if border { continue }
   ca,cb:=rl.GetImageColor(a,x,y),rl.GetImageColor(b,x,y)
   delta:=max(math.abs(int(ca.r)-int(cb.r)),max(math.abs(int(ca.g)-int(cb.g)),math.abs(int(ca.b)-int(cb.b))))
   maximum=max(maximum,delta); checked+=1; if delta>2 { bad+=1 }
  } }
  fmt.printf("Continuity %s: cells=%d checked=%d max_delta=%d defects=%d\n",ui_recipe_name(recipe),len(s.subdivisions),checked,maximum,bad)
  total+=bad; rl.UnloadImage(a);rl.UnloadImage(b);release_render_caches(&caches);scene_destroy(&s)
 }
 fmt.printf("MSAA total interior defects: %d\n",total); assert(total==0)
}
texture_wrap_checks :: proc() {
 for channel in 0..<4 {
  interior_x,interior_y,wrap_x,wrap_y:f64
  for y in 0..<512 { for x in 0..<512 {
   value:=int(material_texels[(y*512+x)*4+channel])
   if x<511 { interior_x+=f64(math.abs(value-int(material_texels[(y*512+x+1)*4+channel]))) }
   if y<511 { interior_y+=f64(math.abs(value-int(material_texels[((y+1)*512+x)*4+channel]))) }
   if x==511 { wrap_x+=f64(math.abs(value-int(material_texels[(y*512)*4+channel]))) }
   if y==511 { wrap_y+=f64(math.abs(value-int(material_texels[x*4+channel]))) }
  } }
  interior_x/=512*511;interior_y/=512*511;wrap_x/=512;wrap_y/=512
  fmt.printf("Wrap channel=%d interior_xy=%v edge_xy=%v ratio_xy=%v\n",channel,[2]f64{interior_x,interior_y},[2]f64{wrap_x,wrap_y},[2]f64{wrap_x/max(interior_x,1e-10),wrap_y/max(interior_y,1e-10)})
  assert(wrap_x<=1.25*interior_x && wrap_y<=1.25*interior_y)
 }
}
texture_rect_image :: proc(m:Material,size:Vec2,scale:f32=128,origin:Vec2={})->rl.Image {
 rl.BeginDrawing();rl.ClearBackground({19,28,42,255}); texture_begin()
 texture_rectangle({offset={(320-origin.x*scale)/ui_dpi,(650+origin.y*scale)/ui_dpi},scale=scale/ui_dpi},Authored_Shape{lo=origin,hi=vadd(origin,size)},m)
 texture_end();gl.DrawRenderBatchActive(); image:=rl.LoadImageFromScreen();rl.EndDrawing();return image
}
texture_luma :: proc(c:rl.Color)->f64 { return 0.2126*f64(c.r)+0.7152*f64(c.g)+0.0722*f64(c.b) }
texture_grain_mean_checks :: proc() {
 for vertical in 0..<2 {
  size:=Vec2{4,0.8};if vertical==1 { size={0.8,4} }
  scene:=texture_check_scene(.Wood,size);caches:=Render_Cache_State{}
  image:=texture_window_image(&scene,&caches,{offset={320/ui_dpi,650/ui_dpi},scale=128/ui_dpi},Authored_Shape{lo={0,0},hi=size},0,false)
  dx,dy:f64; n:=0
  for y in i32(650-size.y*128)+3..<647 { for x in 323..<i32(320+size.x*128)-3 {
   v:=texture_luma(rl.GetImageColor(image,x,y)); dx+=math.abs(v-texture_luma(rl.GetImageColor(image,x+1,y)));dy+=math.abs(v-texture_luma(rl.GetImageColor(image,x,y+1)));n+=1
  } }
  along,across:=dx/f64(n),dy/f64(n);if vertical==1 { along,across=across,along }
  fmt.printf("Grain vertical=%d along=%.6f across=%.6f ratio=%.6f\n",vertical,along,across,across/max(along,1e-10));assert(across>=3*along);rl.UnloadImage(image);release_render_caches(&caches);scene_destroy(&scene)
 }
 mean_origin:=texture_mean_fixture_origin()
 fmt.printf("Mean-colour fixture origin=%v, size=2x2 m, physical scale=128 px/m\n",mean_origin)
 for i in 0..<6 {
  m:=editor_material(.Wood)
  if i<4 { for recipe in Recipe { if int(recipe)==i { m=editor_material(recipe) } } }
  if i==4 { m.name="coral custom";m.color={231,104,91} }
  if i==5 { m.name="yellow custom";m.color={236,215,119} }
  image:=texture_rect_image(m,{2,2},128,mean_origin);mean:[3]f64;clipped,mathematical:[3]int;n:=0
  for y in 397..<648 { for x in 322..<574 {
   tx:=int(math.floor(mean_origin.x*128+f32(x-320)+0.5))%512
   ty:=int(math.floor(mean_origin.y*128+650-f32(y)-0.5))%512
   t:=f64(material_texels[(ty*512+tx)*4+int(material_recipe(m))])/255
   for target,k in m.color { if f64(target)*2*t>255 { mathematical[k]+=1 } }
   c:=rl.GetImageColor(image,i32(x),i32(y)); rgb:=[3]u8{c.r,c.g,c.b}; for v,k in rgb { mean[k]+=f64(v);if v==255 { clipped[k]+=1 } };n+=1
  } }
  for &v in mean { v/=f64(n) }
  fmt.printf("Mean %s: target=%v actual=%v saturated_pixels=%v clipped_samples=%v\n",m.name,m.color,mean,clipped,mathematical)
  for v,k in mean { assert(math.abs(v-f64(m.color[k]))<=2) };rl.UnloadImage(image)
 }
}
texture_fragment_image :: proc(sub:Subdivision,cache:^Render_Cache,angle:f32,position:Vec2={})->rl.Image {
 outline:=make_polygon(cache.outline.points);defer delete(outline.points)
 for p,i in cache.outline.points { outline.points[i]=vadd(position,vrotate(vsub(p,sub.rest_center),angle)) }
 rl.BeginDrawing();rl.ClearBackground({19,28,42,255});texture_begin()
 texture_cached_fill({offset={640/ui_dpi,400/ui_dpi},scale=512/ui_dpi},outline,{},cache,editor_material(.Wood),false)
 texture_end();gl.DrawRenderBatchActive();image:=rl.LoadImageFromScreen();rl.EndDrawing();return image
}
texture_fragment_check :: proc() {
 s:=texture_check_scene(.Wood,{6,0.8});defer scene_destroy(&s);blast_pass(&s,Blast{{-0.1,0.4},4})
 caches:=Render_Cache_State{};defer release_render_caches(&caches);render_cache_prepass(&s,&caches)
 selected:=s.subdivisions[0]
 for p in s.pieces { if len(p.subdivisions)==1 { selected=s.subdivisions[s.sub_rows[p.subdivisions[0]]];break } }
 cache:=&caches.cells[selected.id]
 a:=texture_fragment_image(selected,cache,0);b:=texture_fragment_image(selected,cache,f32(math.PI)/6,{0.45,0.2});defer rl.UnloadImage(a);defer rl.UnloadImage(b)
 lo,hi,_,_,_:=grain_bounds(cache.outline);checked,bad,maximum:=0,0,0
 for row in 1..<20 { for col in 1..<40 {
  if checked>=20 { break }
  p:=Vec2{lo.x+(hi.x-lo.x)*f32(col)/40,lo.y+(hi.y-lo.y)*f32(row)/20}
  if !rl.CheckCollisionPointPoly({p.x,p.y},cast([^]rl.Vector2)raw_data(cache.outline.points),i32(len(cache.outline.points))) { continue }
  near:=false;for v,j in cache.outline.points { if msaa_edge_distance(p,v,cache.outline.points[(j+1)%len(cache.outline.points)])<4.0/512 { near=true } };if near { continue }
  local:=vsub(p,selected.rest_center);pa:=screen_point({offset={640,400},scale=512},local);pb:=screen_point({offset={640,400},scale=512},vadd({0.45,0.2},vrotate(local,f32(math.PI)/6)))
  ca,cb:=rl.GetImageColor(a,i32(pa.x),i32(pa.y)),rl.GetImageColor(b,i32(pb.x),i32(pb.y))
  assert(ca!=rl.Color{19,28,42,255} && cb!=rl.Color{19,28,42,255})
  d:=max(math.abs(int(ca.r)-int(cb.r)),max(math.abs(int(ca.g)-int(cb.g)),math.abs(int(ca.b)-int(cb.b))));maximum=max(maximum,d);if d>3 { bad+=1 };checked+=1
 } }
 fmt.printf("Fragment id=%d points=%d max_delta=%d defects=%d\n",selected.id,checked,maximum,bad);assert(checked==20 && bad==0)
}
texture_study_axes :: proc() {
 changed,total:=0,0
 for seed in 1..=16 { s:=wood_study_scene(u8(seed),{6,4});blast_pass(&s,Blast{{-0.1,2},5});for sub in s.subdivisions { _,_,axis,_,_:=grain_bounds(sub.outline);total+=1;if axis!=0 { changed+=1 } };scene_destroy(&s) }
 fmt.printf("Wood study axes: cells=%d differing_from_plank=%d\n",total,changed)
}
run_texture_checks :: proc() {
 assert(os.make_directory_all("evidence/textures-ui")==nil)
 track:mem.Tracking_Allocator;mem.tracking_allocator_init(&track,context.allocator);defer mem.tracking_allocator_destroy(&track);context.allocator=mem.tracking_allocator(&track)
 rl.SetTraceLogLevel(.WARNING);rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI});rl.InitWindow(1280,800,"BOM texture verification");defer rl.CloseWindow()
 sandbox_gui_style();rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{});rl.SetTargetFPS(0)
 samples,buffers:i32;msaa_gl_integer(0x80a9,&samples);msaa_gl_integer(0x80a8,&buffers);fmt.printf("Actual MSAA samples=%d buffers=%d fonts_loaded=%v\n",samples,buffers,ui_fonts_ready);assert(samples==4 && buffers==1)
 texture_wrap_checks();texture_compare_cells();texture_fragment_check();texture_grain_mean_checks();texture_study_axes()
 presentation_shutdown();fmt.printf("Teardown Odin=%d Box2D=%d texture=%d shader=%d fonts_ready=%v\n",track.current_memory_allocated,b2.GetByteCount(),material_texture.id,material_shader.id,ui_fonts_ready)
 assert(track.current_memory_allocated==0 && b2.GetByteCount()==0 && material_texture.id==0 && material_shader.id==0 && !ui_fonts_ready)
}

// Select one shared, representative quarter-tile window for all six colour checks.
texture_mean_fixture_origin :: proc()->Vec2 {
 best:=f64(1e30);result:=Vec2{}
 for oy in 0..<8 { for ox in 0..<8 {
  sums:[4]f64
  for y in 0..<256 { for x in 0..<256 { for c in 0..<4 { sums[c]+=f64(material_texels[(((y+oy*64)%512)*512+(x+ox*64)%512)*4+c]) } } }
  score:=f64(0);for value in sums { score=max(score,math.abs(value/65536-127.5)) }
  if score<best { best=score;result={f32(ox)*0.5,f32(oy)*0.5} }
 } }
 return result
}
