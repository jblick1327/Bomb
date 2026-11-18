#+feature dynamic-literals
package shared

import nc "../netcode"
import fmt "core:fmt"
import os "core:os"
import strconv "core:strconv"
import time "core:time"
import b2 "vendor:box2d"

NET_REAL_PORT :: u16(47380)

NET_REAL_HASH_REPORT :: u8(0xC1)

net_real_parse_target :: proc(input: string) -> (nc.Address, bool) {
 ip: [4]u8
 octet:=0
 digits:=0
 value:=0
 i:=0
 for i<len(input) && input[i]!=':' {
  ch:=input[i]
  if ch=='.' {
   if digits==0 || octet>=3 { return 0,false }
   ip[octet]=u8(value); octet+=1; digits=0; value=0
  } else if ch>='0' && ch<='9' {
   digits+=1; value=value*10+int(ch-'0')
   if value>255 || digits>3 { return 0,false }
  } else { return 0,false }
  i+=1
 }
 if octet!=3 || digits==0 { return 0,false }
 ip[3]=u8(value)
 port:=NET_REAL_PORT
 if i<len(input) {
  i+=1
  if i==len(input) { return 0,false }
  p:=0
  for i<len(input) {
   ch:=input[i]; if ch<'0' || ch>'9' { return 0,false }
   p=p*10+int(ch-'0'); if p>65535 { return 0,false }
   i+=1
  }
  if p<1 { return 0,false }
  port=u16(p)
 }
 return nc.address_make(ip,port),true
}

net_real_cli_port :: proc(input: string) -> (u16,bool) {
 n,ok:=strconv.parse_int(input)
 if !ok || n<1 || n>65535 { return 0,false }
 return u16(n),true
}

net_real_create_server :: proc(layout_path: string) -> (ns: Net_Server,ok: bool) {
 g:=Headless_Game{world=World{settings=DEFAULT_SANDBOX_SETTINGS},layout=Layout{next_identity=1}}
 // Preserve the legacy empty Edit -> loaded Edit -> Test rebuild sequence.
 world_rebuild_layout(&g.world,&g.layout,true)
 data:[]u8
 if layout_path!="" {
  bytes,err:=os.read_entire_file(layout_path,context.allocator)
  data=bytes
  if err!=nil { fmt.eprintln("Cannot read server layout:",layout_path); headless_game_destroy(&g);return {},false }
 } else { data=transmute([]u8)PRESET_LAYOUTS[0] }
 layout,seed,valid,problem:=decode_layout(data)
 if layout_path!="" { delete(data) }
 if !valid { fmt.eprintln("Server layout invalid:",problem); headless_game_destroy(&g);return {},false }
 destroy_layout(&g.layout);g.layout=layout;g.world.settings.seed=seed
 world_rebuild_layout(&g.world,&g.layout,true)
 headless_game_reset(&g)
 _=world_remove_player(&g.world,0)
 net_server_init_world(&ns,g,true)
 ns.real_logging=true

 return ns,true
}

