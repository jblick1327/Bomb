package ffi

import "core:testing"
import core "../shared"
import nc "../netcode"

empty_baseline :: proc(tick,revision:u64) -> []u8 {
 w:nc.Writer;nc.writer_init(&w)
 nc.write_u8(&w,u8(core.Repl_Kind.Baseline));nc.write_varint(&w,tick);nc.write_u8(&w,core.REPL_CANON_VERSION)
 nc.write_varint(&w,1);nc.write_varint(&w,revision);nc.write_f32(&w,0)
 for _ in 0..<4 { nc.write_varint(&w,0) }
 return w.data[:]
}

@(test)
actor_shape_metadata_matches_authoritative_constructors :: proc(t:^testing.T) {
 info:=BomActorShapeInfo{struct_size=u32(size_of(BomActorShapeInfo)),version=1}
 testing.expect(t,bom_actor_shape_info(&info)==OK)
 testing.expect(t,info.player_radius==core.PLAYER_RADIUS && info.player_segment==core.PLAYER_SEGMENT && info.bomb_radius==core.BOMB_RADIUS)
 info.version=2;testing.expect(t,bom_actor_shape_info(&info)==BAD_ARGUMENT)
}

@(test)
presentation_clock_stays_after_topology_and_before_received_poses :: proc(t:^testing.T) {
 c:core.Net_Client;c.has_complete=true;c.newest_complete=102;c.delay=2;c.rep.tick=100
 core.net_client_update_clock(&c);testing.expect(t,c.clock==100 && c.has_clock)
 for _ in 0..<30 { previous:=c.clock;core.net_client_update_clock(&c);testing.expect(t,c.clock>=previous && c.clock<=102) }
 c.delay=12
 for _ in 0..<30 { previous:=c.clock;core.net_client_update_clock(&c);testing.expect(t,c.clock>=previous && c.clock<=102) }
}

@(test)
received_truth_does_not_advance_presented_topology :: proc(t:^testing.T) {
 c:core.Net_Client;core.net_client_init(&c,1234,0);defer core.net_client_destroy(&c)
 core.net_client_on_structure(&c,empty_baseline(100,10))
 testing.expect(t,c.rep.has_baseline && c.received.has_baseline)
 w:nc.Writer;nc.writer_init(&w);defer nc.writer_destroy(&w)
 nc.write_u8(&w,u8(core.Repl_Kind.Delta));nc.write_varint(&w,105);nc.write_varint(&w,1);nc.write_varint(&w,10);nc.write_varint(&w,11)
 for _ in 0..<8 { nc.write_varint(&w,0) }
 owned:=make([]u8,len(w.data));copy(owned,w.data[:]);core.net_client_on_structure(&c,owned)
 testing.expect(t,c.received.scene.structure_revision==11 && c.rep.scene.structure_revision==10)
 c.has_clock=true;c.clock=104.5;core.net_client_apply_queue(&c)
 testing.expect(t,c.rep.scene.structure_revision==10)
 c.clock=105;core.net_client_apply_queue(&c)
 testing.expect(t,c.rep.scene.structure_revision==11 && c.stats.structure_errors==0)
}

@(test)
missing_reference_and_oversized_parts_fail_safely :: proc(t:^testing.T) {
 rep:core.Replica;core.replica_init(&rep);defer core.replica_destroy(&rep)
 data:=empty_baseline(1,1);defer delete(data)
 // Replace the empty connection count with one connection to absent cells.
 w:nc.Writer;nc.writer_init(&w);defer nc.writer_destroy(&w)
 nc.write_raw(&w,data[:len(data)-2]);nc.write_varint(&w,1)
 nc.write_varint(&w,1);nc.write_varint(&w,1);nc.write_varint(&w,2);nc.write_bool(&w,false);nc.write_varint(&w,0);nc.write_varint(&w,0)
 testing.expect(t,core.replica_apply_message(&rep,w.data[:])!="")
 nc.writer_reset(&w);nc.write_u8(&w,core.REPL_PART_MARK);nc.write_varint(&w,1);nc.write_varint(&w,0);nc.write_varint(&w,65537)
 message,complete,problem:=core.replica_collect(&rep,w.data[:]);delete(message)
 testing.expect(t,!complete && problem!="" && len(rep.part_buffer)==0)
}

@(test)
truncated_and_mutated_structure_messages_do_not_panic :: proc(t:^testing.T) {
 valid:=empty_baseline(1,1);defer delete(valid)
 for length in 0..<len(valid) {
  rep:core.Replica;core.replica_init(&rep)
  testing.expect(t,core.replica_apply_message(&rep,valid[:length])!="")
  core.replica_destroy(&rep)
 }
 state:=u64(0xaabbeedd12345678);bytes:[128]u8
 for iteration in 0..<10000 {
  for &b in bytes { state~=(state<<13);state~=(state>>7);state~=(state<<17);b=u8(state) }
  rep:core.Replica;core.replica_init(&rep)
  _=core.replica_apply_message(&rep,bytes[:iteration%len(bytes)])
  core.replica_destroy(&rep)
 }
}

