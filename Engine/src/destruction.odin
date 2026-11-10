#+feature dynamic-literals
package main

import shared "shared"
import "core:time"
import "core:fmt"

import "core:math"
import "core:mem"

point_in_triangle :: proc(p,a,b,c: Vec2, orientation: f32, tolerance: f32 = 0.00001) -> bool {
	return vcross(vsub(b,a),vsub(p,a))*orientation >= -tolerance &&
	       vcross(vsub(c,b),vsub(p,b))*orientation >= -tolerance &&
	       vcross(vsub(a,c),vsub(p,c))*orientation >= -tolerance
}
// Straight cuts partition a shallow-concave outline directly. Collision convex
// decomposition is deliberately separate from logical fragment generation.

// Reuse the existing one-wave graph update for physics and for each blast wave.
// Ownership, size filtering and engine handles are committed only at the end.

// Descendants partition the outline, inherit its material and keep its rigid
// transform during this event. Their samples lie in the posed convex hull.
// Outward rounding and a strict load margin avoid pruning borderline failures.
// Refine every cell reached by the blast's destructive core, on every object,
// down to the minimum width. Fully doomed cells can use ordinary blast deletion;
// terminal or unpartitionable cells remain for the actual failure decision.
// Preserve birth contexts and inherited connections, and defer final bodies and
// the survivor impulse until the enclosing blast pass finishes.


// Creation-only refinement: inherit seams and birth contexts exactly as damage
// does, but keep unpartitionable live geometry instead of treating it as failed.

