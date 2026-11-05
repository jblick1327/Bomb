package main

import rl "vendor:raylib"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

sandbox_draw_layouts_panel :: proc(game: ^Sandbox,width,height: f32) -> Sandbox_UI_Action {
	rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,205})
	x,y:=(width-760)*0.5,(height-640)*0.5
	rl.DrawRectangleRounded({x,y,760,640},0.025,8,{23,35,49,255})
	x+=28; y+=24
	ui_panel_title("Layouts",x,y)
	if ui_button({x+600,y-3,104,32},"Close") { return .Resume }
	y+=50
	ui_text(.Body,"PRESETS",i32(x),i32(y),YARD_ACCENT)
	button_width:=f32(704-8*(len(PRESET_NAMES)-1))/f32(len(PRESET_NAMES))
	for name,i in PRESET_NAMES {
		if ui_button({x+f32(i)*(button_width+8),y+24,button_width,30},rl.TextFormat("%s",name)) { sandbox_load_preset(game,i); return .None }
	}
	y+=66
	if ui_button({x,y,704,36},"Save current layout") { sandbox_save_current_layout(game) }
	y+=55
	ui_text(.Body,"SAVED",i32(x),i32(y),YARD_ACCENT)
	y+=28
	if game.last_session {
		if ui_button({x,y,704,30},"Autosave (last session)") {
			path:=fmt.aprintf("%s/autosave.json",game.layout_directory); defer delete(path)
			sandbox_load_layout_file(game,path); return .None
		}
		y+=34
	}
	for file in game.layout_files {
		_,name:=os.split_path(file.path)
		if ui_button({x,y,704,30},saved_layout_label(name,file.modified)) { sandbox_load_layout_file(game,file.path); return .None }
		y+=34
	}
	ui_text(.Body,"Drop a layout .json onto the window to load it",i32(x),i32((height+640)*0.5-32),YARD_MUTED)
 if game.status_time>0 { ui_label(.Small,rl.TextFormat("%s",game.status),{x,(height+640)*0.5-60,704,22},YARD_ACCENT,true) }
	return .None
}
sandbox_layout_file_input :: proc(game: ^Sandbox) -> bool {
	if rl.IsFileDropped() {
		files:=rl.LoadDroppedFiles(); defer rl.UnloadDroppedFiles(files)
		paths:=files.paths[:files.count]
		if index:=sandbox_dropped_layout_index(paths); index>=0 { sandbox_load_layout_file(game,string(paths[index])); return true }
	}
	if game.editor.editing && !game.panel_open && (rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)) && rl.IsKeyPressed(.S) {
		sandbox_save_current_layout(game); return true
	}
	return false
}
sandbox_dropped_layout_index :: proc(paths: []cstring) -> int {
	for path,i in paths {
		name:=string(path)
		if len(name)>=5 && strings.equal_fold(name[len(name)-5:],".json") { return i }
	}
	return -1
}

saved_layout_label :: proc(name:string,modified:i64)->cstring {
 stem:=name; if strings.has_suffix(stem,".json") { stem=stem[:len(stem)-5] }
 minutes:=max(i64(0),(time.to_unix_nanoseconds(time.now())-modified)/60_000_000_000)
 if minutes==0 { return rl.TextFormat("%s · just now",stem) }
 if minutes<60 { return rl.TextFormat("%s · %d min ago",stem,minutes) }
 if minutes<1440 { return rl.TextFormat("%s · %d hr ago",stem,minutes/60) }
 return rl.TextFormat("%s · %d days ago",stem,minutes/1440)
}
