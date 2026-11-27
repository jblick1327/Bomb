package main

import "core:math"
import "core:strings"
import "core:sync"
import "core:testing"
import b2 "vendor:box2d"
import shared "shared"

// P6 / G-N12 (owner-delegated 2026-11-27): glue is weak against bending and sliding unless weight presses the joint
// shut. A shelf glued to the side of a post (nothing under it) gives way under its own weight; a deck glued on top of
// the same post (resting on it) holds. Source 1 is a fixed post, source 2 the glued dynamic piece.

overhang_world :: proc(t:^testing.T,piece:[4]f32) -> (layout:shared.Layout,w:shared.World,ok:bool) {
 text:=glue_test_level({{-0.5,0,0.5,4},piece},{{0,1}});defer delete(text)
 fixed,_:=strings.replace(text,`"motion":"dynamic"`,`"motion":"fixed"`,1);defer if raw_data(fixed)!=raw_data(text) { delete(fixed) }
 return glue_test_world(t,fixed)
}

overhang_piece_y :: proc(w:^shared.World) -> f32 {
 for sub in w.scene.subdivisions { if sub.live && sub.provenance.source_identity==2 { return b2.Body_GetPosition(w.scene.pieces[w.scene.piece_rows[sub.owner]].body).y } }
 return math.F32_MAX
}

overhang_live_glue :: proc(w:^shared.World) -> int {
 n:=0
 for c in w.scene.connections { if c.live && c.mortar { n+=1 } }
 return n
}

overhang_run :: proc(t:^testing.T,piece:[4]f32,ticks:int) -> (start_y,end_y:f32,glue_before,glue_after:int,ok:bool) {
 l:shared.Layout;w:shared.World
 l,w,ok=overhang_world(t,piece);if !ok { return };defer shared.destroy_layout(&l);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
 start_y=overhang_piece_y(&w);glue_before=overhang_live_glue(&w)
 for _ in 0..<ticks { events:=shared.world_tick(&w,{},f32(1.0/60.0));delete(events.explosions) }
 end_y=overhang_piece_y(&w);glue_after=overhang_live_glue(&w)
 return
}

@(test)
glue_overhang_shelf_gives_way_resting_deck_holds :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 // Shelf: 3 long, 0.5 thick, glued along its 0.5 end to the post's side, nothing under it.
 {
  start,end,before,after,ok:=overhang_run(t,{0.5,3,3.5,3.5},240);if !ok { return }
  testing.expectf(t,before>0,"the shelf is glued to the post (%d glue links)",before)
  testing.expectf(t,after==0,"the shelf's glue gives way under its own weight: %d links left",after)
  testing.expectf(t,end<start-1 || end==math.F32_MAX,"the shelf falls (or leaves the world and is removed): y %v -> %v",start,end)
 }
 // Deck: the same piece glued centred on top of the post (resting on it). It holds and does not move.
 {
  start,end,before,after,ok:=overhang_run(t,{-1.5,4,1.5,4.5},240);if !ok { return }
  testing.expectf(t,before>0 && after==before,"the deck's glue holds: %d of %d links",after,before)
  testing.expectf(t,math.abs(end-start)<0.01,"the deck stays put: y %v -> %v",start,end)
 }
}
