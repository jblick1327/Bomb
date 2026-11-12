package shared
import t "core:testing"
import b2 "vendor:box2d"

// D12 (owner-approved 2026-11-11). Blast at (0,1); capsule centre (1.4,1), so the
// nearest capsule point is 1.14 from the blast, inside the 1.2 lethal radius.
// A zero-resistance wall at x .9..1, y -1..1.32 hides every capsule point within
// 1.2 (steepest such sight line ~0.31 vs the wall's 0.36); only the top cap, about
// 1.41 away (sight line up to ~0.415), stays exposed inside the 2.2 graze radius.
// Before D12 this player took nothing: the graze gate skipped any capsule
// reaching inside 1.2 and the lethal query saw nothing exposed.
@(test)
graze_d12_exposed_band_part_grazes_when_nearest_point_is_inside_lethal_radius :: proc(test:^t.T) {
 for full in ([2]bool{false,true}) {
  w:=round_test_world();w.elimination_playing=true;_=world_remove_player(&w,1)
  b2.Body_SetTransform(w.players[0].body,{1.4,1},b2.MakeRot(0))
  top:=f32(1.32);if full {top=3}
  _=owner_rule_rectangle(&w.scene,{.9,-1},{1,top},.Indestructible,.Fixed,0)
  physics_sync_structure(&w.scene)
  t.expect(test,round_capsule_hit({1.4,1},{0,1},1.2) && !round_capsule_tangent({1.4,1},{0,1},1.2),"fixture: nearest point strictly inside the lethal radius")
  events:Tick_Events;world_explode(&w,{0,1},5,&events)
  t.expect(test,events.deaths[0]==.None,"no exposed part inside the lethal radius")
  t.expect(test,w.players[0].graze_count==(full?u32(0):1),"D12: an exposed part in the 1.2..2.2 band grazes; full cover still protects")
  delete(events.explosions);round_test_world_destroy(&w)
 }
}

@(test)
graze_d12_keeps_exact_lethal_tangency_and_outer_band_rules :: proc(test:^t.T) {
 t.expect(test,round_capsule_tangent({1.2+PLAYER_RADIUS,1},{0,1},1.2),"N3's harmless tangency fixture is the exact boundary")
 t.expect(test,!round_capsule_tangent({1.45,1},{0,1},1.2) && !round_capsule_tangent({1.47,1},{0,1},1.2))
 nan:=transmute(f32)u32(0x7fc00000)
 t.expect(test,!round_capsule_tangent({nan,1},{0,1},1.2) && !round_capsule_tangent({1,1},{0,1},-1))
}
