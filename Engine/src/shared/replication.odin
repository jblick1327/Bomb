#+feature dynamic-literals
package shared

import nc "../netcode"
import slice "core:slice"
import strings "core:strings"

REPL_CANON_VERSION :: u8(3)

REPL_PART_LIMIT :: 200_000 // Messages above this are split; the reliable limit is 255 KB.

REPL_PART_MARK :: u8(0xB5)

Repl_Kind :: enum u8 { None, Baseline, Delta }

repl_write_material :: proc(w: ^nc.Writer,m: Material) {
 nc.write_string(w,m.name)
 nc.write_f32(w,m.subdivision_strength); nc.write_f32(w,m.connection_strength)
 nc.write_f32(w,m.flexibility); nc.write_f32(w,m.impact_scale)
 nc.write_varint(w,u64(m.generation_count))
 nc.write_f32(w,m.aspect_ratio); nc.write_bool(w,m.triangulate)
 nc.write_f32(w,m.shock_loss); nc.write_f32(w,m.blast_resistance); nc.write_f32(w,m.strip_thickness)
 nc.write_u8(w,m.color[0]); nc.write_u8(w,m.color[1]); nc.write_u8(w,m.color[2])
}

repl_read_material :: proc(r: ^nc.Reader) -> Material {
 m:Material
 m.name=nc.read_string(r)
 m.subdivision_strength=nc.read_f32(r); m.connection_strength=nc.read_f32(r)
 m.flexibility=nc.read_f32(r); m.impact_scale=nc.read_f32(r)
 m.generation_count=int(nc.read_varint(r))
 m.aspect_ratio=nc.read_f32(r); m.triangulate=nc.read_bool(r)
 m.shock_loss=nc.read_f32(r); m.blast_resistance=nc.read_f32(r); m.strip_thickness=nc.read_f32(r)
 m.color[0]=nc.read_u8(r); m.color[1]=nc.read_u8(r); m.color[2]=nc.read_u8(r)
 return m
}

repl_write_cell :: proc(w: ^nc.Writer,sub: Subdivision) {
 nc.write_varint(w,sub.id); nc.write_varint(w,sub.owner); nc.write_varint(w,u64(sub.material))
 nc.write_u64(w,sub.provenance.source_identity);nc.write_u64(w,sub.provenance.source_part_id);nc.write_u32(w,cell_policy_flags(sub.provenance))
 nc.write_f32(w,sub.frame)
 nc.write_varint(w,u64(len(sub.outline.points)))
 for p in sub.outline.points { nc.write_f32(w,p.x); nc.write_f32(w,p.y) }
 nc.write_f32(w,sub.rest_center.x); nc.write_f32(w,sub.rest_center.y)
}

Repl_Cell :: struct { id,owner: u64, material: int, frame: f32, outline: []Vec2, rest_center: Vec2, provenance:Cell_Provenance }

repl_read_cell :: proc(r: ^nc.Reader) -> Repl_Cell {
 c:Repl_Cell
 c.id=nc.read_varint(r); c.owner=nc.read_varint(r); c.material=int(nc.read_varint(r))
 source,part:=nc.read_u64(r),nc.read_u64(r);flags:=nc.read_u32(r)
 policy,valid:=cell_policy_decode(source,part,flags);if !valid { nc.reader_fail(r);return c };c.provenance=policy
 c.frame=nc.read_f32(r)
 count:=nc.read_varint(r)
 if !r.ok || count>REPL_MAX_VERTICES || count>u64(nc.reader_remaining(r))/8 { nc.reader_fail(r); return c }
 c.outline=make([]Vec2,int(count))
 for i in 0..<int(count) { c.outline[i]={nc.read_f32(r),nc.read_f32(r)} }
 c.rest_center={nc.read_f32(r),nc.read_f32(r)}
 return c
}

repl_write_connection :: proc(w: ^nc.Writer,c: Connection) {
 nc.write_varint(w,c.id); nc.write_varint(w,c.a); nc.write_varint(w,c.b); nc.write_bool(w,c.mortar)
 nc.write_varint(w,u64(len(c.glue)))
 for g in c.glue { nc.write_f32(w,g.p.x); nc.write_f32(w,g.p.y); nc.write_f32(w,g.q.x); nc.write_f32(w,g.q.y); nc.write_f32(w,g.w) }
}

Repl_Connection :: struct { id,a,b: u64, mortar: bool, glue: []Glue_Sample }

