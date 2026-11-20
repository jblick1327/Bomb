package main

import "core:testing"
import "core:sync"
import "core:math"
import b2 "vendor:box2d"
import shared "shared"

// OD-8 (G-N9b): mortar welds collide, and structure gravity eases in over the first 60 steps of each level start.

// A dynamic tile hanging in a level with no floor; with glued=true a second tile sits on it, glued (one mortar seam).
od8_level :: proc(glued:bool) -> string {
 if glued { return glue_test_level({{-0.5,20,0.5,20.5},{-0.5,20.5,0.5,21}},{{0,1}}) }
 return glue_test_level({{-0.5,20,0.5,20.5}},{})
}

od8_piece_body :: proc(w:^shared.World,identity:u64) -> b2.BodyId {
 for sub in w.scene.subdivisions { if sub.live && sub.provenance.source_identity==identity { return w.scene.pieces[w.scene.piece_rows[sub.owner]].body } }
 return b2.nullBodyId
}

od8_step :: proc(w:^shared.World) { events:=shared.world_tick(w,{},f32(1.0/60.0));delete(events.explosions) }

@(test)
od8_mortar_weld_pair_collides :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 text:=od8_level(true);defer delete(text)
 layout,w,ok:=glue_test_world(t,text);if !ok { return };defer shared.destroy_layout(&layout);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
 a,b:=od8_piece_body(&w,1),od8_piece_body(&w,2)
 testing.expect(t,a!=b2.nullBodyId && b!=b2.nullBodyId && a!=b,"two glued tiles are two dynamic piece bodies")
 welds:=0
 for c in w.scene.connections {
  if !c.live || !c.mortar || c.joint==b2.nullJointId { continue }
  welds+=1;testing.expect(t,b2.Joint_GetCollideConnected(c.joint),"a mortar weld lets its two bodies collide")
 }
 testing.expect(t,welds>0,"the glue link makes a mortar weld")
 for _ in 0..<3 { od8_step(&w) }
 // The glued faces touch (gap 0): with collideConnected the pair has a touching contact; without it Box2D makes none.
 data:=make([]b2.ContactData,int(b2.Body_GetContactCapacity(a)));defer delete(data)
 touching:=0
 for contact in b2.Body_GetContactData(a,data) {
  ba,bb:=b2.Shape_GetBody(contact.shapeIdA),b2.Shape_GetBody(contact.shapeIdB)
  if (ba==a && bb==b || ba==b && bb==a) && contact.manifold.pointCount>0 { touching+=1 }
 }
 testing.expectf(t,touching>0,"glued tiles must touch through a contact, found %d",touching)
}

@(test)
od8_structure_gravity_ramp_schedule_players_and_round_restart :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 ramp:=shared.structure_gravity_scale
 testing.expect(t,ramp(0)==0 && ramp(1)==f32(1)/60 && ramp(30)==.5 && ramp(59)==f32(59)/60 && ramp(60)==1 && ramp(61)==1 && ramp(1_000_000)==1)
 text:=od8_level(false);defer delete(text)
 layout,w,ok:=glue_test_world(t,text);if !ok { return };defer shared.destroy_layout(&layout);defer shared.scene_destroy(&w.scene);defer delete(w.bombs)
 config:=shared.scene_gameplay_config(&w.scene)
 testing.expect(t,w.tick==0 && w.players[0].active,"a fresh level starts at tick 0 with player 0")
 // World gravity stays the config gravity; only structure bodies are scaled.
 check :: proc(t:^testing.T,w:^shared.World,config:shared.Gameplay_Config,step:u64) {
  piece:=od8_piece_body(w,1)
  testing.expectf(t,w.tick==step && b2.Body_GetGravityScale(piece)==shared.structure_gravity_scale(step),"step %d: piece scale %v",step,b2.Body_GetGravityScale(piece))
  testing.expectf(t,b2.Body_GetGravityScale(w.players[0].body)==config.player.gravity_scale,"step %d: player keeps its own scale",step)
  testing.expect(t,shared.from_b2(b2.World_GetGravity(w.scene.physics.world))==config.gravity)
 }
 g:=math.abs(config.gravity.y);dt:=f32(1.0/60.0)
 previous:=b2.Body_GetLinearVelocity(od8_piece_body(&w,1)).y
 for step in u64(1)..=61 {
  od8_step(&w)
  if step==1 || step==30 || step==60 || step==61 { check(t,&w,config,step) }
  // Vertical speed gained in the step: ramp(step)*g*dt, so full config gravity (what prediction assumes) from step 60 on.
  v:=b2.Body_GetLinearVelocity(od8_piece_body(&w,1)).y;dv:=previous-v;previous=v
  testing.expectf(t,math.abs(dv-shared.structure_gravity_scale(step)*g*dt)<=1e-4,"step %d: dv %v",step,dv)
  if step<60 { testing.expect(t,dv<g*dt) }
 }
 // Round restart: a rebuild starts the level again at tick 0, so the ramp runs again.
 shared.world_rebuild_layout(&w,&layout,false)
 testing.expect(t,w.tick==0)
 od8_step(&w);check(t,&w,config,1)
 for _ in 2..=30 { od8_step(&w) };check(t,&w,config,30)
}

