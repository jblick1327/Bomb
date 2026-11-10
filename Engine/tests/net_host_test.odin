package main

import nc "netcode"
import "core:testing"

// Verify application-layer denial before any scene mutation, and atomic
// layout decoding before replacing the server's authoritative Test world.
@(test)
test_step3_host_mutations_authorized_and_atomic :: proc(t: ^testing.T) {
 ns,ok:=net_real_create_server("")
 testing.expect(t,ok)
 if !ok { return }
 defer net_server_destroy(&ns)
 ns.clients[0].active=true
 ns.clients[0].is_host=true
 ns.clients[1].active=true
 before_epoch:=ns.game.world.scene.epoch
 before_count:=len(ns.game.layout.objects)
 data:[dynamic]u8;defer delete(data)
 append(&data,NET_APP_LAYOUT_UPLOAD)
 append(&data,..transmute([]u8)PRESET_LAYOUTS[1])
 denied:=net_host_apply_layout(&ns,1,data[:])
 testing.expect(t,denied=="host only")
 testing.expect(t,ns.game.world.scene.epoch==before_epoch)
 testing.expect(t,len(ns.game.layout.objects)==before_count)
 malformed:=[]u8{NET_APP_LAYOUT_UPLOAD,'{','}'}
 rejected:=net_host_apply_layout(&ns,0,malformed)
 testing.expect(t,rejected!="")
 testing.expect(t,ns.game.world.scene.epoch==before_epoch)
 testing.expect(t,len(ns.game.layout.objects)==before_count)
 approved:=net_host_apply_layout(&ns,0,data[:])
 testing.expect(t,approved=="")
 testing.expect(t,ns.game.world.scene.epoch>before_epoch)
 testing.expect(t,len(ns.game.layout.objects)>before_count)
 next_epoch:=ns.game.world.scene.epoch
 testing.expect(t,net_host_apply_command(&ns,1,[]u8{NET_APP_HOST_COMMAND,NET_HOST_RESET})=="host only")
 testing.expect(t,ns.game.world.scene.epoch==next_epoch)
 testing.expect(t,net_host_apply_command(&ns,0,[]u8{NET_APP_HOST_COMMAND,NET_HOST_RESET})=="")
 testing.expect(t,ns.game.world.scene.epoch>next_epoch)
}

@(test)
test_step3_host_mode_and_radius_validation :: proc(t: ^testing.T) {
 ns,ok:=net_real_create_server("")
 testing.expect(t,ok)
 if !ok { return }
 defer net_server_destroy(&ns)
 ns.clients[0].active=true;ns.clients[0].is_host=true
 ns.clients[0].radius=3.0
 testing.expect(t,net_host_apply_command(&ns,0,[]u8{NET_APP_HOST_COMMAND,NET_HOST_MODE,255})!="")
 testing.expect(t,ns.game.world.settings.blast_mode==.Manual)
 testing.expect(t,net_host_apply_command(&ns,0,[]u8{NET_APP_HOST_COMMAND,NET_HOST_MODE,1})=="")
 testing.expect(t,ns.game.world.settings.blast_mode==.Falling_Bombs)
 wr:nc.Writer;nc.writer_init(&wr,12);defer nc.writer_destroy(&wr)
 nc.write_u8(&wr,NET_APP_HOST_COMMAND);nc.write_u8(&wr,NET_HOST_BOMB_RADIUS);nc.write_f32(&wr,4.0)
 testing.expect(t,net_host_apply_command(&ns,0,wr.data[:])=="")
 testing.expect(t,ns.game.world.settings.blast_radius==4.0)
 testing.expect(t,ns.clients[0].radius==4.0)
 ns.real_gate=true
 input:=Net_Input{seq=1,radius_q=radius_quantize(2.0)}
 net_server_input(&ns,0,input)
 testing.expect(t,ns.clients[0].radius==4.0) // untrusted per-player radius ignored
 nc.writer_reset(&wr)
 nc.write_u8(&wr,NET_APP_HOST_COMMAND);nc.write_u8(&wr,NET_HOST_BOMB_RADIUS);nc.write_f32(&wr,50.0)
 testing.expect(t,net_host_apply_command(&ns,0,wr.data[:])!="")
 testing.expect(t,ns.game.world.settings.blast_radius==4.0)
}
