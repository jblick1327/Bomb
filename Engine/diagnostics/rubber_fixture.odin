package main

import "core:math"
import b2 "vendor:box2d"

// Deliberate rest-frame bend, shared by the headless and actual-MSAA checks.
rubber_bend_scene :: proc(seam_degrees: f32 = 10) -> Scene {
 s:=new_scene(0.1)
 m:=add_material(&s,editor_material(.Rubber)); owner:=add_piece(&s,m,0)
 ids:[3]u64
 for i in 0..<3 {
  x:=f32(i); points:=[4]Vec2{{x,0},{x+1,0},{x+1,1},{x,1}}; p:=Polygon{points=points[:]}
  ids[i]=add_subdivision(&s,owner,p,Pose{position=centroid(p)})
 }
 for i in 0..<2 { add_connection(&s,ids[i],ids[i+1]) }
 physics_init(&s,{},-100); physics_sync_structure(&s)
 pivot:=Vec2{0,0.5}
 for id,i in ids {
  sub:=s.subdivisions[s.sub_rows[id]]; angle:=-f32(i)*seam_degrees*f32(math.PI)/180
  pose:=Pose{position=vadd(pivot,vrotate(vsub(sub.rest_center,Vec2{f32(i),0.5}),angle)),angle=angle}
  b2.Body_SetTransform(sub.body,to_b2(pose.position),b2.MakeRot(angle))
  sub.pose=pose; pivot=posed_point(sub,{f32(i+1),0.5})
 }
 physics_read_motion(&s)
 return s
}
