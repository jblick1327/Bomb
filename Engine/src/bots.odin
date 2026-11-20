package main

import "core:math"
import "core:math/rand"

// Scripted players for replication tests. One seeded stream per bot: walk to a random x
// across the yard and back, jump at random intervals, and (when enabled) blast a random
// valid point within BOT_BLAST_REACH of the player every 4-8 s.
BOT_BLAST_REACH :: f32(6)
BOT_WALK_MIN_X :: f32(-7.5)
BOT_WALK_MAX_X :: f32(8.5)

Bot :: struct {
 random: rand.Default_Random_State,
 blasting: bool,
 origin_x, target_x: f32,
 returning, travelling: bool,
 jump_timer, blast_timer: f32,
}
bot_uniform :: proc(bot: ^Bot,lo,hi: f32) -> f32 { return rand.float32_range(lo,hi,rand.default_random_generator(&bot.random)) }
bot_init :: proc(bot: ^Bot,seed: u64,blasting: bool) {
 bot^=Bot{blasting=blasting}
 bot.random=rand.create(seed)
 bot.jump_timer=bot_uniform(bot,1,4)
 bot.blast_timer=bot_uniform(bot,4,8)
}
// Fills player `index`'s commands for this tick. Blast points go to commands.blasts.
bot_step :: proc(bot: ^Bot,w: ^World,index: int,dt: f32,commands: ^Player_Commands) {
 player:=w.players[index]
 if !player.active { return }
 bot_step_scene(bot,&w.scene,player.pose.position,dt,commands)
}
// The bot's whole view of the world: its own position and a scene to test aim points against
// (a Net_Client passes its replica).
bot_step_scene :: proc(bot: ^Bot,scene: ^Scene,position: Vec2,dt: f32,commands: ^Player_Commands) {
 x:=position.x
 if !bot.travelling {
  bot.origin_x=x; bot.target_x=bot_uniform(bot,BOT_WALK_MIN_X,BOT_WALK_MAX_X)
  bot.returning=false; bot.travelling=true
 }
 goal:=bot.target_x; if bot.returning { goal=bot.origin_x }
 if math.abs(goal-x)<0.2 {
  if bot.returning { bot.travelling=false } else { bot.returning=true }
  commands.move=0
 } else if goal>x { commands.move=1 } else { commands.move=-1 }
 bot.jump_timer-=dt
 if bot.jump_timer<=0 { commands.jump=true; bot.jump_timer=bot_uniform(bot,1,4) }
 if !bot.blasting { return }
 bot.blast_timer-=dt
 if bot.blast_timer>0 { return }
 bot.blast_timer=bot_uniform(bot,4,8)
 for _ in 0..<32 {
  angle:=bot_uniform(bot,0,2*math.PI); distance:=BOT_BLAST_REACH*math.sqrt(bot_uniform(bot,0,1))
  point:=vadd(position,Vec2{distance*math.cos(angle),distance*math.sin(angle)})
  if point.x<YARD_LEFT || point.x>YARD_RIGHT || point.y<=YARD_FLOOR_BOTTOM { continue }
  if sandbox_valid_aim(scene,point) { append(&commands.blasts,point); return }
 }
}
// Drives a Sandbox's queued commands from bots (index 0 uses the tick arguments).
Bot_Team :: struct { bots: [MAX_PLAYERS]Bot, count: int }
bot_team_init :: proc(team: ^Bot_Team,count: int,blasting: bool,seed: u64) {
 team.count=count
 for i in 0..<count { bot_init(&team.bots[i],seed+u64(i)*0x9e3779b97f4a7c15,blasting) }
}
// Returns player 0's move and jump for sandbox_tick; other players are queued directly.
bot_team_step :: proc(team: ^Bot_Team,game: ^Sandbox,dt: f32 = 1.0/60.0) -> (move: f32,jump: bool) {
 for i in 0..<team.count {
  commands:Player_Commands
  bot_step(&team.bots[i],&game.world,i,dt,&commands)
  queued:=&game.queued.players[i]
  queued.move=commands.move; queued.jump=commands.jump
  append(&queued.blasts,..commands.blasts[:])
  delete(commands.blasts)
 }
 queued0:=game.queued.players[0]
 return queued0.move,queued0.jump
}
