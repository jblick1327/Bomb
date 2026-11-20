package shared
import t "core:testing"

@(test)
input_link_waits_for_acceptance_and_rejects_stale_results :: proc(test:^t.T) {
 c:Input_Link
 offer:=Schedule_Control{kind=.Offer,proposal={{9007199254740999,4,7},1002,9007199254742001},server={1000,0}}
 t.expect(test,input_link_offer(&c,offer))
 _,ready:=input_link_prepare_reset(&c,0);t.expect(test,!ready)
 nonce,_:=input_clock_probe(&c.clock,0);_=input_clock_echo(&c.clock,nonce,{1000,0},.1)
 request,ok:=input_link_prepare_reset(&c,.1);t.expect(test,ok && request.kind==.Request)
 command,ok_command:=input_link_command(&c,127,true)
 t.expect(test,ok_command && command.move==0 && command.jump_edge==0)
 _,ready=input_link_packet(&c,false,0);t.expect(test,!ready)
 accepted:=request;accepted.kind=.Accepted
 stale:=accepted;stale.proposal.first_tick+=1;t.expect(test,!input_link_control_result(&c,stale))
 t.expect(test,input_link_control_result(&c,accepted))
 command,ok_command=input_link_command(&c,127,true)
 t.expect(test,ok_command && command.move==127 && command.jump_edge==1 && command.target_tick==request.proposal.first_tick+1)
 packet,ready_packet:=input_link_packet(&c,true,9007199254740997)
 t.expect(test,ready_packet && packet.count==2 && packet.ack==9007199254740997 && packet.commands[0]==command)
}

@(test)
input_link_rejected_origin_is_not_retargeted :: proc(test:^t.T) {
 c:Input_Link;_=input_link_offer(&c,{kind=.Offer,proposal={{1,1,1},2,1}})
 nonce,_:=input_clock_probe(&c.clock,0);_=input_clock_echo(&c.clock,nonce,{0,.5},.01)
 first,ready:=input_link_prepare_reset(&c,.01);t.expect(test,ready)
 _,_=input_link_command(&c,127,true)
 rejected:=first;rejected.kind=.Rejected;rejected.reason=.Obsolete
 t.expect(test,input_link_control_result(&c,rejected) && !c.history.accepted)
 second,ready_second:=input_link_prepare_reset(&c,.1)
 t.expect(test,ready_second && second.proposal.identity.generation>first.proposal.identity.generation && second.proposal.first_tick>first.proposal.first_tick)
 t.expect(test,!input_link_control_result(&c,Schedule_Control{kind=.Accepted,proposal=first.proposal}))
}

@(test)
input_link_owner_finalizes_missing_slots_and_stall_resets :: proc(test:^t.T) {
 c:Input_Link;p:=Schedule_Proposal{{1,1,1},100,9007199254740993}
 c.active=true;c.has_offer=true;c.offer=p;command_history_begin(&c.history,p)
 for i in 0..<8 { _,_=input_link_command(&c,127,i==0) }
 owner:=Owner_State{identity=p.identity,state_tick=105,finalized_through=105,last_applied_sequence=p.first_sequence,teleport_serial=1}
 t.expect(test,input_link_owner(&c,owner) && c.history.finalized_through==105)
 packet,ready:=input_link_packet(&c,false,0);t.expect(test,ready && packet.count==2 && packet.commands[1].target_tick==106)
 t.expect(test,!input_link_owner(&c,owner))
 owner.state_tick=108;owner.finalized_through=108
 t.expect(test,!input_link_owner(&c,owner) && !c.active && !c.history.accepted)
}
