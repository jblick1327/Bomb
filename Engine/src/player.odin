package main

import b2 "vendor:box2d"
import "core:math"

// Start supported rather than introducing an artificial landing on every Test.

// The player is an ordinary body in the shared world, outside the destruction graph.
player_clear_input :: proc(player: ^Player) {
	player.buffered_jump=0
	player.coyote=0
}
