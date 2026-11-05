package main

import "core:fmt"

PRESET_NAMES :: [5]string{"Materials","Tower","Glass house","Rubber pad","Bridge"}
PRESET_LAYOUTS :: [5]string{
	#load("presets/materials.json"),
	#load("presets/tower.json"),
	#load("presets/glass-house.json"),
	#load("presets/rubber-pad.json"),
 #load("presets/bridge.json"),
}
sandbox_load_preset :: proc(game: ^Sandbox,index: int) -> bool {
	if index<0 || index>=len(PRESET_LAYOUTS) { return false }
	layouts,names:=PRESET_LAYOUTS,PRESET_NAMES
	if !sandbox_load_layout_data(game,transmute([]byte)layouts[index]) { return false }
	notice:=fmt.aprintf("Loaded %s preset",names[index]); defer delete(notice)
	sandbox_notice(game,notice); sandbox_autosave_layout(game)
	return true
}
