package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import "core:fmt"
import "core:math"
import "core:time"

when ODIN_OS == .Windows {
 foreign import msaa_gl "system:opengl32.lib"
 foreign msaa_gl {
  @(link_name="glGetIntegerv")
  msaa_gl_integer :: proc "system" (name: u32,value: ^i32) ---
 }
}

msaa_edge_distance :: proc(p,a,b: Vec2) -> f32 {
 edge:=vsub(b,a)
 t:=clamp(vdot(vsub(p,a),edge)/max(vdot(edge,edge),f32(1e-20)),f32(0),f32(1))
 return vlen(vsub(p,vadd(a,vmul(edge,t))))
}

msaa_film_pixels :: proc(s: ^Scene,view: View,poses: map[u64]Pose,image: rl.Image) -> (int,int) {
 dpi:=f32(image.width)/f32(rl.GetScreenWidth())
 pixel_view:=View{offset=vmul(view.offset,dpi),scale=view.scale*dpi}
 bad,checked:=0,0
 for sub in s.subdivisions {
  cache:=ensure_render_cache(s,sub.id); outline:=render_outline(s,sub,poses,true); defer delete(outline.points)
  for draw,i in cache.draw_edge {
   if !draw { continue }
   p:=screen_point(pixel_view,vmul(vadd(outline.points[i],outline.points[(i+1)%len(outline.points)]),0.5))
   actual:=rl.GetImageColor(image,i32(math.floor(p.x)),i32(math.floor(p.y))); checked+=1
   if math.abs(int(actual.r)-105)>6 || math.abs(int(actual.g)-73)>6 || math.abs(int(actual.b)-120)>6 { bad+=1 }
  }
 }
 return bad,checked
}

msaa_floor_bright_pixels :: proc(s: ^Scene,view: View,poses: map[u64]Pose,frames: map[u64]Pose,image: rl.Image) -> (int,int) {
 dpi:=f32(image.width)/f32(rl.GetScreenWidth()); w,h:=int(image.width),int(image.height)
 pixel_view:=View{offset=vmul(view.offset,dpi),scale=view.scale*dpi}
 floor:=make([]bool,w*h); defer delete(floor)
 for sub in s.subdivisions {
  if sub.material!=0 { continue }
  outline:=render_outline(s,sub,poses,true,frames); defer delete(outline.points)
  points:=make([]rl.Vector2,len(outline.points)); defer delete(points)
  lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
  for point,i in outline.points { p:=screen_point(pixel_view,point); points[i]=p; lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)} }
  x0,x1:=max(0,int(math.floor(lo.x))),min(w-1,int(math.ceil(hi.x)))
  y0,y1:=max(int(math.ceil(pixel_view.offset.y+3-0.5)),max(0,int(math.floor(lo.y)))),min(h-1,int(math.ceil(hi.y)))
  for y in y0..=y1 { for x in x0..=x1 { if rl.CheckCollisionPointPoly({f32(x)+0.5,f32(y)+0.5},raw_data(points),i32(len(points))) { floor[y*w+x]=true } } }
 }
 bad,checked:=0,0
 for inside,i in floor {
  if !inside { continue }; checked+=1
  actual:=rl.GetImageColor(image,i32(i%w),i32(i/w))
  if actual.r>134 || actual.g>148 || actual.b>155 { bad+=1 }
 }
 return bad,checked
}

