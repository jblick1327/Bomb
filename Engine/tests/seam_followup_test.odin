package main

import shared "shared"
import "core:testing"
import "core:sync"
import "core:fmt"

@(test)
demo_quiet_seams :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 g:=seam_demo_game();s:=&g.world.scene;ids:[dynamic]u64;defer delete(ids)
 for c in s.connections { if c.mortar { append(&ids,c.id) } }
 peak:=f32(0)
 for _ in 0..<600 { sandbox_tick(&g,0,false);peak=max(peak,seam_demo_movement(&g)) }
 remaining:=seam_live_count(s,ids[:])
 testing.expect(t,remaining==len(ids) && peak<=0.01)
 fmt.printf("Demo regression blast=false ticks=600 initial=%d surviving=%d max_vertex_displacement=%.9f\n",len(ids),remaining,peak)
 sandbox_destroy(&g)
}

// Check a: the original demo blast must not break any seam more than 1 m
// outside its radius, nor move the right post.
@(test)
demo_original_blast_remote_seams :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 g:=seam_demo_game();s:=&g.world.scene;ids:[dynamic]u64;defer delete(ids)
 event:=Blast{{-3.8,0.5},4}
 for c in s.connections { if c.mortar && seam_far(c,event) { append(&ids,c.id) } }
 sandbox_fixture_radius(&g,event.radius);sandbox_explode(&g,event.position)
 testing.expect(t,len(ids)>0)
 post:=f32(0)
 broke:=make(map[u64]int);defer delete(broke)
 shared.seam_damage_scene=s;shared.seam_damage_peak=make(map[u64]f32);defer { shared.seam_damage_scene=nil;delete(shared.seam_damage_peak);shared.seam_damage_peak=nil }
 for tick in 1..=120 {
  sandbox_tick(&g,0,false);now:=seam_right_post_movement(&g);post=max(post,now)
  for id in ids { if row,ok:=s.conn_rows[id];(!ok || !s.connections[row].live) && broke[id]==0 { broke[id]=tick } }
  if tick==20 || tick==120 {
   live:=seam_live_count(s,ids[:])
   fmt.printf("Original blast tick=%d protected=%d surviving=%d right_post_max_movement=%.9f right_post_now=%.9f\n",tick,len(ids),live,post,now)
   testing.expect(t,live==len(ids),"Every seam more than 1 m outside the blast must be live")
   testing.expect(t,post<0.05,"The right post must stay put")
  }
 }
 for id in ids { fmt.printf("Original blast far_connection=%d first_break_tick=%d peak_damage=%.9f\n",id,broke[id],shared.seam_damage_peak[id]) }
 fmt.printf("Original blast SEAM_TOUGHNESS=%g entries=%d\n",SEAM_TOUGHNESS,len(shared.seam_damage_peak))
 sandbox_destroy(&g)
}
