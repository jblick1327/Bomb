package main
import "core:testing"
import "core:sync"
import "core:fmt"
import "core:os"

@(test)
seam_followup_legacy_world_bytes :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 for fixture in 0..<5 {
  g:Sandbox;ticks:=600
  switch fixture {
  case 0:g=glue_cantilever(true)
  case 1:g=glue_cantilever(false)
  case 2:g=mortar_cantilever(2.4)
  case 3:g=mortar_cantilever(4.4);ticks=240
  case 4:g=mortar_bridge_yard()
  }
  for phase in 0..<2 {
   if phase==1 { for _ in 0..<ticks { sandbox_tick(&g,0,false) } }
   data,ok:=encode_world_snapshot(&g.world);testing.expect(t,ok)
   name:=fmt.aprintf("fixture-%d-phase-%d.json",fixture,phase)
   when #config(SEAM_BASELINE_WRITE,false) {
    path:=fmt.aprintf("%s/%s",#config(SEAM_CAPTURE_DIRECTORY,"evidence/seam-toughness/legacy"),name)
    testing.expect(t,os.write_entire_file(path,data)==nil);delete(path)
   } else {
    path:=fmt.aprintf("evidence/seam-toughness/legacy/%s",name)
    before,err:=os.read_entire_file(path,context.allocator);testing.expect(t,err==nil && world_capture_compatible(before,data),name);delete(before);delete(path)
    when #config(SEAM_CAPTURE_DIRECTORY,"")!="" {
     after:=fmt.aprintf("%s/%s",#config(SEAM_CAPTURE_DIRECTORY,""),name);testing.expect(t,os.write_entire_file(after,data)==nil);delete(after)
    }
   }
   delete(name);delete(data)
  }
  sandbox_destroy(&g)
 }
 fmt.println("Legacy glue cantilever, mortar cantilevers and Bridge: 10 exact World captures")
}
