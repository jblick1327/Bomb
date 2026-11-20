package shared
import t "core:testing"

@(test)
requests_terminal_replay_conflict_and_high_identifiers :: proc(test: ^t.T) {
 c:=Request_Cache{incarnation=9007199254740999}
 id:=u64(9007199254742001)
 state,_:=request_cache_begin(&c,c.incarnation,id,77);t.expect_value(test,state,Request_Begin.New)
 pending:Request_Result;state,pending=request_cache_begin(&c,c.incarnation,id,77)
 t.expect(test,state==.Replay && pending.status==.Pending)
 result:=Request_Result{id,9007199254743999,9007199254744001,.Accepted,0}
 t.expect(test,request_cache_finish(&c,result))
 replay:Request_Result;state,replay=request_cache_begin(&c,c.incarnation,id,77)
 t.expect(test,state==.Replay && replay==result)
 state,_=request_cache_begin(&c,c.incarnation,id,78);t.expect_value(test,state,Request_Begin.Conflict)
 state,_=request_cache_begin(&c,c.incarnation+1,id,77);t.expect_value(test,state,Request_Begin.Wrong_Connection)
 t.expect(test,!request_cache_finish(&c,result))
}

@(test)
requests_eviction_watermark_never_reexecutes_old_or_unresolved :: proc(test: ^t.T) {
 c:=Request_Cache{incarnation=1}
 for id in u64(1)..=REQUEST_RESULT_WINDOW {
  state,_:=request_cache_begin(&c,1,id,id);t.expect_value(test,state,Request_Begin.New)
  if id!=1 { t.expect(test,request_cache_finish(&c,{request_id=id,status=.Rejected,reason=7})) }
 }
 state,_:=request_cache_begin(&c,1,REQUEST_RESULT_WINDOW+1,99);t.expect_value(test,state,Request_Begin.Capacity)
 t.expect(test,request_cache_finish(&c,{request_id=1,status=.Accepted,effect_tick=60,event_id=90}))
 state,_=request_cache_begin(&c,1,REQUEST_RESULT_WINDOW+1,99);t.expect_value(test,state,Request_Begin.New)
 state,_=request_cache_begin(&c,1,1,1);t.expect_value(test,state,Request_Begin.Too_Old)
 request_cache_expire_epoch(&c,100)
 result:Request_Result;state,result=request_cache_begin(&c,1,REQUEST_RESULT_WINDOW+1,99)
 t.expect(test,state==.Replay && result.status==.Wrong_Epoch && result.effect_tick==100)
}

@(test)
requests_expiry_no_rewind_and_epoch_precondition :: proc(test: ^t.T) {
 t.expect_value(test,blast_intent_status(1,1,4,4,100,75,105),Request_Status.Accepted)
 t.expect_value(test,blast_intent_status(1,1,4,4,106,75,105),Request_Status.Expired)
 t.expect_value(test,blast_intent_status(1,1,4,3,100,75,105),Request_Status.Wrong_Epoch)
 t.expect_value(test,blast_intent_status(1,2,4,4,100,75,105),Request_Status.Wrong_Connection)
 t.expect_value(test,blast_intent_status(1,1,4,4,100,103,130),Request_Status.Rejected)
 t.expect_value(test,blast_intent_status(1,1,4,4,100,90,121),Request_Status.Rejected)
 t.expect_value(test,blast_intent_status(1,1,4,4,100,100,99),Request_Status.Rejected)
}
