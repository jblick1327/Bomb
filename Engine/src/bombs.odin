package main

import b2 "vendor:box2d"
import "core:math/rand"

Blast_Mode :: enum { Manual, Falling_Bombs }
BOMB_RADIUS :: f32(0.18)
BOMB_FUSE :: f32(1)
BOMB_DROP_MIN :: f32(1)
BOMB_DROP_MAX :: f32(2.5)
BOMB_SKY_HEIGHT :: f32(7.3)
BOMB_BURST_TIME :: f32(0.3)

Bomb :: struct {
	body: b2.BodyId,
	previous: Vec2,
	landed: bool,
	fuse: f32,
}
Bomb_Burst :: struct { position: Vec2, radius, age: f32 }
Bomb_Rain :: struct {
	bombs: [dynamic]Bomb,
	bursts: [dynamic]Bomb_Burst,
	random: rand.Default_Random_State,
	until_drop: f32,
}
bomb_drop_delay :: proc(rain: ^Bomb_Rain) -> f32 {
	return rand.float32_range(BOMB_DROP_MIN,BOMB_DROP_MAX,rand.default_random_generator(&rain.random))
}
bomb_rain_reset :: proc(rain: ^Bomb_Rain,seed: u8) {
	// The old physics world has already been destroyed. Keep the small list buffers.
	clear(&rain.bombs); clear(&rain.bursts)
	// A separate stream leaves procedural destruction seeds independent of drops.
	rain.random=rand.create(u64(seed)+0x626f6d62)
	rain.until_drop=bomb_drop_delay(rain)
}
bomb_rain_clear :: proc(rain: ^Bomb_Rain) {
	for bomb in rain.bombs { b2.DestroyBody(bomb.body) }
	clear(&rain.bombs); clear(&rain.bursts)
}
sandbox_set_blast_mode :: proc(game: ^Sandbox,mode: Blast_Mode) {
	if mode==game.applied.blast_mode { return }
	game.applied.blast_mode=mode
	bomb_rain_clear(&game.bomb_rain)
	game.bomb_rain.until_drop=bomb_drop_delay(&game.bomb_rain)
	if mode==.Falling_Bombs { sandbox_notice(game,"Falling bombs: one-second fuse after landing") }
	else { sandbox_notice(game,"Manual blast placement") }
}
bomb_spawn :: proc(game: ^Sandbox,position: Vec2) {
	def:=b2.DefaultBodyDef()
	def.type=.dynamicBody
	def.position=to_b2(position)
	def.isBullet=true
	body:=b2.CreateBody(game.scene.physics.world,def)
	shape:=b2.DefaultShapeDef()
	shape.density=0.4
	shape.material.friction=0.7
	shape.material.restitution=0.05
	_ = b2.CreateCircleShape(body,shape,b2.Circle{radius=BOMB_RADIUS})
	append(&game.bomb_rain.bombs,Bomb{body=body,previous=position,fuse=BOMB_FUSE})
}
bomb_has_landed :: proc(bomb: Bomb) -> bool {
	position:=b2.Body_GetPosition(bomb.body)
	buffer:=make([]b2.ContactData,int(b2.Body_GetContactCapacity(bomb.body)))
	defer delete(buffer)
	for contact in b2.Body_GetContactData(bomb.body,buffer) {
		normal:=from_b2(contact.manifold.normal)
		if b2.Shape_GetBody(contact.shapeIdA)==bomb.body { normal=vmul(normal,-1) }
		if normal.y<0.55 { continue }
		for i in 0..<int(contact.manifold.pointCount) {
			point:=contact.manifold.points[i]
			if point.separation<=0.025 && point.point.y<position.y { return true }
		}
	}
	return false
}
bomb_rain_before_step :: proc(game: ^Sandbox,dt: f32) {
	if game.applied.blast_mode!=.Falling_Bombs { return }
	rain:=&game.bomb_rain
	for &bomb in rain.bombs { bomb.previous=from_b2(b2.Body_GetPosition(bomb.body)) }
	rain.until_drop-=dt
	if rain.until_drop<=0 {
		x:=rand.float32_range(-7,8,rand.default_random_generator(&rain.random))
		bomb_spawn(game,{x,BOMB_SKY_HEIGHT})
		rain.until_drop+=bomb_drop_delay(rain)
	}
}
bomb_rain_after_step :: proc(game: ^Sandbox,dt: f32) {
	rain:=&game.bomb_rain
	burst_count:=0
	for burst in rain.bursts {
		next:=burst; next.age+=dt
		if next.age<BOMB_BURST_TIME { rain.bursts[burst_count]=next; burst_count+=1 }
	}
	resize(&rain.bursts,burst_count)
	// Read landing contacts for all bombs before any blast changes the collision world.
	for &bomb in rain.bombs {
		if bomb.landed { bomb.fuse=max(f32(0),bomb.fuse-dt) }
		else if bomb_has_landed(bomb) { bomb.landed=true }
	}
	first_burst:=len(rain.bursts)
	bomb_count:=0
	for bomb in rain.bombs {
		position:=from_b2(b2.Body_GetPosition(bomb.body))
		explode:=bomb.landed && bomb.fuse<=0.000001
		if explode { append(&rain.bursts,Bomb_Burst{position=position,radius=game.applied.blast_radius}) }
		if explode || position.y < -3 || position.x < -9 || position.x > 10 {
			b2.DestroyBody(bomb.body)
		} else { rain.bombs[bomb_count]=bomb; bomb_count+=1 }
	}
	resize(&rain.bombs,bomb_count)
	for burst in rain.bursts[first_burst:] { sandbox_explode(game,burst.position) }
}
