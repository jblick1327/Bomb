#+feature dynamic-literals
package shared



seam_geometry :: proc(c:Connection)->(length:f32,center:Vec2) {
 if len(c.glue)>0 {
  for sample in c.glue { length+=sample.w;center=vadd(center,vmul(vadd(sample.p,sample.q),sample.w*0.5)) }
  if length>0 { center=vmul(center,1/length) };return
 }
 for seg in c.rest_segments { w:=vlen(vsub(seg.b,seg.a));length+=w;center=vadd(center,vmul(vadd(seg.a,seg.b),w*0.5)) }
 if length>0 { center=vmul(center,1/length) };return
}
