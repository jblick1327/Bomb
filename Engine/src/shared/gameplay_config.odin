package shared
import math "core:math"
Gameplay_Config :: struct { version:u32, gravity:Vec2, player:Player_Tuning, bomb_fuse,bomb_drop_min,bomb_drop_max:f32 }
DEFAULT_GAMEPLAY_CONFIG :: Gameplay_Config{1,{0,-9.8},PLAYER_TUNING,BOMB_FUSE,BOMB_DROP_MIN,BOMB_DROP_MAX}
gameplay_config_valid :: proc(c:Gameplay_Config) -> bool {
 return c.version==1&&valid_vec(c.gravity)&&math.abs(c.gravity.x)<=100&&math.abs(c.gravity.y)<=100&&
  in_range(c.player.speed,.1,30)&&in_range(c.player.acceleration,.1,200)&&in_range(c.player.jump_speed,.1,30)&&in_range(c.player.coyote_time,0,1)&&in_range(c.player.jump_buffer,0,1)&&
  in_range(c.bomb_fuse,.1,30)&&in_range(c.bomb_drop_min,.05,60)&&in_range(c.bomb_drop_max,c.bomb_drop_min,60)
}
scene_gameplay_config :: proc(s:^Scene) -> Gameplay_Config { if s.level_policy.active { return s.level_policy.config };return DEFAULT_GAMEPLAY_CONFIG }
player_tuning :: proc(p:^Player) -> Player_Tuning { if p.tuning.acceleration>0 { return p.tuning };return PLAYER_TUNING }
