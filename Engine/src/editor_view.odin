package main

import rl "vendor:raylib"

editor_color :: proc(name: string) -> rl.Color {
	switch name {
	case "wood": return {180,136,82,255}
	case "glass": return {106,191,215,195}
	case "rubber": return {162,112,184,255}
	}
	return {131,145,152,255}
}
editor_screen_rect :: proc(view: View,r: Authored_Rect) -> rl.Rectangle {
	lo,hi:=screen_point(view,{r.lo.x,r.hi.y}),screen_point(view,{r.hi.x,r.lo.y})
	return {lo.x,lo.y,hi.x-lo.x,hi.y-lo.y}
}
sandbox_draw_editor :: proc(game: ^Sandbox,view: View) {
	if !game.editor.editing { return }
	for object in game.editor.objects {
		box:=editor_screen_rect(view,object)
		material:=editor_material(object.material)
		rl.DrawRectangleRec(box,editor_color(material.name))
		if game.outline_width>0 { rl.DrawRectangleLinesEx(box,game.outline_width,YARD_INK) }
		rl.DrawText(rl.TextFormat("%s",material.name),i32(box.x)+5,i32(box.y)+5,16,YARD_INK)
	}
	if game.editor.dragging {
		r:=editor_rectangle(game.editor.start,game.editor.cursor,game.editor.palette)
		box:=editor_screen_rect(view,r)
		color:=rl.Color{111,220,190,100}
		if !editor_valid_rectangle(&game.editor,r) { color={244,132,131,100} }
		rl.DrawRectangleRec(box,color); color.a=255
		rl.DrawRectangleLinesEx(box,2,color)
	}
}
sandbox_editor_input :: proc(game: ^Sandbox,point: Vec2,over_ui: bool) {
	if game.panel_open { game.editor.dragging=false; return }
	if rl.IsMouseButtonPressed(.RIGHT) && !over_ui {
		game.editor.dragging=false
		editor_remove(game,point)
	}
	if rl.IsMouseButtonPressed(.LEFT) && !game.block_blast && !over_ui {
		game.editor.dragging=true; game.editor.start=point
	}
	if game.editor.dragging {
		game.editor.cursor=point
		if rl.IsMouseButtonReleased(.LEFT) {
			if !over_ui { editor_place(game,game.editor.start,point) }
			game.editor.dragging=false
		}
	}
}
