package main

counts_live_subdivisions :: proc(s: ^Scene) -> int { result:=0; for sub in s.subdivisions { if sub.live { result+=1 } }; return result }
