package main

import "core:testing"
import "core:fmt"
import "core:sync"
import "core:math"
import "core:mem"

@(test)
rubber_bite_weights_do_not_cross_gap :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=rubber_bite_scene(); defer scene_destroy(&s)
 caches:=Render_Cache_State{}; defer release_render_caches(&caches)
 cross_gap,checked,_,_:=rubber_bite_measure(&s,&caches)
 fmt.printf("Rubber band A: cross-gap weight references=%d checked_bite_points=%d\n",cross_gap,checked)
 testing.expect(t,checked>0 && cross_gap==0)
}
@(test)
rubber_bite_film_is_hull_only_with_one_top_span :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=rubber_bite_scene(); defer scene_destroy(&s)
 caches:=Render_Cache_State{}; defer release_render_caches(&caches)
 _,_,off_hull,top_spans:=rubber_bite_measure(&s,&caches)
 fmt.printf("Rubber band B: off-hull film segments=%d top-edge spans=%d\n",off_hull,top_spans)
 testing.expect(t,off_hull==0 && top_spans==1)
}
@(test)
rubber_narrow_bite_weights_do_not_cross_gap :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 s:=rubber_bite_scene(true); defer scene_destroy(&s)
 caches:=Render_Cache_State{}; defer release_render_caches(&caches)
 render_cache_prepass(&s,&caches)
 cross_gap,checked:=0,0
 for sub in s.subdivisions {
  cache:=&caches.cells[sub.id]
  for p,i in cache.outline.points {
   // At the top of a one-cell bite, the detour through the row below
   // leaves SKIN_RADIUS. Near the bite bottom that detour is valid.
   if math.abs(p.x-0.8)>1e-5 || math.abs(p.y-1.6)>1e-5 { continue }; checked+=1
   for weight in cache.weights[i] {
    other:=s.subdivisions[s.sub_rows[weight.id]]
    if other.rest_center.x>1.2 && other.rest_center.y>1.2 { cross_gap+=1 }
   }
  }
 }
 fmt.printf("Rubber band A narrow-gap supplement: cross-gap weight references=%d checked_bite_points=%d\n",cross_gap,checked)
 testing.expect(t,checked>0 && cross_gap==0)
}

@(test)
rubber_bands_follow_piece_revisions_splits_and_cleanup :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 track: mem.Tracking_Allocator
 mem.tracking_allocator_init(&track,context.allocator); defer mem.tracking_allocator_destroy(&track)
 context.allocator=mem.tracking_allocator(&track)
 s:=rubber_bite_scene(); caches:=Render_Cache_State{}
 render_cache_prepass(&s,&caches)
 owner:=s.pieces[0].id; revision:=s.pieces[0].render_revision
 segments:=raw_data(caches.bands[owner].segments)
 render_cache_prepass(&s,&caches)
 testing.expect(t,len(caches.bands)==1 && raw_data(caches.bands[owner].segments)==segments,"Unchanged piece must reuse its band")
 f:=Failures{}
 for sub in s.subdivisions { if sub.rest_center.x>1.2 && sub.rest_center.x<1.6 { append(&f.discard_subdivisions,sub.id) } }
 apply_failures(&s,f); delete(f.discard_subdivisions)
 before,ok:=encode_snapshot(&s); testing.expect(t,ok)
 render_cache_prepass(&s,&caches)
 testing.expect(t,len(s.pieces)==2 && len(caches.bands)==2,"Disconnected chunks need separate bands")
 for piece in s.pieces {
  band,found:=caches.bands[piece.id]
  testing.expect(t,found && band.revision==piece.render_revision && len(band.hull)>=3 && len(band.segments)>0)
  testing.expect(t,piece.id!=owner || band.revision!=revision,"Changed geometry must invalidate its band")
  for segment in band.segments {
   testing.expect(t,s.subdivisions[s.sub_rows[segment.a.cell]].owner==piece.id && s.subdivisions[s.sub_rows[segment.b.cell]].owner==piece.id)
  }
 }
 after,encoded:=encode_snapshot(&s)
 testing.expect(t,encoded && string(before)==string(after),"Bands must not mutate the Scene")
 delete(before); delete(after)
 scene_destroy(&s); render_cache_prepass(&s,&caches)
 testing.expect(t,len(caches.bands)==0 && len(caches.cells)==0,"Pre-pass must prune destroyed cells and pieces")
 release_render_caches(&caches)
 fmt.printf("Rubber band cache: split_pieces=2 stale_bands=%d teardown_Odin_bytes=%d\n",len(caches.bands),track.current_memory_allocated)
 testing.expect(t,track.current_memory_allocated==0)
}
