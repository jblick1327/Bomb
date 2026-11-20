#+feature dynamic-literals
package shared

import json "core:encoding/json"
import strings "core:strings"

Wire_Layout_Object :: struct { identity: u64, material: string, lo,hi: Vec2, angle:union { f32 } `json:"angle,omitempty"`, shape:union { string } `json:"shape,omitempty"`, mortar: union { bool } `json:"mortar,omitempty"` }

Wire_Layout :: struct {
	kind: string,
	version: int,
	seed: u64,
	next_identity: u64,
	objects: [dynamic]Wire_Layout_Object,
 materials: [dynamic]Wire_Custom_Material,
 glue:[dynamic]Glue_Link `json:"glue,omitempty"`,
}

decode_layout :: proc(data: []byte) -> (layout: Layout,seed: u8,ok: bool,problem: string) {
 header:struct{version:int};if json.unmarshal(data,&header)!=nil { return {},0,false,"Invalid layout JSON" }
 if header.version==4 { return decode_unity_layout(data) }
	wire:=Wire_Layout{}
	defer {
		delete(wire.kind);delete(wire.glue)
		for object in wire.objects { delete(object.material);if value,ok:=object.shape.(string);ok { delete(value) } }
		delete(wire.objects)
  for m in wire.materials { delete(m.name); delete(m.base) }; delete(wire.materials)
		if !ok { destroy_layout(&layout) }
	}
	if json.unmarshal(data,&wire)!=nil { return {},0,false,"Invalid layout JSON" }
	if wire.kind!="bom-layout" { return {},0,false,"Not a bom-layout file" }
	if wire.version!=1 && wire.version!=2 && wire.version!=3 { return {},0,false,"Unsupported layout version" }
	if wire.seed>255 { return {},0,false,"Seed must be between 0 and 255" }
	if wire.version==1 && len(wire.materials)>0 { return {},0,false,"Version 1 has no custom materials" }
 if len(wire.materials)>4 { return {},0,false,"Maximum 4 custom materials" }
 for m in wire.materials {
  base,known:=material_base_name(m.base)
  if !known { return layout,0,false,"Unknown material base" }
  if reason:=material_name_problem(&layout,m.name); reason!="" { return layout,0,false,reason }
  custom:=custom_from_wire(m,base)
  if reason:=custom_problem(custom); reason!="" { return layout,0,false,reason }
  custom.name=strings.clone(m.name); append(&layout.materials,custom)
 }
 seen:=make(map[u64]bool); defer delete(seen)
	maximum:=u64(0)
	for object in wire.objects {
		choice:=recipe_slot(.Wood); known:=false
		for i in 0..<palette_count(&layout) { if object.material==layout_material(&layout,Slot(i)).name { choice=Slot(i); known=true; break } }
		if !known { return layout,0,false,"Unknown material" }
		if object.identity==0 { return layout,0,false,"Object identity must be nonzero" }
		if seen[object.identity] { return layout,0,false,"Duplicate object identity" }
		r:=Authored_Shape{identity=object.identity,material=choice,lo=object.lo,hi=object.hi}
  if value,present:=object.angle.(f32);present { if wire.version<3 { return layout,0,false,"Angle requires version 3" };r.angle=value }
  if value,present:=object.shape.(string);present { if wire.version<3 || value!="wedge" { return layout,0,false,"Unknown shape" };r.shape=.Wedge }
		if value,exists:=object.mortar.(bool); exists { r.mortar=value }
		if reason:=editor_rectangle_problem(&layout,r); reason!="" { return layout,0,false,reason }
		append(&layout.objects,r)
		seen[object.identity]=true; maximum=max(maximum,object.identity)
	}
	if wire.next_identity<=maximum { return layout,0,false,"next_identity must exceed every object identity" }
	for link in wire.glue {
  if wire.version<3 { return layout,0,false,"Glue requires version 3" }
  if reason:=layout_glue_problem(&layout,link);reason!="" { return layout,0,false,reason };append(&layout.glue,link)
 }
 layout.next_identity=wire.next_identity
	return layout,u8(wire.seed),true,""
}
