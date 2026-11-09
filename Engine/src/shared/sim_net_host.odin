#+feature dynamic-literals
package shared

import nc "../netcode"
import fmt "core:fmt"

NET_APP_HOST_COMMAND :: u8(0xC6)

NET_APP_LAYOUT_UPLOAD :: u8(0xC7)

NET_APP_MAX_LAYOUT :: 200_000 // safely below netcode's reliable-message cap

NET_HOST_RESET :: u8(1)

NET_HOST_MODE :: u8(2)

NET_HOST_BOMB_RADIUS :: u8(3)
NET_HOST_GAME_MODE :: u8(4)

net_host_trim_players :: proc(ns: ^Net_Server) {
 for i in 0..<nc.MAX_CLIENTS {
  if !ns.clients[i].active { _=world_remove_player(&ns.game.world,i) }
 }
}

net_host_apply_layout :: proc(ns: ^Net_Server,index: int,data: []u8) -> string {
 if !ns.clients[index].active || !ns.clients[index].is_host { return "host only" }
 if ns.rounds.mode==.Elimination {return "layout upload requires sandbox mode"}
 if net_rebuild_pending(ns) {return "world rebuild already in progress"}
 if len(data)<2 || len(data)-1>NET_APP_MAX_LAYOUT || data[0]!=NET_APP_LAYOUT_UPLOAD { return "invalid layout upload size" }
 layout,seed,ok,problem:=decode_layout(data[1:])
 if !ok { return problem }
 destroy_layout(&ns.game.layout)
 ns.game.layout=layout
 ns.game.world.settings.seed=seed
 headless_game_reset(&ns.game)
 net_host_trim_players(ns)
 if ns.real_logging { fmt.printf("LAYOUT OK client=%d epoch=%d objects=%d\n",index,ns.game.world.scene.epoch,len(ns.game.layout.objects)) }
 return ""
}

net_host_apply_command :: proc(ns: ^Net_Server,index: int,data: []u8) -> string {
 if !ns.clients[index].active || !ns.clients[index].is_host { return "host only" }
 if net_rebuild_pending(ns) {return "world rebuild already in progress"}
 if len(data)<2 || data[0]!=NET_APP_HOST_COMMAND { return "invalid host command" }
 switch data[1] {
 case NET_HOST_RESET:
  if len(data)!=2 { return "invalid reset command" }
  if ns.rounds.mode==.Elimination && ns.rounds.state!=.Finished {return "round restart requires a finished round"}
  if ns.rounds.id==max(u64) {return "round identity exhausted"}
  if ns.async_rebuild {return net_rebuild_begin(ns)}
  headless_game_reset(&ns.game)
  net_host_trim_players(ns)
  round_server_after_rebuild(ns)
 case NET_HOST_GAME_MODE:
  if len(data)!=3 || data[2]>u8(Game_Mode.Elimination) {return "invalid game mode"}
  if ns.rounds.mode==.Elimination && ns.rounds.state!=.Finished && ns.rounds.state!=.Waiting {return "cannot change mode during an active round"}
  if ns.rounds.id==max(u64) {return "round identity exhausted"}
  ns.round_mode_pending=true;ns.round_next_mode=Game_Mode(data[2])
  if ns.async_rebuild {
   reason:=net_rebuild_begin(ns)
   if reason!="" {ns.round_mode_pending=false}
   return reason
  }
  headless_game_reset(&ns.game);net_host_trim_players(ns);round_server_after_rebuild(ns)
 case NET_HOST_MODE:
  if ns.rounds.mode==.Elimination {return "manual tools require sandbox mode"}
  if len(data)!=3 || data[2]>1 { return "invalid blast mode" }
  headless_game_mode(&ns.game,Blast_Mode(data[2]))
 case NET_HOST_BOMB_RADIUS:
  if ns.rounds.mode==.Elimination && ns.rounds.state!=.Waiting && ns.rounds.state!=.Finished {return "cannot tune an active round"}
  if len(data)!=6 { return "invalid bomb radius" }
  r:nc.Reader;nc.reader_init(&r,data)
  _=nc.read_u8(&r);_=nc.read_u8(&r)
  radius:=nc.read_f32(&r)
  if !r.ok || !finite(radius) || radius<0.5 || radius>6 { return "invalid bomb radius" }
  // In the real-process mode, client-provided blast radius fields are ignored.
  // HOST's value controls both falling bombs and every player's manual blasts.
  ns.game.world.settings.blast_radius=radius
  for &client in ns.clients { if client.active { client.radius=radius } }
  for &player in ns.game.world.players { if player.active { player.blast_radius=radius } }
 case:
  return "unknown host command"
 }
 for i in 0..<nc.MAX_CLIENTS { if ns.clients[i].active { net_host_send_settings(ns,i) } }
 if ns.real_logging { fmt.printf("COMMAND OK client=%d op=%d epoch=%d\n",index,data[1],ns.game.world.scene.epoch) }
 return ""
}

