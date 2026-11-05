package main
import "core:testing"
import "core:sync"
import "core:os"
import "core:fmt"

material_golden :: proc(t:^testing.T,name:string,data:[]byte) {
 when #config(MATERIAL_CAPTURE_DIRECTORY,"")!="" {
  capture:=fmt.aprintf("%s/%s.json",#config(MATERIAL_CAPTURE_DIRECTORY,""),name); defer delete(capture)
  testing.expect(t,os.write_entire_file(capture,data)==nil)
 }
 path:=fmt.aprintf("evidence/material-library/rebaseline/%s.json",name); defer delete(path)
 when #config(MATERIAL_BASELINE,false) { testing.expect(t,os.write_entire_file(path,data)==nil) }
 else {
  old,err:=os.read_entire_file(path,context.allocator); defer delete(old)
  testing.expect(t,err==nil && world_capture_compatible(old,data),name)
 }
}
@(test)
material_legacy_fixture_bytes :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 for i in 0..<5 {
  g:=preset_test_yard(i)
  data,ok:=encode_world_snapshot(&g.world); testing.expect(t,ok)
  material_golden(t,fmt.tprintf("preset-%d",i),data); delete(data); sandbox_destroy(&g)
 }
 for i in 0..<7 {
  g:Sandbox
  switch i {
  case 0:g=soak_yard()
  case 1:g=editor_test_yard()
  case 2:g=glass_pane_yard(3)
  case 3:g=glass_nonglass_yard()
  case 4:g=wood_nonwood_yard()
  case 5:g=sandbox_editor_create()
  case 6:g=glass_pane_yard(4)
  }
  data,ok:=encode_world_snapshot(&g.world); testing.expect(t,ok)
  material_golden(t,fmt.tprintf("world-%d",i),data); delete(data); sandbox_destroy(&g)
 }
 data,_,_:=soak_replay_snapshot(); material_golden(t,"replay-600",data); delete(data)
 for i in 0..<12 {
  s:Scene
  switch i {
  case 0:s=make_wall()
  case 1:s=make_wall(42,0.1)
  case 2:s=rigid_wall()
  case 3:s=rubber_bite_scene()
  case 4:s=rubber_bite_scene(true)
  case 5:s=rubber_bend_scene()
  case 6:s=glass_shock_chain()
  case 7:s=msaa_border_scene()
  case 8:s=wood_plank_scene()
  case 9:s=wood_study_scene(1,{6,4})
  case 10:s=wood_study_scene(16,{6,4})
  case 11:s=wood_study_scene(42,{6,0.8})
  }
  bytes,ok:=encode_snapshot(&s); testing.expect(t,ok)
  material_golden(t,fmt.tprintf("scene-%d",i),bytes); delete(bytes); scene_destroy(&s)
 }
 fmt.println("Material compatibility: 25 fixture/preset byte comparisons passed")
}
