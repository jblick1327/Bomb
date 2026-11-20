#+feature dynamic-literals
package shared

import b2 "vendor:box2d"

BOMB_FUSE :: f32(1)

Bomb :: struct {
	id: u64 `json:"-"`, // Runtime identity, assigned by the world in spawn order.
	body: b2.BodyId,
	landed: bool,
	fuse: f32,
	pose: Pose `json:"-"`, // Mirrored from the body after each physics step and load.
}