net_host_send_settings :: proc(ns:^Net_Server,index:int) {
 w:nc.Writer;nc.writer_init(&w,8);defer nc.writer_destroy(&w)
 nc.write_u8(&w,NET_APP_SETTINGS)
 nc.write_u8(&w,u8(ns.game.world.settings.blast_mode))
 nc.write_f32(&w,ns.game.world.settings.blast_radius)
 _=nc.server_send_reliable(&ns.srv,index,w.data[:])
}

net_host_send_result :: proc(ns: ^Net_Server,index: int,kind: u8,reason: string) {
 w:nc.Writer;nc.writer_init(&w,64);defer nc.writer_destroy(&w)
 nc.write_u8(&w,NET_APP_COMMAND_RESULT)
 nc.write_u8(&w,kind)
 nc.write_bool(&w,reason=="")
 nc.write_string(&w,reason)
 _=nc.server_send_reliable(&ns.srv,index,w.data[:])
}

net_host_dispatch :: proc(ns: ^Net_Server,index: int,data: []u8) {
 if len(data)==0 { return }
 reason:=""
 switch data[0] {
 case NET_APP_LAYOUT_UPLOAD: reason=net_host_apply_layout(ns,index,data)
 case NET_APP_HOST_COMMAND: reason=net_host_apply_command(ns,index,data)
 case: return
 }
 if reason!="" && ns.real_logging {
  if data[0]==NET_APP_LAYOUT_UPLOAD { fmt.printf("LAYOUT REJECT client=%d reason=%s\n",index,reason) }
  else { fmt.printf("COMMAND REJECT client=%d reason=%s\n",index,reason) }
 }
 net_host_send_result(ns,index,data[0],reason)
}

net_host_client_send_layout :: proc(c: ^Net_Client,data: []u8) -> bool {
 if !c.real_gate || !c.real_hello_ok || len(data)==0 || len(data)>NET_APP_MAX_LAYOUT { return false }
 w:nc.Writer;nc.writer_init(&w,len(data)+8);defer nc.writer_destroy(&w)
 nc.write_u8(&w,NET_APP_LAYOUT_UPLOAD)
 nc.write_raw(&w,data)
 return net_request_client_send(c,NET_APP_LAYOUT_UPLOAD,w.data[:])
}

net_host_client_send_command :: proc(c: ^Net_Client,op: u8,mode: u8=0,radius: f32=0) -> bool {
 if !c.real_gate || !c.real_hello_ok { return false }
 w:nc.Writer;nc.writer_init(&w,8);defer nc.writer_destroy(&w)
 nc.write_u8(&w,NET_APP_HOST_COMMAND)
 nc.write_u8(&w,op)
 switch op {
 case NET_HOST_RESET:
 case NET_HOST_MODE: nc.write_u8(&w,mode)
 case NET_HOST_GAME_MODE: nc.write_u8(&w,mode)
 case NET_HOST_BOMB_RADIUS: nc.write_f32(&w,radius)
 case: return false
 }
 return net_request_client_send(c,NET_APP_HOST_COMMAND,w.data[:])
}
