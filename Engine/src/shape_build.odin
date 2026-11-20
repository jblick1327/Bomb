package main
import "core:math"

editor_candidate :: proc(g:^Sandbox,a,b:Vec2)->Authored_Shape {
 r:=editor_rectangle(a,b,g.editor.palette);r.angle=g.editor.angle;r.shape=g.editor.shape
 return shape_snap(&g.layout,r)
}
// Walk the exterior edges of two touching polygons, splitting at shared ends.
