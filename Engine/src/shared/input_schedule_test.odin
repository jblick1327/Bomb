package shared
import t "core:testing"

@(test)
schedule_identity_slots_and_duplicate_conflict :: proc(test: ^t.T) {
 s:Input_Schedule
 id:=Input_Identity{incarnation=9007199254741001,epoch=3,generation=4294967319}
 p:=Schedule_Proposal{identity=id,first_tick=9007199254741100,first_sequence=9007199254741999}
 now:=p.first_tick-3
 t.expect_value(test,input_schedule_reset(&s,id.incarnation,id.epoch,now,p),Schedule_Result.Accepted)
 c:=Scheduled_Command{sequence=p.first_sequence,target_tick=p.first_tick,move=127,jump_edge=9007199254741901}
 t.expect_value(test,input_schedule_insert(&s,id,now,c),Command_Result.Accepted)
 t.expect_value(test,input_schedule_insert(&s,id,now,c),Command_Result.Duplicate)
 conflict:=c;conflict.move=-127
 t.expect_value(test,input_schedule_insert(&s,id,now,conflict),Command_Result.Conflict)
 bad:=id;bad.generation-=1
 t.expect_value(test,input_schedule_insert(&s,bad,now,c),Command_Result.Wrong_Identity)
 wrong_slot:=c;wrong_slot.sequence+=1
 t.expect_value(test,input_schedule_insert(&s,id,now,wrong_slot),Command_Result.Wrong_Slot)
 _=input_schedule_consume(&s,now+1);_=input_schedule_consume(&s,now+2)
 step:=input_schedule_consume(&s,p.first_tick)
 t.expect(test,step.applied && step.command==c)
 t.expect_value(test,s.last_applied_sequence,c.sequence)
 t.expect_value(test,s.finalized_through,c.target_tick)
 t.expect_value(test,input_schedule_insert(&s,id,p.first_tick,c),Command_Result.Too_Late)
}

@(test)
schedule_missing_slots_carry_only_six_held_never_edges :: proc(test: ^t.T) {
 s:Input_Schedule;id:=Input_Identity{1,1,1};p:=Schedule_Proposal{id,12,100}
 t.expect_value(test,input_schedule_reset(&s,1,1,10,p),Schedule_Result.Accepted)
 t.expect_value(test,input_schedule_insert(&s,id,10,{100,12,127,9007199254740993}),Command_Result.Accepted)
 _=input_schedule_consume(&s,11);step:=input_schedule_consume(&s,12)
 t.expect(test,step.applied && step.command.jump_edge==9007199254740993)
 for tick in u64(13)..=18 {
  step=input_schedule_consume(&s,tick)
  t.expect(test,step.carried && step.command.move==127 && step.command.jump_edge==0 && !step.applied)
 }
 step=input_schedule_consume(&s,19)
 t.expect(test,step.neutralized && step.command.move==0 && step.command.jump_edge==0)
 t.expect_value(test,s.finalized_through,u64(19));t.expect_value(test,s.last_applied_sequence,u64(100))
 t.expect_value(test,input_schedule_insert(&s,id,19,{101,13,-127,99}),Command_Result.Too_Late)
}

@(test)
schedule_reset_acceptance_is_atomic_and_terminal :: proc(test: ^t.T) {
 s:Input_Schedule;id:=Input_Identity{2,7,10};p:=Schedule_Proposal{id,102,1000}
 t.expect_value(test,input_schedule_reset(&s,2,7,100,p),Schedule_Result.Accepted)
 t.expect_value(test,input_schedule_insert(&s,id,100,{1000,102,127,1}),Command_Result.Accepted)
 stale:=p;stale.identity.generation+=1;stale.first_tick=101
 t.expect_value(test,input_schedule_reset(&s,2,7,100,stale),Schedule_Result.Obsolete)
 t.expect_value(test,s.identity,id)
 stale.first_tick=133;t.expect_value(test,input_schedule_reset(&s,2,7,100,stale),Schedule_Result.Too_Far)
 stale.first_tick=105;stale.first_sequence=9007199254740999
 t.expect_value(test,input_schedule_reset(&s,2,7,100,stale),Schedule_Result.Accepted)
 t.expect_value(test,input_schedule_insert(&s,id,100,{1000,102,127,1}),Command_Result.Wrong_Identity)
 t.expect_value(test,input_schedule_reset(&s,2,7,100,stale),Schedule_Result.Old_Generation)
 for tick in u64(101)..=105 {
  step:=input_schedule_consume(&s,tick);t.expect(test,!step.applied && step.command.jump_edge==0 && step.command.move==0)
 }
}

@(test)
schedule_repeated_jump_cannot_execute_at_another_slot :: proc(test: ^t.T) {
 s:Input_Schedule;id:=Input_Identity{1,1,1};p:=Schedule_Proposal{id,2,1}
 _=input_schedule_reset(&s,1,1,0,p)
 _=input_schedule_insert(&s,id,0,{1,2,0,9007199254740993})
 _=input_schedule_insert(&s,id,0,{2,3,0,9007199254740993})
 _=input_schedule_consume(&s,1)
 a:=input_schedule_consume(&s,2);b:=input_schedule_consume(&s,3)
 t.expect(test,a.command.jump_edge!=0 && b.command.jump_edge==0 && b.applied)
 t.expect_value(test,s.duplicate_jumps,u64(1))
}

@(test)
history_redundancy_finalization_and_bounded_backlog :: proc(test: ^t.T) {
 h:Command_History;p:=Schedule_Proposal{Input_Identity{9,9,9},1000,9007199254740993}
 command_history_begin(&h,p)
 for i in 0..<INPUT_HISTORY { _,ok:=command_history_push(&h,127,u64(i));t.expect(test,ok) }
 _,overflow:=command_history_push(&h,0,0);t.expect(test,!overflow)
 four,count:=command_history_redundancy(&h);t.expect_value(test,count,4)
 for c,i in four { t.expect_value(test,c.target_tick,u64(1255-i));t.expect_value(test,c.sequence,p.first_sequence+u64(255-i)) }
 t.expect(test,!command_history_finalize(&h,Input_Identity{9,9,8},1255))
 t.expect(test,!command_history_finalize(&h,p.identity,1256))
 t.expect(test,command_history_finalize(&h,p.identity,1255))
 _,ok:=command_history_push(&h,-127,0);t.expect(test,ok)
 _,count=command_history_redundancy(&h);t.expect_value(test,count,1)
 t.expect(test,!command_history_finalize(&h,p.identity,1254))
}
