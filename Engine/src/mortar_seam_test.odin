package main

import "core:testing"
import "core:sync"
import "core:math"
import "core:fmt"

@(test)
mortar_seam_seed_invariance :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 low,high:=f32(1e30),f32(0)
 for seed in u8(1)..=8 { n:=mortar_calibrate(2.4,seed); low=min(low,n); high=max(high,n) }
 testing.expect(t,high/low<=1.25)
 fmt.printf("Mortar seam seed max/min=%.9f\n",high/low)
}

@(test)
mortar_seam_group_counters_and_snap :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=mortar_cantilever(2.4); defer sandbox_destroy(&g)
 s:=&g.world.scene; s.physics.mortar_breaking=false
 for _ in 0..<120 { sandbox_tick(&g,0,false) }
 seams:=mortar_seams(s); defer mortar_free_seams(seams)
 testing.expect(t,len(seams)==2)
 count:=0; index:=-1
 for seam,i in seams {
  count+=len(seam.members)
  testing.expect(t,math.abs(seam.length-0.4)<0.00001)
  if len(seam.members)>1 { index=i }
 }
 testing.expect(t,count==mortar_live_count(s) && index>=0)
 if index<0 { return }
 seam:=seams[index]
 failures:=Failures{}; defer free_failures(&failures)
 seam.force={MORTAR_STRENGTH*seam.length*1.1,0}; seam.torque=0
 for tick in 1..=2 {
  seam.overload_ticks=u8(tick-1); mortar_apply_seam(s,seam,&failures)
  testing.expect(t,len(failures.connections)==0)
  for id in seam.members { testing.expect(t,s.connections[s.conn_rows[id]].overload_ticks==u8(tick)) }
 }
 bytes,ok:=encode_world_snapshot(&g.world); defer delete(bytes); testing.expect(t,ok)
 restored,loaded:=decode_world_snapshot(bytes); testing.expect(t,loaded)
 if loaded {
  defer { scene_destroy(&restored.scene); delete(restored.bombs) }
  groups:=mortar_seams(&restored.scene); defer mortar_free_seams(groups)
  for group in groups { if group.members[0]==seam.members[0] { testing.expect(t,group.overload_ticks==2) } }
  again,encoded:=encode_world_snapshot(&restored); defer delete(again)
  testing.expect(t,encoded && string(bytes)==string(again))
 }
 seam.overload_ticks=2; mortar_apply_seam(s,seam,&failures)
 testing.expect(t,len(failures.connections)==len(seam.members))
 for id,i in seam.members { testing.expect(t,failures.connections[i]==id && s.connections[s.conn_rows[id]].overload_ticks==0) }
 resize(&failures.connections,0)
 seam.overload_ticks=0; seam.force={MORTAR_STRENGTH*seam.length*2,0}
 mortar_apply_seam(s,seam,&failures)
 testing.expect(t,len(failures.connections)==len(seam.members))
 resize(&failures.connections,0)
 seam.overload_ticks=2; seam.force={0,0}; mortar_apply_seam(s,seam,&failures)
 for id in seam.members { testing.expect(t,s.connections[s.conn_rows[id]].overload_ticks==0) }
 // Pure torque uses the whole seam's squared length as well.
 seam.overload_ticks=0; seam.torque=MORTAR_STRENGTH*seam.length*seam.length
 mortar_apply_seam(s,seam,&failures)
 testing.expect(t,len(failures.connections)==len(seam.members))
 expect_valid(t,s)
}