repl_read_connection :: proc(r: ^nc.Reader) -> Repl_Connection {
 c:Repl_Connection
 c.id=nc.read_varint(r); c.a=nc.read_varint(r); c.b=nc.read_varint(r); c.mortar=nc.read_bool(r)
 count:=nc.read_varint(r)
 if !r.ok || count>REPL_MAX_VERTICES || count>u64(nc.reader_remaining(r))/20 { nc.reader_fail(r); return c }
 c.glue=make([]Glue_Sample,int(count))
 for i in 0..<int(count) { c.glue[i]={p={nc.read_f32(r),nc.read_f32(r)},q={nc.read_f32(r),nc.read_f32(r)},w=nc.read_f32(r)} }
 return c
}

repl_write_id_list :: proc(w: ^nc.Writer,ids: []u64) {
 nc.write_varint(w,u64(len(ids)))
 for id in ids { nc.write_varint(w,id) }
}

repl_read_id_list :: proc(r: ^nc.Reader) -> []u64 {
 count:=nc.read_varint(r)
 if !r.ok || count>REPL_MAX_VERTICES || count>u64(nc.reader_remaining(r)) { nc.reader_fail(r); return nil }
 ids:=make([]u64,int(count))
 for i in 0..<int(count) { ids[i]=nc.read_varint(r) }
 return ids
}

repl_piece_cells :: proc(s: ^Scene,p: Piece,out: ^[dynamic]u64) {
 clear(out)
 for id in p.subdivisions { if is_live_subdivision(s,id) { append(out,id) } }
}

repl_hash :: proc(data: []u8) -> u64 {
 h:=u64(0xcbf29ce484222325)
 for b in data { h~=u64(b); h*=0x100000001b3 }
 return h
}

Repl_Scratch :: struct { cells,conns,pieces,list: [dynamic]u64 }

repl_scratch_destroy :: proc(x: ^Repl_Scratch) { delete(x.cells); delete(x.conns); delete(x.pieces); delete(x.list); x^={} }

repl_collect_ids :: proc(s: ^Scene,x: ^Repl_Scratch) {
 clear(&x.cells); clear(&x.conns); clear(&x.pieces)
 for sub in s.subdivisions { if sub.live { append(&x.cells,sub.id) } }
 for c in s.connections { if c.live { append(&x.conns,c.id) } }
 for p in s.pieces { if p.live { append(&x.pieces,p.id) } }
 slice.sort(x.cells[:]); slice.sort(x.conns[:]); slice.sort(x.pieces[:])
}

repl_write_body :: proc(w: ^nc.Writer,s: ^Scene,x: ^Repl_Scratch) {
 nc.write_varint(w,u64(len(s.materials)))
 for m in s.materials { repl_write_material(w,m) }
 nc.write_varint(w,u64(len(x.cells)))
 for id in x.cells { repl_write_cell(w,s.subdivisions[s.sub_rows[id]]) }
 nc.write_varint(w,u64(len(x.conns)))
 for id in x.conns { repl_write_connection(w,s.connections[s.conn_rows[id]]) }
 nc.write_varint(w,u64(len(x.pieces)))
 for id in x.pieces {
  p:=s.pieces[s.piece_rows[id]]
  repl_piece_cells(s,p,&x.list)
  nc.write_varint(w,p.id); nc.write_varint(w,u64(p.material)); nc.write_f32(w,p.ref_rest.x); nc.write_f32(w,p.ref_rest.y); repl_write_id_list(w,x.list[:])
 }
}

canonical_encode_into :: proc(w: ^nc.Writer,s: ^Scene,x: ^Repl_Scratch) {
 scene_finish_references(s)
 repl_collect_ids(s,x)
 nc.write_u8(w,REPL_CANON_VERSION)
 nc.write_varint(w,u64(s.epoch)); nc.write_varint(w,s.structure_revision); nc.write_f32(w,s.anchor_y)
 repl_write_catalog(w,s)
 repl_write_body(w,s,x)
}

canonical_encode :: proc(s: ^Scene) -> []u8 {
 x:Repl_Scratch; defer repl_scratch_destroy(&x)
 w:nc.Writer; nc.writer_init(&w)
 canonical_encode_into(&w,s,&x)
 return w.data[:]
}

Repl_Piece :: struct { material: int, ref_rest: Vec2, cells: [dynamic]u64 }

Repl_Index :: struct {
 valid: bool,
 epoch: u32, revision: u64, anchor_y: f32,
 materials: [dynamic]u64, // hash of each material record
 cells: map[u64]bool,
 conn_hash: map[u64]u64, // 0 for plain connections (immutable); glue hash otherwise
 pieces: map[u64]Repl_Piece,
}

repl_index_destroy :: proc(idx: ^Repl_Index) {
 delete(idx.materials); delete(idx.cells); delete(idx.conn_hash)
 for _,p in idx.pieces { delete(p.cells) }; delete(idx.pieces)
 idx^={}
}

