package main

import "core:testing"
import "core:sync"
import "core:fmt"

@(test)
world_frame_commands_wait_for_tick :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 failures:=0
 revision:=g.world.scene.revision
 sandbox_blast(&g,{-7.4,1})
 if g.world.scene.revision!=revision { failures+=1 }
 radius:=g.world.settings.blast_radius
 sandbox_set_radius(&g,4)
 if g.world.settings.blast_radius!=radius { failures+=1 }
 g.world.players[0].coyote=0.037; g.world.players[0].buffered_jump=0.021
 sandbox_set_panel(&g,true)
 if g.world.players[0].coyote!=0.037 || g.world.players[0].buffered_jump!=0.021 { failures+=1 }
 fmt.printf("A frame mutation violations: %d\n",failures)
 testing.expect(t,failures==0)
}