net_real_run_server :: proc(port: u16,layout: string,seconds: f64 = 0,host_token: string = "",metrics_path:string="",bind_ip:[4]u8={127,0,0,1}) -> bool {
 sock:nc.Socket
 if !nc.socket_open(&sock,port,bind_ip) { fmt.eprintf("Could not bind UDP port %d\n",port);return false }
 defer nc.socket_close(&sock)
 physics_baseline:=b2.GetByteCount()
 ns,ok:=net_real_create_server(layout)
 if !ok { return false }
 ns.real_gate=true;ns.async_rebuild=true
 ns.real_host_token=host_token
 destroyed:=false
 defer {if !destroyed {net_server_destroy(&ns)}}
 fmt.printf("BOM staging server listening on %d.%d.%d.%d:%d; tick=60Hz\n",bind_ip[0],bind_ip[1],bind_ip[2],bind_ip[3],port)
 start:=time.tick_now()
 last:=f64(0)
 accumulator:=f64(0)
 report_at:=f64(10)
 last_bytes:[nc.MAX_CLIENTS]u64
 last_generation:[nc.MAX_CLIENTS]u64
 buf:[nc.MAX_PACKET+64]u8
 overrun_count:=0
 for {
  now:=time.duration_seconds(time.tick_since(start))
  if seconds>0 && now>=seconds { break }
  if ns.real_host_seen && ns.real_host_left_at>=0 && now-ns.real_host_left_at>=5 {
   fmt.println("SERVER host-left shutdown")
   break
  }
  dt:=max(f64(0),min(now-last,0.25));last=now
  accumulator+=dt
  for {
   packet,from,has:=nc.socket_receive(&sock,buf[:])
   if !has { break }
   nc.server_receive(&ns.srv,from,packet,now)
  }
  steps:=0
  for accumulator+1e-9>=NET_STEP_DT && steps<5 {
   net_server_tick(&ns,now)
   accumulator-=NET_STEP_DT
   steps+=1
  }
  if steps==5 && accumulator>=NET_STEP_DT {
   overrun_count+=1
   fmt.eprintf("server tick overrun at %.2fs: dropping %.1fms of accumulated time\n",now,accumulator*1000)
   accumulator=0
  }
  net_scheduled_server_echoes(&ns,(accumulator+time.duration_seconds(time.tick_since(start))-now)/NET_STEP_DT,now)
  packets:=nc.server_take_outgoing(&ns.srv)
  for p in packets { _=nc.socket_send(&sock,p.to,p.data) }
  nc.outgoing_free(&packets)
  if now>=report_at {
   fmt.printf("SERVER time=%.0fs tick=%d active=%d overruns=%d hashes=%d mismatches=%d unrecorded=%d\n",now,ns.tick,nc.server_client_count(&ns.srv),overrun_count,ns.real_hash_checks,ns.real_hash_mismatch,ns.real_hash_unrecorded)
   for &c,i in ns.srv.clients {
    if !c.active { continue }
    bytes:=c.endpoint.stats.bytes_sent
    if last_generation[i]!=ns.real_hash_generation[i] || bytes<last_bytes[i] { last_bytes[i]=0;last_generation[i]=ns.real_hash_generation[i] }
    fmt.printf("  client=%d addr=%v RTT=%.0fms tx=%.0f kbit/s\n",i,c.address,c.endpoint.stats.rtt*1000,f64(bytes-last_bytes[i])*8/10000)
    input:=&ns.clients[i].schedule
    fmt.printf("INPUT client=%d incarnation=%d generation=%d finalized=%d applied_sequence=%d accepted=%d duplicates=%d conflicts=%d late=%d starved=%d neutralized=%d\n",i,ns.clients[i].incarnation,input.identity.generation,input.finalized_through,input.last_applied_sequence,input.accepted,input.duplicates,input.conflicts,input.too_late,input.starved,input.neutralized)
    last_bytes[i]=bytes
   }
   report_at+=10
  }
  time.sleep(time.Millisecond)
 }
 if metrics_path!="" {
  report:=Net_Real_Metrics{ticks=ns.tick,overruns=u64(overrun_count),hash_checks=u64(ns.real_hash_checks),hash_mismatches=u64(ns.real_hash_mismatch),hash_unrecorded=u64(ns.real_hash_unrecorded),sample_capacity=NET_SERVER_TIMING_CAPACITY,first_sample_index=0,tick_ms=ns.tick_ms[:],world_ms=ns.world_ms[:]}
  if ns.tick>NET_SERVER_TIMING_CAPACITY {report.first_sample_index=ns.tick%NET_SERVER_TIMING_CAPACITY}
  bytes,encoded:=exact_json_encode(report,true);defer delete(bytes)
  if !encoded||os.write_entire_file(metrics_path,bytes)!=nil {fmt.eprintln("Cannot write server metrics:",metrics_path);return false}
 }
 fmt.printf("SERVER final hashes=%d mismatches=%d unrecorded=%d\n",ns.real_hash_checks,ns.real_hash_mismatch,ns.real_hash_unrecorded)
 passed:=ns.real_hash_mismatch==0 && ns.real_hash_unrecorded==0
 net_server_destroy(&ns);destroyed=true
 resources:=Net_Real_Resources{box2d_baseline=i64(physics_baseline),box2d_after=i64(b2.GetByteCount())}
 resources.no_lost_world_bytes=resources.box2d_baseline==resources.box2d_after
 fmt.printf("SERVER RESOURCES box2d_baseline=%d box2d_after=%d no_lost_world_bytes=%t\n",resources.box2d_baseline,resources.box2d_after,resources.no_lost_world_bytes)
 if metrics_path!="" {path:=fmt.aprintf("%s.resources.json",metrics_path);defer delete(path);bytes,encoded:=exact_json_encode(resources,true);defer delete(bytes);if !encoded||os.write_entire_file(path,bytes)!=nil {return false}}
 return passed&&resources.no_lost_world_bytes
}