repl_material_hash :: proc(m: Material) -> u64 {
 w:nc.Writer; nc.writer_init(&w); defer nc.writer_destroy(&w)
 repl_write_material(&w,m)
 return repl_hash(w.data[:])
}

repl_connection_hash :: proc(c: Connection) -> u64 {
 if len(c.glue)==0 { return 0 }
 w:nc.Writer; nc.writer_init(&w); defer nc.writer_destroy(&w)
 repl_write_connection(&w,c)
 return repl_hash(w.data[:])|1
}

repl_index_rebuild :: proc(idx: ^Repl_Index,s: ^Scene,x: ^Repl_Scratch) {
 scene_finish_references(s)
 repl_index_destroy(idx)
 idx.valid=true; idx.epoch=s.epoch; idx.revision=s.structure_revision; idx.anchor_y=s.anchor_y
 idx.cells=make(map[u64]bool); idx.conn_hash=make(map[u64]u64); idx.pieces=make(map[u64]Repl_Piece)
 for m in s.materials { append(&idx.materials,repl_material_hash(m)) }
 for sub in s.subdivisions { if sub.live { idx.cells[sub.id]=true } }
 for c in s.connections { if c.live { idx.conn_hash[c.id]=repl_connection_hash(c) } }
 for p in s.pieces {
  if !p.live { continue }
  entry:=Repl_Piece{material=p.material,ref_rest=p.ref_rest}
  repl_piece_cells(s,p,&entry.cells)
  idx.pieces[p.id]=entry
 }
}

Repl_Server :: struct {
 index: Repl_Index,
 scratch: Repl_Scratch,
 seq: u32,
}

repl_server_destroy :: proc(srv: ^Repl_Server) { repl_index_destroy(&srv.index); repl_scratch_destroy(&srv.scratch); srv^={} }

Repl_Output :: struct {
 kind: Repl_Kind,
 message_bytes: int, // before splitting
 parts: [dynamic][]u8,
 delta_cells_added,delta_cells_removed,delta_conns_added,delta_conns_removed,delta_pieces_added,delta_pieces_removed,delta_pieces_changed: int,
}

repl_output_destroy :: proc(out: ^Repl_Output) {
 for part in out.parts { delete(part) }; delete(out.parts); out^={}
}

repl_split :: proc(message: []u8,seq: u32,limit: int,out: ^Repl_Output) {
 count:=max(1,(len(message)+limit-1)/limit)
 for i in 0..<count {
  lo,hi:=i*limit,min(len(message),(i+1)*limit)
  w:nc.Writer; nc.writer_init(&w,hi-lo+16)
  nc.write_u8(&w,REPL_PART_MARK); nc.write_varint(&w,u64(seq)); nc.write_varint(&w,u64(i)); nc.write_varint(&w,u64(count))
  nc.write_raw(&w,message[lo:hi])
  append(&out.parts,w.data[:])
 }
 out.message_bytes=len(message)
}

repl_encode_baseline :: proc(s: ^Scene,tick: u64,x: ^Repl_Scratch,w: ^nc.Writer) {
 nc.write_u8(w,u8(Repl_Kind.Baseline)); nc.write_varint(w,tick)
 canonical_encode_into(w,s,x)
}

repl_server_baseline :: proc(srv: ^Repl_Server,s: ^Scene,tick: u64,limit: int = REPL_PART_LIMIT) -> Repl_Output {
 out:Repl_Output; out.kind=.Baseline
 w:nc.Writer; nc.writer_init(&w); defer nc.writer_destroy(&w)
 repl_encode_baseline(s,tick,&srv.scratch,&w)
 srv.seq+=1
 repl_split(w.data[:],srv.seq,limit,&out)
 return out
}

