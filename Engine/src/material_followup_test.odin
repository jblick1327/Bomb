package main
import "core:testing"
import "core:sync"
import "core:os"
import "core:fmt"
@(test)
material_strip_point15_layout_is_rejected_atomically :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 testing.expect(t,editor_place(&g,{0,0},{1,1})); sandbox_toggle_editor(&g)
 before,bok:=encode_layout(&g.layout,g.world.settings.seed); defer delete(before); testing.expect(t,bok)
 world,wok:=encode_world_snapshot(&g.world); defer delete(world); testing.expect(t,wok)
 data:=`{"kind":"bom-layout","version":2,"seed":42,"next_identity":1,"objects":[],"materials":[{"name":"thin","base":"wood","strip_thickness":0.15}]}`
 testing.expect(t,!sandbox_load_layout_data(&g,transmute([]byte)data))
 testing.expect_value(t,g.status,"Strip thickness must be between 0.2 and 0.6")
 after,aok:=encode_layout(&g.layout,g.world.settings.seed); defer delete(after)
 after_world,awok:=encode_world_snapshot(&g.world); defer delete(after_world)
 testing.expect(t,aok && awok && string(before)==string(after) && string(world)==string(after_world) && !g.editor.editing)
}

@(test)
material_legacy_v3_bytes_and_explicit_defaults :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 // The suggested before-v2-ticked file is a v2 Scene; use an existing v3 World.
 data,err:=os.read_entire_file("evidence/world-v3/continuity-manual-S.json",context.allocator)
 defer delete(data); testing.expect(t,err==nil)
 world,ok:=decode_world_snapshot(data); testing.expect(t,ok)
 defer { scene_destroy(&world.scene); delete(world.bombs) }
 for m in world.scene.materials {
  if m.aspect_ratio<1 { testing.expect(t,m.strip_thickness==0.3) }
  else { testing.expect(t,m.strip_thickness==0) }
  for recipe in Recipe { builtin:=editor_material(recipe); if m.name==builtin.name { testing.expect(t,m.color==builtin.color) } }
 }
 encoded,eok:=encode_world_snapshot(&world); defer delete(encoded)
 // v3 loads into player 0; the world is then written as v4 with an identical Scene section.
 testing.expect(t,eok && world_capture_compatible(data,encoded))
 again,aok:=decode_world_snapshot(encoded); testing.expect(t,aok)
 defer { scene_destroy(&again.scene); delete(again.bombs) }
 second,sok:=encode_world_snapshot(&again); defer delete(second)
 testing.expect(t,sok && string(second)==string(encoded),"v4 must round-trip exactly")
 testing.expect(t,world.players[0].active && world.players[0].blast_radius==world.settings.blast_radius)
 fmt.printf("Legacy v3 continuity-manual-S.json: %d bytes, v4 compatible=%v, v4 exact roundtrip=%v\n",len(data),world_capture_compatible(data,encoded),string(second)==string(encoded))
}

@(test)
material_snapshot_rejects_non_grained_strip_and_render_color_is_explicit :: proc(t:^testing.T) {
 for recipe in Recipe {
  m:=editor_material(recipe)
  testing.expect(t,(m.aspect_ratio<1 && m.strip_thickness==STRIP_MIN) || (m.aspect_ratio>=1 && m.strip_thickness==0))
  if recipe==.Wood { continue }
  s:=new_scene(0.1); add_material(&s,m)
  wire:=read_state(&s)
  wire.materials[0].strip_thickness=f32(0.3)
  data,ok:=exact_json_encode(wire); testing.expect(t,ok)
  rejected,accepted:=decode_snapshot(data); testing.expect(t,!accepted)
  if accepted { scene_destroy(&rejected) }
  delete(data); release_state_view(&wire); scene_destroy(&s)
 }
 m:=editor_material(.Wood); m.color={12,34,56}
 before:=material_color(m); m.name="glass"
 testing.expect(t,material_color(m)==before && before.r==12 && before.g==34 && before.b==56)
 // Unknown legacy names resolve only at decode; renaming in memory has no effect.
 wire:=Snapshot{version=2,minimum_width=0.1}
 append(&wire.materials,Wire_Material{name="old custom",generation_count=1,aspect_ratio=1,impact_scale=f32(1)})
 data,ok:=exact_json_encode(wire); testing.expect(t,ok); defer delete(data); defer release_state_view(&wire)
 s,decoded:=decode_snapshot(data); testing.expect(t,decoded); defer scene_destroy(&s)
 testing.expect(t,s.materials[0].color==editor_material(.Stone).color && s.materials[0].strip_thickness==0)
}
