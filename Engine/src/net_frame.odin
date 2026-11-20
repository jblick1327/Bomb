package main

import nc "netcode"
import "core:math"
import "core:slice"

// Step 2b wire formats: pose frames (unreliable, server -> client), inputs (unreliable,
// client -> server) and reliable events. The netcode quantizers stay as they are; the
// pose grid below is the game-side quantizer chosen by the resolution measurement.



// Quantized pose of one entity. landed and fuse are only meaningful for bombs.

// Signed shortest difference on the angle ring.
// Shortest signed arc between two angles in radians.


// ---------------------------------------------------------------- frame codec


// Appends one entry; `previous` tracks the id-delta chain within a part.
// Exact encoded size of an entry in the current chain, without advancing it.
// Estimated size for budgeting before the final chain is known (id delta assumed 2 bytes).

// Splits the sorted gone keys and sorted entries into independent parts of at most
// FRAME_PART_MAX bytes and appends each part (caller-owned) to `parts`.
// Decodes the body (after the header). Delta entries need the base table row.
// Whole-part decode for tests and fuzzing.

// ---------------------------------------------------------------- input codec

// a is newer than b on the u16 ring.

// ---------------------------------------------------------------- reliable events

