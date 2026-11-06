package main

preset_test_yard :: proc(index: int) -> Sandbox {
	g:=sandbox_editor_create()
	layouts:=PRESET_LAYOUTS
	layout,seed,ok,problem:=decode_layout(transmute([]byte)layouts[index]); assert(ok,problem)
	destroy_layout(&g.layout); g.layout=layout; g.world.settings.seed=seed
	sandbox_toggle_editor(&g)
	return g
}
