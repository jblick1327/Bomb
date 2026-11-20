package main

import "core:testing"
import "core:sync"
import nc "netcode"

@(test)
menu_multiplayer_editor_releases_latch_and_consumes_modals :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 game:=sandbox_editor_create();defer sandbox_destroy(&game)
 net:Net_Game_UI;net.active=true;net.client.real_is_host=true
 sandbox_toggle_editor(&game);sandbox_toggle_editor(&game)
 testing.expect(t,game.block_blast)
 before,ok:=encode_world_snapshot(&game.world);defer delete(before);testing.expect(t,ok)
 net_gui_route_input(&net,&game,{},sandbox_view(1280,800),false)
 testing.expect(t,!game.block_blast,"Host Edit must release placement after mouse-up")
 sandbox_dispatch_ui(&game,.Open,&net)
 sandbox_dispatch_ui(&game,.Help,&net)
 testing.expect(t,game.panel_open && game.menu_page==.Help)
 net_gui_route_input(&net,&game, Sandbox_Input{edit_pressed=true,inspection_pressed=true},sandbox_view(1280,800),false)
 testing.expect(t,game.editor.editing && !game.inspection,"Menu consumes Test and inspection keys")
 net_gui_route_input(&net,&game,Sandbox_Input{menu_pressed=true},sandbox_view(1280,800),false)
 testing.expect(t,!game.panel_open)
 sandbox_dispatch_ui(&game,.Open,&net);sandbox_dispatch_ui(&game,.Multiplayer,&net)
 testing.expect(t,net.open && !game.panel_open,"Only one modal owns input")
 after,encoded:=encode_world_snapshot(&game.world);defer delete(after)
 testing.expect(t,encoded && string(before)==string(after),"Menu navigation must not change the World")
}

@(test)
menu_settings_reach_joiners_and_follow_host_updates :: proc(t:^testing.T) {
 sync.mutex_lock(&physics_test_mutex);defer sync.mutex_unlock(&physics_test_mutex)
 ns:Net_Server;net_server_init(&ns,sandbox_editor_create());defer net_server_destroy(&ns)
 ns.real_gate=true;ns.real_host_token="menu-test-host-token"
 host,guest:Net_Client
 net_client_init(&host,11,0);defer net_client_destroy(&host)
 net_client_init(&guest,22,0);defer net_client_destroy(&guest)
 host.real_gate=true;guest.real_gate=true
 host.real_hello_sent=true;guest.real_hello_sent=true
 join :: proc(ns:^Net_Server,c:^Net_Client,index:int,token:string) {
  connect:=nc.build_control_packet(.Connect,c.nc_client.salt);defer delete(connect)
  nc.server_receive(&ns.srv,nc.Address(index+1),connect,0)
  accept:=nc.build_control_packet(.Accept,c.nc_client.salt,u8(index));defer delete(accept)
  nc.client_receive(&c.nc_client,accept,0)
  w:nc.Writer;nc.writer_init(&w);defer nc.writer_destroy(&w)
  net_app_write_hello(&w,GAME_PROTOCOL_VERSION,GAME_BUILD_ID,token)
  net_app_server_hello(ns,index,w.data[:],0)
 }
 deliver :: proc(ns:^Net_Server,c:^Net_Client,index:int,now:f64) {
  for step in 0..<20 {
   current:=now+f64(step)*0.001
   nc.server_update(&ns.srv,current)
   packets:=nc.server_take_outgoing(&ns.srv)
   for p in packets { if p.to==nc.Address(index+1) { nc.client_receive(&c.nc_client,p.data,current) } }
   nc.outgoing_free(&packets)
   net_client_step(c,current)
   replies:=nc.client_take_outgoing(&c.nc_client)
   for p in replies { nc.server_receive(&ns.srv,nc.Address(index+1),p.data,current) }
   nc.outgoing_free(&replies)
  }
 }
 join(&ns,&host,0,ns.real_host_token)
 deliver(&ns,&host,0,0.01)
 testing.expect(t,host.real_has_settings && host.real_is_host && host.real_settings.blast_radius==5)
 w:nc.Writer;nc.writer_init(&w);defer nc.writer_destroy(&w)
 nc.write_u8(&w,NET_APP_HOST_COMMAND);nc.write_u8(&w,NET_HOST_BOMB_RADIUS);nc.write_f32(&w,2)
 testing.expect(t,net_host_apply_command(&ns,0,w.data[:])=="")
 testing.expect(t,net_host_apply_command(&ns,0,[]u8{NET_APP_HOST_COMMAND,NET_HOST_MODE,1})=="")
 deliver(&ns,&host,0,0.02)
 testing.expect(t,host.real_settings.blast_radius==2 && host.real_settings.blast_mode==.Falling_Bombs)
 join(&ns,&guest,1,"");deliver(&ns,&guest,1,0.03)
 testing.expect(t,guest.real_has_settings && !guest.real_is_host && guest.real_settings.blast_radius==2 && guest.real_settings.blast_mode==.Falling_Bombs)
 testing.expect(t,net_host_apply_command(&ns,1,[]u8{NET_APP_HOST_COMMAND,NET_HOST_MODE,0})=="host only")
 previous:=guest.real_settings
 nc.writer_reset(&w);nc.write_u8(&w,NET_APP_SETTINGS);nc.write_u8(&w,0);nc.write_f32(&w,50)
 testing.expect(t,net_app_client_control(&guest,w.data[:]) && guest.real_settings==previous)
 for n in 1..<len(w.data) { testing.expect(t,net_app_client_control(&guest,w.data[:n]) && guest.real_settings==previous) }
}
