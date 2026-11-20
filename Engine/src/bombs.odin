package main

import b2 "vendor:box2d"
import "core:math/rand"

BOMB_BURST_TIME :: f32(0.3)

Bomb_Burst :: struct { position: Vec2, radius, age: f32 }
sandbox_set_blast_mode :: proc(game: ^Sandbox,mode: Blast_Mode) {
 if mode==sandbox_mode(game) { return }
 game.queued.mode=mode
 if mode==.Falling_Bombs { sandbox_notice(game,"Falling bombs: one-second fuse after landing") }
 else { sandbox_notice(game,"Manual blast placement") }
}

// Direct fixture helper; production spawning belongs to world_tick.
bomb_spawn :: proc(game: ^Sandbox,position: Vec2) { world_bomb_spawn(&game.world,position); game.previous_bombs[game.world.bombs[len(game.world.bombs)-1].id]=position }
