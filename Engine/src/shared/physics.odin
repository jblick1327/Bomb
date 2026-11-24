#+feature dynamic-literals
package shared

import b2 "vendor:box2d"
import math "core:math"

Physics :: struct {
 world: b2.WorldId,
 synced_revision: u64,
 synced: bool,
 active: bool,
 mortar_breaking: bool,
}

piece_anchored :: proc(s: ^Scene,piece_id: u64,anchor_y: f32) -> bool {
 row,ok:=s.piece_rows[piece_id]; if !ok { return false }
 for id in s.pieces[row].subdivisions {
  srow,found:=s.sub_rows[id]; if !found { continue }
  sub:=&s.subdivisions[srow]
  if !sub.live { continue }
  if sub.provenance.motion!=.Legacy { if sub.provenance.pinned { return true };continue }
  if !(anchor_y>-1e30) { continue }
  for a,i in sub.outline.points {
   b:=sub.outline.points[(i+1)%len(sub.outline.points)]
   if math.abs(a.y-anchor_y)<0.00001 && math.abs(b.y-anchor_y)<0.00001 && math.abs(a.x-b.x)>0.00001 { return true }
  }
 }
 return false
}

physics_destroy :: proc(s: ^Scene) {
 if !s.physics.active { return }
 b2.DestroyWorld(s.physics.world)
 for &sub in s.subdivisions { sub.body={}; sub.fixture_count=0; clear(&sub.shapes) }
 for &p in s.pieces { p.body={}; p.physics_revision=0; p.has_body_frame=false; p.source_body={} }
 for &c in s.connections { c.joint={} }
 s.physics = {}
}
