#+feature dynamic-literals
package shared

import b2 "vendor:box2d"
import math "core:math"

Player_Tuning :: struct {
	speed, acceleration, jump_speed, coyote_time, jump_buffer: f32,
}

PLAYER_TUNING :: Player_Tuning{4,32,6.3,0.1,0.1}

PLAYER_RADIUS :: f32(0.26)

PLAYER_SEGMENT :: f32(0.30)

PLAYER_HALF_HEIGHT :: PLAYER_RADIUS+PLAYER_SEGMENT

PLAYER_SPAWN :: Vec2{-4.5,PLAYER_HALF_HEIGHT+0.005}

MAX_PLAYERS :: 4

player_refresh_pose :: proc(player: ^Player) {
	if !player.active { return }
	player.pose=read_body_state(player.body).pose
}

player_create :: proc(world: b2.WorldId,blast_radius: f32 = 0) -> Player {
	def:=b2.DefaultBodyDef()
	def.type=.dynamicBody
	def.position=to_b2(PLAYER_SPAWN)
	def.fixedRotation=true
	def.enableSleep=false
	body:=b2.CreateBody(world,def)
	shape:=b2.DefaultShapeDef()
	shape.density=0.65
	shape.material.friction=0.15
	// Players pass through each other (negative shared group) and collide with everything else.
	shape.filter.groupIndex=-1
	_ = b2.CreateCapsuleShape(body,shape,b2.Capsule{center1={0,-PLAYER_SEGMENT},center2={0,PLAYER_SEGMENT},radius=PLAYER_RADIUS})
	player:=Player{active=true,body=body,blast_radius=blast_radius}
	player_refresh_pose(&player)
	return player
}

player_respawn :: proc(player: ^Player) {
	body:=player.body
	b2.Body_SetTransform(body,to_b2(PLAYER_SPAWN),b2.MakeRot(0))
	b2.Body_SetLinearVelocity(body,{})
	b2.Body_SetAngularVelocity(body,0)
	player^=Player{active=true,body=body,blast_radius=player.blast_radius}
	player_refresh_pose(player)
}

player_read_support :: proc(player: ^Player) {
	player.grounded=false
	player.support_velocity={}
	position:=from_b2(b2.Body_GetPosition(player.body))
	velocity:=from_b2(b2.Body_GetLinearVelocity(player.body))
	buffer:=make([]b2.ContactData,int(b2.Body_GetContactCapacity(player.body)))
	defer delete(buffer)
	for contact in b2.Body_GetContactData(player.body,buffer) {
		a,b:=b2.Shape_GetBody(contact.shapeIdA),b2.Shape_GetBody(contact.shapeIdB)
		normal:=from_b2(contact.manifold.normal)
		other:=a
		if a==player.body { normal=vmul(normal,-1); other=b }
		if normal.y<0.55 { continue }
		for i in 0..<int(contact.manifold.pointCount) {
			point:=contact.manifold.points[i]
			support_velocity:=from_b2(b2.Body_GetWorldPointVelocity(other,point.point))
			if point.separation<=0.025 && point.point.y<position.y-0.1 && vdot(vsub(velocity,support_velocity),normal)<0.8 {
				player.grounded=true
				player.support_velocity=support_velocity
			}
		}
	}
}

player_before_step :: proc(player: ^Player,move: f32,jump_pressed: bool,dt: f32) {
	player_read_support(player)
	if player.grounded { player.coyote=PLAYER_TUNING.coyote_time } else { player.coyote=max(f32(0),player.coyote-dt) }
	if jump_pressed { player.buffered_jump=PLAYER_TUNING.jump_buffer }
	velocity:=from_b2(b2.Body_GetLinearVelocity(player.body))
	target:=clamp(move,f32(-1),f32(1))*PLAYER_TUNING.speed
	velocity.x+=clamp(target-velocity.x,-PLAYER_TUNING.acceleration*dt,PLAYER_TUNING.acceleration*dt)
	if player.buffered_jump>0 && player.coyote>0 {
		velocity.y=PLAYER_TUNING.jump_speed+max(f32(0),player.support_velocity.y)
		player.grounded=false
		player.coyote=0
		player.buffered_jump=0
	}
	player.buffered_jump=max(f32(0),player.buffered_jump-dt)
	b2.Body_SetLinearVelocity(player.body,to_b2(velocity))
}

player_after_step :: proc(player: ^Player) -> bool {
	position:=from_b2(b2.Body_GetPosition(player.body))
	if position.x < -8.5 || position.x > 9.5 || position.y < -3 || position.y > 12 || math.is_nan(position.y) {
		player_respawn(player)
		return true
	}
	player_read_support(player)
	player_refresh_pose(player)
	return false
}
