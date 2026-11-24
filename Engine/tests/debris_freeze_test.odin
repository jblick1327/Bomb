package main

import "core:strings"
import "core:sync"
import "core:testing"
import b2 "vendor:box2d"
import shared "shared"

// NPT (owner-approved 2026-11-24): settled loose debris freezes into a static body on the server world and thaws for
// a nearby blast, a nearby player, or when nothing is left under it (src/shared/debris_freeze.odin).

// A fixed floor slab (source 1) with a loose stone block resting on it (source 2), no glue.
debris_test_world :: proc(t:^testing.T) -> (layout:shared.Layout,w:shared.World,ok:bool) {
 text:=glue_test_level({{-5,0,5,0.5},{0,0.5,0.4,0.9}},{});defer delete(text)
 fixed,_:=strings.replace(text,`"motion":"dynamic"`,`"motion":"fixed"`,1);defer if raw_data(fixed)!=raw_data(text) { delete(fixed) }
 layout,w,ok=glue_test_world(t,fixed)
 w.debris_freeze=true
 return
}

debris_test_piece :: proc(w:^shared.World,identity:u64) -> ^shared.Piece {
 for sub in w.scene.subdivisions { if sub.live && sub.provenance.source_identity==identity { return &w.scene.pieces[w.scene.piece_rows[sub.owner]] } }
 return nil
}

debris_test_step :: proc(w:^shared.World,ticks:int,commands:shared.Tick_Commands={}) {
 for i in 0..<ticks { c:=commands;if i>0 { c={} };events:=shared.world_tick(w,c,f32(1.0/60.0));delete(events.explosions) }
}

@(test)
debris_freeze_settles_static_and_thaws_for_a_blast :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 layout,w,ok:=debris_test_world(t);if !ok { return };defer shared.destroy_layout(&layout);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
 block:=debris_test_piece(&w,2);if !testing.expect(t,block!=nil && block.body!=b2.nullBodyId,"the loose block has a body") { return }
 testing.expect(t,b2.Body_GetType(block.body)==.dynamicBody,"the loose block starts dynamic")
 mass:=b2.Body_GetMass(block.body)
 debris_test_step(&w,60)
 testing.expect(t,!block.frozen,"still settling under the gravity ramp: not frozen yet")
 debris_test_step(&w,120)
 testing.expect(t,block.frozen && b2.Body_GetType(block.body)==.staticBody,"a block at rest for a second freezes into a static body")
 // A blast whose reach (radius + 1 m) misses the block leaves it frozen.
 events:shared.Tick_Events;shared.world_explode(&w,{3,2},0.5,&events);delete(events.explosions)
 testing.expect(t,block.frozen,"a far blast leaves it frozen")
 // A blast 0.7 m above it (radius 0.5, so it does not touch the block) thaws it before the blast step.
 events={};shared.world_explode(&w,{0.2,1.6},0.5,&events);delete(events.explosions)
 block=debris_test_piece(&w,2);if !testing.expect(t,block!=nil,"the block survives a blast that does not reach it") { return }
 testing.expect(t,!block.frozen && b2.Body_GetType(block.body)==.dynamicBody,"a near blast thaws it back to dynamic")
 testing.expectf(t,abs(b2.Body_GetMass(block.body)-mass)<1e-4,"it keeps its own mass after thawing: %v, was %v",b2.Body_GetMass(block.body),mass)
}

@(test)
debris_freeze_thaws_near_a_player_and_without_support :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 layout,w,ok:=debris_test_world(t);if !ok { return };defer shared.destroy_layout(&layout);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
 debris_test_step(&w,180)
 block:=debris_test_piece(&w,2);if !testing.expect(t,block!=nil && block.frozen,"the block freezes") { return }
 // A player standing next to it: it thaws, and does not refreeze while the player stays.
 if !w.players[0].active { testing.expect(t,shared.world_add_player(&w,0),"player added") }
 player:=w.players[0].body
 hold :: proc(body:b2.BodyId) { b2.Body_SetTransform(body,{-0.6,1.5},b2.MakeRot(0));b2.Body_SetLinearVelocity(body,{}) }
 for _ in 0..<120 { hold(player);debris_test_step(&w,1) }
 testing.expect(t,!block.frozen && b2.Body_GetType(block.body)==.dynamicBody,"debris within 1.5 m of a player stays dynamic")
 _=shared.world_remove_player(&w,0)
 debris_test_step(&w,120)
 testing.expect(t,block.frozen,"it freezes again once the player has gone")
 // Remove the floor under it: the support check thaws it and it falls.
 floor:[dynamic]u64;defer delete(floor)
 for sub in w.scene.subdivisions { if sub.live && sub.provenance.source_identity==1 { append(&floor,sub.id) } }
 testing.expect(t,len(floor)>0,"the floor slab has regions")
 y:=b2.Body_GetPosition(block.body).y
 for id in floor { debris_test_step(&w,1,shared.Tick_Commands{remove_region=id}) }
 debris_test_step(&w,60)
 block=debris_test_piece(&w,2);if !testing.expect(t,block!=nil,"the block is still there") { return }
 testing.expect(t,!block.frozen,"unsupported debris thaws")
 testing.expectf(t,b2.Body_GetPosition(block.body).y<y-0.2,"and falls: y %v, was %v",b2.Body_GetPosition(block.body).y,y)
}

@(test)
debris_freeze_off_by_default :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 layout,w,ok:=debris_test_world(t);if !ok { return };defer shared.destroy_layout(&layout);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
 w.debris_freeze=false
 debris_test_step(&w,240)
 block:=debris_test_piece(&w,2);if !testing.expect(t,block!=nil,"the block is there") { return }
 testing.expect(t,!block.frozen && b2.Body_GetType(block.body)==.dynamicBody,"without World.debris_freeze nothing freezes")
}