repl_server_update :: proc(srv: ^Repl_Server,s: ^Scene,tick: u64,limit: int = REPL_PART_LIMIT) -> Repl_Output {
 scene_finish_references(s)
 idx:=&srv.index
 need_baseline:=!idx.valid || idx.epoch!=s.epoch || idx.anchor_y!=s.anchor_y || len(s.materials)<len(idx.materials)
 if !need_baseline {
  for i in 0..<len(idx.materials) { if repl_material_hash(s.materials[i])!=idx.materials[i] { need_baseline=true; break } }
 }
 if need_baseline {
  repl_index_rebuild(idx,s,&srv.scratch)
  return repl_server_baseline(srv,s,tick,limit)
 }
 if idx.revision==s.structure_revision { return {} }
 out:Repl_Output; out.kind=.Delta
 x:=&srv.scratch
 repl_collect_ids(s,x)
 added_cells,removed_cells,added_conns,removed_conns,added_pieces,removed_pieces,changed_pieces:[dynamic]u64
 defer { delete(added_cells); delete(removed_cells); delete(added_conns); delete(removed_conns); delete(added_pieces); delete(removed_pieces); delete(changed_pieces) }
 // Cells are immutable once created, so presence alone identifies them.
 for id in x.cells { if !idx.cells[id] { append(&added_cells,id) } }
 for id in idx.cells { if !is_live_subdivision(s,id) { append(&removed_cells,id) } }
 for id in x.conns {
  c:=s.connections[s.conn_rows[id]]
  old,present:=idx.conn_hash[id]
  if !present { append(&added_conns,id) }
  else if hash:=repl_connection_hash(c); hash!=old { append(&removed_conns,id); append(&added_conns,id) } // glue samples inherited in place
 }
 for id in idx.conn_hash {
  if row,ok:=s.conn_rows[id]; !ok || !s.connections[row].live { append(&removed_conns,id) }
 }
 cells:[dynamic]u64; defer delete(cells)
 for id in x.pieces {
  p:=s.pieces[s.piece_rows[id]]
  repl_piece_cells(s,p,&cells)
  old,present:=idx.pieces[id]
  if !present { append(&added_pieces,id) }
  else if old.material!=p.material { append(&removed_pieces,id); append(&added_pieces,id) }
  else {
   assert(old.ref_rest==p.ref_rest,"a published piece reference must be immutable")
   if !slice.equal(old.cells[:],cells[:]) { append(&changed_pieces,id) }
  }
 }
 for id in idx.pieces {
  if row,ok:=s.piece_rows[id]; !ok || !s.pieces[row].live { append(&removed_pieces,id) }
 }
 slice.sort(removed_cells[:]); slice.sort(removed_conns[:]); slice.sort(removed_pieces[:])
 w:nc.Writer; nc.writer_init(&w); defer nc.writer_destroy(&w)
 nc.write_u8(&w,u8(Repl_Kind.Delta)); nc.write_varint(&w,tick)
 nc.write_varint(&w,u64(s.epoch)); nc.write_varint(&w,idx.revision); nc.write_varint(&w,s.structure_revision)
 nc.write_varint(&w,u64(len(s.materials)-len(idx.materials)))
 for i in len(idx.materials)..<len(s.materials) { repl_write_material(&w,s.materials[i]) }
 nc.write_varint(&w,u64(len(added_cells)))
 for id in added_cells { repl_write_cell(&w,s.subdivisions[s.sub_rows[id]]) }
 repl_write_id_list(&w,removed_cells[:])
 nc.write_varint(&w,u64(len(added_conns)))
 for id in added_conns { repl_write_connection(&w,s.connections[s.conn_rows[id]]) }
 repl_write_id_list(&w,removed_conns[:])
 nc.write_varint(&w,u64(len(added_pieces)))
 for id in added_pieces {
  p:=s.pieces[s.piece_rows[id]]; repl_piece_cells(s,p,&cells)
  nc.write_varint(&w,id); nc.write_varint(&w,u64(p.material)); nc.write_f32(&w,p.ref_rest.x); nc.write_f32(&w,p.ref_rest.y); repl_write_id_list(&w,cells[:])
 }
 repl_write_id_list(&w,removed_pieces[:])
 nc.write_varint(&w,u64(len(changed_pieces)))
 for id in changed_pieces {
  p:=s.pieces[s.piece_rows[id]]; repl_piece_cells(s,p,&cells)
  nc.write_varint(&w,id); repl_write_id_list(&w,cells[:])
 }
 out.delta_cells_added=len(added_cells); out.delta_cells_removed=len(removed_cells)
 out.delta_conns_added=len(added_conns); out.delta_conns_removed=len(removed_conns)
 out.delta_pieces_added=len(added_pieces); out.delta_pieces_removed=len(removed_pieces); out.delta_pieces_changed=len(changed_pieces)
 // Advance the shared index to the scene it just described.
 for m in s.materials[len(idx.materials):] { append(&idx.materials,repl_material_hash(m)) }
 for id in removed_cells { delete_key(&idx.cells,id) }
 for id in added_cells { idx.cells[id]=true }
 for id in removed_conns { delete_key(&idx.conn_hash,id) }
 for id in added_conns { idx.conn_hash[id]=repl_connection_hash(s.connections[s.conn_rows[id]]) }
 for id in removed_pieces { if old,ok:=idx.pieces[id]; ok { delete(old.cells); delete_key(&idx.pieces,id) } }
 for id in added_pieces {
  p:=s.pieces[s.piece_rows[id]]
  entry:=Repl_Piece{material=p.material,ref_rest=p.ref_rest}; repl_piece_cells(s,p,&entry.cells); idx.pieces[id]=entry
 }
 for id in changed_pieces {
  p:=s.pieces[s.piece_rows[id]]
  entry:=idx.pieces[id]; repl_piece_cells(s,p,&entry.cells); idx.pieces[id]=entry
 }
 idx.revision=s.structure_revision
 srv.seq+=1
 repl_split(w.data[:],srv.seq,limit,&out)
 return out
}

