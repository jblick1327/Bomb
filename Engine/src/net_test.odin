#+feature dynamic-literals
package main

import nc "netcode"
import b2 "vendor:box2d"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:testing"

// ---------------------------------------------------------------- quantizers and codecs
@(test)
net_pose_quantizers_stay_within_half_a_step :: proc(t: ^testing.T) {
 random:=rand.create(11); gen:=rand.default_random_generator(&random)
 for _ in 0..<5000 {
  x:=rand.float32_range(-20,20,gen); a:=rand.float32_range(-12,12,gen)
  testing.expect(t,math.abs(f64(pose_dq_pos(pose_q_pos(x)))-f64(x))<=POSE_POS_STEP*0.5+1e-5)
  back:=pose_dq_angle(pose_q_angle(a))
  testing.expect(t,math.abs(f64(radians_delta(back,a)))<=math.PI/f64(POSE_ANGLE_STEPS)+1e-5)
 }
 testing.expect(t,pose_q_angle(-0.0001)==0 && pose_q_angle(2*math.PI)==0)
 testing.expect(t,angle_delta(1,u16(POSE_ANGLE_STEPS-1))==2 && angle_delta(u16(POSE_ANGLE_STEPS-1),1)==-2)
 testing.expect(t,angle_apply(u16(POSE_ANGLE_STEPS-1),2)==1 && angle_apply(1,-2)==u16(POSE_ANGLE_STEPS-1))
 testing.expect(t,pose_q_fuse(0)==0 && pose_q_fuse(BOMB_FUSE)==255 && pose_q_pos(f32(math.nan_f64()))==0)
 // The documented choice.
 testing.expect(t,POSE_POS_STEP==1.0/256 && POSE_ANGLE_STEPS==4096)
}

