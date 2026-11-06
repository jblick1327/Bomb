package main

import nc "netcode"
import "core:fmt"

// Real-process, reliable application commands. No edits to the accepted netcode
// protocol. Only a Hello-authorized HOST can mutate the authoritative world.

// A world rebuild creates player zero if there were no active players. A
// dedicated server must never retain that solo-mode placeholder.

// The entire layout is decoded before anything in the live world changes.
// Ownership of the decoded layout transfers only on success. This is also the
// single place that converts an editor layout into a running multiplayer Test.

// Reset, blast mode and falling-bomb radius are the first host controls. Other
// host-only F3 edit commands and snapshots are handled in the later UI round.





