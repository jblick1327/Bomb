package main

import "core:os"
import "core:fmt"
import "core:strings"
import "core:time"

Saved_Layout :: struct { path: string, modified: i64 }
sandbox_release_layout_files :: proc(game: ^Sandbox) {
	for file in game.layout_files { delete(file.path) }
	delete(game.layout_files); game.layout_files=nil
}
sandbox_refresh_layout_files :: proc(game: ^Sandbox) {
	sandbox_release_layout_files(game); game.last_session=false
	if game.layout_directory=="" { return }
	files,err:=os.read_all_directory_by_path(game.layout_directory,context.allocator)
	if err!=nil { return }
	defer os.file_info_slice_delete(files,context.allocator)
	for file in files {
		if file.type!=.Regular { continue }
		if file.name=="autosave.json" { game.last_session=true }
		if !strings.has_prefix(file.name,"layout-") || !strings.has_suffix(file.name,".json") { continue }
		path:=fmt.aprintf("%s/%s",game.layout_directory,file.name)
		append(&game.layout_files,Saved_Layout{path=path,modified=time.to_unix_nanoseconds(file.modification_time)})
	}
	// Newest first, with a deterministic filename order for timestamp ties.
	for i in 1..<len(game.layout_files) {
		j:=i
		for j>0 {
			a,b:=game.layout_files[j-1],game.layout_files[j]
			if a.modified>b.modified || a.modified==b.modified && a.path>=b.path { break }
			game.layout_files[j-1],game.layout_files[j]=b,a; j-=1
		}
	}
	for len(game.layout_files)>8 { delete(game.layout_files[len(game.layout_files)-1].path); pop(&game.layout_files) }
}
sandbox_save_layout_file :: proc(game: ^Sandbox,path: string) -> bool {
	data,ok:=encode_layout(&game.layout,game.world.settings.seed); defer delete(data)
	return ok && os.write_entire_file(path,data)==nil
}
sandbox_autosave_layout :: proc(game: ^Sandbox) {
	if game.layout_directory=="" || game.layout_revision==game.autosaved_layout_revision { return }
	path:=fmt.aprintf("%s/autosave.json",game.layout_directory); defer delete(path)
	if !sandbox_save_layout_file(game,path) { sandbox_notice(game,"Could not autosave layout"); return }
	game.autosaved_layout_revision=game.layout_revision
	game.last_session=true
}
sandbox_save_current_layout :: proc(game: ^Sandbox) -> bool {
	if game.layout_directory=="" { sandbox_notice(game,"Layout folder unavailable"); return false }
	for number in 1..<1_000_000 {
		path:=fmt.aprintf("%s/layout-%03d.json",game.layout_directory,number)
		if os.exists(path) { delete(path); continue }
		defer delete(path)
		if !sandbox_save_layout_file(game,path) { sandbox_notice(game,"Could not save layout"); return false }
		notice:=fmt.aprintf("Saved %s",path); defer delete(notice)
		sandbox_notice(game,notice); sandbox_refresh_layout_files(game)
		return true
	}
	sandbox_notice(game,"No free layout file number"); return false
}
sandbox_load_layout_file :: proc(game: ^Sandbox,path: string) -> bool {
	data,err:=os.read_entire_file(path,context.allocator); defer delete(data)
	if err!=nil { sandbox_notice(game,"Could not read layout file"); return false }
	if !sandbox_load_layout_data(game,data) { return false }
	notice:=fmt.aprintf("Loaded %s",path); defer delete(notice)
	sandbox_notice(game,notice)
	sandbox_autosave_layout(game)
	return true
}
sandbox_start_layout_files :: proc(game: ^Sandbox,directory: string) {
	game.layout_directory=directory
	path:=fmt.aprintf("%s/autosave.json",directory); defer delete(path)
	if os.is_file(path) { sandbox_load_layout_file(game,path) }
	// A missing or invalid autosave starts empty without overwriting that file.
	game.autosaved_layout_revision=game.layout_revision
	sandbox_refresh_layout_files(game)
}
sandbox_set_layouts_panel :: proc(game: ^Sandbox,open: bool) {
	sandbox_set_panel(game,open); game.layouts_open=open
	if open { sandbox_refresh_layout_files(game) }
}
