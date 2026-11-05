package main
import "core:testing"
import "core:sync"
import "core:fmt"

@(test)
demo_quiet_and_remote_seams :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 for blast in ([2]bool{false,true}) {
  g:=seam_demo_game();s:=&g.world.scene;ids:[dynamic]u64
  event:=Blast{{-4.4,1.5},3};initial:=0
  for c in s.connections { if c.mortar { initial+=1;if !blast || seam_far(c,event) { append(&ids,c.id) } } }
  ticks:=600;if blast { ticks=20;sandbox_fixture_radius(&g,event.radius);sandbox_explode(&g,event.position) }
  peak:=f32(0)
  for _ in 0..<ticks { sandbox_tick(&g,0,false);peak=max(peak,seam_demo_movement(&g)) }
  remaining:=0;for id in ids { if row,ok:=s.conn_rows[id];ok && s.connections[row].live { remaining+=1 } }
  testing.expect(t,remaining==len(ids));if !blast { testing.expect(t,peak<=0.01) }
  fmt.printf("Demo regression blast=%v ticks=%d initial=%d protected=%d surviving=%d max_vertex_displacement=%.9f\n",blast,ticks,initial,len(ids),remaining,peak)
  delete(ids);sandbox_destroy(&g)
 }
}
