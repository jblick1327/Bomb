package main

make_wall :: proc(seed: u8 = 0, minimum_width: f32 = 0) -> Scene {
	s := new_scene(minimum_width)
	m := add_material(&s,make_material(name="brick",subdivision_strength=6,connection_strength=4,flexibility=0.25,generation_count=2,aspect_ratio=1.5))
	p := add_piece(&s,m,seed)
	ids: [3]u64
	for i in 0..<3 {
		x := f32(i)
		poly := make_polygon([]Vec2{{x,0},{x+1,0},{x+1,1},{x,1}})
		center := centroid(poly)
		ids[i] = add_subdivision(&s,p,poly,Pose{position=center})
		delete(poly.points)
	}
	add_connection(&s,ids[0],ids[1]); add_connection(&s,ids[1],ids[2])
	return s
}

test_recipe :: proc(index: int) -> Material {
	switch index {
	case 1: return make_material(name="splinter",subdivision_strength=7,connection_strength=6,flexibility=0.6,generation_count=5,aspect_ratio=0.2)
	case 2: return make_material(name="shatter",subdivision_strength=5,connection_strength=4,flexibility=0.05,generation_count=6,aspect_ratio=1,triangulate=true)
	}
	return make_material(name="chunk",subdivision_strength=6,connection_strength=4,flexibility=0.25,generation_count=3,aspect_ratio=1)
}
// Small editor-authored fixture, no production-only test yard.
editor_test_yard :: proc(settings: Sandbox_Settings = DEFAULT_SANDBOX_SETTINGS) -> Sandbox {
 g:=sandbox_editor_create(); g.applied=settings
 g.editor.palette=.Stone
 assert(editor_place(&g,{1.5,0},{3.9,2.7}))
 sandbox_toggle_editor(&g)
 return g
}
