package shared

import "base:runtime"
import "core:thread"
import "core:sync"
import "core:time"
import "core:fmt"

// Real dedicated servers use the process heap. Each job owns one independent
// physics world. Layout data is immutable and borrowed until the build joins.
// Box2D world creation/destruction is serialized by the single build/cleanup
// pipeline; the active world is only simulated by the server thread.
// https://box2d.org/documentation/md_foundation.html (Multithreading multiple worlds)
Net_Rebuild_Job :: struct {
 worker:^thread.Thread,
 world:World,
 layout:Layout,
 cleanup,success:bool,
 cancelled:b32,
 test_gate:^b32,
 started:time.Tick,
 request_id,request_incarnation:u64,request_client:int,
}

net_rebuild_worker :: proc(t:^thread.Thread) {
 job:=cast(^Net_Rebuild_Job)t.data
 if job.cleanup {
  scene_destroy(&job.world.scene);delete(job.world.bombs);job.world={}
  return
 }
 if job.test_gate!=nil {
  for !sync.atomic_load(job.test_gate) && !sync.atomic_load(&job.cancelled) {time.sleep(time.Millisecond)}
 }
 if sync.atomic_load(&job.cancelled) {return}
 world_rebuild_layout(&job.world,&job.layout,false)
 job.success=job.world.rebuild_error==""
}

net_rebuild_free :: proc(job:^Net_Rebuild_Job,destroy_world:bool) {
 context=runtime.default_context()
 if job==nil {return}
 if job.worker!=nil {thread.join(job.worker);thread.destroy(job.worker)}
 if destroy_world {scene_destroy(&job.world.scene);delete(job.world.bombs)}
 free(job)
}

net_rebuild_pending :: proc(ns:^Net_Server) -> bool {return ns.rebuild!=nil || ns.rebuild_cleanup!=nil}

net_rebuild_begin :: proc(ns:^Net_Server) -> string {
 // This path is enabled only by the real, process-heap dedicated server.
 context=runtime.default_context()
 if net_rebuild_pending(ns) {return "world rebuild already in progress"}
 if ns.game.world.scene.epoch==max(u32) {return "world epoch exhausted"}
 job:=new(Net_Rebuild_Job)
 job.layout=ns.game.layout
 job.world.settings=ns.game.world.settings
 job.world.scene.epoch=ns.game.world.scene.epoch
 job.world.scene.revision=ns.game.world.scene.revision
 // Preserve the config identity while choosing whether a rebuilt level needs
 // its initial radius. A same-level reset must retain authorized host tuning.
 job.world.scene.level_policy=ns.game.world.scene.level_policy
 job.world.scene.config_hash=ns.game.world.scene.config_hash
 job.started=time.tick_now();job.test_gate=ns.rebuild_test_gate
 // Normal priority (P1, 2026-11-24): at .Low a busy host (server plus game windows) starved a 0.4 s build to 6-22 s,
 // and players wait for it between rounds. The build is a few hundred ms and runs beside the server thread.
 job.worker=thread.create(net_rebuild_worker,.Normal)
 if job.worker==nil {free(job);return "cannot start world rebuild"}
 ns.rebuild=job;job.worker.data=job;thread.start(job.worker)
 if ns.real_logging {fmt.printf("REBUILD START epoch=%d tick=%d\n",ns.game.world.scene.epoch+1,ns.tick)}
 return ""
}

net_rebuild_poll :: proc(ns:^Net_Server) {
 context=runtime.default_context()
 if ns.rebuild_cleanup!=nil && thread.is_done(ns.rebuild_cleanup.worker) {
  net_rebuild_free(ns.rebuild_cleanup,false);ns.rebuild_cleanup=nil
 }
 job:=ns.rebuild
 if job==nil || !thread.is_done(job.worker) {return}
 thread.join(job.worker)
 if !job.success {
  net_rebuild_finish_request(ns,job,false)
  ns.round_mode_pending=false;ns.round_dirty=true
  if ns.real_logging {fmt.printf("REBUILD FAILED: %s\n",job.world.rebuild_error)}
  net_rebuild_free(job,true);ns.rebuild=nil
  return
 }
 // Publish only a completely constructed world. Existing physics/networking
 // continue on the old epoch during construction. No partial scene is sent.
 old:=ns.game.world
 // Synchronous resets retain this session-wide sequence. Include bombs spawned
 // in the active world while the replacement was being constructed.
 job.world.next_bomb_id=old.next_bomb_id
 job.world.scene.revision=old.scene.revision+1
 ns.game.world=job.world;job.world={};ns.rebuild=nil
 net_host_trim_players(ns)
 for i in 0..<len(ns.clients) {if ns.clients[i].active {if !ns.game.world.players[i].active {_=world_add_player(&ns.game.world,i)};ns.game.world.players[i].blast_radius=ns.clients[i].radius}}
 round_server_after_rebuild(ns)
 net_rebuild_finish_request(ns,job,true)
 if ns.real_logging {fmt.printf("REBUILD COMMIT epoch=%d tick=%d build_ms=%.3f\n",ns.game.world.scene.epoch,ns.tick,time.duration_seconds(time.tick_since(job.started))*1000)}
 net_rebuild_free(job,false)
 // Destroy the detached old world without blocking transport. Do not accept
 // another build until this finishes, so world lifecycle calls cannot overlap.
 cleanup:=new(Net_Rebuild_Job);cleanup.cleanup=true;cleanup.world=old
 cleanup.worker=thread.create(net_rebuild_worker,.Low)
 if cleanup.worker==nil {net_rebuild_free(cleanup,true);return}
 ns.rebuild_cleanup=cleanup;cleanup.worker.data=cleanup;thread.start(cleanup.worker)
}

net_rebuild_destroy :: proc(ns:^Net_Server) {
 context=runtime.default_context()
 if ns.rebuild!=nil {sync.atomic_store(&ns.rebuild.cancelled,true);net_rebuild_free(ns.rebuild,true);ns.rebuild=nil}
 if ns.rebuild_cleanup!=nil {net_rebuild_free(ns.rebuild_cleanup,false);ns.rebuild_cleanup=nil}
}

net_rebuild_finish_request :: proc(ns:^Net_Server,job:^Net_Rebuild_Job,accepted:bool) {
 if job.request_id==0 {return}
 c:=&ns.clients[job.request_client]
 if !c.active||c.incarnation!=job.request_incarnation||c.requests==nil {return}
 result:=Request_Result{request_id=job.request_id,effect_tick=ns.tick+1,status=.Accepted}
 if !accepted {result.status=.Rejected;result.reason=2}
 if request_cache_finish(c.requests,result) {net_request_send_result(ns,job.request_client,NET_APP_HOST_COMMAND,result)}
}
