package main

import shared "shared"
import "core:testing"
import "core:sync"
import "core:fmt"
import b2 "vendor:box2d"

// Glue links of the cantilever and how many of them are still live.
force_rule_links :: proc(s:^Scene)->[dynamic]u64 {
 links:[dynamic]u64
 for c in s.connections { if len(c.glue)>0 { append(&links,c.id) } }
 return links
}

// Runs the glued cantilever with a free Stone block over its tip and returns
// the first tick at which any glue link has broken (0 if none within ticks).
force_rule_load :: proc(label:string,block_lo,block_hi:Vec2,ticks:int)->int {
 g:=glue_cantilever(true,block_lo,block_hi);s:=&g.world.scene
 // G-N9b fixture: the force rule is measured at full gravity, as before OD-8, by starting past the 60-tick start-up structure ramp.
 g.world.tick=shared.STRUCTURE_GRAVITY_RAMP_TICKS
 links:=force_rule_links(s);defer delete(links)
 for p in s.pieces { if p.live { fmt.printf("Force rule %s piece=%d material=%s mass=%.9f\n",label,p.id,s.materials[p.material].name,b2.Body_GetMass(p.body)) } }
 first,peak_tick,run,longest:=0,0,0,0;peak:=f32(0)
 for tick in 1..=ticks {
  sandbox_tick(&g,0,false)
  seams:=mortar_seams(s);worst:=f32(0)
  for seam in seams { worst=max(worst,vlen(seam.force)/(MORTAR_STRENGTH*seam.length)+abs(seam.torque)/(0.5*MORTAR_STRENGTH*seam.length*seam.length)) }
  mortar_free_seams(seams)
  if worst>peak { peak=worst;peak_tick=tick }
  if worst>=1 { run+=1;longest=max(longest,run) } else { run=0 }
  if first==0 && seam_live_count(s,links[:])<len(links) { first=tick }
 }
 fmt.printf("Force rule %s links=%d live_after_%d=%d first_break_tick=%d peak_r=%.9f peak_tick=%d longest_run_r_ge_1=%d\n",label,len(links),ticks,seam_live_count(s,links[:]),first,peak,peak_tick,longest)
 sandbox_destroy(&g)
 return first
}

// Sustained load still breaks: a 3x mass Stone block (1.2 x 1.5 m against the
// 2 x 0.3 m Stone beam) rests on the tip of the glued cantilever.
@(test)
force_rule_tip_block_breaks :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 first:=force_rule_load("tip-block-3x",{1.3,2.4},{2.5,3.9},30)
 testing.expect(t,first>0 && first<=30,"The overloaded glue must break within 30 ticks")
}

// Check f: a 1 x 1 m Stone block dropped from 3 m onto the tip must break the glue.
@(test)
force_rule_drop_block :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 first:=force_rule_load("drop-1x1-from-3m",{1.5,5.4},{2.5,6.4},300)
 testing.expect(t,first>0,"A hard impact must break the glue")
}

// Observation only (-define:FORCE_RULE_HISTORY=true): prints every seam's r, counter and verdict
// each tick for the five legacy captures, so the old and new rules can be diffed.
@(test)
force_rule_legacy_history :: proc(t:^testing.T) {
 when #config(FORCE_RULE_HISTORY,false) {
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
   shared.seam_diagnostic_scene=&g.world.scene;shared.seam_diagnostic_run=fmt.tprintf("fixture-%d",fixture)
   for tick in 1..=ticks { shared.seam_diagnostic_tick=tick;sandbox_tick(&g,0,false) }
   shared.seam_diagnostic_scene=nil;sandbox_destroy(&g)
  }
 }
}
