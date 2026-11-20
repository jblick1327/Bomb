package main

import "core:math"
import "core:slice"
import "core:fmt"
import "core:os"

wood_study_dimensions :: proc(p: Polygon) -> (f32,f32) {
 lo,hi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}
 for v in p.points { lo={min(lo.x,v.x),min(lo.y,v.y)}; hi={max(hi.x,v.x),max(hi.y,v.y)} }
 return max(hi.x-lo.x,hi.y-lo.y),min(hi.x-lo.x,hi.y-lo.y)
}
wood_study_scene :: proc(seed: u8,size: Vec2) -> Scene {
 s:=new_scene(0.1); m:=add_material(&s,editor_material(.Wood)); owner:=add_piece(&s,m,seed)
 points:=[4]Vec2{{0,0},{size.x,0},{size.x,size.y},{0,size.y}}
 add_subdivision(&s,owner,Polygon{points=points[:]},Pose{position={size.x/2,size.y/2}})
 presplit_piece(&s,owner); return s
}
wood_plank_scene :: proc(seed:u8 = 42) -> Scene {
 g:=Sandbox{world=World{scene=new_scene(0.1),settings=DEFAULT_SANDBOX_SETTINGS}}
 g.world.settings.seed=seed
 append(&g.layout.objects,Authored_Shape{lo={0,0},hi={6,0.8},material=recipe_slot(.Wood),identity=1})
 editor_build_objects(&g); destroy_layout(&g.layout); return g.world.scene
}
wood_plank_checks :: proc(s: ^Scene) -> (int,int,int,int,int) {
 short,thick,oversize,seams,bad_seams:=0,0,0,0,0
 for sub in s.subdivisions {
  length,width:=wood_study_dimensions(sub.outline)
  if length<1-1e-5 { short+=1 }; if width>editor_material(.Wood).strip_thickness+1e-5 { thick+=1 }; if length>2+1e-5 { oversize+=1 }
 }
 for c in s.connections {
  a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
  segments:=shared_segments(a.outline,b.outline)
  points:[dynamic]Vec2
  for segment in segments { endpoints:=[2]Vec2{segment.a,segment.b}; for p in endpoints {
   found:=false; for q in points { if vlen(vsub(p,q))<1e-5 { found=true; break } }; if !found { append(&points,p) }
  } }
  delete(segments)
  slice.sort_by(points[:],proc(a,b: Vec2)->bool { return a.x<b.x || a.x==b.x && a.y<b.y })
  if len(points)>=2 {
   first,last:=points[0],points[len(points)-1]; extent:=vsub(last,first)
   if extent.x>0.5 && extent.x>2*math.abs(extent.y) {
    seams+=1; interior:=0
    for p in points[1:len(points)-1] { if math.abs(vcross(extent,vsub(p,first)))>1e-5*vlen(extent) { interior+=1 } }
    if interior<2 { bad_seams+=1 }
   }
  }
  delete(points)
 }
 return short,thick,oversize,seams,bad_seams
}
wood_nonwood_yard :: proc() -> Sandbox {
 g:=sandbox_editor_create()
 positions:=[4]f32{-7.2,-3,0,3.5}
 for choice in Recipe { if choice==.Wood { continue }; x:=positions[int(choice)]; g.editor.palette=recipe_slot(choice); assert(editor_place(&g,{x,0},{x+1.6,2})) }
 sandbox_toggle_editor(&g)
 blasts:=[3]Vec2{{-6.6,1},{0,0.6},{5.8,1.2}}
 for p in blasts { sandbox_explode(&g,p) }
 return g
}
wood_median :: proc(values: []f32) -> f32 {
 slice.sort(values); if len(values)==0 { return 0 }
 if len(values)%2==1 { return values[len(values)/2] }; return (values[len(values)/2-1]+values[len(values)/2])/2
}
run_wood_study :: proc(directory: string) {
 assert(os.make_directory_all(directory)==nil)
 plank:=wood_plank_scene()
 short,thick,oversize,seams,bad:=wood_plank_checks(&plank)
 fmt.printf("Plank: cells=%d short=%d thick=%d oversize=%d along_seams=%d bad_jagged_seams=%d\n",len(plank.subdivisions),short,thick,oversize,seams,bad)
 scene_destroy(&plank)
 lengths,widths:[dynamic]f32; defer delete(lengths); defer delete(widths)
 elongated,squat,count:=0,0,0; crater_sum,thrown_sum:f32
 fmt.println("seed,fragments,elongated,squat,crater_area,thrown_mass")
 for seed in 1..=16 {
  s:=wood_study_scene(u8(seed),{6,4})
  blast_pass(&s,Blast{{-0.1,2},5})
  largest:=u64(0); mass:=f32(-1)
  for p in s.pieces { if p.mass>mass { mass=p.mass; largest=p.id } }
  surviving,thrown:f32; n,e,q:=0,0,0
  for sub in s.subdivisions {
   area:=polygon_area(sub.outline); surviving+=area
   if sub.owner==largest { continue }; thrown+=area
   length,width:=wood_study_dimensions(sub.outline)
   append(&lengths,length); append(&widths,width); n+=1
   if length/width>=3 { e+=1 }; if length/width<1.6 { q+=1 }
  }
  fmt.printf("%d,%d,%d,%d,%.8f,%.8f\n",seed,n,e,q,24-surviving,thrown)
  count+=n; elongated+=e; squat+=q; crater_sum+=24-surviving; thrown_sum+=thrown
  path:=fmt.aprintf("%s/seed-%02d.json",directory,seed); assert(save_snapshot(&s,path)); delete(path)
  scene_destroy(&s)
 }
 fmt.printf("Grain pooled: fragments=%d elongated_pct=%.6f squat_pct=%.6f median_length=%.8f median_width=%.8f mean_crater=%.8f mean_thrown=%.8f\n",count,100*f64(elongated)/f64(count),100*f64(squat)/f64(count),wood_median(lengths[:]),wood_median(widths[:]),crater_sum/16,thrown_sum/16)
 g:=wood_nonwood_yard(); defer sandbox_destroy(&g)
 path:=fmt.aprintf("%s/nonwood-v3.json",directory); assert(save_world_snapshot(&g.world,path)); delete(path)
}
