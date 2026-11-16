package main
// G-N5 repro: a real native client (the bomcore FFI, same entry points Unity
// calls) connected over loopback UDP to a real BOM-server.exe running the G1
// Bridge, with scripted host blasts that collapse a bay. It paces itself at
// 60 fps like the Unity player and times every bom_client_update call.
//
//   client-update-g1.exe <port> <host-token> <seconds> <blasts> <out.csv>
//   blasts: "t:x,y|t:x,y|..." (seconds after the client has a baseline)
import ffi "../../src/ffi"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:time"

Blast :: struct { at,x,y:f64, sent:bool }
Row :: struct { t,update_ms,sample_ms:f64, revision:u64, poses,cells:u32, prediction:u32 }

main :: proc() {
 if len(os.args)!=6 { fmt.eprintln("usage: client-update-g1 <port> <host-token> <seconds> <blasts> <out.csv>");os.exit(2) }
 port,_:=strconv.parse_int(os.args[1]);token:=os.args[2];seconds,_:=strconv.parse_f64(os.args[3])
 blasts:[dynamic]Blast
 for item in strings.split(os.args[4],"|") {
  if item=="" { continue }
  parts:=strings.split(item,":");xy:=strings.split(parts[1],",")
  at,_:=strconv.parse_f64(parts[0]);x,_:=strconv.parse_f64(xy[0]);y,_:=strconv.parse_f64(xy[1])
  append(&blasts,Blast{at=at,x=x,y=y})
 }
 info:=ffi.BomCreateInfo{struct_size=u32(size_of(ffi.BomCreateInfo)),version=1};handle:u64
 if ffi.bom_client_create(&info,&handle)!=ffi.OK { fmt.eprintln("create failed");os.exit(1) }
 connect:=ffi.BomConnectInfo{struct_size=u32(size_of(ffi.BomConnectInfo)),version=1,ipv4=0x7f000001,port=u32(port),token=raw_data(token),token_length=u32(len(token))}
 if ffi.bom_client_connect(handle,&connect)!=ffi.OK { fmt.eprintln("connect failed");os.exit(1) }
 rows:[dynamic]Row
 start:=time.tick_now();baseline_at:=-1.0;frame:=0
 for {
  target:=f64(frame)/60;frame+=1
  for { elapsed:=time.duration_seconds(time.tick_since(start));if elapsed>=target { break };if target-elapsed>0.002 { time.sleep(time.Millisecond) } }
  now:=time.duration_seconds(time.tick_since(start))
  _=ffi.bom_client_set_held_input(handle,now,0)
  if baseline_at>=0 { for &b in blasts { if !b.sent && now-baseline_at>=b.at { b.sent=true;r:=ffi.bom_client_enqueue_action(handle,now,f32(b.x),f32(b.y));fmt.printf("BLAST t=%.2f at (%.2f,%.2f) status=%d\n",now-baseline_at,b.x,b.y,r) } } }
  t0:=time.tick_now();status:=ffi.bom_client_update(handle,now);update_ms:=time.duration_milliseconds(time.tick_since(t0))
  if status!=ffi.OK { fmt.eprintln("update failed",status);os.exit(1) }
  sample:=ffi.BomSample{struct_size=u32(size_of(ffi.BomSample)),version=1}
  t1:=time.tick_now();sstatus:=ffi.bom_client_acquire_sample(handle,&sample);sample_ms:=time.duration_milliseconds(time.tick_since(t1))
  if sstatus!=ffi.OK { fmt.eprintln("sample failed",sstatus);os.exit(1) }
  has_baseline:=sample.flags&2!=0
  _=ffi.bom_client_release_sample(handle,sample.sample_sequence)
  if has_baseline && baseline_at<0 { baseline_at=now;fmt.printf("BASELINE t=%.2f cells=%d\n",now,sample.cell_count) }
  if baseline_at>=0 {
   append(&rows,Row{now-baseline_at,update_ms,sample_ms,sample.revision,sample.pose_count,sample.cell_count,sample.owner_prediction_status})
   if now-baseline_at>=seconds { break }
  } else if now>20 { fmt.eprintln("no baseline after 20 s");os.exit(1) }
 }
 stats:=ffi.BomPredictionStats{struct_size=u32(size_of(ffi.BomPredictionStats)),version=1}
 _=ffi.bom_client_get_prediction_stats(handle,&stats)
 sb:=strings.builder_make()
 fmt.sbprintln(&sb,"t,update_ms,sample_ms,revision,poses,cells,prediction")
 for r in rows { fmt.sbprintf(&sb,"%.4f,%.4f,%.4f,%d,%d,%d,%d\n",r.t,r.update_ms,r.sample_ms,r.revision,r.poses,r.cells,r.prediction) }
 _=os.write_entire_file(os.args[5],sb.buf[:])
 report(rows[:],"all frames",proc(r:Row,rows:[]Row) -> bool { return true })
 // Blast window as in G1 section 6.3: 0.5 s before to 3 s after each revision change.
 changes:[dynamic]f64
 for i in 1..<len(rows) { if rows[i].revision!=rows[i-1].revision { append(&changes,rows[i].t) } }
 window_rows:[dynamic]Row
 for r in rows { for c in changes { if r.t>=c-0.5 && r.t<=c+3 { append(&window_rows,r);break } } }
 report(window_rows[:],"blast window",proc(r:Row,rows:[]Row) -> bool { return true })
 predicting:=0;for r in rows { if r.prediction==1 { predicting+=1 } }
 fmt.printf("revisions=%d final_cells=%d final_poses=%d predicting_frames=%d/%d corrections=%d snaps=%d conservative_transitions=%d resets=%d\n",len(changes),rows[len(rows)-1].cells,rows[len(rows)-1].poses,predicting,len(rows),stats.correction_count,stats.snap_count,stats.conservative_transitions,stats.reset_count)
 _=ffi.bom_client_disconnect(handle);_=ffi.bom_client_destroy(handle)
}

report :: proc(rows:[]Row,name:string,_:proc(Row,[]Row)->bool) {
 if len(rows)==0 { fmt.printf("%s: no frames\n",name);return }
 values:=make([]f64,len(rows));defer delete(values)
 over_16,over_33:=0,0;total:=0.0
 for r,i in rows { values[i]=r.update_ms;total+=r.update_ms;if r.update_ms>16.7 { over_16+=1 };if r.update_ms>33.3 { over_33+=1 } }
 slice.sort(values)
 q :: proc(v:[]f64,p:f64) -> f64 { i:=int(p*f64(len(v)-1)+0.5);return v[min(i,len(v)-1)] }
 fmt.printf("%s: frames=%d bom_client_update ms p50=%.3f p95=%.3f p99=%.3f max=%.3f mean=%.3f >16.7ms=%d >33.3ms=%d\n",name,len(values),q(values,.5),q(values,.95),q(values,.99),values[len(values)-1],total/f64(len(values)),over_16,over_33)
}
