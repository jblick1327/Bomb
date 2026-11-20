package shared
import math "core:math"
Gameplay_Config :: struct {
 version:u32, gravity:Vec2, player:Player_Tuning,
 bomb_fuse,bomb_drop_min,bomb_drop_max,bomb_radius:f32,
 lethal_radius,graze_radius:f32,
 grazes_to_die:u32,
 elimination_start_interval,elimination_end_interval:Vec2,
 elimination_ramp_seconds:f32,
}
DEFAULT_GAMEPLAY_CONFIG :: Gameplay_Config{
 version=5,gravity={0,-9.8},player=PLAYER_TUNING,
 bomb_fuse=BOMB_FUSE,bomb_drop_min=BOMB_DROP_MIN,bomb_drop_max=BOMB_DROP_MAX,bomb_radius=5,
 lethal_radius=1.2,graze_radius=2.2,
 grazes_to_die=3,
 elimination_start_interval={1,2.5},elimination_end_interval={.4,1},elimination_ramp_seconds=90,
}
gameplay_config_upgrade :: proc(c:Gameplay_Config) -> Gameplay_Config {
 if c.version<1||c.version>4 {return c}
 out:=c
 if c.version==1 {
  out=DEFAULT_GAMEPLAY_CONFIG
  out.gravity=c.gravity;out.player=c.player;out.bomb_fuse=c.bomb_fuse
  out.bomb_drop_min=c.bomb_drop_min;out.bomb_drop_max=c.bomb_drop_max
 }
 // Older configs had no per-body scale. Keep their authored movement intact.
 if c.version<=2 {out.player.gravity_scale=1}
 // D1 applies the new damage zones to old levels without changing their craters.
 if c.version<=3 {out.lethal_radius=DEFAULT_GAMEPLAY_CONFIG.lethal_radius;out.graze_radius=DEFAULT_GAMEPLAY_CONFIG.graze_radius}
 out.version=5;out.grazes_to_die=DEFAULT_GAMEPLAY_CONFIG.grazes_to_die
 return out
}
gameplay_config_valid :: proc(c:Gameplay_Config) -> bool {
 return c.version==5&&valid_vec(c.gravity)&&math.abs(c.gravity.x)<=100&&math.abs(c.gravity.y)<=100&&
  in_range(c.player.speed,.1,30)&&in_range(c.player.acceleration,.1,200)&&in_range(c.player.jump_speed,.1,30)&&in_range(c.player.coyote_time,0,1)&&in_range(c.player.jump_buffer,0,1)&&in_range(c.player.gravity_scale,.1,10)&&
  in_range(c.bomb_fuse,.1,30)&&in_range(c.bomb_drop_min,.05,60)&&in_range(c.bomb_drop_max,c.bomb_drop_min,60)&&in_range(c.bomb_radius,.5,6)&&
  in_range(c.lethal_radius,.1,6)&&in_range(c.graze_radius,c.lethal_radius,6)&&c.grazes_to_die>=1&&c.grazes_to_die<=255&&
  in_range(c.elimination_start_interval.x,.05,60)&&in_range(c.elimination_start_interval.y,c.elimination_start_interval.x,60)&&
  in_range(c.elimination_end_interval.x,.05,60)&&in_range(c.elimination_end_interval.y,c.elimination_end_interval.x,60)&&in_range(c.elimination_ramp_seconds,1.0/60,3600)
}
elimination_bomb_interval :: proc(c:Gameplay_Config,tick:u64) -> Vec2 {
 duration:=max(u64(1),u64(math.round(f64(c.elimination_ramp_seconds)*60)))
 if tick==0 {return c.elimination_start_interval}
 if tick>=duration {return c.elimination_end_interval}
 fraction:=f32(f64(min(tick,duration))/f64(duration))
 return vadd(c.elimination_start_interval,vmul(vsub(c.elimination_end_interval,c.elimination_start_interval),fraction))
}
scene_gameplay_config :: proc(s:^Scene) -> Gameplay_Config { if s.level_policy.active { return s.level_policy.config };return DEFAULT_GAMEPLAY_CONFIG }
player_tuning :: proc(p:^Player) -> Player_Tuning { if p.tuning.acceleration>0 { return p.tuning };return PLAYER_TUNING }
