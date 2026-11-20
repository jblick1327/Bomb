package main

import "core:testing"
import "core:sync"
import "core:strings"
import "core:slice"
import shared "shared"
import b2 "vendor:box2d"

// A bottom-anchored stone slab, seed 42. A shot .25 inside its right face
// releases blast children into open air; no floor or neighbours catch them.
gn11_level :: proc() -> string {
 base:=glue_test_level({{0,0,4,8}},{});defer delete(base)
 anchored,a_alloc:=strings.replace_all(base,`"motion":"dynamic"`,`"motion":"anchored"`);defer if a_alloc { delete(anchored) }
 out,o_alloc:=strings.replace_all(anchored,`"anchors":[]`,`"anchors":[{"a":{"x":0,"y":0},"b":{"x":4,"y":0}}]`)
 if !o_alloc { return strings.clone(out) }
 return out
}

gn11_blast :: proc(w:^World) {
 // Fixture adjusted by the showrunner (AGENTS.md fixture policy): radius 2 released no child from the
 // 4x8 slab; radius 5 at the same point matches the G7+G8 outer-skin probe that released bedrock.
 events:Tick_Events;world_explode(w,{3.75,6},5,&events);delete(events.explosions)
 shared.physics_sync_structure(&w.scene)
}

gn11_released_outside :: proc(w:^World) -> [dynamic]u64 {
 ids:[dynamic]u64
 for sub in w.scene.subdivisions {
  if sub.live && sub.provenance.motion==.Anchored && !shared.piece_anchored(&w.scene,sub.owner,w.scene.anchor_y) &&
     b2.Body_GetType(sub.body)==.dynamicBody && !shared.level_bounds_contains(w.scene.level_policy.fragment_cull,sub.pose.position) { append(&ids,sub.id) }
 }
 return ids
}

@(test)
// Two fresh loads of the same level must replay byte for byte. (A round restart through
// world_rebuild_layout is not byte-identical to a fresh load even under the pre-G-N11 rule:
// evidence/G-N11/gates/Test-4-oldrule-control.log, so it is not the determinism check here.)
anchored_blast_children_escape_are_culled_and_two_runs_are_byte_identical :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 text:=gn11_level();defer delete(text)
 states:[2][]u8;defer { for s in states { delete(s) } }
 culled:[2]int
 for run in 0..<2 {
  layout,w,ok:=glue_test_world(t,text);if !ok { return }
  defer shared.destroy_layout(&layout);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
  for i in 0..<MAX_PLAYERS { _=shared.world_remove_player(&w,i) }
  testing.expect(t,w.tick==0)
  held:=0;for sub in w.scene.subdivisions { if sub.live && sub.provenance.pinned { held+=1 } }
  testing.expect(t,held>0,"the real source starts anchored")
  gn11_blast(&w)
  children:=make(map[u64]bool);defer delete(children)
  for sub in w.scene.subdivisions {
   if sub.live && sub.provenance.motion==.Anchored && !shared.piece_anchored(&w.scene,sub.owner,w.scene.anchor_y) { children[sub.id]=true }
  }
  testing.expect(t,len(children)>0,"the real blast releases anchored-source children")
  for _ in 0..<360 { od8_step(&w) }
  for id in children { if !shared.is_live_subdivision(&w.scene,id) { culled[run]+=1 } }
  outside:=gn11_released_outside(&w);defer delete(outside)
  testing.expect(t,len(outside)==0,"no released live cell remains outside cull bounds")
  held=0;for sub in w.scene.subdivisions { if sub.live && sub.provenance.pinned { held+=1 } }
  testing.expect(t,held>0,"the anchored remainder stays")
  encoded:bool;states[run],encoded=encode_world_snapshot(&w);testing.expect(t,encoded)
 }
 testing.expectf(t,culled[0]>0 && culled[0]==culled[1],"blast children culled in each run: %v",culled)
 testing.expect(t,len(states[0])>0 && string(states[0])==string(states[1]),"two fresh runs replay to byte-identical world snapshots")
}

@(test)
anchored_blast_cleanup_decision_matches_a_snapshot_rebuild :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 text:=gn11_level();defer delete(text)
 layout,w,ok:=glue_test_world(t,text);if !ok { return }
 defer shared.destroy_layout(&layout);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
 for i in 0..<MAX_PLAYERS { _=shared.world_remove_player(&w,i) }
 gn11_blast(&w)
 // Observe immediately before cleanup. Stepping the real physics without the
 // world cleanup lets the test snapshot a child at its first bounds crossing.
 crossed:=false
 for _ in 0..<360 {
  shared.physics_tick(&w.scene,1.0/60)
  ids:=gn11_released_outside(&w);crossed=len(ids)>0;delete(ids)
  if crossed { break }
 }
 testing.expect(t,crossed,"a real blast child crosses the bounds before cleanup");if !crossed { return }
 bytes,encoded:=encode_world_snapshot(&w);defer delete(bytes);testing.expect(t,encoded)
 rebuilt,decoded:=decode_world_snapshot(bytes,w.scene.epoch);testing.expect(t,decoded);if !decoded { return }
 defer shared.scene_destroy(&rebuilt.scene);defer delete(rebuilt.bombs)
 pre,pok:=encode_world_snapshot(&rebuilt);defer delete(pre)
 testing.expect(t,pok && string(pre)==string(bytes),"the rebuilt world encodes to the same bytes before cleanup")
 a,b:=gn11_released_outside(&w),gn11_released_outside(&rebuilt);defer delete(a);defer delete(b)
 testing.expect(t,len(a)>0 && len(a)==len(b))
 if len(a)==len(b) { for id,i in a { testing.expect(t,id==b[i],"the rebuilt state selects the same cells") } }
 testing.expect(t,shared.world_remove_out_of_bounds(&w)&&shared.world_remove_out_of_bounds(&rebuilt))
 for id in a { testing.expect(t,!shared.is_live_subdivision(&w.scene,id)&&!shared.is_live_subdivision(&rebuilt.scene,id)) }
 // The cleanup decision must match: the same cells stay live in both worlds. Whole-world bytes are not
 // compared after cleanup: the structure sync re-reads Box2D poses, and a body rebuilt from a snapshot
 // differs in the last float bit of its angle (evidence/G-N11/gates/Test-6-diag.log), for any cleanup.
 live_w,live_r:=make([dynamic]u64),make([dynamic]u64);defer delete(live_w);defer delete(live_r)
 for sub in w.scene.subdivisions { if sub.live { append(&live_w,sub.id) } }
 for sub in rebuilt.scene.subdivisions { if sub.live { append(&live_r,sub.id) } }
 slice.sort(live_w[:]);slice.sort(live_r[:])
 testing.expect(t,len(live_w)==len(live_r),"same number of live cells after cleanup")
 if len(live_w)==len(live_r) { for id,i in live_w { testing.expect(t,id==live_r[i],"same live cells after cleanup") } }
}
