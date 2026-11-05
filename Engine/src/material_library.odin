package main

import "core:strings"
import "core:fmt"
import "core:unicode"
import rl "vendor:raylib"

// Recipes are families; Slots address the layout palette, including customs.
Custom_Material :: struct {
 name: string,
 base: Recipe,
 toughness: f32,
 blast_resistance: f32,
 color: [3]u8,
 strip_thickness,shock_loss,flexibility: f32,
}
palette_count :: proc(layout:^Layout)->int { return 4+len(layout.materials) }
layout_material :: proc(layout:^Layout,choice:Slot)->Material {
 index:=int(choice)
 if index<4 { return editor_material(builtin_recipe(choice)) }
 custom:=layout.materials[index-4]
 m:=editor_material(custom.base); m.name=custom.name
 m.subdivision_strength*=custom.toughness; m.connection_strength*=custom.toughness
 m.blast_resistance=custom.blast_resistance; m.color=custom.color
 switch custom.base {
 case .Wood:m.strip_thickness=custom.strip_thickness
 case .Glass:m.shock_loss=custom.shock_loss
 case .Rubber:m.flexibility=custom.flexibility
 case .Stone:
 }
 return m
}
layout_base :: proc(layout:^Layout,choice:Slot)->Recipe {
 if int(choice)<4 { return builtin_recipe(choice) }; return layout.materials[int(choice)-4].base
}
material_color :: proc(m:Material)->rl.Color { return {m.color[0],m.color[1],m.color[2],255} }
custom_defaults :: proc(base:Recipe)->Custom_Material {
 m:=editor_material(base)
 strip:=STRIP_MIN; if base==.Wood { strip=m.strip_thickness }
 return {base=base,toughness=1,blast_resistance=m.blast_resistance,color=m.color,strip_thickness=strip,shock_loss=4,flexibility=0.5}
}
destroy_layout :: proc(layout:^Layout) {
 for m in layout.materials { delete(m.name) }; delete(layout.materials); delete(layout.objects); delete(layout.glue); layout^={}
}
material_name_problem :: proc(layout:^Layout,name:string,except:int = -1)->string {
 count:=0
 for r in name { if !unicode.is_print(r) { return "Name must use printable characters" }; count+=1 }
 if count<1 || count>20 { return "Name must be 1-20 printable characters" }
 for i in 0..<palette_count(layout) {
  if i==except+4 { continue }
  if layout_material(layout,Slot(i)).name==name { return "Duplicate material name" }
 }
 return ""
}
in_range :: proc(v,lo,hi:f32)->bool { return finite(v) && v>=lo && v<=hi }
custom_problem :: proc(m:Custom_Material)->string {
 if !in_range(m.toughness,0.25,4) { return "Toughness must be between 0.25 and 4" }
 if !in_range(m.blast_resistance,0,6) { return "Blast resistance must be between 0 and 6" }
 if !in_range(m.strip_thickness,STRIP_MIN,0.6) { return fmt.tprintf("Strip thickness must be between %.1f and 0.6",STRIP_MIN) }
 if !in_range(m.shock_loss,1,12) { return "Shock loss must be between 1 and 12" }
 if !in_range(m.flexibility,0.2,1) { return "Flexibility must be between 0.2 and 1" }
 return ""
}
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