Replica :: struct {
 scene: Scene, // No physics: no bodies, joints or Box2D world.
 has_baseline: bool,
 tick: u64,
 render_counter: u64, // Source of per-piece render_revision values; never repeats within a replica.
 part_seq: u32,
 part_total,part_have: int,
 part_buffer: [dynamic]u8,
 baselines_applied,deltas_applied: int,
 rebuilt: bool, // The last applied message was a Baseline: callers drop their render caches.
}

replica_init :: proc(rep: ^Replica) { rep^=Replica{}; rep.scene=new_scene(0) }

replica_destroy :: proc(rep: ^Replica) { scene_destroy(&rep.scene); delete(rep.part_buffer); rep^={} }

replica_add_material :: proc(rep: ^Replica,m: Material) {
 s:=&rep.scene
 copy:=m
 copy.name=strings.clone(m.name); append(&s.owned_names,copy.name)
 append(&s.materials,copy) // The message supplies the authoritative revision.
}

replica_add_cell :: proc(rep: ^Replica,c: Repl_Cell) {
 s:=&rep.scene
 sub:=Subdivision{id=c.id,owner=c.owner,material=c.material,frame=c.frame,outline=make_polygon(c.outline),rest_center=c.rest_center,live=true,provenance=c.provenance}
 sub.pose=Pose{position=c.rest_center}
 s.sub_rows[sub.id]=len(s.subdivisions); append(&s.subdivisions,sub)
 s.next_id=max(s.next_id,sub.id)
}

replica_add_piece :: proc(rep: ^Replica,id: u64,material: int,ref_rest: Vec2,cells: []u64) {
 s:=&rep.scene
 p:=Piece{id=id,material=material,ref_rest=ref_rest,has_ref_rest=true,live=true}
 append(&p.subdivisions,..cells)
 s.piece_rows[id]=len(s.pieces); append(&s.pieces,p)
 s.next_id=max(s.next_id,id)
 for cell in cells { s.subdivisions[s.sub_rows[cell]].owner=id }
}

replica_add_connection :: proc(rep: ^Replica,c: Repl_Connection) {
 s:=&rep.scene
 a_row,b_row:=s.sub_rows[c.a],s.sub_rows[c.b]
 a,b:=s.subdivisions[a_row],s.subdivisions[b_row]
 // Same derivations as snapshot decode: clients rebuild rest_segments from outlines.
 length,point:=shared_boundary(a.outline,b.outline)
 conn:=Connection{mortar=c.mortar,id=c.id,a=c.a,b=c.b,live=true}
 if len(c.glue)>0 {
  append(&conn.glue,..c.glue)
  length,point=seam_geometry(conn)
 } else { conn.rest_segments=shared_segments(a.outline,b.outline) }
 _ = length
 conn.rest_point=point; conn.local_a=vsub(point,a.rest_center); conn.local_b=vsub(point,b.rest_center)
 if conn.mortar { conn.seam_normal=mortar_link_normal(s,conn) }
 s.conn_rows[c.id]=len(s.connections); append(&s.connections,conn)
 s.connection_pairs[pair_key(c.a,c.b)]=c.id
 append(&s.subdivisions[a_row].incident_links,c.id); append(&s.subdivisions[b_row].incident_links,c.id)
 s.next_id=max(s.next_id,c.id)
}

replica_remove_connection :: proc(rep: ^Replica,id: u64) {
 s:=&rep.scene
 row,ok:=s.conn_rows[id]; if !ok { return }
 c:=s.connections[row]
 if s.connection_pairs[pair_key(c.a,c.b)]==id { delete_key(&s.connection_pairs,pair_key(c.a,c.b)) }
 for endpoint in ([2]u64{c.a,c.b}) {
  if erow,found:=s.sub_rows[endpoint]; found {
   links:=&s.subdivisions[erow].incident_links
   for link,j in links^ { if link==id { unordered_remove(links,j); break } }
  }
 }
 delete(c.rest_segments); delete(c.glue)
 delete_key(&s.conn_rows,id)
 unordered_remove(&s.connections,row)
 if row<len(s.connections) { s.conn_rows[s.connections[row].id]=row }
}

