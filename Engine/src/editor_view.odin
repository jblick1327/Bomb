package main

import rl "vendor:raylib"

editor_screen_rect :: proc(view: View,r: Authored_Shape) -> rl.Rectangle {
	lo,hi:=screen_point(view,{r.lo.x,r.hi.y}),screen_point(view,{r.hi.x,r.lo.y})
	return {lo.x,lo.y,hi.x-lo.x,hi.y-lo.y}
}
sandbox_draw_editor :: proc(game: ^Sandbox,view: View) {
	if !game.editor.editing { return }
	area:=editor_screen_rect(view,Authored_Shape{lo={-7.5,0},hi={8.5,4.8}})
	rl.DrawRectangleLinesEx(area,1,{144,165,178,65})
 texture_begin()
 for object in game.layout.objects { texture_rectangle(view,object,layout_material(&game.layout,object.material)) }
 texture_end()
	for object in game.layout.objects {
		box:=editor_screen_rect(view,object)
		material:=layout_material(&game.layout,object.material)

  if object.mortar { draw_shape_outline(view,object,3,MORTAR_COLOR) }
  if game.editor.glue_tool && game.editor.glue_first==object.identity { draw_shape_outline(view,object,4,YARD_ACCENT) }
		if game.outline_width>0 { draw_shape_outline(view,object,game.outline_width,YARD_INK) }
		label_box:=rl.Rectangle{box.x+5,box.y+5,max(f32(0),box.width-10),20}
  if object.angle!=0 || object.shape!=.Rect { p:=shape_polygon(object);center:=screen_point(view,centroid(p));delete(p.points);label_box.x=center.x-label_box.width*0.5;label_box.y=center.y-10 }
  ui_label(.Small,rl.TextFormat("%s",material.name),label_box,YARD_INK,true)
	}
 draw_editor_glue(game,view)
	if game.editor.dragging {
		r:=editor_candidate(game,game.editor.start,game.editor.cursor)
		box:=editor_screen_rect(view,r)
		color:=rl.Color{111,220,190,100}
		problem:=editor_rectangle_problem(&game.layout,r)
		if problem!="" { color={244,132,131,100} }
		draw_shape_preview(view,r,color); color.a=255
  draw_shape_outline(view,r,2,color)
		label:=rl.TextFormat("%.1f × %.1f",r.hi.x-r.lo.x,r.hi.y-r.lo.y)
		x:=clamp(box.x+box.width+12,f32(12),f32(rl.GetScreenWidth()-240))
		y:=clamp(box.y,f32(98),f32(rl.GetScreenHeight()-130))
		ui_text(.Heading,label,i32(x),i32(y),color)
		if problem!="" { ui_text(.Body,rl.TextFormat("%s",problem),i32(x),i32(y)+26,color) }
	}
}
sandbox_editor_input :: proc(game: ^Sandbox,point: Vec2,over_ui: bool) {
	if game.panel_open { game.editor.dragging=false; return }
 if game.palette_open { game.editor.dragging=false; return }
 if rl.IsKeyPressed(.Q) { game.editor.angle=angle_wrap(game.editor.angle-15) }
 if rl.IsKeyPressed(.E) { game.editor.angle=angle_wrap(game.editor.angle+15) }
 if rl.IsKeyPressed(.T) { if game.editor.shape==.Rect { game.editor.shape=.Wedge } else { game.editor.shape=.Rect } }
 if rl.IsKeyPressed(.G) { game.editor.glue_tool=!game.editor.glue_tool;game.editor.glue_first=0;game.editor.dragging=false }
 if game.editor.glue_tool {
  if rl.IsKeyPressed(.ESCAPE) || rl.IsMouseButtonPressed(.RIGHT) { game.editor.glue_tool=false;game.editor.glue_first=0;return }
  if rl.IsMouseButtonPressed(.LEFT) && !over_ui { editor_glue_click(game,point) };return
 }
 if rl.IsKeyPressed(.M) { game.editor.mortar=!game.editor.mortar }
	keys:=[8]rl.KeyboardKey{.ONE,.TWO,.THREE,.FOUR,.FIVE,.SIX,.SEVEN,.EIGHT}
	for key,i in keys { if i<palette_count(&game.layout) && rl.IsKeyPressed(key) { game.editor.palette=Slot(i) } }
	if rl.IsMouseButtonPressed(.RIGHT) && !over_ui {
		game.editor.dragging=false
		editor_remove(game,point)
	}
	if rl.IsMouseButtonPressed(.LEFT) && !game.block_blast && !over_ui {
		game.editor.dragging=true; game.editor.start=editor_snap(point)
	}
	if game.editor.dragging {
		game.editor.cursor=editor_snap(point)
		if rl.IsMouseButtonReleased(.LEFT) {
			if !over_ui { editor_place(game,game.editor.start,game.editor.cursor) }
			game.editor.dragging=false
		}
	}
}
