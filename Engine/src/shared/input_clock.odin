package shared

import math "core:math"

// Whole ticks never pass through f64. Only bounded differences and sub-ticks do.
Server_Stamp :: struct { tick: u64, phase: f64 }
Clock_Probe :: struct { active: bool, nonce: u64, sent: f64 }
Clock_Sample :: struct { valid: bool, received,rtt: f64, stamp: Server_Stamp }
Input_Clock :: struct {
 probes: [32]Clock_Probe,
 samples: [64]Clock_Sample,
 sample_index: int,
 next_nonce: u64,
 valid,resync: bool,
 estimate: Server_Stamp,
 updated_at,rtt,jitter95,raw_error: f64,
 lead: u32,
 rejected,accepted: u64,
}

server_stamp_advance :: proc(s: Server_Stamp,seconds: f64) -> Server_Stamp {
 if seconds<=0 || math.is_nan(seconds) || math.is_inf(seconds) { return s }
 ticks:=min(seconds*60,3600.0*60)+s.phase
 whole:=u64(math.floor(ticks))
 if whole>max(u64)-s.tick { return {max(u64),0} }
 return {s.tick+whole,ticks-f64(whole)}
}
server_stamp_error :: proc(a,b: Server_Stamp) -> f64 {
 delta:f64
 if a.tick>=b.tick { delta=f64(min(a.tick-b.tick,u64(1000000))) }
 else { delta=-f64(min(b.tick-a.tick,u64(1000000))) }
 return delta+a.phase-b.phase
}
server_stamp_adjust :: proc(s: Server_Stamp,delta: f64) -> Server_Stamp {
 phase:=s.phase+clamp(delta,-0.05,0.05)
 tick:=s.tick
 if phase<0 { if tick==0 { return {} };tick-=1;phase+=1 }
 if phase>=1 { if tick==max(u64) { return {tick,0} };tick+=1;phase-=1 }
 return {tick,phase}
}
input_clock_probe :: proc(c: ^Input_Clock,now: f64) -> (u64,bool) {
 if math.is_nan(now) || math.is_inf(now) || c.next_nonce==max(u64) { return 0,false }
 // Reclaim only expired probes; never replace a live outstanding nonce.
 for &p in c.probes {
  if p.active && now-p.sent>1 { p={} }
  if !p.active {
   c.next_nonce+=1;p={true,c.next_nonce,now};return p.nonce,true
  }
 }
 return 0,false
}
input_clock_now :: proc(c: ^Input_Clock,now: f64) -> (Server_Stamp,bool) {
 if !c.valid || math.is_nan(now) || math.is_inf(now) { return {},false }
 if now<c.updated_at { c.resync=true;return c.estimate,false }
 if now-c.updated_at>0.25 { c.resync=true }
 c.estimate=server_stamp_advance(c.estimate,now-c.updated_at);c.updated_at=now
 return c.estimate,true
}
input_clock_echo :: proc(c: ^Input_Clock,nonce: u64,stamp: Server_Stamp,now: f64) -> bool {
 if math.is_nan(now) || math.is_inf(now) || math.is_nan(stamp.phase) || math.is_inf(stamp.phase) || stamp.phase<0 || stamp.phase>=1 { c.rejected+=1;return false }
 found: ^Clock_Probe
 for &p in c.probes { if p.active && p.nonce==nonce { found=&p;break } }
 if found==nil { c.rejected+=1;return false }
 elapsed:=now-found.sent;found.active=false
 if elapsed<0 || elapsed>1 || (c.accepted>=4 && elapsed>c.rtt*4+0.05) { c.rejected+=1;return false }
 received_stamp:=server_stamp_advance(stamp,elapsed/2)
 if c.accepted==0 { c.rtt=elapsed } else { c.rtt+=(elapsed-c.rtt)/8 }
 c.samples[c.sample_index%len(c.samples)]={true,now,elapsed,received_stamp};c.sample_index=(c.sample_index+1)%len(c.samples)
 // Positive one-way jitter distribution; insertion-sort a fixed bounded array.
 positive:[64]f64;count:=0
 best: ^Clock_Sample
 for &sample in c.samples {
  if !sample.valid || now-sample.received>8 { continue }
  if best==nil || sample.rtt<best.rtt || (sample.rtt==best.rtt && sample.received>best.received) { best=&sample }
  value:=max(0.0,(sample.rtt-c.rtt)/2);j:=count
  for j>0 && positive[j-1]>value { positive[j]=positive[j-1];j-=1 }
  positive[j]=value;count+=1
 }
 if count>0 { c.jitter95=positive[max(0,int(math.ceil(f64(count)*0.95))-1)] }
 c.lead=u32(clamp(math.ceil((c.rtt/2+c.jitter95)*60)+2,2,15))
 candidate:=server_stamp_advance(best.stamp,now-best.received)
 if !c.valid { c.estimate=candidate;c.updated_at=now;c.valid=true }
 else {
  previous:=c.estimate
  _,_=input_clock_now(c,now)
  c.raw_error=server_stamp_error(candidate,c.estimate)
  if math.abs(c.raw_error)>8 { c.resync=true }
  adjusted:=server_stamp_adjust(c.estimate,c.raw_error)
  // A negative correction can slow progress, but never reverse accepted time.
  if server_stamp_error(adjusted,previous)>=0 { c.estimate=adjusted }
 }
 c.accepted+=1
 return true
}

input_clock_target_origin :: proc(c: ^Input_Clock,now: f64) -> (u64,bool) {
 stamp,valid:=input_clock_now(c,now)
 if !valid || stamp.tick>max(u64)-u64(c.lead)-1 { return 0,false }
 // Ceil phase then add the delivery margin, without converting the tick to float.
 return stamp.tick+u64(stamp.phase>0)+u64(c.lead),true
}