replica_remove_cell :: proc(rep: ^Replica,id: u64) {
 s:=&rep.scene
 row,ok:=s.sub_rows[id]; if !ok { return }
 sub:=s.subdivisions[row]
 delete(sub.outline.points); delete(sub.incident_links)
 delete_key(&s.sub_rows,id)
 unordered_remove(&s.subdivisions,row)
 if row<len(s.subdivisions) { s.sub_rows[s.subdivisions[row].id]=row }
}

replica_remove_piece :: proc(rep: ^Replica,id: u64) {
 s:=&rep.scene
 row,ok:=s.piece_rows[id]; if !ok { return }
 p:=s.pieces[row]
 delete(p.subdivisions); delete(p.connections)
 delete_key(&s.piece_rows,id)
 unordered_remove(&s.pieces,row)
 if row<len(s.pieces) { s.piece_rows[s.pieces[row].id]=row }
}

replica_finish_pieces :: proc(rep: ^Replica,touched: map[u64]bool) {
 s:=&rep.scene
 ids:[dynamic]u64; defer delete(ids)
 for id in touched { append(&ids,id) }
 slice.sort(ids[:])
 for id in ids {
  row,ok:=s.piece_rows[id]; if !ok { continue }
  rep.render_counter+=1
  p:=&s.pieces[row]
  p.render_revision=rep.render_counter
  clear(&p.connections)
  for cell in p.subdivisions {
   crow,found:=s.sub_rows[cell]; if !found { continue }
   for link in s.subdivisions[crow].incident_links {
    c:=s.connections[s.conn_rows[link]]
    if !c.mortar && c.a==cell { append(&p.connections,link) }
   }
  }
  slice.sort(p.connections[:])
 }
}

replica_touch_owner :: proc(rep: ^Replica,touched: ^map[u64]bool,cell: u64) {
 s:=&rep.scene
 if row,ok:=s.sub_rows[cell]; ok { touched[s.subdivisions[row].owner]=true }
}

replica_apply_baseline :: proc(rep: ^Replica,r: ^nc.Reader) -> string {
 tick:=nc.read_varint(r)
 version:=nc.read_u8(r)
 epoch:=nc.read_varint(r); revision:=nc.read_varint(r); anchor_y:=nc.read_f32(r)
 if !r.ok || version!=REPL_CANON_VERSION || epoch>0xffffffff || !finite(anchor_y) { return "bad baseline header" }
 scene_destroy(&rep.scene)
 rep.scene=new_scene(0)
 s:=&rep.scene
 s.epoch=u32(epoch); s.structure_revision=revision; s.anchor_y=anchor_y
 if reason:=repl_read_catalog(r,s);reason!="" { return reason }
 count:=nc.read_varint(r)
 if count>1024 { return "too many baseline materials" }
 for _ in 0..<count { m:=repl_read_material(r);if !r.ok || !repl_valid_material(m) { return "invalid baseline material" };replica_add_material(rep,m) }
 cell_count:=nc.read_varint(r)
 if cell_count>REPL_MAX_CELLS { return "too many baseline cells" }
 vertices:=0
 for _ in 0..<cell_count {
  c:=repl_read_cell(r); defer delete(c.outline)
  if !r.ok { return "truncated cells" }
  vertices+=len(c.outline)
  if !repl_valid_cell(c,len(s.materials)) || !repl_valid_source_binding(s,c) || c.id in s.sub_rows || vertices>REPL_MAX_VERTICES { return "invalid or duplicate baseline cell/source binding" }
  replica_add_cell(rep,c)
 }
 conns:[dynamic]Repl_Connection; defer { for c in conns { delete(c.glue) }; delete(conns) }
 conn_count:=nc.read_varint(r)
 if conn_count>REPL_MAX_VERTICES { return "too many baseline connections" }
 for _ in 0..<conn_count { c:=repl_read_connection(r); if !r.ok { delete(c.glue);return "truncated connections" }; append(&conns,c) }
 piece_count:=nc.read_varint(r)
 if piece_count>REPL_MAX_CELLS { return "too many baseline pieces" }
 listed_cells:=0
 for _ in 0..<piece_count {
  id:=nc.read_varint(r); material:=int(nc.read_varint(r)); ref_rest:=Vec2{nc.read_f32(r),nc.read_f32(r)}; cells:=repl_read_id_list(r); defer delete(cells)
  if !r.ok || !valid_vec(ref_rest) { return "truncated or invalid pieces" }
  if !repl_valid_piece(rep,id,material,ref_rest,cells) || id in s.piece_rows { return "invalid baseline piece references" }
  listed_cells+=len(cells)
  for cell in cells { if s.subdivisions[s.sub_rows[cell]].owner!=id { return "baseline owner/membership mismatch" } }
  replica_add_piece(rep,id,material,ref_rest,cells)
 }
 if listed_cells!=len(s.subdivisions) { return "baseline membership does not cover cells" }
 for sub in s.subdivisions { if sub.owner not_in s.piece_rows { return "baseline cell owner is missing" } }
 for c in conns {
  if !repl_valid_connection(c) || c.id in s.conn_rows || c.a not_in s.sub_rows || c.b not_in s.sub_rows { return "invalid baseline connection references" }
  replica_add_connection(rep,c)
 }
 touched:=make(map[u64]bool); defer delete(touched)
 for p in s.pieces { touched[p.id]=true }
 replica_finish_pieces(rep,touched)
 if !r.ok || nc.reader_remaining(r)!=0 { return "truncated or trailing bytes in baseline" }
 rep.tick=tick; rep.has_baseline=true; rep.baselines_applied+=1; rep.rebuilt=true
 return ""
}

