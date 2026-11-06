package main
import "core:testing"
import "core:sync"
import "core:fmt"
import "core:strings"
import b2 "vendor:box2d"

material_test_layout :: proc()->Layout {
 l:=Layout{next_identity=5}
 for base in Recipe {
  m:=custom_defaults(base); m.name=strings.clone(fmt.tprintf("custom %s",editor_material(base).name))
  m.strip_thickness=0.3; m.toughness=1.25; m.color={231,104,91}; append(&l.materials,m)
  x:=f32(int(base))*2
  append(&l.objects,Authored_Shape{identity=u64(int(base)+1),material=Slot(int(base)+4),lo={x,0},hi={x+1,1}})
 }
 return l
}
@(test)
material_v2_roundtrip_validation_and_ownership :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 destroy_layout(&g.layout); g.layout=material_test_layout()
 data,ok:=encode_layout(&g.layout,233); defer delete(data); testing.expect(t,ok)
 copy,seed,decoded,reason:=decode_layout(data); defer destroy_layout(&copy); testing.expect(t,decoded,reason)
 again,ok2:=encode_layout(&copy,seed); defer delete(again); testing.expect(t,ok2 && string(again)==string(data))
 h:=sandbox_editor_create(); defer sandbox_destroy(&h)
 testing.expect(t,sandbox_load_layout_data(&h,data))
 g.world.settings.seed=233; sandbox_toggle_editor(&g); sandbox_toggle_editor(&h); sandbox_reset(&g)
 a,aok:=encode_world_snapshot(&g.world); b,bok:=encode_world_snapshot(&h.world); defer delete(a); defer delete(b)
 testing.expect(t,aok && bok && string(a)==string(b),"Custom World roundtrip")
 testing.expect(t,len(g.world.scene.materials)==9)
 // A Scene owns its custom names independently of later layout renames.
 testing.expect(t,materials_rename(&g,0,"renamed wood")); testing.expect(t,g.world.scene.materials[5].name=="custom wood")
 baseline,ok3:=encode_layout(&g.layout,233); defer delete(baseline); testing.expect(t,ok3)
 cases:=[8]string{
  material_replace(string(data),"custom glass","custom wood"),
  material_replace(string(data),"1.25","4.1"),
  material_replace(string(data),`"base": "wood"`,`"base": "iron"`),
  material_replace(string(data),`"material": "custom wood"`,`"material": "absent"`),
  material_replace(string(data),`"strip_thickness": 0.3`,`"strip_thickness": 0.1`),
  material_replace(string(data),`"shock_loss": 4`,`"shock_loss": 13`),
  material_replace(string(data),`"flexibility": 0.5`,`"flexibility": 0.1`),
  material_replace(string(data),`"blast_resistance": 3`,`"blast_resistance": 7`),
 }
 defer { for s in cases { delete(s) } }
 for bad in cases {
  testing.expect(t,!sandbox_load_layout_data(&g,transmute([]byte)bad),bad)
  bytes,encoded:=encode_layout(&g.layout,233); testing.expect(t,encoded && string(bytes)==string(baseline)); delete(bytes)
  world,encoded2:=encode_world_snapshot(&g.world); testing.expect(t,encoded2 && string(world)==string(a)); delete(world)
 }
 fifth:=custom_defaults(.Wood); fifth.name=strings.clone("fifth"); append(&copy.materials,fifth)
 invalid,encoded:=encode_layout(&copy,233); defer delete(invalid); testing.expect(t,encoded && !sandbox_load_layout_data(&g,invalid))
 testing.expect_value(t,g.status,"Maximum 4 custom materials")
 unchanged,uok:=encode_layout(&g.layout,233); defer delete(unchanged); testing.expect(t,uok && string(unchanged)==string(baseline))
 fmt.println("Material v2: exact layout/World roundtrip; nine rejection cases atomic")
}
@(test)
material_sparse_custom_palette_and_delete :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 for base in Recipe { testing.expect(t,materials_duplicate(&g,base)) }
 testing.expect(t,!materials_duplicate(&g,.Wood))
 g.editor.palette=Slot(7); testing.expect(t,editor_place(&g,{0,0},{1,1}))
 sandbox_toggle_editor(&g)
 testing.expect(t,len(g.world.scene.materials)==6 && g.world.scene.materials[5].name=="stone 1")
 testing.expect(t,g.world.scene.pieces[0].material==5)
 sandbox_toggle_editor(&g)
 testing.expect(t,!materials_delete(&g,3) && g.status=="In use by 1 objects")
 testing.expect(t,materials_delete(&g,1) && int(g.layout.objects[0].material)==6 && int(g.editor.palette)==6)
 testing.expect(t,editor_remove(&g,{0.5,0.5}) && materials_delete(&g,2))
 testing.expect(t,!materials_rename(&g,0,"wood") && !materials_rename(&g,0,"") && !materials_rename(&g,0,"123456789012345678901"))
}

