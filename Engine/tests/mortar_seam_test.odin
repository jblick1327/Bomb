package main

import "core:testing"
import "core:sync"
import "core:math"
import "core:fmt"
import "core:strings"
import json "core:encoding/json"

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
 dt:=f32(1.0/60); step:=f32(0.1)*dt // r=1.1 absorbs 0.1*dt of damage per tick
 near:=proc(a,b: f32) -> bool { return math.abs(a-b)<1e-7 }
 seam.force={MORTAR_STRENGTH*seam.length*1.1,0}; seam.torque=0; mortar_seam_split(&seam)
 testing.expect(t,2*step<SEAM_TOUGHNESS)
 for tick in 1..=2 {
  seam.damage=f32(tick-1)*step; mortar_apply_seam(s,seam,&failures,dt)
  testing.expect(t,len(failures.connections)==0)
  for id in seam.members { testing.expect(t,near(s.connections[s.conn_rows[id]].damage,f32(tick)*step)) }
 }
 bytes,ok:=encode_world_snapshot(&g.world); defer delete(bytes); testing.expect(t,ok)
 restored,loaded:=decode_world_snapshot(bytes); testing.expect(t,loaded)
 if loaded {
  defer { scene_destroy(&restored.scene); delete(restored.bombs) }
  groups:=mortar_seams(&restored.scene); defer mortar_free_seams(groups)
  for group in groups { if group.members[0]==seam.members[0] { testing.expect(t,near(group.damage,2*step)) } }
  again,encoded:=encode_world_snapshot(&restored); defer delete(again)
  testing.expect(t,encoded && string(bytes)==string(again))
 }
 // Accumulated damage plus this tick's excess reaching toughness breaks every member at once.
 seam.damage=SEAM_TOUGHNESS; mortar_apply_seam(s,seam,&failures,dt)
 testing.expect(t,len(failures.connections)==len(seam.members))
 for id,i in seam.members { testing.expect(t,failures.connections[i]==id && s.connections[s.conn_rows[id]].damage==0) }
 resize(&failures.connections,0)
 // The rule is an impulse: the same (r-1)*dt breaks whether it comes in one tick or over several.
 seam.damage=0; seam.force={MORTAR_STRENGTH*seam.length*(1+1.01*SEAM_TOUGHNESS/dt),0}; mortar_seam_split(&seam)
 mortar_apply_seam(s,seam,&failures,dt)
 testing.expect(t,len(failures.connections)==len(seam.members))
 resize(&failures.connections,0)
 seam.damage=0; seam.force={MORTAR_STRENGTH*seam.length*(1+0.99*SEAM_TOUGHNESS/dt),0}; mortar_seam_split(&seam)
 mortar_apply_seam(s,seam,&failures,dt)
 testing.expect(t,len(failures.connections)==0)
 for id in seam.members { testing.expect(t,s.connections[s.conn_rows[id]].damage>0) }
 // At or below capacity a seam heals completely.
 seam.damage=SEAM_TOUGHNESS*0.9; seam.force={MORTAR_STRENGTH*seam.length*0.99,0}; mortar_seam_split(&seam); mortar_apply_seam(s,seam,&failures,dt)
 testing.expect(t,len(failures.connections)==0)
 for id in seam.members { testing.expect(t,s.connections[s.conn_rows[id]].damage==0) }
 // Pure torque uses the whole seam's squared length as well.
 seam.damage=SEAM_TOUGHNESS; seam.force={0,0}; seam.torque=MORTAR_STRENGTH*seam.length*seam.length; mortar_seam_split(&seam)
 mortar_apply_seam(s,seam,&failures,dt)
 testing.expect(t,len(failures.connections)==len(seam.members))
 expect_valid(t,s)
}

@(test)
mortar_seam_damage_snapshot_field :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=mortar_cantilever(2.4); defer sandbox_destroy(&g)
 for &c in g.world.scene.connections { if c.mortar { c.damage=0.0125 } }
 bytes,ok:=encode_world_snapshot(&g.world); defer delete(bytes); testing.expect(t,ok)
 text:=string(bytes)
 testing.expect(t,strings.contains(text,"\"damage\": 0.0125") && !strings.contains(text,"overload_ticks"))
 // Zero damage is omitted.
 for &c in g.world.scene.connections { c.damage=0 }
 plain,pok:=encode_world_snapshot(&g.world); defer delete(plain); testing.expect(t,pok)
 wire:World_Snapshot;testing.expect(t,json.unmarshal(plain,&wire)==nil)
 defer {destroy_decoded_snapshot(&wire.scene);delete(wire.players);delete(wire.bombs)}
 for connection in wire.scene.connections { _,present:=connection.damage.(f32);testing.expect(t,!present,"Zero seam damage must be omitted independently of cell damage policy metadata") }
 // A legacy overload counter is accepted and ignored.
 legacy,_:=strings.replace(string(plain),"\"mortar\": true","\"mortar\": true,\n\t\t\t\t\"overload_ticks\": 2",1); defer delete(legacy)
 testing.expect(t,legacy!=string(plain))
 old,loaded:=decode_world_snapshot(transmute([]byte)legacy); testing.expect(t,loaded)
 if loaded {
  defer { scene_destroy(&old.scene); delete(old.bombs) }
  for c in old.scene.connections { testing.expect(t,c.damage==0) }
  again,encoded:=encode_world_snapshot(&old); defer delete(again)
  testing.expect(t,encoded && string(again)==string(plain))
 }
 // Negative damage is invalid.
 bad,_:=strings.replace(string(plain),"\"mortar\": true","\"mortar\": true,\n\t\t\t\t\"damage\": -1",1); defer delete(bad)
 _,accepted:=decode_world_snapshot(transmute([]byte)bad); testing.expect(t,!accepted)
}