replica_apply_delta :: proc(rep: ^Replica,r: ^nc.Reader) -> string {
 s:=&rep.scene
 tick:=nc.read_varint(r); epoch:=nc.read_varint(r); from:=nc.read_varint(r); to:=nc.read_varint(r)
 if !r.ok || epoch>0xffffffff || to<from { return "bad delta header" }
 if !rep.has_baseline { return "delta before baseline" }
 if u32(epoch)!=s.epoch { return "delta from another epoch" }
 if from!=s.structure_revision { return "delta from_revision does not match" }
 // Parse the whole message before touching the scene.
 materials:[dynamic]Material; defer delete(materials)
 cells_added:[dynamic]Repl_Cell; defer { for c in cells_added { delete(c.outline) }; delete(cells_added) }
 conns_added:[dynamic]Repl_Connection; defer { for c in conns_added { delete(c.glue) }; delete(conns_added) }
 Piece_Add :: Repl_Piece_Add
 pieces_added:[dynamic]Piece_Add; defer { for p in pieces_added { delete(p.cells) }; delete(pieces_added) }
 pieces_changed:[dynamic]Piece_Add; defer { for p in pieces_changed { delete(p.cells) }; delete(pieces_changed) }
 count:=nc.read_varint(r)
 if count>1024 || u64(len(s.materials))+count>1024 { return "too many delta materials" }
 for _ in 0..<count { m:=repl_read_material(r); if !r.ok { return "truncated materials" }; append(&materials,m) }
 count=nc.read_varint(r)
 if count>REPL_MAX_CELLS { return "too many added cells" }
 for _ in 0..<count { c:=repl_read_cell(r); if !r.ok { delete(c.outline); return "truncated cells" }; append(&cells_added,c) }
 cells_removed:=repl_read_id_list(r); defer delete(cells_removed)
 count=nc.read_varint(r)
 if count>REPL_MAX_VERTICES { return "too many added connections" }
 for _ in 0..<count { c:=repl_read_connection(r); if !r.ok { delete(c.glue); return "truncated connections" }; append(&conns_added,c) }
 conns_removed:=repl_read_id_list(r); defer delete(conns_removed)
 count=nc.read_varint(r)
 if count>REPL_MAX_CELLS { return "too many added pieces" }
 for _ in 0..<count {
  id:=nc.read_varint(r); material:=int(nc.read_varint(r)); ref_rest:=Vec2{nc.read_f32(r),nc.read_f32(r)}; cells:=repl_read_id_list(r)
  if !r.ok || !valid_vec(ref_rest) { delete(cells); return "truncated or invalid pieces" }
  append(&pieces_added,Piece_Add{id=id,material=material,ref_rest=ref_rest,cells=cells})
 }
 pieces_removed:=repl_read_id_list(r); defer delete(pieces_removed)
 count=nc.read_varint(r)
 if count>REPL_MAX_CELLS { return "too many changed pieces" }
 for _ in 0..<count {
  id:=nc.read_varint(r); cells:=repl_read_id_list(r)
  if !r.ok { delete(cells); return "truncated changed pieces" }
  append(&pieces_changed,Piece_Add{id=id,cells=cells})
 }
 if !r.ok || nc.reader_remaining(r)!=0 { return "malformed delta" }
 if problem:=repl_validate_delta(rep,materials[:],cells_added[:],cells_removed,conns_added[:],conns_removed,pieces_added[:],pieces_removed,pieces_changed[:]);problem!="" { return problem }
 // Apply: materials, removals (connections, pieces, cells), additions (cells, pieces, connections).
 for m in materials { replica_add_material(rep,m) }
 touched:=make(map[u64]bool); defer delete(touched)
 for id in conns_removed {
  if row,ok:=s.conn_rows[id]; ok { c:=s.connections[row]; replica_touch_owner(rep,&touched,c.a); replica_touch_owner(rep,&touched,c.b) }
  replica_remove_connection(rep,id)
 }
 for id in pieces_removed { replica_remove_piece(rep,id) }
 for id in cells_removed { replica_remove_cell(rep,id) }
 for c in cells_added { replica_add_cell(rep,c) }
 for p in pieces_added { replica_add_piece(rep,p.id,p.material,p.ref_rest,p.cells); touched[p.id]=true }
 for p in pieces_changed {
  row,ok:=s.piece_rows[p.id]; if !ok { return "changed piece is unknown" }
  clear(&s.pieces[row].subdivisions); append(&s.pieces[row].subdivisions,..p.cells)
  for cell in p.cells { s.subdivisions[s.sub_rows[cell]].owner=p.id }
  touched[p.id]=true
 }
 for c in conns_added {
  replica_add_connection(rep,c)
  replica_touch_owner(rep,&touched,c.a); replica_touch_owner(rep,&touched,c.b)
 }
 replica_finish_pieces(rep,touched)
 s.structure_revision=to
 rep.tick=tick; rep.deltas_applied+=1; rep.rebuilt=false
 return ""
}

