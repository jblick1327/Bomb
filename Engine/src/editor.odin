package main

import "core:math"

Palette :: enum { Wood, Glass, Rubber, Stone }
RUBBER_CELL_SIZE :: f32(0.4)
Authored_Rect :: struct { lo,hi: Vec2, material: Palette, identity: u64 }
Material_Editor :: struct {
	editing,dragging: bool,
	palette: Palette,
	start,cursor: Vec2,
	next_identity: u64,
	objects: [dynamic]Authored_Rect,
}
// Explicit palette; ground independently selects Stone from the same table.
PALETTE_MATERIALS :: [Palette]Material{
 .Wood = {name="wood",subdivision_strength=28,connection_strength=22,flexibility=0,impact_scale=1,generation_count=5,aspect_ratio=0.2},
 .Glass = {name="glass",subdivision_strength=16,connection_strength=12,flexibility=0,impact_scale=1,generation_count=6,aspect_ratio=1,triangulate=true},
 .Rubber = {name="rubber",subdivision_strength=45,connection_strength=90,flexibility=0.5,impact_scale=0,generation_count=3,aspect_ratio=1},
 .Stone = {name="stone",subdivision_strength=35,connection_strength=20,flexibility=0,impact_scale=1.6,generation_count=3,aspect_ratio=1},
}
editor_material :: proc(choice: Palette) -> Material { table:=PALETTE_MATERIALS; return table[choice] }
sandbox_editor_create :: proc() -> Sandbox {
	game:=Sandbox{applied=DEFAULT_SANDBOX_SETTINGS,previous=make(map[u64]Pose),surface=true,joints=true,outline_width=2}
	game.editor.editing=true
	sandbox_reset(&game)
	return game
}
editor_rectangle :: proc(a,b: Vec2,material: Palette) -> Authored_Rect {
	return Authored_Rect{lo={min(a.x,b.x),min(a.y,b.y)},hi={max(a.x,b.x),max(a.y,b.y)},material=material}
}
editor_overlaps :: proc(a,b: Authored_Rect) -> bool {
	return a.lo.x<b.hi.x && a.hi.x>b.lo.x && a.lo.y<b.hi.y && a.hi.y>b.lo.y
}
editor_valid_rectangle :: proc(editor: ^Material_Editor,r: Authored_Rect) -> bool {
	if !valid_vec(r.lo) || !valid_vec(r.hi) || r.hi.x-r.lo.x<0.2 || r.hi.y-r.lo.y<0.2 { return false }
	if r.lo.x< -7.5 || r.hi.x>8.5 || r.lo.y<0 || r.hi.y>4.8 { return false }
	// Reserve the initial player's footprint, too; no body starts inside a solid.
	spawn:=Authored_Rect{lo={PLAYER_SPAWN.x-PLAYER_RADIUS,0},hi={PLAYER_SPAWN.x+PLAYER_RADIUS,PLAYER_SPAWN.y+PLAYER_HALF_HEIGHT}}
	if editor_overlaps(r,spawn) { return false }
	for object in editor.objects { if editor_overlaps(r,object) { return false } }
	return true
}
editor_place :: proc(game: ^Sandbox,a,b: Vec2) -> bool {
	if !game.editor.editing || game.panel_open { return false }
	r:=editor_rectangle(a,b,game.editor.palette)
	if !editor_valid_rectangle(&game.editor,r) { sandbox_notice(game,"Place a rectangle above ground, clear of objects and spawn"); return false }
	game.editor.next_identity+=1; r.identity=game.editor.next_identity
	append(&game.editor.objects,r)
	return true
}
editor_remove :: proc(game: ^Sandbox,point: Vec2) -> bool {
	if !game.editor.editing || game.panel_open { return false }
	for object,i in game.editor.objects {
		if point.x>=object.lo.x && point.x<=object.hi.x && point.y>=object.lo.y && point.y<=object.hi.y {
			ordered_remove(&game.editor.objects,i); return true
		}
	}
	return false
}
sandbox_toggle_editor :: proc(game: ^Sandbox) {
	if game.panel_open { return }
	game.editor.editing=!game.editor.editing
	game.editor.dragging=false
	sandbox_reset(game)
	if game.editor.editing { sandbox_notice(game,"Edit: undamaged layout restored") }
	else { sandbox_notice(game,"Test: R restores this layout and seed") }
}
editor_build_objects :: proc(game: ^Sandbox) {
	s:=&game.scene
	materials: [4]int
	for choice in Palette { materials[int(choice)]=add_material(s,editor_material(choice)) }
	editor_build_rectangles(game,materials)
}
// Reuse construction with the existing table when the soak replenishes its yard.
editor_build_rectangles :: proc(game: ^Sandbox,materials: [4]int) {
	s:=&game.scene
	if game.editor.editing { return }
	for object in game.editor.objects {
		seed:=derive_seed(game.applied.seed,0x10000+object.identity)
		if object.material==.Rubber { seed=0 }
		owner:=add_piece(s,materials[int(object.material)],seed)
		nx,ny:=1,1
		if object.material==.Rubber {
			nx=int(math.ceil((object.hi.x-object.lo.x)/RUBBER_CELL_SIZE-0.00001))
			ny=int(math.ceil((object.hi.y-object.lo.y)/RUBBER_CELL_SIZE-0.00001))
		}
		// Uniform fitted cells: one target size, no tiny leftover edge strips.
		dx,dy:=(object.hi.x-object.lo.x)/f32(nx),(object.hi.y-object.lo.y)/f32(ny)
		ids:=make([]u64,nx*ny)
		for row in 0..<ny {
			for column in 0..<nx {
				x0,x1:=object.lo.x+f32(column)*dx,object.lo.x+f32(column+1)*dx
				y0,y1:=object.lo.y+f32(row)*dy,object.lo.y+f32(row+1)*dy
				points:=[4]Vec2{{x0,y0},{x1,y0},{x1,y1},{x0,y1}}
				outline:=Polygon{points=points[:]}
				id:=add_subdivision(s,owner,outline,Pose{position=centroid(outline)})

				index:=row*nx+column; ids[index]=id
				if column>0 { connection:=add_connection(s,ids[index-1],id); assert(connection!=0); }
				if row>0 { connection:=add_connection(s,ids[index-nx],id); assert(connection!=0); }
			}
		}
		delete(ids)
		if object.material!=.Rubber { presplit_piece(s,owner) }
	}
}
