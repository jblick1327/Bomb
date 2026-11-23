package ffi

import "core:math"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:time"
import w "core:sys/windows"
import core "../shared"

// Pump-thread gates (ABI 1.7). The gap test runs against the shipped loopback server
// (Server/BOM-server.exe, or BOM_TEST_SERVER); the others use connected-state fixtures.

pump_fake_slot :: proc(t:^testing.T,salt:u32) -> (u64,^Client_Slot) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 testing.expect(t,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);testing.expect(t,status==OK)
 {context.allocator=s.ctx.allocator;core.net_client_init(&s.client,salt,0)}
 s.client.nc_client.state=.Connected;s.client.real_gate=false;s.live=true
 return handle,s
}
pump_read :: proc(s:^Client_Slot,field:^u64) -> u64 { sync.mutex_lock(&s.lock);defer sync.mutex_unlock(&s.lock);return field^ }
pump_stats :: proc(t:^testing.T,handle:u64) -> BomStats {
 stats:=BomStats{struct_size=u32(size_of(BomStats)),version=1}
 testing.expect(t,bom_client_get_stats(handle,&stats)==OK);return stats
}
pump_wait_ticks :: proc(s:^Client_Slot,ticks:u64) -> bool {
 start:=time.tick_now()
 for pump_read(s,&s.pump_ticks)<ticks { if time.duration_seconds(time.tick_since(start))>2 {return false};time.sleep(100*time.Microsecond) }
 return true
}

@(test)
test_pump_clock_matches_managed_timebase :: proc(t:^testing.T) {
 // BomSession.Now is (double)Stopwatch.GetTimestamp()/Stopwatch.Frequency, i.e. QPC.
 c,f:w.LARGE_INTEGER;w.QueryPerformanceFrequency(&f);w.QueryPerformanceCounter(&c)
 managed:=f64(c)/f64(f);native:=bom_clock_now()
 testing.expectf(t,abs(native-managed)<0.001,"native clock %.6f vs QPC timebase %.6f",native,managed)
 a:=bom_clock_now();start:=time.tick_now();time.sleep(100*time.Millisecond)
 b:=bom_clock_now();elapsed:=time.duration_seconds(time.tick_since(start))
 testing.expectf(t,abs((b-a)-elapsed)<0.001,"clock rate: native %.6f s vs core:time %.6f s",b-a,elapsed)
}

@(test)
test_pump_start_rules_and_old_stats_size :: proc(t:^testing.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 testing.expect(t,bom_client_create(&info,&handle)==OK)
 testing.expect(t,bom_client_start_pump(handle,bom_clock_now())==NOT_CONNECTED)
 old:=BomStats{struct_size=u32(offset_of(BomStats,pump_running)),version=1}
 testing.expect(t,bom_client_get_stats(handle,&old)==OK && old.struct_size==u32(offset_of(BomStats,pump_running)),"1.6-sized stats still accepted")
 short:=BomStats{struct_size=u32(offset_of(BomStats,pump_running))-8,version=1}
 testing.expect(t,bom_client_get_stats(handle,&short)==BAD_ARGUMENT)
 testing.expect(t,bom_client_destroy(handle)==OK)
 h2,s:=pump_fake_slot(t,7001)
 testing.expect(t,bom_client_start_pump(h2,bom_clock_now())==OK && bom_client_start_pump(h2,bom_clock_now())==OK,"start is idempotent")
 testing.expect(t,pump_wait_ticks(s,2))
 stats:=pump_stats(t,h2)
 testing.expect(t,stats.pump_running==1||stats.pump_running==2)
 testing.expect(t,bom_client_update(h2,bom_clock_now())==OK,"main-thread update while pumping")
 testing.expect(t,bom_client_destroy(h2)==OK)
}

