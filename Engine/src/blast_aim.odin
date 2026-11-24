package main

import "core:math"

blast_damage_radius :: proc(scene: ^Scene,r: f32) -> f32 {
 strength:=math.inf_f32(1)
 for cell in scene.subdivisions {
  if !cell.live { continue }
  material:=scene.materials[cell.material]
  if finite(material.subdivision_strength) { strength=min(strength,material.subdivision_strength) }
  if finite(material.connection_strength) { strength=min(strength,material.connection_strength) }
 }
 return max(f32(0),r-strength/BLAST_LOAD_MULTIPLIER)
}
