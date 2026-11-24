package main

import "core:math"
import b2 "vendor:box2d"
import rl "vendor:raylib"

// Impulse toughness, in seconds of excess capacity. Each tick a seam with r >= 1 accumulates
// (r-1)*dt of damage and any tick below capacity heals it fully; it breaks at damage >= SEAM_TOUGHNESS.
// 0.4 s: geometric mean of the feasible sweep range 0.2..0.8 s (evidence/seam-toughness/sweep.md); the
// define exists only so scripts/seam-toughness-sweep.py can repeat that sweep.
MORTAR_COLOR :: rl.Color{236,226,198,255}
draw_mortar :: proc(s: ^Scene,view: View,poses,frames: map[u64]Pose,outline_width: f32) {
 ids:[dynamic]u64; defer delete(ids)
 for c in s.connections { if c.live && c.mortar { append(&ids,c.id) } }; sort_ids(ids[:])
 for id in ids {
  c:=s.connections[s.conn_rows[id]]
  if len(c.glue)>0 { draw_glue_connection(s,c,view,poses,frames,outline_width);continue }
  sub:=s.subdivisions[s.sub_rows[c.a]]
  rigid:=s.materials[sub.material].flexibility==0
  frame:=rigid_render_frame(s,sub,poses,frames)
  posed:=render_subdivision(s,sub,poses,frames)
  for segment in c.rest_segments {
   a,b:=posed_point(posed,segment.a),posed_point(posed,segment.b)
   if rigid { a=rigid_render_point(frame,segment.a); b=rigid_render_point(frame,segment.b) }
   rl.DrawLineEx(screen_point(view,a),screen_point(view,b),max(f32(2),outline_width),MORTAR_COLOR)
  }
 }
}

// Groups are emitted by their smallest connection ID; members are sorted by ID.
// The first member fixes the force orientation for the unordered body pair.
mortar_seam_need :: proc(seam: Mortar_Seam) -> f32 {
 return vlen(seam.force)/seam.length+2*math.abs(seam.torque)/(seam.length*seam.length)
}

