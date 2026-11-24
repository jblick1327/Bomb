package main

import "base:runtime"
import b2 "vendor:box2d"

// Shape user data is the stable region ID, never a pointer into packed storage.
// Pending children have no bodies yet; include just those staged records too.
