package shared
import math "core:math"

PREDICTION_HISTORY_TICKS :: 256
PREDICTION_TOPOLOGY_LIMIT :: 16
PREDICTION_TOPOLOGY_BYTES :: 32*1024*1024
PREDICTION_EXTRAPOLATE_TICKS :: u64(6)

Collision_Topology :: struct { scene:Scene, effective_tick:u64, bytes:int }
Collision_Frame :: struct { valid:bool, tick:u64, epoch:u32, poses:Pose_Table }
Collision_History :: struct {
 epoch:u32,
 topology:[dynamic]^Collision_Topology,
 bytes:int,
 frames:[PREDICTION_HISTORY_TICKS]Collision_Frame,
 newest:u64,
 has_frame:bool,
 dropped_windows:u64,
}

collision_history_destroy :: proc(h:^Collision_History) {
 for topology in h.topology { scene_destroy(&topology.scene);free(topology) }
 delete(h.topology)
 for &frame in h.frames { if frame.valid { delete(frame.poses) } }
 h^={}
}
collision_history_topology :: proc(h:^Collision_History,tick:u64,revision:u64=0) -> ^Collision_Topology {
 best:^Collision_Topology
 for topology in h.topology {
  if topology.effective_tick>tick || (revision!=0 && topology.scene.structure_revision!=revision) { continue }
  if best==nil || topology.effective_tick>best.effective_tick || (topology.effective_tick==best.effective_tick && topology.scene.structure_revision>best.scene.structure_revision) { best=topology }
 }
 return best
}
collision_topology_copy :: proc(source:^Scene,effective:u64) -> ^Collision_Topology {
 out:=new(Collision_Topology);out.scene=new_scene(0);s:=&out.scene
 s.epoch=source.epoch;s.structure_revision=source.structure_revision;s.anchor_y=source.anchor_y;out.effective_tick=effective
 append(&s.materials,..source.materials[:]);for &m in s.materials { m.name="" }
 out.bytes=size_of(Collision_Topology)+len(s.materials)*size_of(Material)
 for original in source.subdivisions {
  if !original.live { continue }
  sub:=Subdivision{id=original.id,owner=original.owner,material=original.material,frame=original.frame,rest_center=original.rest_center,live=true,outline=make_polygon(original.outline.points)}
  s.sub_rows[sub.id]=len(s.subdivisions);append(&s.subdivisions,sub)
  out.bytes+=size_of(Subdivision)+len(sub.outline.points)*size_of(Vec2)+32
 }
 for original in source.pieces {
  if !original.live { continue }
  piece:=Piece{id=original.id,material=original.material,ref_rest=original.ref_rest,has_ref_rest=true,live=true}
  for id in original.subdivisions { if id in s.sub_rows { append(&piece.subdivisions,id) } }
  s.piece_rows[piece.id]=len(s.pieces);append(&s.pieces,piece)
  out.bytes+=size_of(Piece)+len(piece.subdivisions)*size_of(u64)+32
 }
 return out
}
collision_history_record_topology :: proc(h:^Collision_History,source:^Scene,effective:u64) -> bool {
 if h.epoch!=source.epoch { dropped:=h.dropped_windows;collision_history_destroy(h);h.epoch=source.epoch;h.dropped_windows=dropped }
 for existing in h.topology { if existing.scene.structure_revision==source.structure_revision { return true } }
 topology:=collision_topology_copy(source,effective)
 if topology.bytes>PREDICTION_TOPOLOGY_BYTES { scene_destroy(&topology.scene);free(topology);return false }
 // Reclaim versions older than the retained pose window, preserving the one
 // effective at its first tick. No replay may subsequently claim older history.
 oldest:=h.newest>255?h.newest-255:u64(0)
 keeper:=collision_history_topology(h,oldest)
 i:=0
 for i<len(h.topology) {
  old:=h.topology[i]
  if old!=keeper && old.effective_tick<oldest {
   h.bytes-=old.bytes;scene_destroy(&old.scene);free(old);ordered_remove(&h.topology,i)
  } else { i+=1 }
 }
 if len(h.topology)>=PREDICTION_TOPOLOGY_LIMIT || h.bytes+topology.bytes>PREDICTION_TOPOLOGY_BYTES {
  // Explicit bounded-history invalidation. Retain fresh truth and warm again;
  // never pretend today's shattered geometry describes the evicted past.
  dropped:=h.dropped_windows+1;epoch:=h.epoch;collision_history_destroy(h);h.epoch=epoch;h.dropped_windows=dropped
 }
 append(&h.topology,topology);h.bytes+=topology.bytes
 return true
}
collision_history_record_frame :: proc(h:^Collision_History,epoch:u32,tick:u64,poses:^Pose_Table) -> bool {
 if epoch!=h.epoch || len(poses^)>4096 { return false }
 if h.has_frame && tick<h.newest && h.newest-tick>=PREDICTION_HISTORY_TICKS { return false }
 slot:=&h.frames[tick%PREDICTION_HISTORY_TICKS]
 if slot.valid { delete(slot.poses) }
 slot^={true,tick,epoch,table_clone(poses)}
 h.newest=max(h.newest,tick);h.has_frame=true
 return true
}
// Poses are sampled at an integer simulation tick. Interpolation uses bracketing
// received samples; future extrapolation is bounded to 100ms and marked estimated.
collision_history_pose :: proc(h:^Collision_History,tick,key:u64) -> (pose:Net_Drawn,estimated,valid:bool) {
 lower,upper:^Collision_Frame
 for &frame in h.frames {
  if !frame.valid || frame.epoch!=h.epoch { continue }
  if frame.tick<=tick && (lower==nil || frame.tick>lower.tick) { lower=&frame }
  if frame.tick>=tick && (upper==nil || frame.tick<upper.tick) { upper=&frame }
 }
 if lower==nil { return }
 a,found:=lower.poses[key];if !found { return }
 if upper!=nil {
  b,exists:=upper.poses[key];if !exists { return }
  if upper.tick==lower.tick { return net_drawn_single(a),false,true }
  return net_drawn_from(a,b,f32(tick-lower.tick)/f32(upper.tick-lower.tick)),false,true
 }
 if tick-lower.tick>PREDICTION_EXTRAPOLATE_TICKS { return }
 previous:^Collision_Frame
 for &frame in h.frames { if frame.valid && frame.epoch==h.epoch && frame.tick<lower.tick && (previous==nil || frame.tick>previous.tick) { previous=&frame } }
 if previous==nil { return }
 b,exists:=previous.poses[key];if !exists { return }
 current:=net_drawn_single(a);old:=net_drawn_single(b)
 delta:=f32(lower.tick-previous.tick);ahead:=f32(tick-lower.tick)
 current.x+=(current.x-old.x)/delta*ahead;current.y+=(current.y-old.y)/delta*ahead
 current.angle+=radians_delta(current.angle,old.angle)/delta*ahead
 if !finite(current.x) || !finite(current.y) || math.abs(current.x)>1e6 || math.abs(current.y)>1e6 { return }
 return current,true,true
}