// Measure interiors, including bonded seams, but exclude silhouettes/crack strokes.
msaa_measure :: proc(s: ^Scene,view: View,poses: map[u64]Pose,frames: map[u64]Pose,image: rl.Image,width: f32) -> (int,int) {
 w,h:=int(image.width),int(image.height)
 // High-DPI windows expose logical drawing coordinates and physical image pixels.
 dpi:=f32(image.width)/f32(rl.GetScreenWidth())
 pixel_view:=View{offset=vmul(view.offset,dpi),scale=view.scale*dpi}
 expected:=make([]rl.Color,w*h); defer delete(expected)
 excluded:=make([]bool,w*h); defer delete(excluded)
 for sub in s.subdivisions {
  cache:=ensure_render_cache(s,sub.id)
  outline:=render_outline(s,sub,poses,true,frames); defer delete(outline.points)
  points:=make([]rl.Vector2,len(outline.points)); defer delete(points)
  lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
  for point,i in outline.points {
   p:=screen_point(pixel_view,point); points[i]=p
   lo={min(lo.x,p.x),min(lo.y,p.y)}; hi={max(hi.x,p.x),max(hi.y,p.y)}
  }
  color:=editor_color(s.materials[sub.material].name)
  a:=f32(color.a)/255
  flat:=rl.Color{u8(math.round(f32(color.r)*a+19*(1-a))),u8(math.round(f32(color.g)*a+28*(1-a))),u8(math.round(f32(color.b)*a+42*(1-a))),255}
  x0,x1:=max(0,int(math.floor(lo.x))-4),min(w-1,int(math.ceil(hi.x))+4)
  y0,y1:=max(0,int(math.floor(lo.y))-4),min(h-1,int(math.ceil(hi.y))+4)
  for y in y0..=y1 { for x in x0..=x1 {
   pixel:=rl.Vector2{f32(x)+0.5,f32(y)+0.5}
   if rl.CheckCollisionPointPoly(pixel,raw_data(points),i32(len(points))) { expected[y*w+x]=flat }
  } }
  stroke_width:=max(f32(1),width)
  if s.materials[sub.material].flexibility>0 { stroke_width=max(FILM_PX,width) }
  margin:=2+stroke_width*dpi*0.5
  for draw,i in cache.draw_edge {
   if !draw { continue }
   a,b:=points[i],points[(i+1)%len(points)]
   ex0,ex1:=max(0,int(math.floor(min(a.x,b.x)-margin))),min(w-1,int(math.ceil(max(a.x,b.x)+margin)))
   ey0,ey1:=max(0,int(math.floor(min(a.y,b.y)-margin))),min(h-1,int(math.ceil(max(a.y,b.y)+margin)))
   for y in ey0..=ey1 { for x in ex0..=ex1 {
    if msaa_edge_distance({f32(x)+0.5,f32(y)+0.5},{a.x,a.y},{b.x,b.y})<=margin { excluded[y*w+x]=true }
   } }
  }
 }
 bad,checked:=0,0
 for color,i in expected {
  if color.a==0 || excluded[i] { continue }
  actual:=rl.GetImageColor(image,i32(i%w),i32(i/w)); checked+=1
  if math.abs(int(actual.r)-int(color.r))>8 || math.abs(int(actual.g)-int(color.g))>8 || math.abs(int(actual.b)-int(color.b))>8 { if bad<8 { fmt.printf("interior pixel (%d,%d) actual=%v expected=%v\n",i%w,i/w,actual,color) }; bad+=1 }
 }
 return bad,checked
}

