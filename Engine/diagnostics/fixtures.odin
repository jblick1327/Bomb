package main
import b2 "vendor:box2d"

// Explicit tuning for historical simulation fixtures, never a gameplay default.
sandbox_fixture_player_tuning :: proc(g:^Sandbox,tuning:Player_Tuning) {
 for &player in g.world.players { if player.active {
  player.tuning=tuning;b2.Body_SetGravityScale(player.body,tuning.gravity_scale)
 } }
}

preset_test_yard :: proc(index: int) -> Sandbox {
	g:=sandbox_editor_create()
	layouts:=PRESET_LAYOUTS
	layout,seed,ok,problem:=decode_layout(transmute([]byte)layouts[index]); assert(ok,problem)
	destroy_layout(&g.layout); g.layout=layout; g.world.settings.seed=seed
	sandbox_toggle_editor(&g)
	return g
}
