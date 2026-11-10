package main

free_failures :: proc(f: ^Failures) { delete(f.subdivisions); delete(f.connections); delete(f.discard_subdivisions); delete(f.impact_sources); f^={} }
