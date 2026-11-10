package shared
import t "core:testing"
import b2 "vendor:box2d"

round_test_world :: proc()->World {
 w:=World{settings=DEFAULT_SANDBOX_SETTINGS};layout:=Layout{next_identity=1}
 world_rebuild_layout(&w,&layout,false)
 _=world_add_player(&w,1)
 return w
}
round_test_world_destroy :: proc(w:^World) {scene_destroy(&w.scene);delete(w.bombs)}

@(test)
round_world_accumulates_detonations_at_actual_capsule_poses_without_choosing_a_winner :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w)
 w.elimination_playing=true
 b2.Body_SetTransform(w.players[0].body,{0,1},b2.MakeRot(0))
 b2.Body_SetTransform(w.players[1].body,{6,1},b2.MakeRot(0))
 events:Tick_Events;defer delete(events.explosions)
 world_explode(&w,{0,1.6},0.5,&events)
 t.expect(test,events.deaths[0]==.Blast && events.deaths[1]==.None)
 world_explode(&w,{6,1},0.5,&events)
 t.expect(test,events.deaths[0]==.Blast && events.deaths[1]==.Blast)
 t.expect(test,w.players[0].active && w.players[1].active && len(events.explosions)==2)
}

@(test)
round_world_bounds_death_does_not_respawn_but_sandbox_still_does :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w)
 w.elimination_playing=true
 b2.Body_SetTransform(w.players[0].body,{30,1},b2.MakeRot(0))
 before:=w.players[0].teleport_serial
 events:=world_tick(&w,{},1.0/60);defer delete(events.explosions)
 t.expect(test,events.deaths[0]==.Bounds && !events.player_respawned[0] && w.players[0].teleport_serial==before && w.players[0].pose.position.x>29)
 w.elimination_playing=false
 sandbox:=world_tick(&w,{},1.0/60);defer delete(sandbox.explosions)
 t.expect(test,sandbox.deaths[0]==.None && sandbox.player_respawned[0] && w.players[0].teleport_serial==before+1)
}

@(test)
round_world_blocks_manual_blasts_and_keeps_falling_bomb_defaults :: proc(test:^t.T) {
 w:=round_test_world();defer round_test_world_destroy(&w)
 w.elimination_playing=true
 w.settings.blast_mode=.Manual
 commands:Tick_Commands;points:=[1]Vec2{{2,4}};commands.players[0].blasts=make([dynamic]Vec2)
 append(&commands.players[0].blasts,..points[:]);defer delete(commands.players[0].blasts)
 events:=world_tick(&w,commands,1.0/60);defer delete(events.explosions)
 t.expect(test,len(events.explosions)==0 && events.blast_rejected[0])
}