random_table :: proc(gen: rand.Generator,count: int,bombs: bool = true) -> Pose_Table {
 table:=make(Pose_Table)
 for i in 0..<count {
  kind:=Ent_Kind(rand.int_max(4,gen)); if !bombs && kind==.Bomb { kind=.Piece }
  key:=ent_key(kind,u64(rand.int_max(5000,gen)+i*3))
  table[key]=Pose_State{x=i32(rand.int_max(40000,gen)-20000),y=i32(rand.int_max(20000,gen)-8000),a=u16(rand.int_max(POSE_ANGLE_STEPS,gen)),landed=kind==.Bomb && rand.int_max(2,gen)==1,fuse=kind==.Bomb?u8(rand.int_max(256,gen)):0}
 }
 return table
}
// What the client does with decoded parts: base - gone + entries.
apply_parts :: proc(base: ^Pose_Table,parts: [][]u8) -> (table: Pose_Table,ok: bool) {
 table=table_clone(base)
 have:=make([]bool,len(parts)); defer delete(have)
 for data in parts {
  part,good:=frame_decode_part(data,base); defer frame_part_destroy(&part)
  if !good || len(data)>FRAME_PART_MAX || part.count!=len(parts) || have[part.index] { delete(table); return {},false }
  have[part.index]=true
  for key in part.gone { delete_key(&table,key) }
  for e in part.entries { table[e.key]=e.state }
 }
 return table,true
}
@(test)
net_frame_codec_round_trips :: proc(t: ^testing.T) {
 random:=rand.create(5); gen:=rand.default_random_generator(&random)
 for round in 0..<40 {
  base:=random_table(gen,round*15); defer delete(base)
  // Next state: change some rows, drop some, add some (absolute).
  target:=table_clone(&base); defer delete(target)
  gone:[dynamic]u64; defer delete(gone)
  for key,state in base {
   switch rand.int_max(4,gen) {
   case 0: s:=state; s.x+=i32(rand.int_max(2001,gen)-1000); s.y-=i32(rand.int_max(300,gen)); s.a=angle_apply(s.a,i64(rand.int_max(40000,gen)-20000)); if key_kind(key)==.Bomb { s.fuse=u8(rand.int_max(256,gen)); s.landed=!s.landed }; target[key]=s
   case 1: delete_key(&target,key); append(&gone,key)
   case: // unchanged
   }
  }
  fresh:=random_table(gen,round*7+3,false); defer delete(fresh)
  for key,state in fresh { if key not_in base { target[key]=state } }
  entries:[dynamic]Frame_Entry; defer delete(entries)
  for key,state in target { if old,has:=base[key]; !has || old!=state { append(&entries,Frame_Entry{key,state}) } }
  slice.sort_by(entries[:],proc(a,b: Frame_Entry) -> bool { return a.key<b.key })
  slice.sort(gone[:])
  for use_base in ([2]bool{true,false}) {
   // Without a base every entry is absolute and nothing can be "gone".
   parts:[dynamic][]u8; defer { for p in parts { delete(p) }; delete(parts) }
   if use_base { frame_encode(7,1000+u64(round),true,999,0x1234,&base,entries[:],gone[:],&parts) }
   else {
    all:[dynamic]Frame_Entry; defer delete(all)
    for key,state in target { append(&all,Frame_Entry{key,state}) }
    slice.sort_by(all[:],proc(a,b: Frame_Entry) -> bool { return a.key<b.key })
    frame_encode(7,1000+u64(round),false,0,0x1234,nil,all[:],nil,&parts)
   }
   for p in parts { testing.expect(t,len(p)<=FRAME_PART_MAX) }
   first,ok:=frame_decode_part(parts[0],use_base?&base:nil); defer frame_part_destroy(&first)
   testing.expect(t,ok && first.epoch==7 && first.tick==1000+u64(round) && first.has_base==use_base && first.blast_seq==0x1234 && first.count==len(parts))
   if use_base { testing.expect(t,first.base_tick==999) }
   rebuilt,good:=apply_parts(use_base?&base:&Pose_Table{},parts[:]); defer delete(rebuilt)
   if !use_base { delete_key(&rebuilt,0xFFFFFFFFFFFFFFFF) }
   testing.expectf(t,good && tables_equal(&rebuilt,&target),"round %d use_base=%v did not reproduce the target table",round,use_base)
   if round>=30 && use_base { testing.expectf(t,len(parts)>1 || len(entries)<100,"round %d should have needed several parts",round) }
  }
 }
}
@(test)
net_frame_splits_into_independent_parts :: proc(t: ^testing.T) {
 random:=rand.create(9); gen:=rand.default_random_generator(&random)
 target:=random_table(gen,1500,false); defer delete(target)
 entries:[dynamic]Frame_Entry; defer delete(entries)
 for key,state in target { append(&entries,Frame_Entry{key,state}) }
 slice.sort_by(entries[:],proc(a,b: Frame_Entry) -> bool { return a.key<b.key })
 gone:[dynamic]u64; defer delete(gone)
 base:=Pose_Table{}; defer delete(base)
 for i in 0..<400 { key:=ent_key(.Piece,u64(900000+i)); base[key]=Pose_State{}; append(&gone,key) }
 parts:[dynamic][]u8; defer { for p in parts { delete(p) }; delete(parts) }
 frame_encode(1,50,true,49,0,&base,entries[:],gone[:],&parts)
 testing.expect(t,len(parts)>5)
 // Every part decodes on its own (parts repeat the header) and in any order.
 total_entries,total_gone:=0,0
 slice.reverse(parts[:])
 for p in parts {
  part,ok:=frame_decode_part(p,&base); defer frame_part_destroy(&part)
  testing.expect(t,ok && len(p)<=FRAME_PART_MAX && part.tick==50 && part.base_tick==49)
  total_entries+=len(part.entries); total_gone+=len(part.gone)
 }
 testing.expect(t,total_entries==len(entries) && total_gone==len(gone))
 // A delta entry without its base row is rejected.
 with_row:=Pose_Table{}; defer delete(with_row)
 only:=ent_key(.Piece,5); with_row[only]=Pose_State{x=1}
 single:[dynamic][]u8; defer { for p in single { delete(p) }; delete(single) }
 frame_encode(1,2,true,1,0,&with_row,[]Frame_Entry{{only,Pose_State{x=9}}},nil,&single)
 empty:=Pose_Table{}
 missing,ok:=frame_decode_part(single[0],&empty); frame_part_destroy(&missing)
 testing.expect(t,!ok)
 present,ok2:=frame_decode_part(single[0],&with_row); defer frame_part_destroy(&present)
 testing.expect(t,ok2 && present.entries[0].state.x==9)
}
@(test)
net_input_and_event_codecs_round_trip :: proc(t: ^testing.T) {
 in_:=Net_Input{epoch=3,seq=65535,has_ack=true,ack=123456,move=-127,radius_q=200,jump_counter=65535,blast_count=2}
 in_.blasts[0]={seq=65534,x=-5000,y=3000,radius_q=9}; in_.blasts[1]={seq=65535,x=8000,y=-2,radius_q=255}
 w:nc.Writer; nc.writer_init(&w); defer nc.writer_destroy(&w)
 input_encode(in_,&w)
 out,ok:=input_decode(w.data[:])
 testing.expect(t,ok && out.epoch==3 && out.seq==65535 && out.has_ack && out.ack==123456 && out.move==-127 && out.radius_q==200 && out.jump_counter==65535 && out.blast_count==2 && out.blasts[1]==in_.blasts[1] && out.blasts[0]==in_.blasts[0])
 none:=Net_Input{}; clear(&w.data); input_encode(none,&w)
 out,ok=input_decode(w.data[:]); testing.expect(t,ok && !out.has_ack && out.blast_count==0)
 testing.expect(t,seq16_newer(1,65535) && !seq16_newer(65535,1) && !seq16_newer(5,5))
 testing.expect(t,radius_dequantize(radius_quantize(5))>4.98 && radius_dequantize(radius_quantize(5))<5.02 && radius_quantize(100)==255 && radius_quantize(0)==0)
 clear(&w.data); event_encode_explosion(&w,77,{1.5,-2},3.25)
 e,eok:=event_decode(w.data[:]); testing.expect(t,eok && e.kind==NET_EVENT_EXPLOSION && e.tick==77 && e.position==Vec2{1.5,-2} && e.radius==3.25)
 clear(&w.data); event_encode_rejected(&w,78,9)
 e,eok=event_decode(w.data[:]); testing.expect(t,eok && e.kind==NET_EVENT_BLAST_REJECTED && e.tick==78 && e.seq==9)
}
@(test)
net_decoders_survive_10000_random_buffers :: proc(t: ^testing.T) {
 random:=rand.create(2026); gen:=rand.default_random_generator(&random)
 base:=random_table(gen,60); defer delete(base)
 entries:[dynamic]Frame_Entry; defer delete(entries)
 for key,state in base { append(&entries,Frame_Entry{key,state}) }
 slice.sort_by(entries[:],proc(a,b: Frame_Entry) -> bool { return a.key<b.key })
 parts:[dynamic][]u8; defer { for p in parts { delete(p) }; delete(parts) }
 frame_encode(2,10,true,9,1,&base,entries[:],nil,&parts)
 valid_input:nc.Writer; nc.writer_init(&valid_input); defer nc.writer_destroy(&valid_input)
 input_encode(Net_Input{epoch=1,seq=4,has_ack=true,ack=9,blast_count=1,blasts={0={seq=1,x=5,y=6,radius_q=7}}},&valid_input)
 accepted:=0
 for i in 0..<10000 {
  buffer:[]u8
  switch i%4 {
  case 0: buffer=make([]u8,rand.int_max(300,gen)); for &b in buffer { b=u8(rand.int_max(256,gen)) }
  case 1: buffer=slice.clone(parts[rand.int_max(len(parts),gen)]); for _ in 0..<1+rand.int_max(6,gen) { if len(buffer)>0 { buffer[rand.int_max(len(buffer),gen)]=u8(rand.int_max(256,gen)) } }
  case 2: source:=parts[rand.int_max(len(parts),gen)]; buffer=slice.clone(source[:rand.int_max(len(source)+1,gen)])
  case 3: buffer=slice.clone(valid_input.data[:]); for _ in 0..<1+rand.int_max(3,gen) { buffer[rand.int_max(len(buffer),gen)]=u8(rand.int_max(256,gen)) }
  }
  if len(buffer)>0 && i%2==0 { buffer[0]=NET_MSG_FRAME }
  for use_base in ([2]bool{true,false}) {
   part,ok:=frame_decode_part(buffer,use_base?&base:nil)
   if ok { accepted+=1 }; frame_part_destroy(&part)
  }
  if len(buffer)>0 && i%3==0 { buffer[0]=NET_MSG_INPUT }
  if _,ok:=input_decode(buffer); ok { accepted+=1 }
  _,_ = event_decode(buffer)
  repl_peek(buffer)
  delete(buffer)
 }
 fmt.printf("Fuzz: 10000 buffers through frame/input/event decode, %d accepted, no panic\n",accepted)
}

