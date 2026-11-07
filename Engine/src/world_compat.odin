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
 if !ok_old || !ok_new {
  a,b:Snapshot
  defer destroy_decoded_snapshot(&a);defer destroy_decoded_snapshot(&b)
  if json.unmarshal(old,&a)!=nil||json.unmarshal(fresh,&b)!=nil { return false }
  return legacy_scene_migration_identical(&a,&b)
 }
 old_wire,new_wire:World_Snapshot
 if json.unmarshal(old,&old_wire)!=nil { return false }
 defer { destroy_decoded_snapshot(&old_wire.scene); delete(old_wire.players);delete(old_wire.bombs) }
 if old_wire.version==3 {
  legacy:World_Snapshot_V3
  if json.unmarshal(old,&legacy)!=nil { destroy_decoded_snapshot(&legacy.scene);delete(legacy.bombs);return false }
  destroy_decoded_snapshot(&old_wire.scene);delete(old_wire.bombs)
  old_wire.scene=legacy.scene;old_wire.bombs=legacy.bombs
  append(&old_wire.players,Wire_Player_Entry{index=0,body=legacy.player.body,coyote=legacy.player.coyote,buffered_jump=legacy.player.buffered_jump,blast_radius=legacy.settings.blast_radius})
 }
 if json.unmarshal(fresh,&new_wire)!=nil { return false }
 defer { destroy_decoded_snapshot(&new_wire.scene); delete(new_wire.players); delete(new_wire.bombs) }
 if old_scene!=new_scene&&!legacy_scene_migration_identical(&old_wire.scene,&new_wire.scene) { return false }
 if (old_wire.version!=3&&old_wire.version!=4)||new_wire.version!=4 { return false }
 Rest :: struct { players:[dynamic]Wire_Player_Entry,bombs:[dynamic]Wire_Bomb,rain:Bomb_Rain,settings:Sandbox_Settings,tick:u64 }
 a:=Rest{old_wire.players,old_wire.bombs,old_wire.rain,old_wire.settings,old_wire.tick}
 b:=Rest{new_wire.players,new_wire.bombs,new_wire.rain,new_wire.settings,new_wire.tick}
 // The optional bomb id is a later addition to the format; it is not part of the comparison.
 if old_wire.version==3 { for &bomb in a.bombs { bomb.id=nil };for &bomb in b.bombs { bomb.id=nil } }
 bytes_a,ok_a:=exact_json_encode(a,false); defer delete(bytes_a)
 bytes_b,ok_b:=exact_json_encode(b,false); defer delete(bytes_b)
 return ok_a && ok_b && string(bytes_a)==string(bytes_b)
}

// Scene v3 adds provenance/catalog fields. For historical legacy fixtures only,
// compare every pre-existing field using exact f32/u64 serialization. Do not
// normalize geometry, material, pose, ownership or simulation values. Authored
// policies/catalogs cannot use this migration exception.
legacy_scene_migration_identical :: proc(a,b:^Snapshot) -> bool {
 if a.version!=2||b.version!=3||a.level_json!=""||b.level_json!=""||len(a.source_parts)!=0||len(b.source_parts)!=0 { return false }
 for sub in b.subdivisions { if sub.provenance.motion!=.Legacy||sub.provenance.damage!=.Destructible { return false } }
 aa,bb:=legacy_scene_physics_bytes(a),legacy_scene_physics_bytes(b);defer delete(aa);defer delete(bb)
 return aa!=nil&&bb!=nil&&string(aa)==string(bb)
}
legacy_scene_physics_bytes :: proc(view:^Snapshot) -> []u8 {
 wire:=Legacy_Scene_Wire{version=2,next_id=view.next_id,revision=view.revision,minimum_width=view.minimum_width,materials=view.materials,connections=view.connections,pieces=view.pieces}
 defer delete(wire.subdivisions)
 for sub in view.subdivisions { item:=Snapshot_Cell{id=sub.id,owner=sub.owner,material=sub.material,seed=sub.seed,outline=sub.outline,rest_center=sub.rest_center,pose=sub.pose,live=sub.live};if sub.frame!=0 { item.frame=sub.frame };append(&wire.subdivisions,item) }
 bytes,ok:=exact_json_encode(wire,false);if !ok { delete(bytes);return nil };return bytes
}
