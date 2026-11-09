package ffi

import "core:testing"
import "core:math"
import core "../shared"
import nc "../netcode"

// Deterministic adapter unit fixture, separate from the real UDP executable gates.
// Synthetic receive timestamps only prevent a transport timeout in this clock test.
timing_fixture :: proc(t:^testing.T,intervals:[]f64) -> (u64,u16,u64) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 testing.expect(t,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);testing.expect(t,status==OK)
 context.allocator=s.ctx.allocator
 core.net_client_init(&s.client,1234,0)
 
 s.client.nc_client.state=.Connected;s.client.real_gate=false;s.live=true
 defer { testing.expect(t,bom_client_destroy(handle)==OK) }
 testing.expect(t,bom_client_set_held_input(handle,0,1)==OK)
 testing.expect(t,bom_client_set_held_input(handle,2.25,-1)==OK)
 testing.expect(t,bom_client_set_held_input(handle,5.5,0)==OK)
 testing.expect(t,bom_client_enqueue_jump(handle,1.025)==OK)
 testing.expect(t,bom_client_enqueue_jump(handle,1.030)==OK)
 testing.expect(t,bom_client_enqueue_action(handle,3.1415,-6.4,2.3)==OK)
 testing.expect(t,bom_client_enqueue_action(handle,3.1425,1000,1000)==OK)
 testing.expect(t,bom_client_update(handle,0)==OK)
 now:=f64(0)
 for dt in intervals {
  now=min(f64(10),now+dt)
  s.client.nc_client.last_recv=s.transport_now+dt
  testing.expect(t,bom_client_update(handle,now)==OK)
 }
 testing.expect(t,math.abs(now-10)<1e-6)
 testing.expect(t,s.stall_count==0 && s.held_move==0)
 return u64(s.client.stats.input_count),s.client.jump_counter,s.client.stats.input_payload_hash
}
@(test)
test_timing_same_commands_for_30_60_144_and_irregular :: proc(t:^testing.T) {
 expected:u64
 for fps in ([4]int{30,60,144,1000}) {
  intervals:=make([]f64,fps*10);defer delete(intervals)
  for &dt in intervals { dt=1/f64(fps) }
  commands,jumps,digest:=timing_fixture(t,intervals)
  if expected==0 { expected=digest }
  testing.expect(t,commands==600 && jumps==2 && digest==expected,"complete command bytes preserve both close edges and actions across render schedules")
 }
 irregular:[dynamic]f64;defer delete(irregular)
 now:=f64(0);i:=0
 pattern:=[5]f64{0.003,0.011,0.027,0.007,0.021}
 for now<10 {
  dt:=pattern[i%5]
  dt=min(dt,10-now);append(&irregular,dt);now+=dt;i+=1
 }
 commands,jumps,digest:=timing_fixture(t,irregular[:])
 testing.expect(t,commands==600 && jumps==2 && digest==expected)
}
@(test)
test_fractional_sample_does_not_advance_fixed_commands :: proc(t:^testing.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 testing.expect(t,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);testing.expect(t,status==OK);context.allocator=s.ctx.allocator
 core.net_client_init(&s.client,1236,0);s.live=true
 defer { testing.expect(t,bom_client_destroy(handle)==OK) }
 s.client.has_epoch=true;s.client.epoch=1;s.journal_epoch=1
 s.client.has_clock=true;s.client.has_complete=true;s.client.clock=10;s.client.newest_complete=11
 s.accumulator=core.NET_STEP_DT*0.5
 key:=core.ent_key(.Player,0)
 for tick in 10..=11 {
  frame:=&s.client.ring[tick%core.NET_CLIENT_RING]
  frame.valid=true;frame.tick=u64(tick);frame.table=make(core.Pose_Table)
  frame.table[key]=core.Pose_State{x=i32((tick-10)*256)}
 }
 sample:=BomSample{struct_size=u32(size_of(BomSample)),version=1}
 testing.expect(t,bom_client_acquire_sample(handle,&sample)==OK)
 testing.expect(t,math.abs(sample.presentation_tick-10.5)<1e-9)
 testing.expect(t,sample.pose_count==1 && math.abs(sample.poses[0].x-0.5)<0.00001)
 testing.expect(t,s.client.clock==10 && s.client.stats.input_count==0,"sampling cannot generate a command or advance the fixed clock")
 testing.expect(t,bom_client_release_sample(handle,sample.sample_sequence)==OK)
 testing.expect(t,bom_client_ack_sample(handle,sample.sample_sequence)==OK)
}
@(test)
test_timing_stall_backward_and_duplicate_do_not_burst :: proc(t:^testing.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 testing.expect(t,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);testing.expect(t,status==OK)
 context.allocator=s.ctx.allocator
 core.net_client_init(&s.client,1235,0);s.client.nc_client.state=.Connected;s.live=true
 
 defer { testing.expect(t,bom_client_destroy(handle)==OK) }
 testing.expect(t,bom_client_update(handle,0)==OK)
 testing.expect(t,bom_client_enqueue_jump(handle,0.1)==OK)
 testing.expect(t,bom_client_update(handle,0.5)==OK)
 testing.expect(t,s.client.stats.input_count==0 && len(s.jumps)==0 && s.stall_count==1)
 testing.expect(t,bom_client_update(handle,0.4)==OK)
 testing.expect(t,s.client.stats.input_count==0 && s.stall_count==2)
 testing.expect(t,bom_client_update(handle,0.4)==OK)
 testing.expect(t,s.client.stats.input_count==0 && s.stall_count==2)
}
