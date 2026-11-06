package shared
import t "core:testing"
import math "core:math"

@(test)
clock_exact_large_ticks_nonce_and_phase :: proc(test: ^t.T) {
 c:Input_Clock;c.next_nonce=9007199254740993
 nonce,ok:=input_clock_probe(&c,10);t.expect(test,ok && nonce==9007199254740994)
 t.expect(test,input_clock_echo(&c,nonce,{9007199254742001,0.25},10.1))
 stamp,valid:=input_clock_now(&c,10.1)
 t.expect(test,valid && stamp.tick==9007199254742004 && math.abs(stamp.phase-0.25)<1e-6)
 target,valid_target:=input_clock_target_origin(&c,10.1)
 t.expect(test,valid_target && target==9007199254742004+1+u64(c.lead))
 t.expect(test,!input_clock_echo(&c,nonce,{99,0},10.2))
 t.expect(test,!input_clock_echo(&c,nonce+1,{99,0},10.2))
}

@(test)
clock_bounded_probes_outliers_and_lead :: proc(test: ^t.T) {
 c:Input_Clock
 for i in 0..<32 { _,ok:=input_clock_probe(&c,f64(i)*0.001);t.expect(test,ok) }
 _,overflow:=input_clock_probe(&c,0.05);t.expect(test,!overflow)
 _,reclaimed:=input_clock_probe(&c,1.1);t.expect(test,reclaimed)
 c={}
 for i in 0..<20 {
  now:=f64(i)*0.25;nonce,_:=input_clock_probe(&c,now)
  t.expect(test,input_clock_echo(&c,nonce,{u64(i*15+3),0},now+0.1))
 }
 t.expect(test,c.lead>=5 && c.lead<=6 && c.accepted==20)
 nonce,_:=input_clock_probe(&c,6)
 t.expect(test,!input_clock_echo(&c,nonce,{600,0},6.9))
 nonce,_=input_clock_probe(&c,7)
 t.expect(test,!input_clock_echo(&c,nonce,{600,1},7.1))
}

@(test)
clock_never_reverses_and_marks_discontinuity :: proc(test: ^t.T) {
 c:Input_Clock;nonce,_:=input_clock_probe(&c,0)
 _=input_clock_echo(&c,nonce,{1000,0},0.1)
 old:=c.estimate
 nonce,_=input_clock_probe(&c,0.11);_=input_clock_echo(&c,nonce,{1000,0},0.111)
 t.expect(test,server_stamp_error(c.estimate,old)>=0)
 _,valid:=input_clock_now(&c,0.05);t.expect(test,!valid && c.resync)
 c.resync=false;_,valid=input_clock_now(&c,0.5);t.expect(test,valid && c.resync)
}
