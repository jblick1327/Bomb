package main

import nc "netcode"
import "core:math"
import "core:slice"

// In-process client for step 2b: a netcode endpoint, a physics-free replica, the pose
// tables of complete frames, an adaptive render clock and the interpolated poses to draw.





// ---------------------------------------------------------------- receiving
// A new epoch's Baseline resets the replica, the tables and the clock.

// ---------------------------------------------------------------- clock and delay
// Applies queued structure messages and events whose tick the clock has reached, in order.

// ---------------------------------------------------------------- draw poses
// Interpolates between the tables of the complete frames that bracket the render tick.

// ---------------------------------------------------------------- one client step
// Process everything delivered since the last step, then produce this tick's input.
