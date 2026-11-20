package shared

import t "core:testing"
import math "core:math"

// OD-10 (G-N10b): the bearing rule. Compression across a seam's face is not charged to the glue; tension, shear and
// torque are. The seam normal is G-N10's measured v3: glue-sample links (every glued seam in a level) use the
// direction between the two cell centres; sandbox mortar links (rest segments) use their longest segment.
// These tests pin down what that normal actually is on straight, offset, L-shaped, diagonal and gap seams.

od10_close :: proc(a,b: Vec2,eps: f32 = 1e-5) -> bool { return math.abs(a.x-b.x)<=eps && math.abs(a.y-b.y)<=eps }

// Normal of one link between two cells given by their rest outlines. glue=true makes a glue-sample link (no rest
// segments, as built by level glue); otherwise the link carries `segments` as its rest segments (sandbox mortar).
od10_link_normal :: proc(outline_a,outline_b: []Vec2,glue: bool,segments: []Segment=nil) -> Vec2 {
 s:Scene; s.sub_rows=make(map[u64]int); defer delete(s.sub_rows); defer delete(s.subdivisions)
 pa,pb:=make_polygon(outline_a),make_polygon(outline_b); defer delete(pa.points); defer delete(pb.points)
 append(&s.subdivisions,Subdivision{id=1,rest_center=centroid(pa)},Subdivision{id=2,rest_center=centroid(pb)})
 s.sub_rows[1]=0; s.sub_rows[2]=1
 c:=Connection{id=3,a=1,b=2,mortar=true,live=true}; defer { delete(c.glue); delete(c.rest_segments) }
 if glue { append(&c.glue,Glue_Sample{w=1}) } else { append(&c.rest_segments,..segments) }
 return mortar_link_normal(&s,c)
}

// The share of a pure bearing load (the weld pushing b straight away from a along `load`) that is still charged.
od10_charged_share :: proc(normal,load: Vec2) -> f32 {
 seam:=Mortar_Seam{normal=normal,force=load}; mortar_seam_split(&seam)
 return vlen(seam.charged)/vlen(load)
}

@(test)
od10_glue_normal_is_the_cell_centre_direction :: proc(test: ^t.T) {
 r2:=f32(math.sqrt(f32(2)))
 // Straight stack, same width: centre direction = face normal (up); a block resting on it is not charged at all.
 {
  n:=od10_link_normal({{0,0},{1,0},{1,.5},{0,.5}},{{0,.5},{1,.5},{1,1},{0,1}},true)
  t.expectf(test,od10_close(n,{0,1}),"straight stack %v",n)
  t.expect(test,od10_charged_share(n,{0,100})==0)
 }
 // Offset stack (b shifted half a cell right): the centre direction tilts 45°, so 71 % of a vertical bearing load
 // is still charged. This is the measured v3; the shared-face normal (up) was measured and rejected in G-N10b.
 {
  n:=od10_link_normal({{0,0},{1,0},{1,.5},{0,.5}},{{.5,.5},{1.5,.5},{1.5,1},{.5,1}},true)
  t.expectf(test,od10_close(n,{1/r2,1/r2}),"offset stack %v",n)
  t.expectf(test,math.abs(od10_charged_share(n,{0,100})-1/r2)<1e-5,"offset share %v",od10_charged_share(n,{0,100}))
 }
 // L-shaped cell a with b sitting in its notch (on the lower leg, against the upright): a's centroid is
 // (0.8333, 0.4167), b's (1.5, 0.75), so the normal is (2,1)/sqrt(5): 26.6° off the leg's face normal, between the
 // two faces b touches. A vertical bearing load is 89 % charged; a sideways push into the upright 45 %.
 {
  n:=od10_link_normal({{0,0},{2,0},{2,.5},{1,.5},{1,1},{0,1}},{{1,.5},{2,.5},{2,1},{1,1}},true)
  r5:=f32(math.sqrt(f32(5)))
  t.expectf(test,od10_close(n,{2/r5,1/r5}),"L-shaped %v",n)
  t.expectf(test,math.abs(od10_charged_share(n,{0,100})-2/r5)<1e-5,"L vertical share %v",od10_charged_share(n,{0,100}))
  t.expectf(test,math.abs(od10_charged_share(n,{100,0})-1/r5)<1e-5,"L sideways share %v",od10_charged_share(n,{100,0}))
 }
 // Diagonal seam between two mirror triangles of a unit square: the centre direction is the diagonal's normal.
 {
  n:=od10_link_normal({{0,0},{1,0},{1,1}},{{0,0},{1,1},{0,1}},true)
  t.expectf(test,od10_close(n,{-1/r2,1/r2}),"diagonal %v",n)
  t.expect(test,od10_charged_share(n,{-70,70})<1e-6)
 }
 // Diagonal seam between unequal triangles (a twice b's size): the centres are level, so the normal is
 // horizontal, 45° off the face. A load straight across the face is 71 % charged.
 {
  n:=od10_link_normal({{0,0},{2,0},{2,2}},{{0,0},{1,1},{0,1}},true)
  t.expectf(test,od10_close(n,{-1,0}),"unequal diagonal %v",n)
  t.expectf(test,math.abs(od10_charged_share(n,{-70,70})-1/r2)<1e-5,"unequal diagonal share %v",od10_charged_share(n,{-70,70}))
 }
 // Glue across a gap (0.036, as the Tower's pillars were before G5b): no shared face; the centre direction (up).
 {
  n:=od10_link_normal({{0,0},{1,0},{1,.5},{0,.5}},{{0,.536},{1,.536},{1,1.036},{0,1.036}},true)
  t.expectf(test,od10_close(n,{0,1}),"gap %v",n)
 }
 // Reversing the link reverses the normal (it always points from cell a to cell b).
 {
  n:=od10_link_normal({{0,.5},{1,.5},{1,1},{0,1}},{{0,0},{1,0},{1,.5},{0,.5}},true)
  t.expectf(test,od10_close(n,{0,-1}),"reversed %v",n)
 }
 // Coincident centres define no direction: the normal is zero and the seam is charged in full (the old rule).
 {
  n:=od10_link_normal({{0,0},{1,0},{1,1},{0,1}},{{0,0},{1,0},{1,1},{0,1}},true)
  t.expect(test,n==Vec2{})
  t.expect(test,od10_charged_share(n,{0,100})==1)
 }
}