// ---------------------------------------------------------------- server rules
test_server :: proc() -> Net_Server {
 g:=soak_yard(); sandbox_fixture_mode(&g,.Falling_Bombs)
 ns:Net_Server; net_server_init(&ns,g,true)
 return ns
}
@(test)
net_server_frame_matches_rigid_render_frame :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 ns:=test_server(); defer net_server_destroy(&ns)
 sandbox_explode(&ns.game,{-4.3,1})
 for _ in 0..<90 { world_tick(&ns.game.world,Tick_Commands{},1.0/60.0) }
 net_collect(&ns)
 s:=&ns.game.world.scene
 checked,worst:=0,f32(0)
 for p in s.pieces {
  if !p.live || s.materials[p.material].flexibility>0 { continue }
  entity,present:=ns.current[ent_key(.Piece,p.id)]
  testing.expectf(t,present==(b2.Body_GetType(p.body)==.dynamicBody),"piece %d replicated=%v but body type is %v",p.id,present,b2.Body_GetType(p.body))
  if !present { continue }
  anchor:Subdivision
  for id in p.subdivisions { if sub:=s.subdivisions[s.sub_rows[id]]; sub.live { anchor=sub; break } }
  frame:=frame_to_reference(rigid_render_frame(s,anchor,nil),p.ref_rest)
  worst=max(worst,vlen(vsub(Vec2{entity.fx,entity.fy},frame.position)))
  testing.expect(t,math.abs(f64(radians_delta(entity.fa,frame.angle)))<1e-3)
  checked+=1
 }
 testing.expectf(t,checked>20 && worst<1e-3,"piece frames checked=%d worst origin difference=%g",checked,worst)
}
@(test)
net_server_blast_rules_and_exactly_once :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 ns:=test_server(); defer net_server_destroy(&ns)
 sandbox_fixture_mode(&ns.game,.Manual)
 net_server_join(&ns,0)
 blast :: proc(seq: u16,x,y: f32) -> Net_Blast { return {seq=seq,x=nc.quantize_pos(x),y=nc.quantize_pos(y),radius_q=radius_quantize(2)} }
 send :: proc(ns: ^Net_Server,seq_no: u16,blasts: ..Net_Blast) {
  in_:=Net_Input{seq=seq_no,blast_count=len(blasts)}
  for b,i in blasts { in_.blasts[i]=b }
  net_server_input(ns,0,in_)
 }
 c:=&ns.clients[0]
 // Repeated delivery of the same blasts applies each exactly once; outside the yard is rejected.
 send(&ns,1,blast(1,-4.3,1),blast(2,40,1))
 send(&ns,2,blast(1,-4.3,1),blast(2,40,1),blast(3,2.5,1))
 net_server_tick(&ns,1.0/60)
 send(&ns,3,blast(1,-4.3,1),blast(2,40,1),blast(3,2.5,1))
 net_server_tick(&ns,2.0/60)
 testing.expectf(t,c.stats.blasts_applied==2 && c.stats.blasts_rejected==1 && c.stats.rejected_outside==1 && c.stats.blast_duplicates==0,"applied=%d rejected=%d outside=%d",c.stats.blasts_applied,c.stats.blasts_rejected,c.stats.rejected_outside)
 testing.expect(t,c.last_blast_seq==3)
 // Rate limit: four per second. Points in empty air above the pile.
 for i in 0..<6 { send(&ns,u16(10+i),blast(u16(10+i),-6+f32(i)*0.4,6)) }
 start_applied:=c.stats.blasts_applied
 in_:=Net_Input{seq=20,blast_count=6}
 for i in 0..<6 { in_.blasts[i]=blast(u16(10+i),-6+f32(i)*0.4,6) }
 net_server_input(&ns,0,in_)
 net_server_tick(&ns,3.0/60)
 testing.expectf(t,c.stats.blasts_applied-start_applied<=NET_BLAST_RATE_COUNT-1+1 && c.stats.rejected_rate>=1,"rate limit applied=%d rate_rejected=%d",c.stats.blasts_applied-start_applied,c.stats.rejected_rate)
 testing.expect(t,c.stats.blasts_applied+c.stats.blasts_rejected==9)
 // A blast into solid ground is rejected (and consumes its sequence number).
 for _ in 0..<70 { net_server_tick(&ns,4.0/60) }
 send(&ns,30,blast(40,-7.5,-1))
 net_server_tick(&ns,5.0/60)
 testing.expect(t,c.stats.rejected_solid==1 && c.last_blast_seq==40)
 // Jumps: a cumulative counter, one jump per advance, none when it repeats.
 jumps:=c.stats.jumps_applied
 for counter in ([]u16{1,1,2,2,2,3}) { net_server_input(&ns,0,Net_Input{seq=100+counter,jump_counter=counter}) }
 testing.expect(t,c.stats.jumps_applied-jumps==3)
}
@(test)
net_server_budget_priority_and_final_pose :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 ns:=test_server(); defer net_server_destroy(&ns)
 sandbox_fixture_mode(&ns.game,.Manual)
 net_server_join(&ns,0)
 c:=&ns.clients[0]
 for point in ([]Vec2{{-6.4,2.3},{-4.3,1},{-0.7,1},{2.5,1},{4.3,2.4},{6.2,1}}) { sandbox_explode(&ns.game,point) }
 big_frames,total_frames:=0,0
 // An ideal client: it acks every frame at once.
 for tick in 0..<1500 {
  net_server_tick(&ns,f64(tick+1)/60)
  total_frames+=1
  // No acks for the first 40 ticks: every moving entity is a candidate without a row.
  if tick>0 { testing.expect(t,c.stats.frame_bytes[len(c.stats.frame_bytes)-1]<=i32(FRAME_BUDGET+4*FRAME_PART_MAX)) }
  if c.stats.frame_bytes[len(c.stats.frame_bytes)-1]>i32(FRAME_PART_MAX) { big_frames+=1 }
  if tick>=40 { net_server_input(&ns,0,Net_Input{epoch=ns.game.world.scene.epoch,seq=u16(tick+1),has_ack=true,ack=ns.tick}) }
 }
 testing.expect(t,c.stats.ticks==1500 && c.has_ack && c.acked==ns.tick)
 // The final resting pose arrived: every entity equals its acked row, except bodies still awake.
 acked:=&c.ring[c.acked%NET_SENT_RING]
 off,asleep_off:=0,0
 for key,e in ns.current {
  if row,ok:=acked[key]; !ok || row!=e.state {
   off+=1
   if key_kind(key)==.Piece { if r,found:=ns.game.world.scene.piece_rows[key_id(key)]; found && !b2.Body_IsAwake(ns.game.world.scene.pieces[r].body) { asleep_off+=1 } }
  }
 }
 testing.expectf(t,asleep_off==0,"%d sleeping pieces differ from the acked table (%d entities differ in all)",asleep_off,off)
 fmt.printf("Budget test: saturated ticks=%d of %d, frames over one part=%d, max staleness=%d ticks, entities off=%d\n",c.stats.saturated_ticks,total_frames,big_frames,c.stats.staleness_max,off)
}
@(test)
net_server_epoch_change_resets_frame_state :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 ns:=test_server(); defer net_server_destroy(&ns)
 sandbox_fixture_mode(&ns.game,.Manual)
 net_server_join(&ns,0)
 c:=&ns.clients[0]
 for tick in 0..<30 {
  net_server_tick(&ns,f64(tick+1)/60)
  net_server_input(&ns,0,Net_Input{epoch=ns.game.world.scene.epoch,seq=u16(tick+1),has_ack=true,ack=ns.tick})
 }
 testing.expect(t,c.has_ack)
 epoch:=ns.game.world.scene.epoch
 sandbox_reset(&ns.game)
 net_server_tick(&ns,31.0/60)
 testing.expect(t,ns.game.world.scene.epoch==epoch+1 && !c.has_ack && ns.frame_epoch==epoch+1)
 // An ack that still names the old epoch is ignored; the first frame of the new epoch is absolute.
 net_server_input(&ns,0,Net_Input{epoch=epoch,seq=99,has_ack=true,ack=ns.tick})
 testing.expect(t,!c.has_ack)
}

