package ffi
import t "core:testing"
import nc "../netcode"
@(test)
reconnect_reuses_local_port_with_fresh_salt_even_if_disconnect_is_lost :: proc(test:^t.T) {
 info:=BomCreateInfo{struct_size=u32(size_of(BomCreateInfo)),version=1};handle:u64
 t.expect(test,bom_client_create(&info,&handle)==OK);defer t.expect(test,bom_client_destroy(handle)==OK)
 connection:=BomConnectInfo{struct_size=u32(size_of(BomConnectInfo)),version=1,ipv4=0x7f000001,port=32000}
 t.expect(test,bom_client_connect(handle,&connection)==OK)
 slot,status:=get_slot(handle);t.expect(test,status==OK);context=slot.ctx
 port,salt:=nc.socket_port(&slot.socket),slot.client.nc_client.salt
 server:nc.Server;nc.server_init(&server);defer nc.server_destroy(&server)
 address:=nc.address_loopback(port)
 // Fill all four real transport slots, then discard every response. The
 // reconnect must replace the stale address instead of needing a fifth slot.
 for i in 0..<4 {
  packet:=nc.build_control_packet(.Connect,i==0?salt:u32(i+100))
  nc.server_receive(&server,i==0?address:nc.address_loopback(u16(10000+i)),packet,0);delete(packet)
 }
 t.expect(test,nc.server_client_count(&server)==4)
 t.expect(test,bom_client_disconnect(handle)==OK&&bom_client_connect(handle,&connection)==OK)
 t.expect(test,nc.socket_port(&slot.socket)==port&&slot.client.nc_client.salt!=salt&&slot.connection_generation==2)
 packet:=nc.build_control_packet(.Connect,slot.client.nc_client.salt);defer delete(packet);nc.server_receive(&server,address,packet,1)
 t.expect(test,nc.server_client_count(&server)==4&&server.clients[0].salt==slot.client.nc_client.salt)
 stale:=nc.build_control_packet(.Disconnect,salt);defer delete(stale);nc.server_receive(&server,address,stale,2)
 t.expect(test,server.clients[0].active,"a delayed old disconnect must not close the new generation")
}