@(test)
od10_sandbox_mortar_normal_is_the_longest_rest_segment :: proc(test: ^t.T) {
 r2:=f32(math.sqrt(f32(2)))
 la:=[]Vec2{{0,0},{2,0},{2,.5},{1,.5},{1,1},{0,1}};lb:=[]Vec2{{1,.5},{2,.5},{2,1},{1,1}}
 // L-shaped: two shared segments (the leg, length 1, and the upright, 0.5). The longest wins: the leg's face normal.
 n:=od10_link_normal(la,lb,false,{{{1,.5},{1,1}},{{1,.5},{2,.5}}})
 t.expectf(test,od10_close(n,{0,1}),"L-shaped segments %v",n)
 // Equal lengths: the first segment wins (oriented toward b).
 n=od10_link_normal(la,lb,false,{{{1,.5},{1,1}},{{1,.5},{1.5,.5}}})
 t.expectf(test,od10_close(n,{1,0}),"tie %v",n)
 // Diagonal segment: its perpendicular, pointing from a to b.
 n=od10_link_normal({{0,0},{1,0},{1,1}},{{0,0},{1,1},{0,1}},false,{{{0,0},{1,1}}})
 t.expectf(test,od10_close(n,{-1/r2,1/r2}),"diagonal segment %v",n)
 // A degenerate segment falls back to the centre direction.
 n=od10_link_normal({{0,0},{1,0},{1,.5},{0,.5}},{{.5,.5},{1.5,.5},{1.5,1},{.5,1}},false,{{{1,.5},{1,.5}}})
 t.expectf(test,od10_close(n,{1/r2,1/r2}),"degenerate %v",n)
}

@(test)
od10_compression_is_not_charged_tension_shear_and_torque_are :: proc(test: ^t.T) {
 s:Scene; s.sub_rows=make(map[u64]int); s.conn_rows=make(map[u64]int)
 defer delete(s.sub_rows); defer delete(s.conn_rows); defer delete(s.subdivisions); defer delete(s.connections); defer delete(s.materials)
 append(&s.materials,Material{})
 append(&s.subdivisions,Subdivision{id=1},Subdivision{id=2}); s.sub_rows[1]=0; s.sub_rows[2]=1
 append(&s.connections,Connection{id=3,a=1,b=2,mortar=true,live=true}); s.conn_rows[3]=0
 L:=f32(.5); strength:=MORTAR_STRENGTH*material_glue_toughness(Material{})
 seam:=Mortar_Seam{length=L,normal={0,1}}; append(&seam.members,u64(3)); defer delete(seam.members)
 ratio :: proc(s: ^Scene,seam: ^Mortar_Seam,force: Vec2,torque: f32) -> f32 { seam.force=force; seam.torque=torque; mortar_seam_split(seam); return mortar_seam_ratio(s,seam^) }
 near :: proc(a,b: f32) -> bool { return math.abs(a-b)<=1e-5*max(f32(1),math.abs(b)) }
 // Compression ten times the capacity: all bearing, r = 0, and the damage clock does not run.
 big:=10*strength*L
 t.expect(test,ratio(&s,&seam,{0,big},0)==0 && seam.bearing==big && seam.charged==Vec2{})
 failures:Failures; defer free_failures(&failures)
 seam.damage=SEAM_TOUGHNESS*.9; mortar_apply_seam(&s,seam,&failures,1.0/60)
 t.expect(test,len(failures.connections)==0 && s.connections[0].damage==0,"a seam in pure bearing heals and never breaks")
 // Tension (the weld pulling b back toward a) is charged in full.
 t.expect(test,near(ratio(&s,&seam,{0,-1.1*strength*L},0),1.1) && seam.bearing==0)
 // Shear along the face is charged in full.
 t.expect(test,near(ratio(&s,&seam,{1.1*strength*L,0},0),1.1))
 // Shear with bearing: only the shear part is charged.
 t.expect(test,near(ratio(&s,&seam,{1.1*strength*L,big},0),1.1) && seam.charged==Vec2{1.1*strength*L,0})
 // Torque is charged in full, bearing or not (no moment relief: that was v4).
 q:=1.1*0.5*strength*L*L
 t.expect(test,near(ratio(&s,&seam,{},q),1.1))
 t.expect(test,near(ratio(&s,&seam,{0,big},q),1.1))
 // Over capacity in tension the clock runs and the seam breaks as before.
 seam.force={0,-2*strength*L}; mortar_seam_split(&seam); seam.damage=SEAM_TOUGHNESS
 mortar_apply_seam(&s,seam,&failures,1.0/60)
 t.expect(test,len(failures.connections)==1 && failures.connections[0]==3)
}
