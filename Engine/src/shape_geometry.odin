package main
import "core:math"

shape_snap :: proc(layout:^Layout,r:Authored_Shape)->Authored_Shape {
 if r.shape==.Rect && math.mod(r.angle,90)==0 { return r }
 spawn:=Authored_Shape{lo={PLAYER_SPAWN.x-PLAYER_RADIUS,0},hi={PLAYER_SPAWN.x+PLAYER_RADIUS,PLAYER_SPAWN.y+PLAYER_HALF_HEIGHT}}
 if shape_overlap(r,spawn) { return r }
 for other in layout.objects { if shape_overlap(r,other) { return r } }
 p:=shape_polygon(r);defer delete(p.points)
 lowest:=f32(1e30);for v in p.points { lowest=min(lowest,v.y) }
 if lowest< -1e-6 { return r }
 distance:=math.abs(lowest);move:=Vec2{0,-lowest}
 for other in layout.objects { q:=shape_polygon(other);d,v:=polygon_contact(p,q);delete(q.points);if d<distance { distance=d;move=v } }
 if distance>0.3 { return r }
 snapped:=r;snapped.lo=vadd(r.lo,move);snapped.hi=vadd(r.hi,move)
 test:=shape_polygon(snapped);defer delete(test.points);for v in test.points { if v.y< -1e-6 { return r } }
 if shape_overlap(snapped,spawn) { return r }
 for other in layout.objects { if shape_overlap(snapped,other) { return r } }
 return snapped
}
frame_grain :: proc(p:Polygon,frame:f32)->(lo,hi:Vec2,axis:int,length,thickness:f32) {
 if frame==0 { return grain_bounds(p) };local:=frame_polygon(p,frame);defer delete(local.points);return grain_bounds(local)
}

// Invert the actual f32 rotation matrix in f64, avoiding a second scale error.
