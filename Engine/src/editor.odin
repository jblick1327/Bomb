package main

import "core:math"
import "core:strings"
import b2 "vendor:box2d"

Recipe :: enum { Wood, Glass, Rubber, Stone }
Slot :: distinct int
recipe_slot :: proc(recipe:Recipe)->Slot { return Slot(int(recipe)) }
// Reverse lookup visits only valid enum members; integers never become Recipes.
builtin_recipe :: proc(slot:Slot)->Recipe {
 for recipe in Recipe { if recipe_slot(recipe)==slot { return recipe } }
 panic("Expected a built-in palette slot")
}
RUBBER_CELL_SIZE :: f32(0.4)
EDITOR_GRID :: f32(0.1)
editor_snap :: proc(v: Vec2) -> Vec2 {
	// Division preserves the bits of the matching decimal f32 literal.
	return {f32(i32(math.round(v.x*10)))/10,f32(i32(math.round(v.y*10)))/10}
}
Shape_Kind :: enum { Rect, Wedge }
Glue_Link :: struct { a,b:u64 }
Authored_Shape :: struct { angle:f32, shape:Shape_Kind, lo,hi: Vec2, material: Slot, identity: u64, mortar: bool }
Layout :: struct { next_identity: u64, objects: [dynamic]Authored_Shape, materials: [dynamic]Custom_Material, glue:[dynamic]Glue_Link }
Material_Editor :: struct {
	editing,dragging: bool,
 angle:f32, shape:Shape_Kind, glue_tool:bool, glue_first:u64,
 mortar: bool,
	palette: Slot,
	start,cursor: Vec2,
}
// Explicit palette; ground independently selects Stone from the same table.
PALETTE_MATERIALS :: [Recipe]Material{
 .Wood = {name="wood",color={180,136,82},strip_thickness=0.2,blast_resistance=1.5,subdivision_strength=28,connection_strength=22,flexibility=0,impact_scale=1,generation_count=5,aspect_ratio=0.2},
 .Glass = {name="glass",color={86,153,174},blast_resistance=0.5,subdivision_strength=16,connection_strength=12,flexibility=0,impact_scale=1,generation_count=6,aspect_ratio=1,triangulate=true,shock_loss=4},
 .Rubber = {name="rubber",color={162,112,184},blast_resistance=3,subdivision_strength=45,connection_strength=90,flexibility=0.5,impact_scale=0,generation_count=3,aspect_ratio=1},
 .Stone = {name="stone",color={131,145,152},blast_resistance=3,subdivision_strength=35,connection_strength=20,flexibility=0,impact_scale=1.6,generation_count=3,aspect_ratio=1},
}
editor_material :: proc(choice: Recipe) -> Material { table:=PALETTE_MATERIALS; return table[choice] }
sandbox_editor_create :: proc() -> Sandbox {
	game:=Sandbox{world=World{settings=DEFAULT_SANDBOX_SETTINGS},previous_bombs=make(map[b2.BodyId]Vec2),previous=make(map[u64]Pose),surface=true,joints=true,outline_width=2}
	game.editor.editing=true
	game.layout.next_identity=1
	sandbox_reset(&game)
	return game
}
editor_rectangle :: proc(a,b: Vec2,material: Slot) -> Authored_Shape {
	return Authored_Shape{lo={min(a.x,b.x),min(a.y,b.y)},hi={max(a.x,b.x),max(a.y,b.y)},material=material}
}
editor_overlaps :: proc(a,b: Authored_Shape) -> bool {
 if a.angle==0 && b.angle==0 && a.shape==.Rect && b.shape==.Rect { return max(f32(0),min(a.hi.x,b.hi.x)-max(a.lo.x,b.lo.x))*max(f32(0),min(a.hi.y,b.hi.y)-max(a.lo.y,b.lo.y))>1e-6 }
 return shape_overlap(a,b)
}

editor_rectangle_problem :: proc(editor: ^Layout,r: Authored_Shape) -> string {
	if !finite(r.angle) || r.angle<0 || r.angle>=360 { return "Angle must be between 0 and 360" }
 if !valid_vec(r.lo) || !valid_vec(r.hi) { return "Outside the build area" }
	if r.hi.x-r.lo.x<0.2 || r.hi.y-r.lo.y<0.2 { return "Too small (min 0.2)" }
	polygon:=shape_polygon(r);defer delete(polygon.points)
 for v in polygon.points { if v.x< -7.5 || v.x>8.5 || v.y< -1e-6 || v.y>4.8 { return "Outside the build area" } }
	// Reserve the initial player's footprint, too; no body starts inside a solid.
	spawn:=Authored_Shape{lo={PLAYER_SPAWN.x-PLAYER_RADIUS,0},hi={PLAYER_SPAWN.x+PLAYER_RADIUS,PLAYER_SPAWN.y+PLAYER_HALF_HEIGHT}}
	if editor_overlaps(r,spawn) { return "Overlaps the spawn" }
	for object in editor.objects { if editor_overlaps(r,object) { return "Overlaps an object" } }
	return ""
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
	game.editor.editing=!game.editor.editing
	game.editor.dragging=false
	sandbox_reset(game)
	if game.editor.editing { sandbox_notice(game,"Edit: undamaged layout restored") }
	else { sandbox_notice(game,"Test: R restores this layout and seed") }
}
editor_build_objects :: proc(game: ^Sandbox, objects: ^[dynamic]Built_Object = nil) {
	s:=&game.world.scene
	materials: [8]int
	for choice in Recipe { materials[int(choice)]=add_material(s,editor_material(choice)) }
 for i in 4..<palette_count(&game.layout) {
  used:=false; for object in game.layout.objects { if int(object.material)==i { used=true; break } }
  if used {
   m:=layout_material(&game.layout,Slot(i)); m.name=strings.clone(m.name); append(&s.owned_names,m.name)
   materials[i]=add_material(s,m)
  }
 }
	editor_build_rectangles(game,materials,objects)
}
// Reuse construction with the existing table when the soak replenishes its yard.
editor_build_rectangles :: proc(game: ^Sandbox,materials: [8]int, objects: ^[dynamic]Built_Object = nil) {
	s:=&game.world.scene
	if game.editor.editing { return }
	for object in game.layout.objects {
		seed:=derive_seed(game.world.settings.seed,0x10000+object.identity)
		if layout_base(&game.layout,object.material)==.Rubber { seed=0 }
		first_id:=s.next_id+1
		owner:=add_piece(s,materials[int(object.material)],seed)
  if object.angle!=0 || object.shape!=.Rect { build_shaped_object(s,object,owner); if objects!=nil { append(objects,built_object(object,first_id,s.next_id+1)) };continue }
		nx,ny:=1,1
		if layout_base(&game.layout,object.material)==.Rubber {
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
		if layout_base(&game.layout,object.material)!=.Rubber { presplit_piece(s,owner) }
  if objects!=nil { append(objects,Built_Object{identity=object.identity,mortar=object.mortar,lo=object.lo,hi=object.hi,first_id=first_id,end_id=s.next_id+1}) }
	}
}
