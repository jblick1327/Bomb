package main

import "core:math"
import "core:strings"
import b2 "vendor:box2d"

// Reverse lookup visits only valid enum members; integers never become Recipes.
EDITOR_GRID :: f32(0.1)
editor_snap :: proc(v: Vec2) -> Vec2 {
	// Division preserves the bits of the matching decimal f32 literal.
	return {f32(i32(math.round(v.x*10)))/10,f32(i32(math.round(v.y*10)))/10}
}
Material_Editor :: struct {
	editing,dragging: bool,
 angle:f32, shape:Shape_Kind, glue_tool:bool, glue_first:u64,
 mortar: bool,
	palette: Slot,
	start,cursor: Vec2,
}
// Explicit palette; ground independently selects Stone from the same table.
sandbox_editor_create :: proc() -> Sandbox {
	game:=Sandbox{world=World{settings=DEFAULT_SANDBOX_SETTINGS},previous_bombs=make(map[u64]Vec2),previous=make(map[u64]Pose),surface=true,joints=true,outline_width=2}
	game.editor.editing=true
	game.layout.next_identity=1
	sandbox_reset(&game)
	return game
}
editor_rectangle :: proc(a,b: Vec2,material: Slot) -> Authored_Shape {
	return Authored_Shape{lo={min(a.x,b.x),min(a.y,b.y)},hi={max(a.x,b.x),max(a.y,b.y)},material=material}
}

editor_valid_rectangle :: proc(editor: ^Layout,r: Authored_Shape) -> bool { return editor_rectangle_problem(editor,r)=="" }
editor_place :: proc(game: ^Sandbox,a,b: Vec2) -> bool {
	if !game.editor.editing || game.panel_open { return false }
	r:=editor_candidate(game,a,b)
	if problem:=editor_rectangle_problem(&game.layout,r); problem!="" { sandbox_notice(game,problem); return false }
	r.mortar=game.editor.mortar
	r.identity=game.layout.next_identity; game.layout.next_identity+=1
	append(&game.layout.objects,r)
	sandbox_layout_changed(game)
	return true
}
editor_remove :: proc(game: ^Sandbox,point: Vec2) -> bool {
	if !game.editor.editing || game.panel_open { return false }
	for object,i in game.layout.objects {
		polygon:=shape_polygon(object);inside:=convex_contains(polygon,point);delete(polygon.points)
  if inside {
   for j:=len(game.layout.glue)-1;j>=0;j-=1 { link:=game.layout.glue[j];if link.a==object.identity || link.b==object.identity { ordered_remove(&game.layout.glue,j) } }
			ordered_remove(&game.layout.objects,i); sandbox_layout_changed(game); return true
		}
	}
	return false
}
sandbox_toggle_editor :: proc(game: ^Sandbox) {
	if game.panel_open { return }
	game.palette_open=false
	game.editor.editing=!game.editor.editing
	game.editor.dragging=false
	sandbox_reset(game)
	if game.editor.editing { sandbox_notice(game,"Edit: undamaged layout restored") }
	else { sandbox_notice(game,"Test: R restores this layout and seed") }
}
editor_build_objects :: proc(game: ^Sandbox,objects: ^[dynamic]Built_Object=nil) {
 layout_build_objects(&game.world,&game.layout,game.editor.editing,objects)
}
editor_build_rectangles :: proc(game: ^Sandbox,materials: [8]int,objects: ^[dynamic]Built_Object=nil) {
 layout_build_rectangles(&game.world,&game.layout,game.editor.editing,materials,objects)
}