@(test)
sample_preserves_full_ids_reference_pivots_and_rubber_centers :: proc(t:^testing.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 testing.expect(t,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);testing.expect(t,status==OK);context=s.ctx
 core.net_client_init(&s.client,1234,0);nc.endpoint_init(&s.client.nc_client.endpoint,1234);s.live=true
 defer testing.expect(t,bom_client_destroy(handle)==OK)
 rep:=&s.client.rep
 core.replica_add_material(rep,core.Material{name="rigid",color={255,0,0}})
 core.replica_add_material(rep,core.Material{name="rubber",flexibility=0.5,color={0,255,0}})
 base:=u64(9007199254740993)
 rigid:=[3]core.Vec2{{9,3},{12,3},{9,6}};rubber:=[3]core.Vec2{{4,5},{6,5},{5,8}}
 core.replica_add_cell(rep,core.Repl_Cell{id=base,owner=base+100,material=0,outline=rigid[:],rest_center={10,4}})
 core.replica_add_cell(rep,core.Repl_Cell{id=base+1,owner=base+101,material=1,outline=rubber[:],rest_center={5,6}})
 first:=[1]u64{base};second:=[1]u64{base+1}
 core.replica_add_piece(rep,base+100,0,{8,2},first[:]);core.replica_add_piece(rep,base+101,1,{77,88},second[:])
 rep.has_baseline=true;rep.scene.epoch=1;rep.scene.structure_revision=9;rep.tick=42;s.client.epoch=1;s.client.has_epoch=true;s.journal_epoch=1
 s.client.drawn[core.ent_key(.Piece,base+100)]={x=2,y=4,angle=1.57079632679}
 s.client.drawn[core.ent_key(.Rubber,base+1)]={x=9,y=10,angle=-0.5}
 sample:=BomSample{struct_size=u32(size_of(BomSample)),version=1};testing.expect(t,bom_client_acquire_sample(handle,&sample)==OK)
 testing.expect(t,sample.cell_count==2 && sample.pose_count==2)
 cells:=sample.cells[:sample.cell_count]
 testing.expect(t,cells[0].id==base && cells[0].piece_id==base+100 && cells[0].pivot_x==8 && cells[0].pivot_y==2)
 testing.expect(t,cells[1].id==base+1 && cells[1].pose_kind==1 && cells[1].pivot_x==5 && cells[1].pivot_y==6)
 for pose in sample.poses[:sample.pose_count] {
  if pose.kind==0 { testing.expect(t,pose.id==base+100 && pose.angle>1.57 && pose.angle<1.58) }
  if pose.kind==1 { testing.expect(t,pose.id==base+1 && pose.angle== -0.5) }
 }
 testing.expect(t,bom_client_release_sample(handle,sample.sample_sequence)==OK)
}

@(test)
complete_topology_transaction_remains_until_acknowledged :: proc(t:^testing.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 testing.expect(t,bom_client_create(&info,&handle)==OK)
 s,status:=get_slot(handle);testing.expect(t,status==OK);context=s.ctx
 core.net_client_init(&s.client,1234,0);nc.endpoint_init(&s.client.nc_client.endpoint,1234);s.live=true
 defer testing.expect(t,bom_client_destroy(handle)==OK)
 core.net_client_on_structure(&s.client,empty_baseline(100,10))
 sample:=BomSample{struct_size=u32(size_of(BomSample)),version=1}
 testing.expect(t,bom_client_acquire_sample(handle,&sample)==OK)
 id:=sample.transaction_id
 testing.expect(t,sample.transaction_flags==3 && sample.to_revision==10 && sample.received_revision==10)
 testing.expect(t,bom_client_release_sample(handle,sample.sample_sequence)==OK)
 testing.expect(t,bom_client_acquire_sample(handle,&sample)==OK)
 testing.expect(t,sample.transaction_id==id && sample.transaction_flags==3)
 testing.expect(t,bom_client_release_sample(handle,sample.sample_sequence)==OK)
 testing.expect(t,bom_client_ack_sample(handle,sample.sample_sequence)==OK)
 testing.expect(t,bom_client_acquire_sample(handle,&sample)==OK)
 testing.expect(t,sample.transaction_id==id && sample.transaction_flags==0)
 testing.expect(t,bom_client_release_sample(handle,sample.sample_sequence)==OK)
}