// ---------------------------------------------------------------- client clock, interpolation, queue
test_client :: proc() -> Net_Client {
 c:Net_Client; net_client_init(&c,1234,0)
 c.has_epoch=true; c.epoch=1; c.has_complete=true; c.has_clock=true
 return c
}
put_frame :: proc(c: ^Net_Client,tick: u64,states: map[u64]Pose_State) {
 table:=make(Pose_Table)
 for key,s in states { table[key]=s }
 slot:=&c.ring[tick%NET_CLIENT_RING]
 if slot.valid { delete(slot.table) }
 slot^={valid=true,tick=tick,table=table}
 c.newest_complete=max(c.newest_complete,tick)
}
@(test)
net_client_clock_adjusts_by_at_most_five_percent_and_snaps :: proc(t: ^testing.T) {
 c:=test_client(); defer net_client_destroy(&c)
 c.newest_complete=1000; c.delay=2; c.clock=990
 net_client_update_clock(&c)
 testing.expect(t,c.clock>990+1 && math.abs(c.clock-991.05)<1e-9 && c.stats.snaps==0,"far behind: rate is capped at +5%")
 c.clock=1010; net_client_update_clock(&c)
 testing.expect(t,math.abs(c.clock-1010.95)<1e-9,"far ahead: rate is capped at -5%")
 c.clock=997.9; net_client_update_clock(&c)
 testing.expect(t,math.abs(c.clock-998.9)<0.01,"on target: real time")
 c.clock=900; net_client_update_clock(&c)
 testing.expect(t,c.clock==998 && c.stats.snaps==1,"more than 0.5 s off: snap")
 c.clock=1031; net_client_update_clock(&c)
 testing.expect(t,c.clock==998 && c.stats.snaps==2)
}
@(test)
net_client_delay_adapts_to_jitter_and_loss :: proc(t: ^testing.T) {
 c:=test_client(); defer net_client_destroy(&c)
 // A lossless, jitter-free link settles at the minimum of 2.
 for tick in 1..=120 { c.newest_complete=u64(tick); append(&c.arrivals,Arrival{f64(tick)/60+0.3,u64(tick)}) }
 net_client_update_delay(&c,2.0+0.3)
 testing.expect(t,c.delay==2)
 // 2 ticks of jitter at p95: 1 + 2.
 clear(&c.arrivals)
 for tick in 1..=120 { jitter:=tick%10<2 ? 2.0/60 : 0.0; append(&c.arrivals,Arrival{f64(tick)/60+0.3+jitter,u64(tick)}) }
 net_client_update_delay(&c,2.3)
 testing.expectf(t,c.delay==2 || c.delay==3,"delay %d",c.delay)
 clear(&c.arrivals)
 for tick in 1..=120 { jitter:=tick%5<2 ? 3.0/60 : 0.0; append(&c.arrivals,Arrival{f64(tick)/60+0.3+jitter,u64(tick)}) }
 net_client_update_delay(&c,2.3)
 testing.expectf(t,c.delay==4,"40%% of frames 3 ticks late: 1+3, got %d",c.delay)
 // A frame lost within 2 s adds 2; it is lost once a frame 8 ticks newer completes without it.
 clear(&c.arrivals); for tick in 1..=120 { append(&c.arrivals,Arrival{f64(tick)/60,u64(tick)}) }
 append(&c.missing,50); c.newest_complete=120
 net_client_update_delay(&c,2.0)
 testing.expectf(t,c.delay==3 && c.stats.frames_lost==1,"no jitter, one loss: 1+0+2, got %d lost %d",c.delay,c.stats.frames_lost)
 // After 2 s without loss it drops back, and the delay is capped at 12.
 net_client_update_delay(&c,4.5)
 testing.expect(t,c.delay==2)
 clear(&c.arrivals); for tick in 1..=120 { append(&c.arrivals,Arrival{f64(tick)/60+(tick%2==0 ? 0.5 : 0),u64(tick)}) }
 net_client_update_delay(&c,2.0)
 testing.expect(t,c.delay==NET_DELAY_MAX)
}
@(test)
net_client_interpolates_between_bracketing_frames :: proc(t: ^testing.T) {
 c:=test_client(); defer net_client_destroy(&c)
 player:=ent_key(.Player,1); bomb:=ent_key(.Bomb,7); gone_bomb:=ent_key(.Bomb,8); unknown_piece:=ent_key(.Piece,999)
 near_wrap:=u16(POSE_ANGLE_STEPS-100)
 a:=map[u64]Pose_State{player={x=pose_q_pos(0),y=pose_q_pos(0),a=near_wrap},bomb={x=pose_q_pos(1),y=pose_q_pos(2)},gone_bomb={x=pose_q_pos(5),y=pose_q_pos(5)},unknown_piece={}}
 b:=map[u64]Pose_State{player={x=pose_q_pos(4),y=pose_q_pos(-4),a=100},bomb={x=pose_q_pos(3),y=pose_q_pos(2),landed=true,fuse=255},unknown_piece={}}
 defer { delete(a); delete(b) }
 put_frame(&c,100,a); put_frame(&c,104,b)
 c.clock=101
 net_client_compute_drawn(&c)
 p,ok:=c.drawn[player]
 testing.expect(t,ok && math.abs(f64(p.x)-1)<0.01 && math.abs(f64(p.y)+1)<0.01,"positions lerp")
 // 200 steps apart across the wrap: the shortest arc, a quarter of the way.
 step:=f64(2*math.PI)/f64(POSE_ANGLE_STEPS)
 testing.expectf(t,math.abs(f64(radians_delta(p.angle,pose_dq_angle(near_wrap)))-50*step)<1e-3,"angle took the short way, got delta %g",radians_delta(p.angle,pose_dq_angle(near_wrap)))
 testing.expect(t,c.drawn[bomb].x>1.4 && c.drawn[bomb].x<1.6 && !c.drawn[bomb].landed)
 // gone at the upper frame: drawn until the clock reaches it.
 _,gone_drawn:=c.drawn[gone_bomb]; testing.expect(t,gone_drawn)
 // Rows that are not in the replica's structure are not drawn.
 _,unknown_drawn:=c.drawn[unknown_piece]; testing.expect(t,!unknown_drawn)
 c.clock=104; net_client_compute_drawn(&c)
 _,gone_drawn=c.drawn[gone_bomb]; testing.expect(t,!gone_drawn,"gone at T1: not drawn once the clock reaches T1")
 testing.expect(t,c.drawn[bomb].landed && c.drawn[bomb].x==3)
 // New at the later frame: shown from that frame, not before.
 new_bomb:=ent_key(.Bomb,9)
 c2:=map[u64]Pose_State{player={},new_bomb={x=pose_q_pos(2)}}; defer delete(c2)
 put_frame(&c,108,c2)
 c.clock=106; net_client_compute_drawn(&c)
 _,new_drawn:=c.drawn[new_bomb]; testing.expect(t,!new_drawn)
 c.clock=108; net_client_compute_drawn(&c)
 _,new_drawn=c.drawn[new_bomb]; testing.expect(t,new_drawn && c.drawn[new_bomb].x==2)
 // The clock past the newest frame draws that frame (no extrapolation).
 c.clock=130; net_client_compute_drawn(&c)
 testing.expect(t,c.drawn[new_bomb].x==2)
}
@(test)
net_client_structure_waits_for_its_tick_and_epoch_resets :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 srv:Repl_Server; defer repl_server_destroy(&srv)
 c:Net_Client; net_client_init(&c,77,0); defer net_client_destroy(&c)
 base:=repl_server_update(&srv,&g.world.scene,10); defer repl_output_destroy(&base)
 for part in base.parts { net_client_on_reliable(&c,part) }
 testing.expect(t,c.has_epoch && c.rep.has_baseline && c.stats.structure_applied==1 && len(c.queue)==0,"the first Baseline applies on arrival")
 revision:=c.rep.scene.structure_revision
 testing.expect(t,sandbox_fixture_blast(&g,{-4.3,1}))
 d1:=repl_server_update(&srv,&g.world.scene,50); defer repl_output_destroy(&d1)
 testing.expect(t,sandbox_fixture_blast(&g,{2.5,1}))
 d2:=repl_server_update(&srv,&g.world.scene,60); defer repl_output_destroy(&d2)
 // Delivered early: queued, not applied.
 c.has_clock=true; c.clock=40
 for part in d1.parts { net_client_on_reliable(&c,part) }
 for part in d2.parts { net_client_on_reliable(&c,part) }
 net_client_apply_queue(&c)
 testing.expect(t,len(c.queue)==2 && c.rep.scene.structure_revision==revision)
 c.clock=55; net_client_apply_queue(&c)
 testing.expect(t,len(c.queue)==1 && c.rep.scene.structure_revision!=revision,"first delta applies at its tick, second waits")
 c.clock=60; net_client_apply_queue(&c)
 testing.expect(t,len(c.queue)==0 && scenes_equal(&g.world.scene,&c.rep.scene) && c.stats.late_messages==0)
 // Delivered after the clock passed its tick: counted as late and applied at once.
 testing.expect(t,sandbox_fixture_blast(&g,{4.3,2.4}))
 d3:=repl_server_update(&srv,&g.world.scene,61); defer repl_output_destroy(&d3)
 c.clock=70
 for part in d3.parts { net_client_on_reliable(&c,part) }
 testing.expect(t,c.stats.late_messages==1 && c.stats.late_structure==1 && math.abs(c.stats.late_max_ticks-9)<1e-9)
 net_client_apply_queue(&c)
 testing.expect(t,scenes_equal(&g.world.scene,&c.rep.scene))
 // Events are queued by tick too.
 w:nc.Writer; nc.writer_init(&w); defer nc.writer_destroy(&w)
 event_encode_explosion(&w,200,{1,1},2)
 net_client_on_reliable(&c,w.data[:]); net_client_apply_queue(&c)
 testing.expect(t,len(c.queue)==1 && c.stats.events_played==0)
 c.clock=200; net_client_apply_queue(&c)
 testing.expect(t,len(c.queue)==0 && c.stats.events_played==1 && len(c.bursts)==1)
 // A new epoch's Baseline resets the replica, the tables and the clock.
 last:=map[u64]Pose_State{ent_key(.Player,0)={}}; defer delete(last)
 put_frame(&c,300,last)
 c.has_complete=true; c.has_clock=true
 sandbox_reset(&g)
 fresh:=repl_server_update(&srv,&g.world.scene,300); defer repl_output_destroy(&fresh)
 testing.expect(t,fresh.kind==.Baseline)
 for part in fresh.parts { net_client_on_reliable(&c,part) }
 testing.expect(t,c.epoch==g.world.scene.epoch && !c.has_complete && !c.has_clock && c.stats.resets==2 && len(c.queue)==0 && scenes_equal(&g.world.scene,&c.rep.scene))
 for slot in c.ring { testing.expect(t,!slot.valid) }
}

