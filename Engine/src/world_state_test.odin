package main

import "base:runtime"
import "core:reflect"
import "core:testing"
import "core:sync"
import "core:fmt"
import b2 "vendor:box2d"

// Walk the complete wire record, including geometry, motion, materials and rain.
snapshot_float_bits :: proc(v: any,bits: ^[dynamic]u32) {
 ti:=runtime.type_info_base(type_info_of(v.id))
 #partial switch info in ti.variant {
 case runtime.Type_Info_Float: append(bits,transmute(u32)(^f32)(v.data)^)
 case runtime.Type_Info_Struct:
  for _,i in info.names[:info.field_count] {
   if reflect.struct_tag_get(reflect.Struct_Tag(info.tags[i]),"json")=="-" { continue }
   snapshot_float_bits(any{rawptr(uintptr(v.data)+info.offsets[i]),info.types[i].id},bits)
  }
 case runtime.Type_Info_Slice:
  a:=(^runtime.Raw_Slice)(v.data)
  for i in 0..<a.len { snapshot_float_bits(any{rawptr(uintptr(a.data)+uintptr(i*info.elem.size)),info.elem.id},bits) }
 case runtime.Type_Info_Dynamic_Array:
  a:=(^runtime.Raw_Dynamic_Array)(v.data)
  for i in 0..<a.len { snapshot_float_bits(any{rawptr(uintptr(a.data)+uintptr(i*info.elem.size)),info.elem.id},bits) }
 case runtime.Type_Info_Array:
  for i in 0..<info.count { snapshot_float_bits(any{rawptr(uintptr(v.data)+uintptr(i*info.elem.size)),info.elem.id},bits) }
 case runtime.Type_Info_Union: inner:=reflect.get_union_variant(v); if inner!=nil { snapshot_float_bits(inner,bits) }
 }
}
world_float_mismatches :: proc(a,b: ^World) -> int {
 x:=read_world_state(a); y:=read_world_state(b)
 defer release_world_state(&x); defer release_world_state(&y)
 xb,yb:[dynamic]u32; defer delete(xb); defer delete(yb)
 snapshot_float_bits(x,&xb); snapshot_float_bits(y,&yb)
 bad:=abs(len(xb)-len(yb))
 for i in 0..<min(len(xb),len(yb)) { if xb[i]!=yb[i] { bad+=1 } }
 return bad
}
@(test)
world_snapshot_floats_and_bombs_are_exact :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 sandbox_fixture_mode(&g,.Falling_Bombs)
 for i in 0..<240 { if i==239 { bomb_spawn(&g,{7,BOMB_SKY_HEIGHT}) }; sandbox_tick(&g,0,false) }
 airborne,landed:=0,0
 for bomb in g.world.bombs { if bomb.landed { landed+=1 } else { airborne+=1 } }
 fmt.printf("B tick240 airborne=%d landed=%d\n",airborne,landed)
 testing.expect(t,airborne>0 && landed>0)
 // Exercise small and signed-zero values that fixed decimal printing destroys.
 g.world.players[0].coyote=0.0000000012345678; g.world.players[0].buffered_jump=transmute(f32)u32(0x80000000)
 data,ok:=encode_world_snapshot(&g.world); defer delete(data); testing.expect(t,ok)
 restored,decoded:=decode_world_snapshot(data)
 defer { scene_destroy(&restored.scene); delete(restored.bombs) }
 testing.expect(t,decoded)
 if !decoded { return }
 bad:=world_float_mismatches(&g.world,&restored)
 again,encoded:=encode_world_snapshot(&restored); defer delete(again)
 fmt.printf("B float mismatches=%d bombs_before=%d bombs_after=%d bytes_identical=%v\n",bad,len(g.world.bombs),len(restored.bombs),encoded && string(data)==string(again))
 testing.expect(t,bad==0)
 testing.expect(t,len(g.world.bombs)==len(restored.bombs) && g.world.rain==restored.rain && g.world.tick==restored.tick)
 testing.expect(t,string(data)==string(again))
}
@(test)
world_snapshot_loads_real_v2_fixture :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 data:=#load("../evidence/world-v3/before-v2-ticked.json")
 w,ok:=decode_world_snapshot(transmute([]byte)data); defer { scene_destroy(&w.scene); delete(w.bombs) }
 testing.expect(t,ok)
 if ok { valid,_:=validate_scene(&w.scene); testing.expect(t,valid && len(w.bombs)==0 && from_b2(b2.Body_GetPosition(w.players[0].body))==PLAYER_SPAWN && w.tick==0) }
}


