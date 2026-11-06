package shared

// Match the presentation limits before allocating or dereferencing decoded IDs.
REPL_MAX_CELLS :: 100_000
REPL_MAX_VERTICES :: 1_000_000
REPL_MAX_ASSEMBLED_BYTES :: 32*1024*1024
Repl_Piece_Add :: struct { id: u64, material: int, ref_rest: Vec2, cells: []u64 }

repl_valid_material :: proc(m:Material) -> bool {
 return len(m.name)<=4096 && m.generation_count>=0 && finite(m.subdivision_strength) && finite(m.connection_strength) && finite(m.flexibility) && finite(m.impact_scale) && finite(m.aspect_ratio) && finite(m.shock_loss) && finite(m.blast_resistance) && finite(m.strip_thickness)
}
repl_valid_cell :: proc(c:Repl_Cell,materials:int) -> bool {
 if c.id==0 || c.owner==0 || c.material<0 || c.material>=materials || !finite(c.frame) || !valid_vec(c.rest_center) || len(c.outline)<3 || len(c.outline)>REPL_MAX_VERTICES { return false }
 for p in c.outline { if !valid_vec(p) { return false } }
 return true
}
repl_valid_connection :: proc(c:Repl_Connection) -> bool {
 if c.id==0 || c.a==0 || c.b==0 || c.a==c.b { return false }
 for g in c.glue { if !valid_vec(g.p) || !valid_vec(g.q) || !finite(g.w) { return false } }
 return true
}
repl_valid_piece :: proc(rep:^Replica,id:u64,material:int,ref_rest:Vec2,cells:[]u64) -> bool {
 if id==0 || material<0 || material>=len(rep.scene.materials) || !valid_vec(ref_rest) || len(cells)==0 || len(cells)>REPL_MAX_CELLS { return false }
 seen:=make(map[u64]bool);defer delete(seen)
 for cell in cells { if cell not_in rep.scene.sub_rows || seen[cell] { return false };seen[cell]=true }
 return true
}

// Validate the complete prospective reference graph before mutating live data.
// Membership lists are authoritative: an existing cell may move to a new piece.
repl_validate_delta :: proc(rep:^Replica,materials:[]Material,cells_added:[]Repl_Cell,cells_removed:[]u64,conns_added:[]Repl_Connection,conns_removed:[]u64,pieces_added:[]Repl_Piece_Add,pieces_removed:[]u64,pieces_changed:[]Repl_Piece_Add) -> string {
 s:=&rep.scene
 cells:=make(map[u64]bool);defer delete(cells)
 vertices:=0
 pieces:=make(map[u64][]u64);defer delete(pieces)
 conns:=make(map[u64][2]u64);defer delete(conns)
 for c in s.subdivisions { cells[c.id]=true;vertices+=len(c.outline.points) }
 for p in s.pieces { pieces[p.id]=p.subdivisions[:] }
 for c in s.connections { conns[c.id]={c.a,c.b} }
 for id in cells_removed { if cells[id] { vertices-=len(s.subdivisions[s.sub_rows[id]].outline.points) };delete_key(&cells,id) }
 for id in pieces_removed { delete_key(&pieces,id) }
 for id in conns_removed { delete_key(&conns,id) }
 for m in materials { if !repl_valid_material(m) { return "invalid delta material" } }
 for c in cells_added {
  if !repl_valid_cell(c,len(s.materials)+len(materials)) || cells[c.id] { return "invalid or duplicate delta cell" }
  cells[c.id]=true
  vertices+=len(c.outline)
 }
 if len(cells)>REPL_MAX_CELLS { return "delta exceeds cell capacity" }
 if vertices>REPL_MAX_VERTICES { return "delta exceeds outline capacity" }
 for p in pieces_added {
  if p.id==0 || p.id in pieces || p.material<0 || p.material>=len(s.materials)+len(materials) || !valid_vec(p.ref_rest) { return "invalid or duplicate delta piece" }
  pieces[p.id]=p.cells
 }
 changed:=make(map[u64]bool);defer delete(changed)
 for p in pieces_changed {
  if p.id not_in pieces || changed[p.id] { return "unknown or duplicate changed piece" }
  changed[p.id]=true;pieces[p.id]=p.cells
 }
 membership:=make(map[u64]u64);defer delete(membership)
 for id,list in pieces {
  if len(list)==0 { return "empty delta piece" }
  for cell in list {
   if !cells[cell] || cell in membership { return "invalid delta membership" }
   membership[cell]=id
  }
 }
 if len(membership)!=len(cells) { return "delta leaves an unowned cell" }
 for c in cells_added { if membership[c.id]!=c.owner { return "delta cell owner does not match membership" } }
 for c in conns_added {
  if !repl_valid_connection(c) || c.id in conns { return "invalid or duplicate delta connection" }
  conns[c.id]={c.a,c.b}
 }
 for _,ends in conns { if !cells[ends[0]] || !cells[ends[1]] { return "delta connection endpoint is missing" } }
 return ""
}
