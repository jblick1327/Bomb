package main

import "core:strings"
import "core:fmt"
import "core:unicode"
import rl "vendor:raylib"

// Recipes are families; Slots address the layout palette, including customs.
material_color :: proc(m:Material)->rl.Color { return {m.color[0],m.color[1],m.color[2],255} }
materials_duplicate :: proc(game:^Sandbox,base:Recipe)->bool { return materials_duplicate_slot(game,recipe_slot(base)) }
materials_duplicate_slot :: proc(game:^Sandbox,slot:Slot)->bool {
 if len(game.layout.materials)>=4 { sandbox_notice(game,"Maximum 4 custom materials"); return false }
 m:=custom_defaults(layout_base(&game.layout,slot))
 if int(slot)>=4 { m=game.layout.materials[int(slot)-4] }
 prefix:=layout_material(&game.layout,slot).name
 // Reserve room for a copy suffix; names are validated in printable codepoints.
 for len(prefix)>15 { end:=len(prefix)-1; for end>0 && prefix[end]&0xc0==0x80 { end-=1 }; prefix=prefix[:end] }
 m.name=""
 for n in 1..=12 {
  name:=fmt.aprintf("%s %d",prefix,n)
  if material_name_problem(&game.layout,name)=="" { m.name=name; break }; delete(name)
 }
 append(&game.layout.materials,m); game.material_selected=3+len(game.layout.materials)
 materials_sync_name(game); sandbox_layout_changed(game); return true
}
material_usage :: proc(layout:^Layout,index:int)->int { n:=0; for object in layout.objects { if int(object.material)==index+4 { n+=1 } }; return n }
materials_rename :: proc(game:^Sandbox,index:int,name:string)->bool {
 if reason:=material_name_problem(&game.layout,name,index); reason!="" { sandbox_notice(game,reason); return false }
 next:=strings.clone(name); delete(game.layout.materials[index].name); game.layout.materials[index].name=next
 sandbox_layout_changed(game); return true
}
materials_delete :: proc(game:^Sandbox,index:int)->bool {
 used:=0; for object in game.layout.objects { if int(object.material)==index+4 { used+=1 } }
 if used>0 { sandbox_notice(game,fmt.tprintf("In use by %d objects",used)); return false }
 delete(game.layout.materials[index].name); ordered_remove(&game.layout.materials,index)
 for &object in game.layout.objects { if int(object.material)>index+4 { object.material=Slot(int(object.material)-1) } }
 if int(game.editor.palette)==index+4 { game.editor.palette=recipe_slot(.Wood) }
 else if int(game.editor.palette)>index+4 { game.editor.palette=Slot(int(game.editor.palette)-1) }
 game.material_selected=min(game.material_selected,palette_count(&game.layout)-1)
 materials_sync_name(game); sandbox_layout_changed(game); return true
}
