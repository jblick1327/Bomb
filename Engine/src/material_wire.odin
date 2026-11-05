package main

Wire_Custom_Material :: struct {
 name,base: string,
 toughness: union { f32 } `json:"toughness,omitempty"`,
 blast_resistance: union { f32 } `json:"blast_resistance,omitempty"`,
 color: union { [3]u8 } `json:"color,omitempty"`,
 strip_thickness: union { f32 } `json:"strip_thickness,omitempty"`,
 shock_loss: union { f32 } `json:"shock_loss,omitempty"`,
 flexibility: union { f32 } `json:"flexibility,omitempty"`,
}
material_base_name :: proc(name:string)->(Recipe,bool) {
 for p in Recipe { if editor_material(p).name==name { return p,true } }; return .Wood,false
}
custom_from_wire :: proc(w:Wire_Custom_Material,base:Recipe)->Custom_Material {
 m:=custom_defaults(base); m.name=w.name
 if v,ok:=w.toughness.(f32); ok { m.toughness=v }
 if v,ok:=w.blast_resistance.(f32); ok { m.blast_resistance=v }
 if v,ok:=w.color.([3]u8); ok { m.color=v }
 if v,ok:=w.strip_thickness.(f32); ok { m.strip_thickness=v }
 if v,ok:=w.shock_loss.(f32); ok { m.shock_loss=v }
 if v,ok:=w.flexibility.(f32); ok { m.flexibility=v }
 return m
}
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