// Intentionally draw to the MSAA window, flush, and read BEFORE buffer swapping.
sandbox_smoke_msaa :: proc() {
 when ODIN_OS == .Windows {
  samples,buffers:i32
  msaa_gl_integer(0x80a9,&samples); msaa_gl_integer(0x80a8,&buffers)
  fmt.printf("MSAA default framebuffer: samples=%d sample_buffers=%d\n",samples,buffers)
  assert(samples==4 && buffers==1,"Capture must exercise actual 4x MSAA")
 }
 fmt.printf("Window logical=%dx%d framebuffer=%dx%d DPI=%v\n",rl.GetScreenWidth(),rl.GetScreenHeight(),rl.GetRenderWidth(),rl.GetRenderHeight(),rl.GetWindowScaleDPI())
 texture:=rl.GetShapesTexture(); rect:=rl.GetShapesTextureRectangle()
 fmt.printf("Shapes texture: id=%d size=%dx%d rect=%v\n",texture.id,texture.width,texture.height,rect)
 total,film_bad,floor_bad:=0,0,0
 for fixture in 0..<5 {
  game:=sandbox_editor_create()
  // Same ordinary Wood placement used by the native editor playthrough.
  hi:=Vec2{3.1,1.6}; lo:=Vec2{1.5,0}
  view:=sandbox_view(1280,800)
  name:=string("yard")
  if fixture==1 || fixture==3 { lo={0,0}; hi={6,4}; view={offset={140,700},scale=150}; name="wood6x4" }
  assert(editor_place(&game,lo,hi)); sandbox_toggle_editor(&game)
  for _ in 0..<120 { sandbox_tick(&game,0,false) }
  if fixture==2 {
   scene_destroy(&game.scene); game.scene=msaa_border_scene(); clear(&game.previous); name="borders"
  }
  if fixture==4 {
   scene_destroy(&game.scene); game.scene=rubber_bend_scene(); clear(&game.previous)
   name="rubber-bend"; view={offset={140,700},scale=150}
  }
  if fixture==3 {
   sandbox_explode(&game,{-0.1,2}); name="wood-blast"
   for _ in 0..<5 {
    for &sub in game.scene.subdivisions { if sub.material==0 { release_render_cache(&sub.render) } }
    start:=time.tick_now()
    for sub in game.scene.subdivisions { if sub.material==0 { ensure_render_cache(&game.scene,sub.id) } }
    fmt.printf("Floor cache rebuild ms: %.6f\n",f64(time.tick_diff(start,time.tick_now()))/f64(time.Millisecond))
   }
  }
  before,ok:=encode_snapshot(&game.scene); assert(ok)
  path:=fmt.aprintf("output/msaa-%s.json",name)
  assert(save_snapshot(&game.scene,path)); delete(path)
  poses:=make(map[u64]Pose)
  for sub in game.scene.subdivisions {
   pose:=sub.pose
   if old,found:=game.previous[sub.id]; found { pose=interpolate_region_pose(&game.scene,sub,old,0.5) }
   poses[sub.id]=pose
  }
  frames:=render_piece_frames(&game.scene,poses,game.previous,0.5)
  widths:=[2]f32{0,2}
  for width in widths {
   rl.BeginDrawing()
   rl.ClearBackground({19,28,42,255})
   draw_scene(&game.scene,view,poses,0,true,false,false,true,width,frames)
   rlgl.DrawRenderBatchActive()
   image:=rl.LoadImageFromScreen()
   rl.EndDrawing()
   bad,checked:=msaa_measure(&game.scene,view,poses,frames,image,width)
   fmt.printf("MSAA,%s,%.0f,%d,%d\n",name,width,bad,checked)
   if fixture==4 && width==0 { count,samples:=msaa_film_pixels(&game.scene,view,poses,image); film_bad+=count; fmt.printf("B film: bad=%d checked=%d\n",count,samples) }
   if fixture==3 && width==0 { count,samples:=msaa_floor_bright_pixels(&game.scene,view,poses,frames,image); floor_bad+=count; fmt.printf("D floor: bright=%d checked=%d\n",count,samples) }
   assert(rl.ExportImage(image,rl.TextFormat("output/msaa-%s-%.0f.png",name,width)))
   rl.UnloadImage(image)
   total+=bad
  }
  after,encoded:=encode_snapshot(&game.scene)
  assert(encoded && string(before)==string(after),"MSAA captures must not mutate simulation")
  delete(before); delete(after); delete(poses); delete(frames); sandbox_destroy(&game)
 }
 fmt.printf("MSAA total interior defects: %d\n",total)
 assert(total==0,"MSAA window has interior seam dots")
 assert(film_bad==0,"Rubber film midpoint pixels must match within six")
 assert(floor_bad==0,"Opaque floor interiors must have no bright seals")
}

// Two anchored neighbours and a rigid cycle with a broken internal bond.
msaa_border_scene :: proc() -> Scene {
 s:=new_scene(0.1)
 stone:=add_material(&s,editor_material(.Stone)); wood:=add_material(&s,editor_material(.Wood))
 for side in 0..<2 {
  p:=add_piece(&s,stone,u8(42+side)); x0,x1:=f32(-8),f32(0); if side==1 { x0=0; x1=9 }
  points:=[4]Vec2{{x0,-3},{x1,-3},{x1,0},{x0,0}}; poly:=Polygon{points=points[:]}
  add_subdivision(&s,p,poly,Pose{position=centroid(poly)}); presplit_piece(&s,p)
 }
 owner:=add_piece(&s,wood,0); ids:[4]u64
 for i in 0..<4 {
  x,y:=f32(1+i%2),f32(i/2); points:=[4]Vec2{{x,y},{x+1,y},{x+1,y+1},{x,y+1}}; p:=Polygon{points=points[:]}
  ids[i]=add_subdivision(&s,owner,p,Pose{position=centroid(p)})
 }
 for a in 0..<4 { for b in a+1..<4 { add_connection(&s,ids[a],ids[b]) } }
 physics_init(&s,{},-3)
 f:=Failures{}; append(&f.connections,s.connection_pairs[pair_key(ids[0],ids[1])]); apply_failures(&s,f); free_failures(&f); physics_sync_structure(&s)
 return s
}