material_knob_yard :: proc(base:Recipe,size:Vec2,knob:f32,kind:int)->Sandbox {
 g:=sandbox_editor_create(); assert(materials_duplicate(&g,base)); g.editor.palette=Slot(4)
 m:=&g.layout.materials[0]
 switch kind { case 0:m.toughness=knob; case 1:m.strip_thickness=knob; case 2:m.shock_loss=knob; case 3:m.blast_resistance=knob; case 4:m.flexibility=knob }
 if kind==4 {
 g.editor.mortar=true; g.editor.palette=recipe_slot(.Stone); assert(editor_place(&g,{0,0},{0.4,1})); assert(editor_place(&g,{1.2,0},{1.6,1}))
 g.editor.palette=Slot(4); assert(editor_place(&g,{0,1},{1.6,1.4}))
 } else { assert(editor_place(&g,{0,0},size)) }; sandbox_toggle_editor(&g); return g
}
material_area :: proc(s:^Scene,index:int)->f32 { a:f32; for sub in s.subdivisions { if sub.live && sub.material==index { a+=polygon_area(sub.outline) } }; return a }
material_largest :: proc(s:^Scene,index:int)->f32 {
 a,largest:f32; for p in s.pieces { if p.live && p.material==index { a+=p.mass; largest=max(largest,p.mass) } }; if a==0 { return 0 }; return largest/a
}
@(test)
material_knobs_measured :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 // Identical seeds, geometry, blast and scene minimum width in every pair.
 lost:[2]f32
 for value,i in ([2]f32{1,2}) {
  g:=material_knob_yard(.Wood,{6,0.8},value,0)
  blast_pass(&g.world.scene,Blast{{-0.1,0.4},4})
  lost[i]=4.8-material_area(&g.world.scene,5); sandbox_destroy(&g)
 }
 fmt.printf("Wood toughness 1/2 lost area: %v\n",lost); testing.expect(t,lost[1]<lost[0])
 maximum:[2]f32; cell_counts:[2]int
 for value,i in ([2]f32{0.2,0.4}) {
  g:=material_knob_yard(.Wood,{6,0.8},value,1)
  for sub in g.world.scene.subdivisions { if sub.material==5 { _,w:=wood_study_dimensions(sub.outline); maximum[i]=max(maximum[i],w); cell_counts[i]+=1 } }
  sandbox_destroy(&g)
 }
 fmt.printf("Wood thickness .2/.4, 6x0.8, layout seed42 identity1: maximum built=%v cells=%v\n",maximum,cell_counts)
 testing.expect(t,maximum[0]<=STRIP_MIN && maximum[1]>STRIP_MIN)
 fractions:[2]f32
 for value,i in ([2]f32{4,2}) {
  g:=material_knob_yard(.Glass,{5,2.5},value,2)
  blast_pass(&g.world.scene,Blast{{-0.6,1.25},3})
  fractions[i]=material_largest(&g.world.scene,5); sandbox_destroy(&g)
 }
 fmt.printf("Glass shock 4/2 largest fraction=%v\n",fractions); testing.expect(t,fractions[1]<fractions[0])
 protected:[2]f32
 for value,i in ([2]f32{3,6}) {
  g:=sandbox_editor_create(); assert(materials_duplicate(&g,.Stone)); g.layout.materials[0].blast_resistance=value
  g.editor.palette=Slot(4); assert(editor_place(&g,{2,0},{2.2,2.4}))
  g.editor.palette=recipe_slot(.Wood); assert(editor_place(&g,{2.2,0},{3.2,1.6})); sandbox_toggle_editor(&g)
  blast_pass(&g.world.scene,Blast{{1,1},4.8})
  protected[i]=1.6-material_area(&g.world.scene,1); sandbox_destroy(&g)
 }
 fmt.printf("Stone resistance 3/6 wood lost=%v\n",protected); testing.expect(t,protected[0]-protected[1]>0.01)
 sag,speeds:[2]f32
 for value,i in ([2]f32{0.5,0.25}) {
  g:=material_knob_yard(.Rubber,{4,0.4},value,4)

  cells,links,_:=counts_runtime(&g.world.scene)
  for _ in 0..<600 { sandbox_tick(&g,0,false) }
  after_cells,after_links,_:=counts_runtime(&g.world.scene)
  testing.expect(t,cells==after_cells && links==after_links,"Sag fixture must not break")
  for sub in g.world.scene.subdivisions { if sub.material==5 { speeds[i]=max(speeds[i],vlen(sub.pose.velocity)) } }
  for sub in g.world.scene.subdivisions { if sub.material==5 && sub.rest_center.x>0.5 && sub.rest_center.x<1.1 { sag[i]=max(sag[i],sub.rest_center.y-sub.pose.position.y) } }
  sandbox_destroy(&g)
 }
 fmt.printf("Rubber flexibility .5/.25 sag=%v max_speed=%v\n",sag,speeds); testing.expect(t,speeds[0]<0.01 && speeds[1]<0.01); testing.expect(t,sag[0]-sag[1]>0.1)
 testing.expect(t,b2.GetByteCount()==0)
}

