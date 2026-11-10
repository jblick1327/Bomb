package shared
import t "core:testing"

round_test_waiting :: proc()->Round_Controller {
 r:=Round_Controller{mode=.Elimination}
 _=round_begin(&r)
 _=round_connect(&r,0,100,1);_=round_connect(&r,1,200,2)
 round_ready(&r,0,1,true);round_ready(&r,1,2,true)
 return r
}
round_test_playing :: proc()->Round_Controller {
 r:=round_test_waiting();round_prepare_tick(&r,60);round_prepare_tick(&r,240);return r
}

@(test)
round_countdown_requires_two_ready_players_for_exactly_180_server_ticks :: proc(test:^t.T) {
 r:=round_test_waiting();round_ready(&r,1,2,false)
 round_prepare_tick(&r,10);t.expect(test,r.state==.Waiting)
 round_ready(&r,1,999,true);round_prepare_tick(&r,11);t.expect(test,r.state==.Waiting)
 round_ready(&r,1,2,true);round_prepare_tick(&r,12)
 t.expect(test,r.state==.Countdown && r.countdown_tick==12 && r.start_tick==192)
 for tick in u64(13)..<192 {round_prepare_tick(&r,tick);t.expect(test,r.state==.Countdown)}
 round_prepare_tick(&r,192);t.expect(test,r.state==.Playing && r.players[0].alive && r.players[1].alive)
}

@(test)
round_countdown_interrupt_and_generation_change_cannot_resume_old_timer :: proc(test:^t.T) {
 r:=round_test_waiting();round_prepare_tick(&r,10);round_disconnect(&r,1)
 round_prepare_tick(&r,11);t.expect(test,r.state==.Waiting && r.start_tick==0)
 _=round_connect(&r,1,200,3);round_ready(&r,1,3,true);round_prepare_tick(&r,50)
 t.expect(test,r.state==.Countdown && r.start_tick==230)
 // Replacing a connection while still ready invalidates the captured participant.
 _=round_connect(&r,1,200,4);round_ready(&r,1,4,true);round_prepare_tick(&r,51)
 t.expect(test,r.state==.Waiting)
}

@(test)
round_simultaneous_deaths_draw_and_awards_are_idempotent :: proc(test:^t.T) {
 r:=round_test_playing()
 for tick in u64(240)..<300 {round_finish_tick(&r,tick,{},1)}
 deaths:[MAX_PLAYERS]Round_Death;deaths[0]=.Blast;deaths[1]=.Bounds
 round_finish_tick(&r,300,deaths,0)
 t.expect(test,r.state==.Finished && r.draw && r.winner==0 && r.end_tick==300)
 t.expect(test,r.players[0].xp_gained==601 && r.players[1].xp_gained==601)
 for _ in 0..<20 {round_finish_tick(&r,301,deaths,10);round_award(&r)}
 for s in r.sessions[:2] {t.expect(test,s.total_xp==601 && s.wins==0 && s.awarded_round==1)}
}

@(test)
round_disconnect_combines_with_same_tick_blast_and_rejoin_stays_spectator :: proc(test:^t.T) {
 r:=round_test_playing();round_disconnect(&r,0)
 _=round_connect(&r,0,100,3);round_ready(&r,0,3,true)
 deaths:[MAX_PLAYERS]Round_Death;deaths[1]=.Blast
 round_finish_tick(&r,240,deaths,1)
 t.expect(test,r.state==.Finished && r.draw && r.reason==.Mixed)
 t.expect(test,r.players[0].death==.Disconnect && r.players[0].bombs_faced==0)
 t.expect(test,r.players[1].death==.Blast && r.players[1].bombs_faced==1)
 t.expect(test,r.players[0].generation==1 && r.connections[0].generation==3)
}

@(test)
round_forfeit_winner_and_restart_keep_session_totals_and_reset_transients :: proc(test:^t.T) {
 r:=round_test_playing();round_finish_tick(&r,240,{},2);round_disconnect(&r,1)
 round_finish_tick(&r,241,{},0)
 t.expect(test,r.winner==100 && !r.draw && r.reason==.Forfeit)
 t.expect(test,r.sessions[0].wins==1 && r.sessions[0].total_xp==20)
 _=round_connect(&r,2,300,3);round_ready(&r,2,3,true)
 round_prepare_tick(&r,500);t.expect(test,r.state==.Finished && r.players[1].session_id==200)
 t.expect(test,round_begin(&r) && r.id==2 && r.state==.Waiting && r.bombs_spawned==0 && r.winner==0)
 t.expect(test,r.sessions[0].total_xp==20 && r.sessions[0].wins==1 && !r.connections[0].ready)
 round_ready(&r,0,1,true);round_ready(&r,2,3,true);round_prepare_tick(&r,600);round_prepare_tick(&r,780)
 deaths:[MAX_PLAYERS]Round_Death;deaths[2]=.Bounds;round_finish_tick(&r,780,deaths,3)
 t.expect(test,r.winner==100 && r.sessions[0].total_xp==50 && r.sessions[0].wins==2)
}

