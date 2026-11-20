package main
import "core:math"

validate_glue_samples :: proc(c:Connection,a,b:Subdivision)->string {
 if !c.mortar { return "Glue must be mortar" }
 for sample in c.glue {
  if !valid_vec(sample.p) || !valid_vec(sample.q) || !finite(sample.w) || sample.w<=0 { return "Invalid glue sample" }
  if vlen(vsub(sample.p,sample.q))>GLUE_FILLET+1e-4 { return "Glue sample too wide" }
  if vlen(vsub(sample.p,boundary_nearest(a.outline,sample.p)))>1e-4 || vlen(vsub(sample.q,boundary_nearest(b.outline,sample.q)))>1e-4 { return "Glue sample off boundary" }
 };return ""
}
