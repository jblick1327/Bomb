#+feature dynamic-literals
package shared

import b2 "vendor:box2d"

Player :: struct {
	active: bool,
	body: b2.BodyId,
	grounded: bool,
	coyote, buffered_jump: f32,
	support_velocity: Vec2,
	support_cell: u64,
	support_kind: u8, // 0 none, 1 stable cell, 2 static floor, 3 unidentified dynamic body
	teleport_serial: u64,
	blast_radius: f32,
	// Runtime-only mirror of the body pose, refreshed after every physics step
	// and snapshot load. Drawing reads this, never the body.
	pose: Pose `json:"-"`,
}