@(test)
round_spectators_do_not_take_participant_slots_and_session_admission_is_bounded :: proc(test:^t.T) {
 r:=Round_Controller{mode=.Elimination};_=round_begin(&r)
 _=round_connect(&r,0,100,1,true);_=round_connect(&r,1,200,2);_=round_connect(&r,2,300,3)
 for i in 0..<3 {round_ready(&r,i,u64(i+1),true)}
 round_prepare_tick(&r,1);t.expect(test,r.players[0].session_id==200 && r.players[1].session_id==300)
 t.expect(test,!round_connect(&r,3,200,4))
 round_disconnect(&r,0)
 for id in u64(1000)..<1125 {_=round_connect(&r,0,id,id);round_disconnect(&r,0)}
 t.expect(test,r.session_count==ROUND_SESSION_CAPACITY && !round_connect(&r,0,9999,9999))
}

@(test)
round_capsule_uses_capsule_boundary_and_separate_lethal_radius :: proc(test:^t.T) {
 t.expect(test,round_capsule_hit({0,0},{0,2.7},2.2)) // Center-distance alone would miss.
 t.expect(test,!round_capsule_hit({0,0},{0,2.8},2.2))
 t.expect(test,round_capsule_hit({0,0},{2.45,0},2.2))
 t.expect(test,!round_capsule_hit({0,0},{2.47,0},2.2))
 t.expect(test,round_capsule_hit({0,0},{0,0.5},0.2))
 t.expect(test,!round_capsule_hit({0,0},{0,0},-1))
}

@(test)
round_xp_thresholds_and_arithmetic_do_not_overflow :: proc(test:^t.T) {
 cases:=[8]struct{xp,level,inside,next:u64}{
  {0,1,0,100},{99,1,99,100},{100,2,0,150},{249,2,149,150},
  {250,3,0,200},{449,3,199,200},{450,4,0,250},{700,5,0,300},
 }
 for c in cases {p:=round_progress(c.xp);t.expect(test,p.level==c.level && p.xp_in_level==c.inside && p.xp_to_next==c.next)}
 p:=round_progress(max(u64));t.expect(test,p.level>1 && p.xp_in_level<p.xp_to_next)
 t.expect(test,round_add_sat(max(u64)-1,3)==max(u64) && round_mul_sat(max(u64),10)==max(u64))
 r:=round_test_playing();r.players[0].bombs_faced=max(u64);r.players[0].alive_ticks=max(u64)
 deaths:[MAX_PLAYERS]Round_Death;deaths[1]=.Blast;round_finish_tick(&r,240,deaths,1)
 t.expect(test,r.sessions[0].total_xp==max(u64))
}

@(test)
round_sandbox_does_not_run_elimination_rules :: proc(test:^t.T) {
 r:=round_test_waiting();r.mode=.Sandbox
 round_prepare_tick(&r,10);round_finish_tick(&r,10,{.Blast,.Blast,.None,.None},10)
 t.expect(test,r.state==.Waiting && r.sessions[0].total_xp==0 && r.bombs_spawned==0)
}

@(test)
round_waiting_starts_with_validated_ready_players_without_waiting_for_a_loading_slot :: proc(test:^t.T) {
 r:=round_test_waiting();round_ready(&r,1,2,false)
 _=round_connect(&r,2,300,3);round_ready(&r,2,3,true)
 round_prepare_tick(&r,10);t.expect(test,r.state==.Countdown&&r.players[0].session_id==100&&r.players[1].session_id==300)
 round_ready(&r,1,2,true);round_prepare_tick(&r,11)
 t.expect(test,r.state==.Countdown && r.players[0].session_id==100 && r.players[1].session_id==300 && r.players[2].session_id==200 && r.start_tick==190,"already-connected loading player joins without replacing selected participants or extending countdown")
 round_disconnect(&r,2);round_prepare_tick(&r,12);t.expect(test,r.state==.Waiting)
 round_prepare_tick(&r,13)
 t.expect(test,r.state==.Countdown && r.players[0].session_id==100 && r.players[1].session_id==200)
}
