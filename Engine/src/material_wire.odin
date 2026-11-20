package main

custom_to_wire :: proc(m:Custom_Material)->Wire_Custom_Material {
 w:=Wire_Custom_Material{name=m.name,base=editor_material(m.base).name,toughness=m.toughness,blast_resistance=m.blast_resistance,color=m.color}
 switch m.base {
 case .Wood:w.strip_thickness=m.strip_thickness
 case .Glass:w.shock_loss=m.shock_loss
 case .Rubber:w.flexibility=m.flexibility
 case .Stone:
 }
 return w
}