// ---------------------------------------------------------------- end to end
@(test)
net_end_to_end_short_soak :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 result:=net_soak_run(Net_Soak_Config{ticks=1500,flush_ticks=180,seed=4321,reset_tick=700})
 testing.expect(t,result.table_checked>1000 && result.table_mismatch==0,"acked tables must equal the server's records")
 testing.expect(t,result.structure_errors==0 && result.epochs_seen==1)
 for i in 0..<nc.MAX_CLIENTS {
  testing.expectf(t,result.structure_mismatch[i]==0 && result.structure_unrecorded[i]==0 && result.structure_applied[i]>5,"client %d structure",i)
  testing.expectf(t,result.final_equal[i] && result.final_revision_equal[i],"client %d final structure",i)
  testing.expectf(t,result.jumps_pressed[i]==result.jumps_applied[i],"client %d jumps %d vs %d",i,result.jumps_pressed[i],result.jumps_applied[i])
  testing.expectf(t,result.blasts_applied[i]+result.blasts_rejected[i]==result.blasts_issued[i] && result.blast_duplicates[i]==0,"client %d blasts",i)
  testing.expectf(t,result.final_pose_mismatch[i]==result.final_pose_awake[i],"client %d: %d entities differ, %d awake",i,result.final_pose_mismatch[i],result.final_pose_awake[i])
 }
 testing.expect(t,result.delay_local_final==2)
}

