package main
import "core:slice"
import "core:time"
import "core:math"
import "core:mem"
// Immutable pre-blast posed polygons, in stable cell-ID order. Intersection
// intervals support concave outlines and rays starting/ending inside material.
// Boundary-only contact has zero chord; descendants inherit their original owner.
// Grid deduplication and sort preserve the original cell-ID summation order.
cover_inside :: proc(p:Vec2,points:[]Vec2) -> bool {
 inside:=false
 for a,i in points { b:=points[(i+1)%len(points)]; e:=vsub(b,a); m:=vsub(p,a)
  if vcross(e,m)==0 && vdot(m,e)>=0 && vdot(m,e)<=vdot(e,e) { return true }
  if (a.y>p.y)!=(b.y>p.y) && p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x { inside=!inside }
 }; return inside
}
// Positive-area intersection with a convex CCW shadow hull. Boundary-only
// contact is not overlap: it cannot attenuate any ray (including floor seams).

// Resistance cannot turn a geometrically insufficient load into a failure.
// Return the upper bound without querying cover when the decision is already final.
