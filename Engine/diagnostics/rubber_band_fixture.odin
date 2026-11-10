package main

import "core:math"

// Use the editor's ordinary authored-object construction, discarding all three
// cells in one structural failure before creating any physics bodies.
rubber_bite_scene :: proc(narrow: bool = false) -> Scene {
 g:=Sandbox{world=World{scene=new_scene(0.1),settings=DEFAULT_SANDBOX_SETTINGS}}
 append(&g.layout.objects,Authored_Shape{lo={0,0},hi={2.4,1.6},material=recipe_slot(.Rubber),identity=1})
 editor_build_objects(&g); destroy_layout(&g.layout)
 s:=&g.world.scene
 assert(len(s.subdivisions)==24 && !s.physics.active)
 f:=Failures{}
 bite_hi:=f32(1.6); if narrow { bite_hi=1.2 }
 for sub in s.subdivisions {
  p:=sub.rest_center
  if p.y>1.2 && p.x>0.8 && p.x<bite_hi || p.x>1.6 && p.x<2 && p.y>0.4 && p.y<0.8 { append(&f.discard_subdivisions,sub.id) }
 }
 removed:=3; if narrow { removed=2 }; assert(len(f.discard_subdivisions)==removed)
 apply_failures(s,f); delete(f.discard_subdivisions)
 assert(len(s.subdivisions)==24-removed && len(s.pieces)==1)
 return g.world.scene
}

rubber_bite_measure :: proc(s: ^Scene,caches: ^Render_Cache_State) -> (int,int,int,int) {
 render_cache_prepass(s,caches)
 cross_gap,checked:=0,0
 for sub in s.subdivisions {
  cache:=&caches.cells[sub.id]
  for p,i in cache.outline.points {
   if math.abs(p.x-0.8)>1e-5 || p.y<1.2-1e-5 || p.y>1.6+1e-5 { continue }
   checked+=1
   for weight in cache.weights[i] {
    other:=s.subdivisions[s.sub_rows[weight.id]]
    if other.rest_center.x>1.6 && other.rest_center.y>1.2 { cross_gap+=1 }
   }
  }
 }
 // Known outer rectangle: an independent oracle for the production hull.
 hull:=[4]Vec2{{0,0},{2.4,0},{2.4,1.6},{0,1.6}}
 segments:=caches.bands[s.pieces[0].id].segments[:]
 off_hull,top_spans:=0,0
 for segment in segments {
  a,b:=film_rest(caches,segment.a),film_rest(caches,segment.b)
  on_hull:=false
  for h,i in hull { if rubber_on_segment(a,h,hull[(i+1)%len(hull)]) && rubber_on_segment(b,h,hull[(i+1)%len(hull)]) { on_hull=true; break } }
  if !on_hull { off_hull+=1 }
  if math.abs(a.y-1.6)<1e-5 && math.abs(b.y-1.6)<1e-5 && math.abs(math.abs(a.x-b.x)-0.8)<1e-5 && min(a.x,b.x)>0.79 && max(a.x,b.x)<1.61 { top_spans+=1 }
 }
 return cross_gap,checked,off_hull,top_spans
}