@(test)
net_server_budget_fresh_first_priority_and_convergence :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 ns:=test_server(); defer net_server_destroy(&ns)
 sandbox_fixture_mode(&ns.game,.Manual)
 net_server_join(&ns,0)
 c:=&ns.clients[0]
 player:=ns.game.world.players[0].pose.position
 // 800 synthetic pieces: #0 is large, fast and next to the player; the rest are slow, small and far away.
 set_states :: proc(ns: ^Net_Server,shift: i32,player: Vec2) {
  clear(&ns.current)
  for i in 0..<800 {
   e:=Net_Entity{state={x=i32(i)*40+shift,y=7},fx=30,fy=30,speed=0.01,area=0.05}
   if i==0 { e.fx=player.x; e.fy=player.y; e.speed=50; e.area=1 }
   ns.current[ent_key(.Piece,u64(100000+i))]=e
  }
  sorted_keys(&ns.current,&ns.keys)
 }
 set_states(&ns,0,player); ns.tick=1
 net_build_frame(&ns,0)
 first:=table_clone(&c.ring[1]); defer delete(first)
 bytes1:=c.stats.frame_bytes[len(c.stats.frame_bytes)-1]
 testing.expectf(t,len(first)>150 && len(first)<800 && bytes1<=i32(FRAME_BUDGET+40+FRAME_PART_MAX/8),"first frame sent %d rows in %d bytes",len(first),bytes1)
 testing.expect(t,c.stats.saturated_ticks==1,"800 fresh candidates cannot fit the budget")
 _,has_zero:=first[ent_key(.Piece,100000)]
 testing.expect(t,has_zero,"the highest-priority entity is in the first frame")
 net_server_ack(&ns,c,1)
 // Everything moves. Entities without a row in the acked table go before those that have one.
 set_states(&ns,5,player); ns.tick=2
 net_build_frame(&ns,0)
 second:=&c.ring[2%NET_SENT_RING]
 with_row_sent,fresh_sent:=0,0
 for key,state in second^ {
  old,had:=first[key]
  if !had { fresh_sent+=1 } else if old!=state { with_row_sent+=1 }
 }
 testing.expectf(t,fresh_sent>0 && with_row_sent==0,"fresh-first: %d fresh rows sent, %d changed rows sent",fresh_sent,with_row_sent)
 // Candidates keep accumulating until sent, so every entity eventually arrives at its final state.
 for tick in u64(3)..<30 {
  net_server_ack(&ns,c,tick-1)
  ns.tick=tick
  net_build_frame(&ns,0)
 }
 final:=&c.ring[29%NET_SENT_RING]
 wrong:=0
 for key,e in ns.current { if row,ok:=final[key]; !ok || row!=e.state { wrong+=1 } }
 testing.expectf(t,wrong==0,"%d of 800 entities never reached their final pose",wrong)
 testing.expectf(t,c.stats.staleness_max>=1 && c.stats.staleness_max<30,"max staleness %d",c.stats.staleness_max)
}

