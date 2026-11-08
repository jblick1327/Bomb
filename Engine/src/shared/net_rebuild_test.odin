package shared
import "base:runtime"
import t "core:testing"
import "core:sync"
import "core:time"
import b2 "vendor:box2d"

net_test_rebuild_server :: proc()->Net_Server {
 context=runtime.default_context()
 game:=Headless_Game{world=World{settings=DEFAULT_SANDBOX_SETTINGS},layout=Layout{next_identity=1}}
 world_rebuild_layout(&game.world,&game.layout,false)
 server:Net_Server;net_server_init_world(&server,game,false);server.async_rebuild=true
 return server
}

@(test)
background_reset_keeps_old_world_live_and_publishes_one_complete_epoch :: proc(test:^t.T) {
 // Real server jobs use the process heap. Verify Box2D's owned byte counter
 // after joining both workers, in addition to the synchronous allocator suite.
 context=runtime.default_context()
 bytes:=b2.GetByteCount();server:=net_test_rebuild_server();live:=true
 defer {if live {net_server_destroy(&server)}}
 gate:b32;server.rebuild_test_gate=&gate
 net_server_join(&server,1);server.clients[1].is_host=true
 epoch:=server.game.world.scene.epoch;old:=server.game.world.scene.physics.world
 command:=[2]u8{NET_APP_HOST_COMMAND,NET_HOST_RESET}
 t.expect(test,net_host_apply_command(&server,1,command[:])=="")
 t.expect(test,net_host_apply_command(&server,1,command[:])=="world rebuild already in progress")
 for i in 0..<12 {net_server_tick(&server,f64(i)/60)}
 t.expect(test,server.tick==12 && server.game.world.tick==12 && server.game.world.scene.epoch==epoch)
 t.expect(test,server.game.world.scene.physics.world==old && b2.World_IsValid(old))
 // Join while the new world is being built: commit uses the current player set.
 net_server_join(&server,2)
 sync.atomic_store(&gate,true)
 start:=time.tick_now()
 for net_rebuild_pending(&server) && time.duration_seconds(time.tick_since(start))<5 {net_rebuild_poll(&server);time.sleep(time.Millisecond)}
 t.expect(test,!net_rebuild_pending(&server) && server.game.world.scene.epoch==epoch+1 && server.game.world.tick==0)
 t.expect(test,server.game.world.players[1].active && server.game.world.players[2].active && !server.game.world.players[0].active)
 t.expect(test,!b2.World_IsValid(old) && b2.World_IsValid(server.game.world.scene.physics.world))
 net_rebuild_poll(&server);t.expect(test,server.game.world.scene.epoch==epoch+1)
 net_server_destroy(&server);live=false
 t.expect(test,b2.GetByteCount()==bytes)
}

@(test)
background_reset_shutdown_cancels_held_work_and_joins_without_leaking_worlds :: proc(test:^t.T) {
 context=runtime.default_context()
 bytes:=b2.GetByteCount();server:=net_test_rebuild_server();gate:b32;server.rebuild_test_gate=&gate
 t.expect(test,net_rebuild_begin(&server)=="")
 net_server_destroy(&server)
 t.expect(test,server.rebuild==nil && server.rebuild_cleanup==nil && b2.GetByteCount()==bytes)
}
