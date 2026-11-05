package main

import "core:encoding/json"
import "core:strings"

// Legacy (v3) World captures differ from v4 only in the player block. A v3 capture
// and a v4 capture of the same state are equivalent when their Scene sections are
// byte-identical and the non-scene fields (player 0, bombs, rain, settings, tick)
// are bit-equal once re-encoded with the exact writer.

// The text of the top-level "scene" object, braces included.
world_scene_section :: proc(data: []byte) -> (string,bool) {
 text:=string(data)
 key:=`"scene":`
 start:=strings.index(text,key); if start<0 { return "",false }
 i:=start+len(key)
 for i<len(text) && (text[i]==' ' || text[i]=='\n' || text[i]=='\t' || text[i]=='\r') { i+=1 }
 if i>=len(text) || text[i]!='{' { return "",false }
 begin:=i; depth:=0; in_string:=false
 for ; i<len(text); i+=1 {
  c:=text[i]
  if in_string {
   if c==0x5c { i+=1 } else if c==0x22 { in_string=false }
   continue
  }
  switch c {
  case '"': in_string=true
  case '{': depth+=1
  case '}': depth-=1; if depth==0 { return text[begin:i+1],true }
  }
 }
 return "",false
}
Compat_Rest :: struct {
 player: Wire_Player,
 bombs: [dynamic]Wire_Bomb,
 rain: Bomb_Rain,
 settings: Sandbox_Settings,
 tick: u64,
}
world_capture_compatible :: proc(old,fresh: []byte) -> bool {
 if string(old)==string(fresh) { return true }
 old_scene,ok_old:=world_scene_section(old); new_scene,ok_new:=world_scene_section(fresh)
 if !ok_old || !ok_new || old_scene!=new_scene { return false }
 old_wire:=World_Snapshot_V3{}; new_wire:=World_Snapshot{}
 if json.unmarshal(old,&old_wire)!=nil { return false }
 defer { destroy_decoded_snapshot(&old_wire.scene); delete(old_wire.bombs) }
 if json.unmarshal(fresh,&new_wire)!=nil { return false }
 defer { destroy_decoded_snapshot(&new_wire.scene); delete(new_wire.players); delete(new_wire.bombs) }
 if old_wire.version!=3 || new_wire.version!=4 || len(new_wire.players)==0 || new_wire.players[0].index!=0 { return false }
 first:=new_wire.players[0]
 a:=Compat_Rest{player=old_wire.player,bombs=old_wire.bombs,rain=old_wire.rain,settings=old_wire.settings,tick=old_wire.tick}
 b:=Compat_Rest{player={body=first.body,coyote=first.coyote,buffered_jump=first.buffered_jump},bombs=new_wire.bombs,rain=new_wire.rain,settings=new_wire.settings,tick=new_wire.tick}
 // The optional bomb id is a later addition to the format; it is not part of the comparison.
 for &bomb in a.bombs { bomb.id=nil }
 for &bomb in b.bombs { bomb.id=nil }
 bytes_a,ok_a:=exact_json_encode(a,false); defer delete(bytes_a)
 bytes_b,ok_b:=exact_json_encode(b,false); defer delete(bytes_b)
 return ok_a && ok_b && string(bytes_a)==string(bytes_b)
}
