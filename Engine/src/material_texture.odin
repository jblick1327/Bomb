package main
import rl "vendor:raylib"
import gl "vendor:raylib/rlgl"
import "core:math"
import "core:mem"

TEXTURE_SIZE :: 512
material_texture:rl.Texture2D
material_shader:rl.Shader
material_texels:[]u8
material_texture_allocator:mem.Allocator
texture_hash :: proc(x,y,seed:int)->f32 {
 h:=u32(x)*0x9e3779b9 ~ u32(y)*0x85ebca6b ~ u32(seed)*0xc2b2ae35
 h~=h>>16; h*=0x7feb352d; h~=h>>15; h*=0x846ca68b; h~=h>>16
 return f32(h>>8)/16777216
}
texture_vnoise :: proc(x,y:f32,cu,cv,seed:int)->f32 {
 u,v:=x*f32(cu)/512,y*f32(cv)/512
 ix,iy:=int(math.floor(u)),int(math.floor(v)); a,b:=u-f32(ix),v-f32(iy)
 a=a*a*(3-2*a); b=b*b*(3-2*b)
 x0,y0:=((ix%cu)+cu)%cu,((iy%cv)+cv)%cv; x1,y1:=(x0+1)%cu,(y0+1)%cv
 p,q:=texture_hash(x0,y0,seed),texture_hash(x1,y0,seed); r,s:=texture_hash(x0,y1,seed),texture_hash(x1,y1,seed)
 return (p+(q-p)*a)*(1-b)+(r+(s-r)*a)*b
}
texture_fbm :: proc(x,y:f32,cu,cv,oct,seed:int)->f32 {
 value,weights:f32; weight:=f32(1)
 for o in 0..<oct { value+=weight*texture_vnoise(x,y,cu<<uint(o),cv<<uint(o),seed+o); weights+=weight; weight*=0.5 }
 return value/weights
}
texture_bilinear :: proc(values:[]f32,x,y:f32)->f32 {
 ix,iy:=int(math.floor(x)),int(math.floor(y)); a,b:=x-f32(ix),y-f32(iy)
 x0,y0:=((ix%512)+512)%512,((iy%512)+512)%512; x1,y1:=(x0+1)%512,(y0+1)%512
 return (values[y0*512+x0]*(1-a)+values[y0*512+x1]*a)*(1-b)+(values[y1*512+x0]*(1-a)+values[y1*512+x1]*a)*b
}
texture_generate :: proc()->[]u8 {
 bytes:=make([]u8,512*512*4)
 raw,lines:=make([]f32,512*512),make([]f32,512*512); defer delete(raw); defer delete(lines)
 for y in 0..<512 { for x in 0..<512 { lines[y*512+x]=texture_fbm(f32(x),f32(y),1,40,3,21) } }
 amplitudes:=[4]f32{0.2,0.06,0.05,0.12}
 for channel in 0..<4 {
  sum:f64
  for y in 0..<512 { for x in 0..<512 {
   fx,fy:=f32(x),f32(y); n:f32
   switch channel {
   case 0:warp:=(texture_fbm(fx,fy,2,2,3,11)-0.5)*14; n=0.65*texture_bilinear(lines,fx,fy+warp)+0.35*texture_fbm(fx,fy,4,160,2,31)
   case 1:n=0.6*math.sin(2*f32(math.PI)*3*(fx+fy)/512)+0.4*texture_fbm(fx,fy,4,4,3,51)
   case 2:n=texture_fbm(fx,fy,32,32,3,61)
   case 3:n=texture_fbm(fx,fy,8,8,5,41); if texture_hash(x,y,71)>0.985 { n+=0.35 }; if texture_hash(x,y,81)>0.99 { n-=0.25 }
   }
   raw[y*512+x]=n; sum+=f64(n)
  } }
  mean:=sum/f64(len(raw)); variance:f64; for n in raw { variance+=(f64(n)-mean)*(f64(n)-mean) }; std:=math.sqrt(variance/f64(len(raw)))
  for n,i in raw { normalized:=clamp(0.5+(f64(n)-mean)/(6*std),f64(0),f64(1)); t:=0.5+f64(amplitudes[channel])*(normalized-0.5); bytes[i*4+channel]=u8(math.round(t*255)) }
 }
 return bytes
}
texture_init :: proc() {
 if material_texture.id!=0 { return }
 material_texture_allocator=context.allocator; material_texels=texture_generate()
 image:=rl.Image{data=raw_data(material_texels),width=512,height=512,mipmaps=1,format=.UNCOMPRESSED_R8G8B8A8}
 material_texture=rl.LoadTextureFromImage(image); rl.SetTextureWrap(material_texture,.REPEAT); rl.GenTextureMipmaps(&material_texture); rl.SetTextureFilter(material_texture,.TRILINEAR)
 shader:cstring=`#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
out vec4 finalColor;
void main() {
 vec4 channels = texture(texture0, fragTexCoord);
 int family = int(round(fragColor.a * 3.0));
 float t = family == 0 ? channels.r : family == 1 ? channels.g : family == 2 ? channels.b : channels.a;
 finalColor = vec4(clamp(fragColor.rgb * (2.0*t), 0.0, 1.0), 1.0);
}`
 material_shader=rl.LoadShaderFromMemory(nil,shader); assert(material_shader.id!=0)
}
texture_shutdown :: proc() {
 if material_shader.id!=0 { rl.UnloadShader(material_shader); material_shader={} }
 if material_texture.id!=0 { rl.UnloadTexture(material_texture); material_texture={} }
 delete(material_texels,material_texture_allocator); material_texels=nil
}
presentation_shutdown :: proc() { texture_shutdown(); ui_font_shutdown() }
material_recipe :: proc(m:Material)->Recipe {
 if m.aspect_ratio<1 { return .Wood }; if m.triangulate { return .Glass }; if m.flexibility>0 { return .Rubber }; return .Stone
}
texture_begin :: proc() { rl.BeginShaderMode(material_shader); gl.Begin(gl.TRIANGLES); gl.SetTexture(material_texture.id) }
texture_end :: proc() { gl.End(); gl.SetTexture(gl.GetTextureIdDefault()); rl.EndShaderMode() }
texture_vertex :: proc(view:View,world,rest:Vec2,vertical:bool,frame:f32=0) {
 uv:=vmul(rest,0.25); if frame!=0 { uv=vmul(vrotate(rest,-frame),0.25) }; if vertical { uv={uv.y,uv.x} }
 gl.TexCoord2f(uv.x,uv.y); p:=screen_point(view,world); gl.Vertex2f(p.x,p.y)
}
texture_triangle :: proc(view:View,world,rest:[3]Vec2,color:rl.Color,recipe:Recipe,vertical:bool,frame:f32=0) {
 gl.Color4ub(color.r,color.g,color.b,u8(int(recipe)*85))
 a,b,c:=screen_point(view,world[0]),screen_point(view,world[1]),screen_point(view,world[2])
 cross:=(f64(b.x)-f64(a.x))*(f64(c.y)-f64(a.y))-(f64(b.y)-f64(a.y))*(f64(c.x)-f64(a.x))
 order:=[3]int{0,1,2}; if cross>=0 { order={2,1,0} }
 for i in order { texture_vertex(view,world[i],rest[i],vertical,frame) }
}
texture_cached_fill :: proc(view:View,outline:Polygon,hub:Vec2,cache:^Render_Cache,m:Material,vertical:bool,frame:f32=0) {
 for i:=0;i+2<len(cache.triangles);i+=3 {
  world,rest:[3]Vec2
  for j in 0..<3 { index:=cache.triangles[i+j]; world[j]=fill_point(outline,hub,index); rest[j]=fill_point(cache.outline,cache.hub,index) }
  texture_triangle(view,world,rest,material_color(m),material_recipe(m),vertical,frame)
 }
}
texture_rectangle :: proc(view:View,r:Authored_Shape,m:Material) {
 p:=shape_polygon(r);defer delete(p.points)
 vertical:=m.aspect_ratio<1 && r.hi.y-r.lo.y>r.hi.x-r.lo.x
 for i in 1..<len(p.points)-1 { triangle:=[3]Vec2{p.points[0],p.points[i],p.points[i+1]};texture_triangle(view,triangle,triangle,material_color(m),material_recipe(m),vertical,r.angle*math.PI/180) }
}
