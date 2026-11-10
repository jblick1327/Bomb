package shared
import b2 "vendor:box2d"

Owner_State :: struct {
 identity: Input_Identity,
 state_tick,topology_revision,finalized_through,last_applied_sequence,last_jump_edge,teleport_serial: u64,
 position,velocity,support_velocity: Vec2,
 coyote,buffered_jump: f32,
 support_cell: u64,
 grounded: bool,
 support_kind: u8,
 held: i8,
 missing: u32,
}
owner_state_capture :: proc(player: ^Player,schedule: ^Input_Schedule,tick,revision: u64) -> Owner_State {
 return {
  identity=schedule.identity,state_tick=tick,topology_revision=revision,
  finalized_through=schedule.finalized_through,last_applied_sequence=schedule.last_applied_sequence,
  last_jump_edge=max(schedule.last_jump_edge,schedule.terminal_jump_edge),
  teleport_serial=player.teleport_serial,
  position=from_b2(b2.Body_GetPosition(player.body)),velocity=from_b2(b2.Body_GetLinearVelocity(player.body)),
  support_velocity=player.support_velocity,coyote=player.coyote,buffered_jump=player.buffered_jump,
  support_cell=player.support_cell,grounded=player.grounded,support_kind=player.support_kind,
  held=schedule.held,missing=schedule.missing,
 }
}
owner_state_valid :: proc(o: Owner_State) -> bool {
 return o.identity.incarnation!=0 && o.identity.generation!=0 && o.finalized_through<=o.state_tick &&
  finite(o.position.x) && finite(o.position.y) && finite(o.velocity.x) && finite(o.velocity.y) &&
  finite(o.support_velocity.x) && finite(o.support_velocity.y) && finite(o.coyote) && finite(o.buffered_jump) &&
  o.coyote>=0 && o.coyote<=1.00001 && o.buffered_jump>=0 && o.buffered_jump<=1.00001 &&
  o.support_kind<=3 && o.held!=min(i8) && o.missing<=INPUT_HELD_GRACE+1 &&
  (o.support_kind==1 || o.support_cell==0)
}
owner_state_restore :: proc(world: b2.WorldId,player: ^Player,o: Owner_State) -> bool {
 if !owner_state_valid(o) { return false }
 radius:=player.blast_radius;tuning:=player.tuning
 // Recreate only the prediction body: stale contact manifolds/warm starts may
 // not survive an authoritative rewind. The server never calls this helper.
 if player.active && b2.Body_IsValid(player.body) { b2.DestroyBody(player.body) }
 player^=player_create(world,radius)
 player.tuning=tuning
 b2.Body_SetTransform(player.body,to_b2(o.position),b2.MakeRot(0))
 b2.Body_SetLinearVelocity(player.body,to_b2(o.velocity))
 player.grounded=o.grounded;player.coyote=o.coyote;player.buffered_jump=o.buffered_jump
 player.support_velocity=o.support_velocity;player.support_cell=o.support_cell;player.support_kind=o.support_kind
 player.teleport_serial=o.teleport_serial
 player_refresh_pose(player)
 return true
}
