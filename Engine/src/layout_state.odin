package main

import "core:encoding/json"
import "core:strings"

encode_layout :: proc(layout: ^Layout,seed: u8) -> ([]byte,bool) {
	wire:=Wire_Layout{kind="bom-layout",version=3,seed=u64(seed),next_identity=layout.next_identity}
	defer { delete(wire.objects); delete(wire.materials);delete(wire.glue) }
 append(&wire.glue,..layout.glue[:])
 for m in layout.materials { append(&wire.materials,custom_to_wire(m)) }
	for object in layout.objects {
		w:=Wire_Layout_Object{identity=object.identity,material=layout_material(layout,object.material).name,lo=object.lo,hi=object.hi}
  if object.angle!=0 { w.angle=object.angle };if object.shape==.Wedge { w.shape="wedge" };if object.mortar { w.mortar=true }; append(&wire.objects,w)
	}
	data,ok:=exact_json_encode(wire)
 return data,ok
}
sandbox_layout_changed :: proc(game: ^Sandbox) { game.layout_revision+=1 }
// A successful layout load is a build/replace path. Keep authored identities and
// the seed together, discard the damaged Test world, and return to paused Edit.
sandbox_replace_layout :: proc(game: ^Sandbox,layout: Layout,seed: u8) {
	destroy_layout(&game.layout); game.layout=layout
 game.editor.palette=recipe_slot(.Wood); game.material_selected=0; game.material_name_edit=false; game.materials_open=false
	game.world.settings.seed=seed
	game.editor.editing=true
	game.panel_open=false; game.layouts_open=false
 game.palette_open=false
	sandbox_reset(game)
	sandbox_layout_changed(game)
}
sandbox_load_layout_data :: proc(game: ^Sandbox,data: []byte) -> bool {
	layout,seed,ok,problem:=decode_layout(data)
	if !ok { sandbox_notice(game,problem); return false }
	sandbox_replace_layout(game,layout,seed)
	return true
}
