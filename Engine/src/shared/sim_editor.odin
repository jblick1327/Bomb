#+feature dynamic-literals
package shared



Recipe :: enum { Wood, Glass, Rubber, Stone }

Slot :: distinct int

recipe_slot :: proc(recipe:Recipe)->Slot { return Slot(int(recipe)) }

builtin_recipe :: proc(slot:Slot)->Recipe {
 for recipe in Recipe { if recipe_slot(recipe)==slot { return recipe } }
 panic("Expected a built-in palette slot")
}

RUBBER_CELL_SIZE :: f32(0.4)

Shape_Kind :: enum { Rect, Wedge }

Glue_Link :: struct { a,b:u64 }

Authored_Shape :: struct { angle:f32, shape:Shape_Kind, lo,hi: Vec2, material: Slot, identity: u64, mortar: bool }

Layout :: struct { next_identity: u64, objects: [dynamic]Authored_Shape, materials: [dynamic]Custom_Material, glue:[dynamic]Glue_Link }

PALETTE_MATERIALS :: [Recipe]Material{
 .Wood = {name="wood",color={180,136,82},strip_thickness=0.2,blast_resistance=1.5,subdivision_strength=28,connection_strength=22,flexibility=0,impact_scale=1,generation_count=5,aspect_ratio=0.2},
 .Glass = {name="glass",color={86,153,174},blast_resistance=0.5,subdivision_strength=16,connection_strength=12,flexibility=0,impact_scale=1,generation_count=6,aspect_ratio=1,triangulate=true,shock_loss=4},
 .Rubber = {name="rubber",color={162,112,184},blast_resistance=3,subdivision_strength=45,connection_strength=90,flexibility=0.5,impact_scale=0,generation_count=3,aspect_ratio=1},
 .Stone = {name="stone",color={131,145,152},blast_resistance=3,subdivision_strength=35,connection_strength=20,flexibility=0,impact_scale=1.6,generation_count=3,aspect_ratio=1},
}

editor_material :: proc(choice: Recipe) -> Material { table:=PALETTE_MATERIALS; return table[choice] }

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
