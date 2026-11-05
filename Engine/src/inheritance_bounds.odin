package main
// Conservative: shared_segments accepts endpoints within 1e-4 of a line.
// This padded box rejection cannot remove an accepted boundary overlap.
inheritance_bounds_overlap :: proc(a,b: Polygon) -> bool {
 alo,ahi:=Vec2{1e30,1e30},Vec2{-1e30,-1e30}; blo,bhi:=alo,ahi
 for p in a.points { alo={min(alo.x,p.x),min(alo.y,p.y)}; ahi={max(ahi.x,p.x),max(ahi.y,p.y)} }
 for p in b.points { blo={min(blo.x,p.x),min(blo.y,p.y)}; bhi={max(bhi.x,p.x),max(bhi.y,p.y)} }
 return alo.x<=bhi.x+0.001 && blo.x<=ahi.x+0.001 && alo.y<=bhi.y+0.001 && blo.y<=ahi.y+0.001
}
