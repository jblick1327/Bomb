package main

import "core:testing"
import "core:sync"
import "core:fmt"
import "core:math"

@(test)
aim_damage_radius_matches_live_material_thresholds :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 floor:=blast_damage_radius(&g.world.scene,5)
 g.editor.palette=recipe_slot(.Glass)
 assert(editor_place(&g,{1.5,0},{4.5,2})); sandbox_toggle_editor(&g)
 glass:=blast_damage_radius(&g.world.scene,5); small:=blast_damage_radius(&g.world.scene,1)
 bad:=0
 if math.abs(floor-3)>0.000001 { bad+=1 }
 if math.abs(glass-3.8)>0.000001 { bad+=1 }
 if small!=0 { bad+=1 }
 fmt.printf("E damage radii: floor=%.1f glass=%.1f small=%.1f mismatches=%d\n",floor,glass,small,bad)
 testing.expect(t,bad==0)
}
