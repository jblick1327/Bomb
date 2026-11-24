package shared

import b2 "vendor:box2d"
import rand "core:math/rand"
import math "core:math"

// N4 (D6) Elimination items. Values follow Darryn's AlphaV0.1 BombDropper,
// FallingCollectibleItem and ArenaPlayerController defaults. Every rule here is
// server-side; clients receive items as actors and effects in the round snapshot.
Item_Kind :: enum u8 { None, Silver_Coin, Gold_Coin, Invincibility, Slow, Speed_Boost }
Speed_Effect :: enum u8 { None, Boost, Slow }

Item_Tuning :: struct {
 first_interval,interval:Vec2, // seconds, uniform [x,y]
 silver_chance,gold_chance:f32, // the rest is shared evenly by the three effects
 silver_value,gold_value:u32,
 effect_ticks:u32,
 boost_scale,slow_scale:f32,
 fall_acceleration:f32,
 lifetime_ticks:u32,
}
// First item 3..min(8,12) s after the round starts, then every 12..20 s.
ITEM_TUNING :: Item_Tuning{first_interval={3,8},interval={12,20},silver_chance=.25,gold_chance=.15,silver_value=10,gold_value=50,effect_ticks=600,boost_scale=1.5,slow_scale=.5,fall_acceleration=18,lifetime_ticks=900}
ITEM_RADIUS :: f32(0.35)
ITEM_SLOTS :: 4 // lifetime 15 s / minimum interval 12 s: at most two coexist.

Item :: struct {
 id:u64,
 kind:Item_Kind,
 position:Vec2,
 fall_speed:f32,
 landed:bool,
 ticks_left:u32,
}
Item_Rain :: struct {
 random:rand.Default_Random_State,
 until_spawn:u64, // ticks
 next_id:u64,
 items:[ITEM_SLOTS]Item, // compacted, ascending id
 count:int,
}

item_seconds_ticks :: proc(seconds:f32) -> u64 { return u64(max(f64(1),math.round(f64(seconds)*60))) }

// A separate stream from bomb drops and destruction seeds, so adding items
// leaves the existing bomb schedule unchanged.
item_rain_reset :: proc(rain:^Item_Rain,seed:u8) {
 rain^={}
 rain.random=rand.create(u64(seed)+0x6974656d)
 t:=ITEM_TUNING
 rain.until_spawn=item_seconds_ticks(rand.float32_range(t.first_interval.x,min(t.first_interval.y,t.interval.x),rand.default_random_generator(&rain.random)))
}

item_pick_kind :: proc(rain:^Item_Rain) -> Item_Kind {
 t:=ITEM_TUNING;gen:=rand.default_random_generator(&rain.random)
 roll:=rand.float32(gen)
 if roll<t.silver_chance {return .Silver_Coin}
 if roll<t.silver_chance+t.gold_chance {return .Gold_Coin}
 return Item_Kind(u8(Item_Kind.Invincibility)+u8(min(rand.float32(gen)*3,2)))
}

item_spawn :: proc(w:^World) {
 rain:=&w.items
 lo,hi,height:=f32(-7),f32(8),BOMB_SKY_HEIGHT
 if w.scene.level_policy.active {limits:=w.scene.level_policy.bombs;lo=limits.spawn_x.x;hi=limits.spawn_x.y;height=limits.spawn_height}
 gen:=rand.default_random_generator(&rain.random)
 x:=rand.float32_range(lo,hi,gen)
 kind:=item_pick_kind(rain)
 rain.next_id+=1
 if rain.count==ITEM_SLOTS { // unreachable with Darryn's timings; drop the oldest
  copy(rain.items[:ITEM_SLOTS-1],rain.items[1:]);rain.count-=1
 }
 rain.items[rain.count]=Item{id=rain.next_id,kind=kind,position={x,height},ticks_left=ITEM_TUNING.lifetime_ticks}
 rain.count+=1
}

Item_Cast :: struct { fraction:f32, hit:bool }
item_cast_callback :: proc "c" (shape:b2.ShapeId,point,normal:b2.Vec2,fraction:f32,ctx:rawptr) -> f32 {
 // Players collect items; bombs are transient. Items land on structure and floors.
 if b2.Shape_GetFilter(shape).groupIndex<0 {return -1}
 if b2.Body_IsBullet(b2.Shape_GetBody(shape)) {return -1}
 hitinfo:=(^Item_Cast)(ctx)
 if !hitinfo.hit || fraction<hitinfo.fraction {hitinfo.fraction=fraction;hitinfo.hit=true}
 return fraction
}

