package main

import shared "shared"
import "core:time"

import "core:math"
import "core:slice"

// Same monotone chain and sort as convex_hull, with caller-owned storage.
// Capture each common cut once, then install the exact same displaced midpoint
// in both outlines. Parent boundary vertices are untouched, including T junctions.

// Merge adjacent triangles whenever their union is convex. In particular this
// avoids feeding thin ears from a displaced boundary to Box2D as tiny fixtures.

// Local double-precision predicates distinguish real crossings from f32
// cancellation at translated, nearly collinear seam vertices.
