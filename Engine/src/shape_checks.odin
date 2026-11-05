package main
import rl "vendor:raylib"
import gl "vendor:raylib/rlgl"
import b2 "vendor:box2d"
import "core:math"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:time"

shape_check_scene :: proc(r:Authored_Shape,recipe:Recipe)->Scene {
 s:=new_scene(0.1);add_material(&s,editor_material(recipe));owner:=add_piece(&s,0,42);build_shaped_object(&s,r,owner);return s
}
shape_texture_checks :: proc() {
 for wedge in ([2]bool{false,true}) {
  r:=Authored_Shape{lo={-3,-0.4},hi={3,0.4},angle=30};recipe:=Recipe.Wood
  if wedge { r.lo={-1,-0.5};r.hi={1,0.5};r.shape=.Wedge;recipe=.Stone }
  s:=shape_check_scene(r,recipe);caches:=Render_Cache_State{}
  view:=View{offset={640/ui_dpi,400/ui_dpi},scale=128/ui_dpi}
  a:=texture_window_image(&s,&caches,view,r,0,false);b:=texture_window_image(&s,&caches,view,r,0,true)
  dpi:=f32(a.width)/f32(rl.GetScreenWidth());p:=shape_polygon(r);checked,bad,maximum:=0,0,0
  margin:=f32(2.1)/(view.scale*dpi)
  for y in 0..<a.height { for x in 0..<a.width {
   point:=world_point(view,{(f32(x)+0.5)/dpi,(f32(y)+0.5)/dpi})
   if !convex_contains(p,point) || vlen(vsub(point,boundary_nearest(p,point)))<margin { continue }
   border:=false
   for sub in s.subdivisions { cache:=&caches.cells[sub.id];for drawn,i in cache.draw_edge { if drawn && msaa_edge_distance(point,cache.outline.points[i],cache.outline.points[(i+1)%len(cache.outline.points)])<margin { border=true;break } };if border { break } }
   if border { continue }
   ca,cb:=rl.GetImageColor(a,x,y),rl.GetImageColor(b,x,y)
   delta:=max(math.abs(int(ca.r)-int(cb.r)),max(math.abs(int(ca.g)-int(cb.g)),math.abs(int(ca.b)-int(cb.b))))
   maximum=max(maximum,delta);checked+=1;if delta>2 { bad+=1 }
  } }
  fmt.printf("Shape MSAA wedge=%v cells=%d checked=%d max_delta=%d defects=%d\n",wedge,len(s.subdivisions),checked,maximum,bad);assert(checked>1000 && bad==0)
  if !wedge {
   along,across:f64;count:=0
   for y in 0..<60 { for x in 0..<500 {
    local:=Vec2{-2.8+f32(x)/128,-0.25+f32(y)/128};world:=vrotate(local,math.PI/6)
    screen:=screen_point(view,world);screen.x*=dpi;screen.y*=dpi
    dx,dy:=vrotate({1,0},math.PI/6),vrotate({0,1},math.PI/6)
    value:=shape_image_luma(a,screen.x,screen.y)
    along+=math.abs(value-shape_image_luma(a,screen.x+dx.x,screen.y-dx.y));across+=math.abs(value-shape_image_luma(a,screen.x+dy.x,screen.y-dy.y));count+=1
   } }
   fmt.printf("Rotated grain physical128px/m samples=%d along=%.6f across=%.6f ratio=%.6f\n",count,along/f64(count),across/f64(count),across/max(along,1e-10));assert(across>=3*along)
  }
  delete(p.points);rl.UnloadImage(a);rl.UnloadImage(b);release_render_caches(&caches);scene_destroy(&s)
 }
}
shape_image_luma :: proc(image:rl.Image,x,y:f32)->f64 {
 ix,iy:=i32(math.floor(x)),i32(math.floor(y));u,v:=f64(x-f32(ix)),f64(y-f32(iy))
 a,b:=texture_luma(rl.GetImageColor(image,ix,iy)),texture_luma(rl.GetImageColor(image,ix+1,iy))
 c,d:=texture_luma(rl.GetImageColor(image,ix,iy+1)),texture_luma(rl.GetImageColor(image,ix+1,iy+1))
 return (a*(1-u)+b*u)*(1-v)+(c*(1-u)+d*u)*v
}
shape_key :: proc(g:^Sandbox,target:rl.RenderTexture2D,key:rl.KeyboardKey) {
 sandbox_smoke_frame(g,target,smoke_key(key,true));sandbox_smoke_frame(g,target,smoke_key(key,false))
}
shape_click :: proc(g:^Sandbox,target:rl.RenderTexture2D,p:Vec2) {
 screen:=screen_point(sandbox_view(1280,800),p);sandbox_smoke_click(g,target,i32(screen.x),i32(screen.y))
}
shape_native_smoke :: proc() {
 g:=sandbox_editor_create();defer sandbox_destroy(&g)
 directory:=fmt.aprintf("output/shape-smoke-%d",time.to_unix_nanoseconds(time.now()));defer delete(directory);assert(os.make_directory_all(directory)==nil);g.layout_directory=directory
 target:=rl.LoadRenderTexture(1280,800);defer rl.UnloadRenderTexture(target)
 sandbox_smoke_frame(&g,target,smoke_mouse(20,40),smoke_button(false))
 editor_smoke_drag(&g,target,{0,0},{0.5,3});assert(len(g.layout.objects)==1)
 shape_key(&g,target,.E);shape_key(&g,target,.E);assert(g.editor.angle==30)
 editor_smoke_drag(&g,target,{0.6,1.4},{2.6,1.7});assert(len(g.layout.objects)==2)
 wall,beam:=g.layout.objects[0],g.layout.objects[1];a,b:=shape_polygon(wall),shape_polygon(beam);distance,_:=polygon_contact(a,b);assert(distance<1e-5 && !shape_overlap(wall,beam));delete(a.points);delete(b.points)
 editor_smoke_drag(&g,target,{0.6,1.4},{2.6,1.7});assert(len(g.layout.objects)==2 && g.status=="Overlaps an object")
 shape_key(&g,target,.T);editor_smoke_drag(&g,target,{4,1},{6,2});assert(len(g.layout.objects)==3 && g.layout.objects[2].shape==.Wedge)
 shape_key(&g,target,.G);assert(g.editor.glue_tool)
 shape_click(&g,target,{0.25,1.5});shape_click(&g,target,vmul(vadd(beam.lo,beam.hi),0.5));assert(len(g.layout.glue)==1)
 shape_click(&g,target,{0.25,1.5});shape_click(&g,target,vmul(vadd(beam.lo,beam.hi),0.5));assert(len(g.layout.glue)==0)
 shape_click(&g,target,{0.25,1.5});shape_click(&g,target,vmul(vadd(beam.lo,beam.hi),0.5));assert(len(g.layout.glue)==1)
 shape_click(&g,target,{0.25,0.5});shape_click(&g,target,{0.25,-0.2});assert(len(g.layout.glue)==2 && g.layout.glue[1].b==0)
 shape_click(&g,target,{0.25,1.5});p:=shape_polygon(g.layout.objects[2]);shape_click(&g,target,centroid(p));delete(p.points);assert(g.status=="Objects must touch to glue" && len(g.layout.glue)==2)
 shape_key(&g,target,.ESCAPE);assert(!g.editor.glue_tool && !g.panel_open)
 assert(sandbox_save_current_layout(&g));assert(len(g.layout_files)==1)
 before,ok:=encode_layout(&g.layout,g.world.settings.seed);assert(ok);defer delete(before)
 assert(sandbox_load_layout_file(&g,g.layout_files[0].path));after,aok:=encode_layout(&g.layout,g.world.settings.seed);assert(aok && string(before)==string(after));delete(after)
 shape_key(&g,target,.ENTER);assert(!g.editor.editing);shape_key(&g,target,.ENTER);assert(g.editor.editing)
 screen:=screen_point(sandbox_view(1280,800),vmul(vadd(beam.lo,beam.hi),0.5))
 sandbox_smoke_frame(&g,target,smoke_mouse(i32(screen.x),i32(screen.y)),rl.AutomationEvent{type=5,params={1,0,0,0}})
 sandbox_smoke_frame(&g,target,rl.AutomationEvent{type=6,params={1,0,0,0}})
 assert(len(g.layout.objects)==2 && len(g.layout.glue)==1 && g.layout.glue[0].b==0)
 fmt.printf("Shape native smoke: rotate, wedge, snap_distance=%.9f, overlap rejection, glue link/unlink/floor/not-touching, Escape, delete links, save/load, Test/Edit passed\n",distance)
}
shape_demo_captures :: proc() {
 g:=sandbox_editor_create();defer sandbox_destroy(&g);l:=shape_demo_layout();data,ok:=encode_layout(&l,42);destroy_layout(&l);assert(ok);defer delete(data)
 assert(sandbox_load_layout_data(&g,data));assert(os.write_entire_file("evidence/rotation-glue/demo-layout.json",data)==nil)
 target:=rl.LoadRenderTexture(1280,800);defer rl.UnloadRenderTexture(target)
 poses:=make(map[u64]Pose);defer delete(poses)
 for i in 0..<3 {
  view:=sandbox_view(1280,800)
  if i==1 { view={offset={1120,1200},scale=400} }
  if i==2 { sandbox_toggle_editor(&g);sandbox_fixture_radius(&g,4);sandbox_explode(&g,{-3.8,0.5});for _ in 0..<20 { sandbox_tick(&g,0,false) } }
  g.status_time=0;ui_overflows=0
  rl.BeginDrawing();rl.BeginTextureMode(target);rl.ClearBackground({19,28,42,255});if i==1 {
   texture_begin();for object in g.layout.objects { texture_rectangle(view,object,layout_material(&g.layout,object.material)) };texture_end()
   for object in g.layout.objects { draw_shape_outline(view,object,2,YARD_INK) };draw_editor_glue(&g,view)
   rl.DrawRectangle(0,0,1280,88,{19,28,42,255});ui_text(.Title,"Glue at a leaning beam",24,20,YARD_INK);ui_text(.Small,"Wood / Stone",24,58,YARD_MUTED)
  } else { sandbox_draw_world(&g,view,poses);sandbox_draw_hud(&g,1280,800) };rl.EndTextureMode();rl.EndDrawing()
  name:=cstring("evidence/rotation-glue/demo-edit.png");if i==1 { name="evidence/rotation-glue/glue-closeup.png" };if i==2 { name="evidence/rotation-glue/demo-test-blast.png" }
  sandbox_smoke_export(target,name);fmt.printf("Capture %s overflow=%d\n",name,ui_overflows);assert(ui_overflows==0)
 }
}
run_shape_checks :: proc() {
 assert(os.make_directory_all("evidence/rotation-glue")==nil)
 track:mem.Tracking_Allocator;mem.tracking_allocator_init(&track,context.allocator);defer mem.tracking_allocator_destroy(&track);context.allocator=mem.tracking_allocator(&track)
 rl.SetTraceLogLevel(.WARNING);rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_HIGHDPI});rl.InitWindow(1280,800,"BOM shapes and glue verification");defer rl.CloseWindow()
 rl.SetExitKey(.KEY_NULL);sandbox_gui_style();rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{});rl.SetTargetFPS(0)
 samples,buffers:i32;msaa_gl_integer(0x80a9,&samples);msaa_gl_integer(0x80a8,&buffers);fmt.printf("Actual MSAA samples=%d buffers=%d fonts=%v\n",samples,buffers,ui_fonts_ready);assert(samples==4 && buffers==1)
 shape_texture_checks();shape_native_smoke();shape_demo_captures()
 presentation_shutdown();fmt.printf("Shape teardown Odin=%d Box2D=%d texture=%d shader=%d fonts=%v\n",track.current_memory_allocated,b2.GetByteCount(),material_texture.id,material_shader.id,ui_fonts_ready);assert(track.current_memory_allocated==0 && b2.GetByteCount()==0)
}