@(test)
test_pump_acquire_hold_blocks_pump_then_resumes :: proc(t:^testing.T) {
 handle,s:=pump_fake_slot(t,7100)
 testing.expect(t,bom_client_start_pump(handle,bom_clock_now())==OK)
 testing.expect(t,pump_wait_ticks(s,3))
 sample:=BomSample{struct_size=u32(size_of(BomSample)),version=1}
 // Acquire just before the pump's next wake so it waits for (almost) the whole hold.
 for attempt in 0..<50 {
  testing.expect(t,bom_client_acquire_sample(handle,&sample)==OK)
  if s.next_tick-qpc_now()<0.002 || attempt==49 { break }
  wake:=s.next_tick
  testing.expect(t,bom_client_release_sample(handle,sample.sample_sequence)==OK)
  for qpc_now()<wake-0.0015 { time.sleep(200*time.Microsecond) }
 }
 before:=s.pump_ticks // safe: the slot lock is held by this thread
 stats:=BomStats{struct_size=u32(size_of(BomStats)),version=1}
 testing.expect(t,bom_client_get_stats(handle,&stats)==OK,"owner-thread call while a sample is held must not self-deadlock")
 testing.expect(t,bom_client_set_held_input(handle,qpc_now(),1)==BUSY && bom_client_update(handle,qpc_now())==BUSY,"existing BUSY codes kept")
 error:=BomError{struct_size=u32(size_of(BomError)),version=1}
 testing.expect(t,bom_client_last_error(handle,&error)==OK)
 time.sleep(20*time.Millisecond)
 testing.expect(t,s.pump_ticks==before,"the pump cannot run while the sample is held")
 testing.expect(t,bom_client_release_sample(handle,sample.sample_sequence)==OK)
 testing.expect(t,pump_wait_ticks(s,before+3),"pump resumes after release")
 stats=pump_stats(t,handle)
 testing.expectf(t,stats.pump_lock_wait_max_ms>=15,"pump lock wait reported: %.2f ms",stats.pump_lock_wait_max_ms)
 testing.expect(t,stats.stall_count==0,"a 20 ms hold is not a stall")
 testing.expect(t,bom_client_destroy(handle)==OK)
}

@(test)
test_pump_destroy_and_disconnect_mid_pump_1000 :: proc(t:^testing.T) {
 // destroy itself asserts Odin live bytes 0 and Box2D back at its baseline (IO_ERROR otherwise).
 for i in 0..<1000 {
  handle,s:=pump_fake_slot(t,u32(10000+i))
  testing.expect(t,bom_client_start_pump(handle,bom_clock_now())==OK)
  switch i%5 {
  case 0: // teardown while the thread is starting or waiting for its first lock
  case 1: time.sleep(50*time.Microsecond)
  case: _=pump_wait_ticks(s,1);time.sleep(time.Duration(i%5-1)*400*time.Microsecond)
  }
  if i%2==0 { testing.expect(t,bom_client_disconnect(handle)==OK) }
  status:=bom_client_destroy(handle)
  testing.expectf(t,status==OK,"iteration %d destroy %d",i,status)
  if status!=OK { return }
 }
}

