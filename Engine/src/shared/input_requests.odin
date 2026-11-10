package shared

REQUEST_RESULT_WINDOW :: 1024
Request_Status :: enum u8 { Pending, Accepted, Rejected, Expired, Wrong_Epoch, Wrong_Connection, Too_Old, Conflict, Capacity, Cleared }
Request_Result :: struct { request_id,effect_tick,event_id: u64, status: Request_Status, reason: u16 }
Request_Entry :: struct { occupied: bool, request_id: u64, fingerprint: [32]u8, result: Request_Result }
Request_Cache :: struct {
 incarnation: u64,
 highest,low_watermark: u64,
 entries: [REQUEST_RESULT_WINDOW]Request_Entry,
}
Request_Begin :: enum { New, Replay, Too_Old, Conflict, Capacity, Wrong_Connection }

request_cache_key :: proc(value:$T) -> (key:[32]u8) {
 when T==[32]u8 { return value } else { for i in 0..<8 { key[i]=u8(u64(value)>>u32(i*8)) };return }
}
request_cache_begin :: proc(c: ^Request_Cache,incarnation,id:u64,fingerprint:$T) -> (Request_Begin,Request_Result) {
 key:=request_cache_key(fingerprint)
 if incarnation==0 || incarnation!=c.incarnation { return .Wrong_Connection,{request_id=id,status=.Wrong_Connection} }
 if id==0 { return .Too_Old,{request_id=id,status=.Too_Old} }
 slot:=&c.entries[id%REQUEST_RESULT_WINDOW]
 if slot.occupied && slot.request_id==id {
  if slot.fingerprint!=key { return .Conflict,{request_id=id,status=.Conflict} }
  return .Replay,slot.result
 }
 if id<=c.low_watermark || id<=c.highest { return .Too_Old,{request_id=id,status=.Too_Old} }
 if slot.occupied && slot.result.status==.Pending { return .Capacity,{request_id=id,status=.Capacity} }
 if slot.occupied { c.low_watermark=max(c.low_watermark,slot.request_id) }
 c.highest=id
 slot^={occupied=true,request_id=id,fingerprint=key,result={request_id=id,status=.Pending}}
 return .New,slot.result
}
request_cache_finish :: proc(c: ^Request_Cache,result: Request_Result) -> bool {
 slot:=&c.entries[result.request_id%REQUEST_RESULT_WINDOW]
 if !slot.occupied || slot.request_id!=result.request_id || slot.result.status!=.Pending || result.status==.Pending { return false }
 slot.result=result;return true
}
request_cache_expire_epoch :: proc(c: ^Request_Cache,tick: u64) {
 for &slot in c.entries {
  if slot.occupied && slot.result.status==.Pending { slot.result={request_id=slot.request_id,effect_tick=tick,status=.Wrong_Epoch} }
 }
}
// Exact tick age filter; bounds/rate/host/aim authorization remain separate.
blast_intent_status :: proc(expected_incarnation,incarnation: u64,expected_epoch,epoch: u32,now_tick,created_tick,deadline_tick: u64) -> Request_Status {
 if incarnation==0 || incarnation!=expected_incarnation { return .Wrong_Connection }
 if epoch!=expected_epoch { return .Wrong_Epoch }
 if created_tick>now_tick && created_tick-now_tick>2 { return .Rejected }
 if deadline_tick<created_tick || deadline_tick-created_tick>30 { return .Rejected }
 if now_tick>deadline_tick { return .Expired }
 return .Accepted
}