@(test)
material_optional_snapshot_fields_preserve_legacy_defaults :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=material_knob_yard(.Wood,{2,0.8},0.25,1); defer sandbox_destroy(&g)
 g.world.scene.materials[5].color=[3]u8{0,0,0}
 bytes,ok:=encode_world_snapshot(&g.world); defer delete(bytes); testing.expect(t,ok)
 restored,decoded:=decode_world_snapshot(bytes); testing.expect(t,decoded)
 defer { scene_destroy(&restored.scene); delete(restored.bombs) }
 testing.expect(t,restored.scene.materials[5].strip_thickness==0.25 && material_color(restored.scene.materials[5]).r==0)
 again,aok:=encode_world_snapshot(&restored); defer delete(again); testing.expect(t,aok && string(bytes)==string(again))
 // Absence always means 0.3, even after the built-in changes to explicit 0.2.
 s:=new_scene(0.1); defer scene_destroy(&s); add_material(&s,make_material(name="wood",aspect_ratio=0.2,strip_thickness=0.3,color={180,136,82}))
 data,encoded:=encode_snapshot(&s); defer delete(data); testing.expect(t,encoded && !strings.contains(string(data),"strip_thickness") && !strings.contains(string(data),"color"))
 old,loaded:=decode_snapshot(data); defer scene_destroy(&old); testing.expect(t,loaded && old.materials[0].strip_thickness==0.3)
 wire:=read_world_state(&g.world); defer release_world_state(&wire)
 wire.scene.materials[5].strip_thickness=f32(-0.1)
 bad,bok:=exact_json_encode(wire); defer delete(bad); testing.expect(t,bok)
 rejected,accepted:=decode_world_snapshot(bad); testing.expect(t,!accepted)
 if accepted { scene_destroy(&rejected.scene); delete(rejected.bombs) }
}

material_replace :: proc(s,old,new:string)->string { result,ok:=strings.replace_all(s,old,new); assert(ok); return result }

@(test)
material_decode_ranges_names_and_rgb :: proc(t:^testing.T) {
 cases:=[]string{
  `"toughness":0.24`,`"toughness":4.01`,
  `"blast_resistance":-0.01`,`"blast_resistance":6.01`,
  `"strip_thickness":0.199`,`"strip_thickness":0.601`,
  `"shock_loss":0.99`,`"shock_loss":12.01`,
  `"flexibility":0.199`,`"flexibility":1.01`,
  `"color":[-1,0,0]`,`"color":[256,0,0]`,`"color":[1,2]`,`"color":[1,2,3,4]`,
 }
 for field in cases {
  data:=fmt.aprintf(`{"kind":"bom-layout","version":2,"seed":42,"next_identity":1,"materials":[{"name":"X","base":"wood",%s}],"objects":[]}`,field)
  l,_,ok,_:=decode_layout(transmute([]byte)data); testing.expect(t,!ok,field); destroy_layout(&l); delete(data)
 }
 for name in ([]string{`""`,`"wood"`,`"line\nbreak"`,`"123456789012345678901"`}) {
  data:=fmt.aprintf(`{"kind":"bom-layout","version":2,"next_identity":1,"materials":[{"name":%s,"base":"wood"}]}`,name)
  l,_,ok,_:=decode_layout(transmute([]byte)data); testing.expect(t,!ok,name); destroy_layout(&l); delete(data)
 }
 data:=`{"kind":"bom-layout","version":2,"next_identity":1,"materials":[{"name":"defaults","base":"wood"}]}`
 l,_,ok,_:=decode_layout(transmute([]byte)data); defer destroy_layout(&l); testing.expect(t,ok)
 testing.expect(t,l.materials[0].toughness==1 && l.materials[0].strip_thickness==editor_material(.Wood).strip_thickness)
}
