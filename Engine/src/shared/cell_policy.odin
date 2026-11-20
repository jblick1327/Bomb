package shared

Motion_Policy :: enum u8 { Legacy, Dynamic, Fixed, Anchored }
Damage_Policy :: enum u8 { Destructible, Indestructible }
Cell_Provenance :: struct { source_identity,source_part_id:u64, motion:Motion_Policy, damage:Damage_Policy, pinned:bool }
Source_Part_Anchors :: struct { source_identity,source_part_id:u64, segments:[dynamic]Segment }
SOURCE_DIAGNOSTIC :: SOURCE_RESERVED_START
SOURCE_GROUND :: SOURCE_RESERVED_START+1

cell_pinned :: proc(s:^Scene,sub:Subdivision) -> bool {
 switch sub.provenance.motion {
 case .Legacy:
  if !(s.anchor_y> -1e30) { return false }
  for a,i in sub.outline.points { b:=sub.outline.points[(i+1)%len(sub.outline.points)];if abs(a.y-s.anchor_y)<.00001&&abs(b.y-s.anchor_y)<.00001&&abs(a.x-b.x)>.00001 { return true } }
 case .Dynamic:return false
 case .Fixed:return true
 case .Anchored:
  for part in s.source_parts {
   if part.source_identity!=sub.provenance.source_identity||part.source_part_id!=sub.provenance.source_part_id { continue }
   for anchor in part.segments { for a,i in sub.outline.points { if _,ok:=segment_overlap(anchor,Segment{a,sub.outline.points[(i+1)%len(sub.outline.points)]});ok { return true } } }
  }
 }
 return false
}
cell_resolve_pin :: proc(s:^Scene,id:u64) { sub:=&s.subdivisions[s.sub_rows[id]];sub.provenance.pinned=cell_pinned(s,sub^) }
cell_inherit_provenance :: proc(s:^Scene,child:u64,parent:Subdivision) { s.subdivisions[s.sub_rows[child]].provenance=parent.provenance;cell_resolve_pin(s,child) }
cell_damage_allowed :: proc(sub:Subdivision) -> bool { return sub.provenance.damage!=.Indestructible }
connection_damage_allowed :: proc(s:^Scene,c:Connection) -> bool {
 a,b:=s.subdivisions[s.sub_rows[c.a]],s.subdivisions[s.sub_rows[c.b]]
 return !(a.provenance.source_identity!=0&&a.provenance.source_identity==b.provenance.source_identity&&a.provenance.damage==.Indestructible&&b.provenance.damage==.Indestructible)
}
cell_policy_flags :: proc(p:Cell_Provenance) -> u32 { return u32(p.motion)|(u32(p.damage)<<2)|(p.pinned?u32(8):u32(0)) }
cell_policy_decode :: proc(source,part:u64,flags:u32) -> (p:Cell_Provenance,ok:bool) {
 if flags&~u32(15)!=0||source==0&&part!=0||source!=0&&part==0 { return {},false }
 p={source,part,Motion_Policy(flags&3),Damage_Policy((flags>>2)&1),flags&8!=0}
 if p.motion==.Dynamic&&p.pinned||p.motion==.Fixed&&!p.pinned { return {},false }
 return p,true
}