replica_apply_message :: proc(rep: ^Replica,message: []u8) -> string {
 r:nc.Reader; nc.reader_init(&r,message)
 kind:=Repl_Kind(nc.read_u8(&r))
 if !r.ok { return "empty message" }
 #partial switch kind {
 case .Baseline: return replica_apply_baseline(rep,&r)
 case .Delta: return replica_apply_delta(rep,&r)
 }
 return "unknown message kind"
}

replica_receive :: proc(rep: ^Replica,part: []u8) -> (applied: bool,err: string) {
 r:nc.Reader; nc.reader_init(&r,part)
 mark:=nc.read_u8(&r); seq:=u32(nc.read_varint(&r)); index:=int(nc.read_varint(&r)); total:=int(nc.read_varint(&r))
 if !r.ok || mark!=REPL_PART_MARK || total<1 || total>65536 || index<0 || index>=total { return false,"bad part header" }
 if index==0 {
  clear(&rep.part_buffer); rep.part_seq=seq; rep.part_total=total; rep.part_have=0
 } else if seq!=rep.part_seq || total!=rep.part_total || index!=rep.part_have {
  return false,"part out of sequence"
 }
 if len(rep.part_buffer)+len(part)-r.pos>REPL_MAX_ASSEMBLED_BYTES { clear(&rep.part_buffer);return false,"assembled structure exceeds capacity" }
 append(&rep.part_buffer,..part[r.pos:])
 rep.part_have+=1
 if rep.part_have<rep.part_total { return false,"" }
 message:=rep.part_buffer[:]
 err=replica_apply_message(rep,message)
 clear(&rep.part_buffer); rep.part_total=0; rep.part_have=0
 return err=="",err
}

replica_collect :: proc(rep: ^Replica,part: []u8) -> (message: []u8,complete: bool,err: string) {
 r:nc.Reader; nc.reader_init(&r,part)
 mark:=nc.read_u8(&r); seq:=u32(nc.read_varint(&r)); index:=int(nc.read_varint(&r)); total:=int(nc.read_varint(&r))
 if !r.ok || mark!=REPL_PART_MARK || total<1 || total>65536 || index<0 || index>=total { return nil,false,"bad part header" }
 if index==0 {
  clear(&rep.part_buffer); rep.part_seq=seq; rep.part_total=total; rep.part_have=0
 } else if seq!=rep.part_seq || total!=rep.part_total || index!=rep.part_have {
  return nil,false,"part out of sequence"
 }
 if len(rep.part_buffer)+len(part)-r.pos>REPL_MAX_ASSEMBLED_BYTES { clear(&rep.part_buffer);return nil,false,"assembled structure exceeds capacity" }
 append(&rep.part_buffer,..part[r.pos:])
 rep.part_have+=1
 if rep.part_have<rep.part_total { return nil,false,"" }
 message=slice.clone(rep.part_buffer[:])
 clear(&rep.part_buffer); rep.part_total=0; rep.part_have=0
 return message,true,""
}

repl_peek :: proc(message: []u8) -> (kind: Repl_Kind,tick: u64,epoch: u64,ok: bool) {
 r:nc.Reader; nc.reader_init(&r,message)
 kind=Repl_Kind(nc.read_u8(&r)); tick=nc.read_varint(&r)
 if kind==.Baseline { _ = nc.read_u8(&r); epoch=nc.read_varint(&r) }
 else if kind==.Delta { epoch=nc.read_varint(&r) }
 return kind,tick,epoch,r.ok && (kind==.Baseline || kind==.Delta)
}