// ---------------------------------------------------------------- bomb ids
@(test)
bomb_ids_round_trip_and_legacy_bombs_get_sequential_ids :: proc(t: ^testing.T) {
 sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
 g:=soak_yard(); defer sandbox_destroy(&g)
 // Sequential ids are not written, so snapshots stay byte-compatible with the earlier format.
 world_bomb_spawn(&g.world,{0,6}); world_bomb_spawn(&g.world,{1,6})
 testing.expect(t,g.world.bombs[0].id==1 && g.world.bombs[1].id==2 && g.world.next_bomb_id==2)
 plain,ok:=encode_world_snapshot(&g.world); testing.expect(t,ok); defer delete(plain)
 index:=strings.index(string(plain),"\"bombs\"")
 testing.expect(t,index>0 && !strings.contains(string(plain)[index:],"\"id\""),"sequential ids are omitted")
 loaded,lok:=decode_world_snapshot(plain); testing.expect(t,lok)
 testing.expect(t,len(loaded.bombs)==2 && loaded.bombs[0].id==1 && loaded.bombs[1].id==2 && loaded.next_bomb_id==2)
 scene_destroy(&loaded.scene); delete(loaded.bombs)
 // Falling bombs make live ids non-sequential: they are written and read back.
 sandbox_fixture_mode(&g,.Falling_Bombs)
 for _ in 0..<2400 {
  sandbox_tick(&g,0,false)
  odd:=false; for bomb,i in g.world.bombs { if bomb.id!=u64(i+1) { odd=true } }
  if odd { break }
 }
 testing.expect(t,len(g.world.bombs)>0 && g.world.bombs[0].id>1,"fixture must produce non-sequential live ids")
 data,ok2:=encode_world_snapshot(&g.world); testing.expect(t,ok2); defer delete(data)
 testing.expect(t,strings.contains(string(data)[strings.index(string(data),"\"bombs\""):],"\"id\""))
 loaded,lok=decode_world_snapshot(data); testing.expect(t,lok)
 defer { scene_destroy(&loaded.scene); delete(loaded.bombs) }
 testing.expect(t,len(loaded.bombs)==len(g.world.bombs))
 highest:=u64(0)
 for bomb,i in g.world.bombs { testing.expect(t,loaded.bombs[i].id==bomb.id); highest=max(highest,bomb.id) }
 testing.expect(t,loaded.next_bomb_id>=highest)
 // Duplicate explicit ids are rejected.
 if len(g.world.bombs)>1 {
  twice,_:=strings.replace_all(string(data),fmt.tprintf("\"id\": %d",g.world.bombs[1].id),fmt.tprintf("\"id\": %d",g.world.bombs[0].id)); defer delete(twice)
  bad,bad_ok:=decode_world_snapshot(transmute([]byte)twice)
  if bad_ok { scene_destroy(&bad.scene); delete(bad.bombs) }
  testing.expect(t,!bad_ok,"duplicate bomb ids must be rejected")
 }
}
