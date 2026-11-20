#+feature dynamic-literals
package shared

import fmt "core:fmt"
import unicode "core:unicode"

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
 m.subdivision_strength*=custom.toughness; m.connection_strength*=custom.toughness; m.glue_toughness=custom.toughness
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

// OD-2 (owner, 2026-11-17): the Bridge truss, posts, girders and braces use this custom.
// Stone base, toughness 1.25 (subdivision 43.75, connection 25, glue load capacity 350/unit), blast resistance 4, navy.
// Colour and the unused strip/shock/flex fields match the G1 Bridge generator's steel.
steel_material :: proc() -> Custom_Material {
 return {name="steel",base=.Stone,toughness=1.25,blast_resistance=4,color={52,66,86},strip_thickness=0.2,shock_loss=4,flexibility=0.5}
}

custom_defaults :: proc(base:Recipe)->Custom_Material {
 m:=editor_material(base)
 strip:=STRIP_MIN; if base==.Wood { strip=m.strip_thickness }
 return {base=base,toughness=1,blast_resistance=m.blast_resistance,color=m.color,strip_thickness=strip,shock_loss=4,flexibility=0.5}
}

destroy_layout :: proc(layout:^Layout) {
 if layout.level!=nil { destroy_level_layout(layout.level);free(layout.level) }
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
