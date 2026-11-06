package main

import shared "shared"
import "core:time"

import b2 "vendor:box2d"
import "core:math"


// The single anchoring rule shared by physics and presentation: a piece is
// static when some live cell has a non-degenerate edge lying on anchor_y.
// Reclamation is ordered by logical IDs, before packed records are removed.
// Bodies use the shared rest origin for rigid pieces, region centres for soft cells.
// This runs only between steps. Regrouping transfers one rigid body to its largest group.
// Contacts use the inelastic, normal velocity change implied by approach speed.
// A max across events also combines multiple points/fixtures of one body pair
// without counting their shared approach velocity more than once.
// Region contacts use their current connected piece; external actors use body mass.