@(test)
od8_ramp_is_deterministic_and_a_snapshot_rebuild_mid_ramp_matches :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 TICKS,SAVE::90,25
 // Determinism: a glued pair (weld + contact), two runs, byte-identical canonical state.
 {
  text:=od8_level(true);defer delete(text)
  states:[2][]u8;defer { for s in states { delete(s) } }
  for run in 0..<2 {
   layout,w,ok:=glue_test_world(t,text);if !ok { return }
   for _ in 0..<TICKS { od8_step(&w) }
   states[run]=shared.canonical_encode(&w.scene)
   shared.destroy_layout(&layout);shared.scene_destroy(&w.scene);delete(w.bombs)
  }
  testing.expect(t,len(states[0])>0 && string(states[0])==string(states[1]),"two runs must be byte-identical")
 }
 // Rebuild mid-ramp: a free tile (no contacts, so no warm-start state lives outside the snapshot).
 // Fixture choice (AGENTS fixture policy): contacts' warm start is not in snapshots under any rule, so a
 // contact-free tile isolates the ramp; the tick restored from the snapshot must resume the same schedule.
 text:=od8_level(false);defer delete(text)
 layout,straight,ok:=glue_test_world(t,text);if !ok { return };defer shared.destroy_layout(&layout);defer shared.scene_destroy(&straight.scene);defer delete(straight.bombs)
 start:=b2.Body_GetPosition(od8_piece_body(&straight,1)).y
 for _ in 0..<SAVE { od8_step(&straight) }
 // The ramp acted: full gravity would drop the tile 0.85 in 25 steps; the ramp drops it about 0.12.
 drop:=start-b2.Body_GetPosition(od8_piece_body(&straight,1)).y
 testing.expectf(t,drop>0.05 && drop<0.3,"ramped drop after %d steps: %v",SAVE,drop)
 bytes,encoded:=encode_world_snapshot(&straight);defer delete(bytes);testing.expect(t,encoded)
 rebuilt,decoded:=decode_world_snapshot(bytes,straight.scene.epoch);testing.expect(t,decoded);if !decoded { return }
 defer shared.scene_destroy(&rebuilt.scene);defer delete(rebuilt.bombs)
 testing.expect(t,rebuilt.tick==SAVE)
 for _ in SAVE..<TICKS { od8_step(&straight);od8_step(&rebuilt) }
 // Compare world snapshots (every cell pose and velocity, players, tick). canonical_encode also carries the
 // structure_revision counter, which a rebuild numbers differently (5 vs 6 here) even with no step taken.
 a,a_ok:=encode_world_snapshot(&straight);b,b_ok:=encode_world_snapshot(&rebuilt);defer delete(a);defer delete(b)
 testing.expect(t,a_ok && b_ok && string(a)==string(b),"a world rebuilt from a snapshot mid-ramp must continue exactly like the uninterrupted world")
 testing.expect(t,b2.Body_GetGravityScale(od8_piece_body(&rebuilt,1))==1 && rebuilt.tick==TICKS)
}
