package shared
import math "core:math"
import slice "core:slice"

capsule_add_angle :: proc(angles:^[dynamic]f64,angle:f64) {
 tau:=2*math.PI
 value:=angle-math.floor(angle/tau)*tau
 append(angles,value)
}
capsule_add_point_angle :: proc(angles:^[dynamic]f64,origin,point:Vec2) {
 capsule_add_angle(angles,math.atan2(f64(point.y)-f64(origin.y),f64(point.x)-f64(origin.x)))
}
capsule_edge_circle_angles :: proc(angles:^[dynamic]f64,origin,a,b,center:Vec2,radius:f64) {
 dx,dy:=f64(b.x)-f64(a.x),f64(b.y)-f64(a.y)
 ox,oy:=f64(a.x)-f64(center.x),f64(a.y)-f64(center.y)
 aa:=dx*dx+dy*dy;if aa==0 {return}
 bb:=2*(ox*dx+oy*dy);cc:=ox*ox+oy*oy-radius*radius
 discriminant:=bb*bb-4*aa*cc;if discriminant<0 {return}
 root:=math.sqrt(discriminant)
 for t in ([2]f64{(-bb-root)/(2*aa),(-bb+root)/(2*aa)}) {
  if t>=0&&t<=1 {capsule_add_angle(angles,math.atan2(f64(a.y)+dy*t-f64(origin.y),f64(a.x)+dx*t-f64(origin.x)))}
 }
}
capsule_ray_distance :: proc(center,origin:Vec2,angle:f64) -> (f32,bool) {
 dx,dy:=math.cos(angle),math.sin(angle);best:=f64(1e300)
 for offset in ([2]f32{-PLAYER_SEGMENT,PLAYER_SEGMENT}) {
  ox,oy:=f64(origin.x)-f64(center.x),f64(origin.y)-f64(center.y+offset)
  bb:=ox*dx+oy*dy;cc:=ox*ox+oy*oy-f64(PLAYER_RADIUS)*f64(PLAYER_RADIUS)
  disc:=bb*bb-cc
  if disc>=0 {hit:= -bb-math.sqrt(disc);if hit>=0 {best=min(best,hit)}}
 }
 // Middle rectangle plus the two end disks is the exact upright capsule.
 enter,exit:=f64(0),f64(1e300)
 lo:=Vec2{center.x-PLAYER_RADIUS,center.y-PLAYER_SEGMENT};hi:=Vec2{center.x+PLAYER_RADIUS,center.y+PLAYER_SEGMENT}
 for axis in 0..<2 {
  o,d,l,h:=f64(origin.x),dx,f64(lo.x),f64(hi.x)
  if axis==1 {o=f64(origin.y);d=dy;l=f64(lo.y);h=f64(hi.y)}
  if d==0 {if o<l||o>h {exit=-1};continue}
  a,b:=(l-o)/d,(h-o)/d;enter=max(enter,min(a,b));exit=min(exit,max(a,b))
 }
 if exit>=enter&&exit>=0 {best=min(best,enter)}
 return f32(best),best<1e299
}
capsule_ray_reached :: proc(c:^Cover,center:Vec2,blast:Blast,angle:f64) -> bool {
 distance,hit:=capsule_ray_distance(center,blast.position,angle)
 if !hit||blast_load(distance,blast.radius)<=0 {return false}
 point:=Vec2{f32(f64(blast.position.x)+math.cos(angle)*f64(distance)),f32(f64(blast.position.y)+math.sin(angle)*f64(distance))}
 return !cover_ray_occluded(c,blast.position,point)
}