@(test)
test_pump_keeps_sending_through_main_thread_gaps :: proc(t:^testing.T) {
 server:=os.get_env("BOM_TEST_SERVER",context.allocator);defer delete(server)
 if server=="" { delete(server);server=strings.concatenate({#directory,"../../../Server/BOM-server.exe"}) }
 testing.expectf(t,os.exists(server),"loopback server missing: %s",server)
 if !os.exists(server) { return }
 port:="47391"
 process,err:=os.process_start({command={server,"--port",port,"--seconds","40"}})
 testing.expect(t,err==nil);if err!=nil { return }
 defer { _=os.process_kill(process);_,_=os.process_wait(process) }
 time.sleep(500*time.Millisecond)

 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 testing.expect(t,bom_client_create(&info,&handle)==OK)
 defer testing.expect(t,bom_client_destroy(handle)==OK)
 connection:=BomConnectInfo{struct_size=u32(size_of(BomConnectInfo)),version=1,ipv4=0x7f000001,port=47391}
 testing.expect(t,bom_client_connect(handle,&connection)==OK)
 testing.expect(t,bom_client_start_pump(handle,bom_clock_now())==OK)
 s,_:=get_slot(handle)
 // Unity-like frames: update, then acquire/copy/release/ack.
 frame :: proc(t:^testing.T,handle:u64) -> bool {
  if bom_client_update(handle,bom_clock_now())!=OK { return false }
  sample:=BomSample{struct_size=u32(size_of(BomSample)),version=1}
  if bom_client_acquire_sample(handle,&sample)!=OK { return false }
  testing.expect(t,bom_client_release_sample(handle,sample.sample_sequence)==OK)
  testing.expect(t,bom_client_ack_sample(handle,sample.sample_sequence)==OK)
  return true
 }
 frames :: proc(t:^testing.T,handle:u64,seconds:f64) -> bool {
  start:=bom_clock_now()
  for bom_clock_now()-start<seconds { time.sleep(16*time.Millisecond);if !frame(t,handle) {return false} } // ends on a call
  return true
 }
 ready:=false;start:=bom_clock_now()
 for !ready && bom_clock_now()-start<10 {
  if !frame(t,handle) { break }
  sync.mutex_lock(&s.lock);ready=s.client.real_hello_ok&&s.client.has_clock;sync.mutex_unlock(&s.lock)
  time.sleep(16*time.Millisecond)
 }
 if !ready {
  sync.mutex_lock(&s.lock)
  testing.expectf(t,false,"handshake and clock with the pump running: state=%v hello=%v clock=%v live=%v pump_status=%d reason=%q last_error=%q ticks=%d",s.client.nc_client.state,s.client.real_hello_ok,s.client.has_clock,s.live,s.pump_status,s.pump_reason,s.last_error,s.pump_ticks)
  sync.mutex_unlock(&s.lock);return
 }
 testing.expect(t,bom_client_set_held_input(handle,bom_clock_now(),1)==OK)
 testing.expect(t,frames(t,handle,0.5))
 for gap in ([3]f64{0.1,0.3,1.0}) {
  // get_stats does not feed the heartbeat; the last input call was the end of frames().
  quiet_from:=bom_clock_now()
  before:=pump_stats(t,handle);neutral_before:=pump_read(s,&s.heartbeat_neutral_ticks)
  time.sleep(time.Duration(gap*f64(time.Second))) // the main thread makes no call at all
  after:=pump_stats(t,handle);neutral:=pump_read(s,&s.heartbeat_neutral_ticks)-neutral_before
  silence:=bom_clock_now()-quiet_from // Sleep overshoots on Windows; bound by what really happened
  sent:=after.input_count-before.input_count;expected:=silence*60
  testing.expectf(t,f64(sent)>=expected*0.85 && f64(sent)<=expected*1.15+2,"gap %.1f s: %d inputs (expected about %.0f)",gap,sent,expected)
  testing.expectf(t,after.stall_count==before.stall_count,"gap %.1f s: stall_count %d -> %d",gap,before.stall_count,after.stall_count)
  if gap<PUMP_INPUT_HEARTBEAT {
   testing.expectf(t,neutral==0,"gap %.1f s: held move must stay held (neutral ticks %d)",gap,neutral)
  } else {
   limit:=(silence-PUMP_INPUT_HEARTBEAT)*60
   testing.expectf(t,neutral>0 && f64(neutral)<=limit+2,"gap %.1f s (%.3f s silent): neutral only after 250 ms (%d ticks, at most %.1f)",gap,silence,neutral,limit+2)
  }
  testing.expectf(t,frames(t,handle,0.4),"gap %.1f s: connection alive afterwards",gap)
 }
 final:=pump_stats(t,handle)
 testing.expectf(t,final.stall_count==0,"no stalls with the pump running (%d)",final.stall_count)
 testing.expect(t,bom_client_disconnect(handle)==OK)
}

@(test)
test_pump_runs_on_the_callers_timebase :: proc(t:^testing.T) {
 // Unity's Mono Stopwatch counts the same QPC ticks from another origin (seen in a Rounds
 // player: 199,415 s apart). Input timestamps are in that timebase, so the pump must be too.
 MONO_ORIGIN :: f64(-199415.483)
 unity_now :: proc() -> f64 { return bom_clock_now()+MONO_ORIGIN }
 handle,s:=pump_fake_slot(t,7200)
 testing.expect(t,bom_client_start_pump(handle,unity_now())==OK)
 testing.expect(t,pump_wait_ticks(s,2))
 testing.expect(t,bom_client_update(handle,unity_now())==OK)
 testing.expect(t,bom_client_set_held_input(handle,unity_now(),1)==OK)
 testing.expect(t,bom_client_enqueue_action(handle,unity_now()+0.02,1,1)==OK)
 testing.expect(t,pump_wait_ticks(s,pump_read(s,&s.pump_ticks)+4))
 sync.mutex_lock(&s.lock)
 gap:=s.next_tick-unity_now()
 testing.expectf(t,gap>-0.02 && gap<0.05,"pump ticks in Unity's timebase (next_tick - now = %.4f s)",gap)
 testing.expectf(t,s.client.stats.blasts_dropped==0 && len(s.actions)==0,"an action at Unity's now is applied, not expired (dropped %d, queued %d)",s.client.stats.blasts_dropped,len(s.actions))
 testing.expect(t,s.held_move==1 && s.heartbeat_neutral_ticks==0,"held input applies at its own tick")
 testing.expect(t,s.stall_count==0)
 sync.mutex_unlock(&s.lock)
 testing.expect(t,bom_client_start_pump(handle,math.nan_f64())==OK,"already running: start is a no-op")
 testing.expect(t,bom_client_destroy(handle)==OK)
 h2,_:=pump_fake_slot(t,7201)
 testing.expect(t,bom_client_start_pump(h2,math.inf_f64(1))==BAD_ARGUMENT)
 testing.expect(t,bom_client_destroy(h2)==OK)
}