// Falls at Darryn's constant acceleration with x fixed, stops on the first
// surface below, and stays there until the next detonation resumes the fall.
item_fall :: proc(w:^World,item:^Item,dt:f32) {
 if item.landed || !w.scene.physics.active {return}
 item.fall_speed+=ITEM_TUNING.fall_acceleration*dt
 distance:=item.fall_speed*dt
 if distance<=0 {return}
 proxy:=b2.MakeProxy({to_b2(item.position)},ITEM_RADIUS)
 hitinfo:=Item_Cast{}
 _=b2.World_CastShape(w.scene.physics.world,proxy,{0,-distance},STRUCTURE_QUERY_FILTER,item_cast_callback,&hitinfo) // also sees frozen debris
 if hitinfo.hit {
  item.position.y-=distance*max(f32(0),hitinfo.fraction);item.landed=true;item.fall_speed=0
 }else{item.position.y-=distance}
}

item_outside :: proc(w:^World,p:Vec2) -> bool {
 if w.scene.level_policy.active {return !level_bounds_contains(w.scene.level_policy.bombs.cleanup_bounds,p)}
 return p.y < -3 || p.x < -9 || p.x > 10
}

// Inclusive capsule/circle overlap with the upright native player capsule.
item_capsule_overlap :: proc(center,item:Vec2) -> bool {
 if !valid_vec(center) || !valid_vec(item) {return false}
 nearest:=Vec2{center.x,clamp(item.y,center.y-PLAYER_SEGMENT,center.y+PLAYER_SEGMENT)}
 delta:=vsub(item,nearest);reach:=f64(PLAYER_RADIUS)+f64(ITEM_RADIUS)
 return f64(delta.x)*f64(delta.x)+f64(delta.y)*f64(delta.y)<=reach*reach
}

item_apply :: proc(player:^Player,kind:Item_Kind) {
 t:=ITEM_TUNING
 switch kind {
 case .None:
 case .Silver_Coin: player.coins+=t.silver_value
 case .Gold_Coin: player.coins+=t.gold_value
 case .Invincibility: player.invincible_ticks=t.effect_ticks
 case .Slow: player.speed_effect=.Slow;player.speed_ticks=t.effect_ticks
 case .Speed_Boost: player.speed_effect=.Boost;player.speed_ticks=t.effect_ticks
 }
}

// One Elimination tick, after the physics step and before bomb detonations:
// spawn, fall, expire, then collect in ascending item id and player index.
item_rain_step :: proc(w:^World,dt:f32,events:^Tick_Events) {
 rain:=&w.items
 if rain.until_spawn>0 {rain.until_spawn-=1}
 if rain.until_spawn==0 {
  item_spawn(w)
  t:=ITEM_TUNING
  rain.until_spawn=item_seconds_ticks(rand.float32_range(t.interval.x,t.interval.y,rand.default_random_generator(&rain.random)))
 }
 kept:=0
 for i in 0..<rain.count {
  item:=rain.items[i]
  if item.ticks_left==0 {continue} // present for exactly lifetime_ticks world ticks
  item.ticks_left-=1
  item_fall(w,&item,dt)
  collected:=false
  for &player,p in w.players {
   if !player.active || events.deaths[p]!=.None {continue}
   if item_capsule_overlap(from_b2(b2.Body_GetPosition(player.body)),item.position) {item_apply(&player,item.kind);collected=true;break}
  }
  if collected || item_outside(w,item.position) {continue}
  rain.items[kept]=item;kept+=1
 }
 for i in kept..<rain.count {rain.items[i]={}}
 rain.count=kept
}

item_rain_resume :: proc(rain:^Item_Rain) { for &item in rain.items[:rain.count] {item.landed=false} }

player_speed_scale :: proc(p:^Player) -> f32 {
 if p.speed_ticks==0 {return 1}
 #partial switch p.speed_effect {
 case .Boost: return ITEM_TUNING.boost_scale
 case .Slow: return ITEM_TUNING.slow_scale
 }
 return 1
}