// Visibility can change only at polygon-vertex directions, capsule tangencies,
// capsule/occluder intersections or capsule/blast-radius intersections. Test
// those directions and the open angular intervals between them. This detects
// partial exposure without an arbitrary finite set of points on the capsule.
blast_capsule_visible :: proc(c:^Cover,center:Vec2,blast:Blast) -> bool {
 if !valid_vec(center)||!valid_vec(blast.position)||!finite(blast.radius)||blast.radius<=0 {return false}
 nearest:=Vec2{center.x,clamp(blast.position.y,center.y-PLAYER_SEGMENT,center.y+PLAYER_SEGMENT)}
 gap:=vlen(vsub(blast.position,nearest))-PLAYER_RADIUS
 if gap<=0 {return true}
 if blast_load(gap,blast.radius)<=0 {return false}
 angles:[dynamic]f64;defer delete(angles);append(&angles,0)
 radius:=f64(PLAYER_RADIUS)
 for offset in ([2]f32{-PLAYER_SEGMENT,PLAYER_SEGMENT}) {
  cap:=Vec2{center.x,center.y+offset}
  x,y:=f64(cap.x)-f64(blast.position.x),f64(cap.y)-f64(blast.position.y)
  distance:=math.sqrt(x*x+y*y);base:=math.atan2(y,x)
  if distance>radius {spread:=math.asin(radius/distance);capsule_add_angle(&angles,base-spread);capsule_add_angle(&angles,base+spread)}
  if distance>0 {
   cosine:=(distance*distance+f64(blast.radius)*f64(blast.radius)-radius*radius)/(2*distance*f64(blast.radius))
   if cosine>= -1&&cosine<=1 {spread:=math.acos(cosine);capsule_add_angle(&angles,base-spread);capsule_add_angle(&angles,base+spread)}
  }
 }
 for x in ([2]f32{center.x-PLAYER_RADIUS,center.x+PLAYER_RADIUS}) {
  for y in ([2]f32{center.y-PLAYER_SEGMENT,center.y+PLAYER_SEGMENT}) {capsule_add_point_angle(&angles,blast.position,{x,y})}
  delta:=f64(x)-f64(blast.position.x);square:=f64(blast.radius)*f64(blast.radius)-delta*delta
  if square>=0 {for sign in ([2]f64{-1,1}) {
   y:=f64(blast.position.y)+sign*math.sqrt(square)
   if y>=f64(center.y-PLAYER_SEGMENT)&&y<=f64(center.y+PLAYER_SEGMENT) {capsule_add_point_angle(&angles,blast.position,{x,f32(y)})}
  }}
 }
 lo:=Vec2{min(blast.position.x,center.x-PLAYER_RADIUS),min(blast.position.y,center.y-PLAYER_HALF_HEIGHT)}
 hi:=Vec2{max(blast.position.x,center.x+PLAYER_RADIUS),max(blast.position.y,center.y+PLAYER_HALF_HEIGHT)}
 cover_candidates(c,lo,hi)
 for index in c.candidates {
  cell:=c.cells[index]
  for a,i in cell.points {
   b:=cell.points[(i+1)%len(cell.points)]
   capsule_add_point_angle(&angles,blast.position,a)
   for offset in ([2]f32{-PLAYER_SEGMENT,PLAYER_SEGMENT}) {capsule_edge_circle_angles(&angles,blast.position,a,b,{center.x,center.y+offset},radius)}
   if b.x!=a.x {for side in ([2]f32{center.x-PLAYER_RADIUS,center.x+PLAYER_RADIUS}) {
    t:=(f64(side)-f64(a.x))/(f64(b.x)-f64(a.x));y:=f64(a.y)+(f64(b.y)-f64(a.y))*t
    if t>=0&&t<=1&&y>=f64(center.y-PLAYER_SEGMENT)&&y<=f64(center.y+PLAYER_SEGMENT) {capsule_add_point_angle(&angles,blast.position,{side,f32(y)})}
   }}
  }
 }
 slice.sort(angles[:])
 unique:=0
 for angle in angles {if unique==0||angle!=angles[unique-1] {angles[unique]=angle;unique+=1}}
 resize(&angles,unique)
 for angle,i in angles {
  if capsule_ray_reached(c,center,blast,angle) {return true}
  next:=angles[0]+2*math.PI;if i+1<len(angles) {next=angles[i+1]}
  if next>angle&&capsule_ray_reached(c,center,blast,(angle+next)*.5) {return true}
 }
 return false
}
