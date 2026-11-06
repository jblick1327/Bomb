package shared
import "core:fmt"
import "core:time"
// Shared instrumentation state, independent of diagnostic rendering entry points.
BOM_MORTAR_MEASURE :: #config(BOM_MORTAR_MEASURE,false)
BOM_FRAME_BENCH :: #config(BOM_FRAME_BENCH,false)
@(thread_local) cover_wood_failures:int
when BOM_MORTAR_MEASURE { @(thread_local) mortar_measured_force_breaks: int }
when BOM_FRAME_BENCH {
 frame_measuring: bool
 frame_cache_ms,frame_physics_ms: f64
 frame_ms :: proc(start:time.Tick)->f64 { return f64(time.tick_diff(start,time.tick_now()))/f64(time.Millisecond) }
}
seam_diagnostic_scene:^Scene
seam_diagnostic_layout:^Layout
seam_diagnostic_tick:int
seam_diagnostic_run:string
seam_diagnostic_phase:string
seam_object :: proc(sub:Subdivision)->u64 {
 if seam_diagnostic_layout==nil { return 0 }
 for object in seam_diagnostic_layout.objects { p:=shape_polygon(object);inside:=convex_contains(p,sub.rest_center);delete(p.points);if inside { return object.identity } };return 0
}
seam_diagnostic_death :: proc(s:^Scene,c:Connection,path:string) {
 if s!=seam_diagnostic_scene { return }
 a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
 fmt.printf("DEATH run=%s tick=%d phase=%s path=%s id=%d objects=%d/%d glue=%v endpoints_live=%v/%v\n",seam_diagnostic_run,seam_diagnostic_tick,seam_diagnostic_phase,path,c.id,seam_object(a),seam_object(b),len(c.glue)>0,a.live,b.live)
}
// Peak damage per connection id, recorded for one scene while seam_damage_scene is set (a break tick's
// value includes the excess that broke it).
seam_damage_scene:^Scene
seam_damage_peak:map[u64]f32
seam_diagnostic_force :: proc(s:^Scene,seam:Mortar_Seam,r:f32,broken:bool,damage:f32) {
 if s==seam_damage_scene && s!=nil { for id in seam.members { seam_damage_peak[id]=max(seam_damage_peak[id],damage) } }
 if s!=seam_diagnostic_scene { return }
 fmt.printf("FORCE run=%s tick=%d bodies=%v/%v r=%.9f damage_before=%.9f damage_after=%.9f broken=%v ids=%v\n",seam_diagnostic_run,seam_diagnostic_tick,seam.bodies[0],seam.bodies[1],r,seam.damage,damage,broken,seam.members[:])
}

when ODIN_TEST { @(thread_local) glass_commit_test_calls: int }