net_real_cli_server :: proc(args: []string) -> bool {
 if len(args)>0&&args[0]=="--validate-layout" {
  if len(args)<4||args[2]!="--report" {fmt.eprintln("Use --validate-layout input.json --report report.json [--settle-ticks N] [--settle-window-ticks N]");return false}
  ticks,window:=0,120
  seen_ticks,seen_window:=false,false
  i:=4
  for i<len(args) {
   if i+1>=len(args) {return false}
   n,ok:=strconv.parse_int(args[i+1]);if !ok || n<0 {return false}
   switch args[i] {
   case "--settle-ticks": if seen_ticks || n==0 {return false};ticks=n;seen_ticks=true
   case "--settle-window-ticks": if seen_window {return false};window=n;seen_window=true
   case: return false
   }
   i+=2
  }
  if seen_window && !seen_ticks {return false}
  return level_validate_cli(args[1],args[3],ticks,window)
 }
 port:=NET_REAL_PORT
 layout:=""
 seconds:=f64(0)
 host_token:=""
 metrics_path:=""
 bind_ip:=[4]u8{127,0,0,1}
 i:=0
 for i<len(args) {
  switch args[i] {
  case "--bind":
   if i+1>=len(args){return false};ip,ok:=net_real_cli_bind(args[i+1]);if !ok {fmt.eprintln("--bind requires a numeric IPv4 address without a port");return false};bind_ip=ip;i+=2
  case "--port":
   if i+1>=len(args) { fmt.eprintln("--port requires 1..65535");return false }
   p,ok:=net_real_cli_port(args[i+1]);if !ok { fmt.eprintln("Invalid port");return false };port=p;i+=2
  case "--layout":
   if i+1>=len(args) { fmt.eprintln("--layout needs a path");return false };layout=args[i+1];i+=2
  case "--seconds":
   if i+1>=len(args) { return false }
   n,ok:=strconv.parse_int(args[i+1]);if !ok || n<1 { return false };seconds=f64(n);i+=2
  case "--metrics":
   if i+1>=len(args)||len(args[i+1])==0 {return false};metrics_path=args[i+1];i+=2
  case "--host-token":
   if i+1>=len(args) || len(args[i+1])<16 || len(args[i+1])>NET_APP_MAX_TOKEN {
    fmt.eprintln("--host-token requires a random secret of 16..128 characters");return false
   }
   host_token=args[i+1];i+=2
  case: fmt.eprintln("Unknown --server option:",args[i]);return false
  }
 }
 if bind_ip[0]!=127&&len(host_token)<16 {fmt.eprintln("Non-loopback bind requires --host-token");return false}
 return net_real_run_server(port,layout,seconds,host_token,metrics_path,bind_ip)
}

Net_Real_Metrics :: struct {
 ticks:u64,overruns:u64,hash_checks:u64,hash_mismatches:u64,hash_unrecorded:u64,
 sample_capacity:u64,first_sample_index:u64,
 tick_ms:[]f64,world_ms:[]f64,
}

Net_Real_Resources :: struct {box2d_baseline,box2d_after:i64,no_lost_world_bytes:bool}

net_real_cli_bind :: proc(text:string)->([4]u8,bool) {
 for byte in text {if byte==':' {return {},false}}
 address,ok:=net_real_parse_target(text)
 return nc.address_ip(address),ok
}
