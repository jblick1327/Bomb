package main

import nc "netcode"

// Optional reference/test input source. The shared client has no bot state.
net_bot_client_input :: proc(c: ^Net_Client,data: rawptr) {
 bot:=cast(^Bot)data
 c.human_move=0; c.human_jump_pending=false
 if bot==nil || c.idle || !c.has_epoch || !c.has_complete { return }
 index:=c.nc_client.client_index
  position:Vec2; have:=false
  if d,ok:=c.drawn[ent_key(.Player,u64(index))]; ok { position={d.x,d.y}; have=true }
  else if f:=&c.ring[c.newest_complete%NET_CLIENT_RING]; f.valid { if s,ok:=f.table[ent_key(.Player,u64(index))]; ok { position={pose_dq_pos(s.x),pose_dq_pos(s.y)}; have=true } }
  if have {
   commands:Player_Commands
   bot_step_scene(bot,&c.rep.scene,position,f32(NET_STEP_DT),&commands)
   c.human_move=commands.move
   c.human_jump_pending=commands.jump
   for point in commands.blasts {
    c.blast_seq+=1
    if len(c.blasts)>=NET_MAX_BLASTS { ordered_remove(&c.blasts,0); c.stats.blasts_dropped+=1 }
    append(&c.blasts,Net_Blast{seq=c.blast_seq,x=nc.quantize_pos(point.x),y=nc.quantize_pos(point.y),radius_q=c.radius_q})
    c.stats.blasts_issued+=1
   }
   delete(commands.blasts)
  }

}
