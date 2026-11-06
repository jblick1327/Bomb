package main

import nc "netcode"
import "core:slice"
import "core:strings"

// Structure replication, offline. A server keeps ONE shared index of the live
// structure and emits a Baseline or a Delta per tick when Scene.structure_revision
// changes. A Replica is a physics-free Scene built only from those messages.
//
// Canonical structure = what a client needs to draw: epoch, structure_revision,
// anchor_y, materials, cells (id, owner, material, frame, outline, rest_center),
// connections (id, a, b, mortar, glue samples) and pieces (id, material, cell ids
// in the host's order, immutable ref_rest). No seeds, damage, velocities or Box2D handles.


// ---------------------------------------------------------------- field codecs
// Cells of a piece in the host's order, live ones only.

// ---------------------------------------------------------------- canonical encode
// Appends the canonical structure to w. Equality of two scenes' canonical bytes is the
// replication invariant.

// ---------------------------------------------------------------- shared structure index

// ---------------------------------------------------------------- messages
// A joining client gets a Baseline at the current revision.
// Called once per tick after world_tick. Emits nothing, a Baseline (new epoch or first
// call) or exactly one Delta diffed against the shared index. Every client gets the same stream.

// ---------------------------------------------------------------- replica

// Every piece touched by a change gets a fresh render_revision and its non-mortar
// connection list rebuilt from its cells' links, as the host maintains it.

// Applies one complete (reassembled) message.
// Feed one part (a reliable-channel message). Parts apply atomically: nothing is
// applied until the last part of a message has arrived.

// Like replica_receive, but hands back the reassembled message (caller-owned) instead
// of applying it, so the client can hold it until its render clock reaches the stamped tick.
// The tick stamped on a Baseline or Delta message, and (Baseline only) its epoch.
