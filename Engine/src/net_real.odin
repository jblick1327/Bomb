package main

import nc "netcode"
import rl "vendor:raylib"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:time"

// Step 3 staging: real UDP process transport over the already accepted step 2b
// endpoints. This deliberately does not modify src/netcode/ or the replica wire
// protocol. Host/Join UI and application-level authorization follow separately.
NET_REAL_PORT :: u16(47380)
NET_REAL_HASH_REPORT :: u8(0xC1)

// Strict dotted-decimal IPv4 parser; optional :port. DNS is intentionally not
// supported in this staging CLI. Every component must be decimal, 0..255.
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

// The in-process net server owns its Sandbox. Start with the actual Materials
// preset rather than the editor's empty yard; force Test so authored shapes exist.
net_real_create_server :: proc(layout_path: string) -> (ns: Net_Server,ok: bool) {
 g:=sandbox_editor_create()
 if layout_path!="" {
  data,err:=os.read_entire_file(layout_path,context.allocator)
  if err!=nil { fmt.eprintln("Cannot read server layout:",layout_path); sandbox_destroy(&g);return {},false }
  ok=sandbox_load_layout_data(&g,data)
  delete(data)
 } else {
  ok=sandbox_load_layout_data(&g,transmute([]u8)PRESET_LAYOUTS[0])
 }
 if !ok { fmt.eprintln("Server layout invalid");sandbox_destroy(&g);return {},false }
 g.editor.editing=false
 sandbox_reset(&g)
 // No fake player 0 before anyone joins. Each connect owns a slot, added
 // by the established net_server_join code.
 _=world_remove_player(&g.world,0)
 net_server_init(&ns,g,true)
 ns.real_logging=true
 return ns,true
}

// Fixed 60 Hz accumulator with a bounded catch-up. Call on a dedicated headless
// process. No raylib window or render initialization occurs in this path.
net_real_run_server :: proc(port: u16,layout: string,seconds: f64 = 0,host_token: string = "") -> bool {
 sock:nc.Socket
 if !nc.socket_open(&sock,port,{127,0,0,1}) { fmt.eprintf("Could not bind UDP port %d\n",port);return false }
 defer nc.socket_close(&sock)
 ns,ok:=net_real_create_server(layout)
 if !ok { return false }
 ns.real_gate=true
 ns.real_host_token=host_token
 defer net_server_destroy(&ns)
 fmt.printf("BOM staging server listening on 127.0.0.1:%d only; tick=60Hz\n",port)
 start:=time.tick_now()
 last:=f64(0)
 accumulator:=f64(0)
 report_at:=f64(10)
 last_bytes:[nc.MAX_CLIENTS]u64
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
  packets:=nc.server_take_outgoing(&ns.srv)
  for p in packets { _=nc.socket_send(&sock,p.to,p.data) }
  nc.outgoing_free(&packets)
  if now>=report_at {
   fmt.printf("SERVER time=%.0fs tick=%d active=%d overruns=%d hashes=%d mismatches=%d unrecorded=%d\n",now,ns.tick,nc.server_client_count(&ns.srv),overrun_count,ns.real_hash_checks,ns.real_hash_mismatch,ns.real_hash_unrecorded)
   for &c,i in ns.srv.clients {
    if !c.active { continue }
    bytes:=c.endpoint.stats.bytes_sent
    fmt.printf("  client=%d addr=%v RTT=%.0fms tx=%.0f kbit/s\n",i,c.address,c.endpoint.stats.rtt*1000,f64(bytes-last_bytes[i])*8/10000)
    last_bytes[i]=bytes
   }
   report_at+=10
  }
  time.sleep(time.Millisecond)
 }
 fmt.printf("SERVER final hashes=%d mismatches=%d unrecorded=%d\n",ns.real_hash_checks,ns.real_hash_mismatch,ns.real_hash_unrecorded)
 return ns.real_hash_mismatch==0 && ns.real_hash_unrecorded==0
}

// A real second-process bot reuses the step 2b player, including jump counter,
// numbered blasts, replica, interpolation, acks and adaptive clock.
net_real_run_bot :: proc(target: nc.Address,seconds: f64 = 60,hidden_window: bool = false,host_token: string = "",protocol_version: u32 = GAME_PROTOCOL_VERSION,upload_path: string="",request_reset: bool=false) -> bool {
 upload_data: []u8
 defer { if upload_data!=nil { delete(upload_data) } }
 if upload_path!="" {
  data,err:=os.read_entire_file(upload_path,context.allocator)
  if err!=nil || len(data)==0 || len(data)>NET_APP_MAX_LAYOUT {
   fmt.eprintln("Cannot read a valid upload file:",upload_path)
   if err==nil { delete(data) }
   return false
  }
  upload_data=data
 }
 if hidden_window {
  rl.SetTraceLogLevel(.WARNING)
  rl.SetConfigFlags({.WINDOW_HIDDEN})
  rl.InitWindow(1280,800,"BOM step 3 hidden-window smoke")
  sandbox_gui_style()
  rl.SetTargetFPS(60)
  rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{})
 }
 defer { if hidden_window { presentation_shutdown(); rl.CloseWindow() } }
 sock:nc.Socket
 if !nc.socket_open(&sock) { fmt.eprintln("Could not open bot UDP socket");return false }
 defer nc.socket_close(&sock)
 client:Net_Client
 net_client_init(&client,nc.random_salt(),0,42,true)
 defer net_client_destroy(&client)
 client.real_gate=true
 client.real_host_token=host_token
 client.real_protocol=protocol_version
 client.verify=true
 start:=time.tick_now()
 last_tick:=f64(0)
 next_report:=f64(10)
 upload_sent,reset_sent:=false,false
 buf:[nc.MAX_PACKET+64]u8
 for {
  now:=time.duration_seconds(time.tick_since(start))
  if seconds>0 && now>=seconds { break }
  for {
   packet,from,has:=nc.socket_receive(&sock,buf[:])
   if !has { break }
   if from==target { nc.client_receive(&client.nc_client,packet,now) }
  }
  if now-last_tick>=NET_STEP_DT {
   net_client_step(&client,now)
   if client.real_hello_ok {
    if len(upload_data)>0 && !upload_sent { upload_sent=net_host_client_send_layout(&client,upload_data) }
    if request_reset && !reset_sent && now>=3 && (len(upload_data)==0 || upload_sent) {
     reset_sent=net_host_client_send_command(&client,NET_HOST_RESET)
    }
   }
   // Report every newly applied canonical revision over reliable transport.
   // The server checks it against its own recorded canonical hash.
   for a in client.applied {
    writer:nc.Writer;nc.writer_init(&writer,32)
    nc.write_u8(&writer,NET_REAL_HASH_REPORT)
    nc.write_u32(&writer,a.epoch)
    nc.write_u64(&writer,a.revision)
    nc.write_u64(&writer,a.hash)
    _=nc.client_send_reliable(&client.nc_client,writer.data[:])
    nc.writer_destroy(&writer)
   }
   clear(&client.applied)
   last_tick=now
  }
  packets:=nc.client_take_outgoing(&client.nc_client)
  for p in packets { _=nc.socket_send(&sock,target,p.data) }
  nc.outgoing_free(&packets)
  if client.real_reason!="" || client.nc_client.state==.Failed || client.nc_client.state==.Timed_Out || client.nc_client.state==.Disconnected {
   fmt.eprintf("bot disconnected: %v (%s) (%s)\n",client.nc_client.state,client.nc_client.reject_reason,client.real_reason)
   return false
  }
  if hidden_window {
   rl.BeginDrawing()
   rl.ClearBackground({19,28,42,255})
   net_client_draw(&client,sandbox_view(1280,800))
   rl.EndDrawing()
  }
  if now>=next_report {
   fmt.printf("BOT time=%.0fs state=%v epoch=%d revision=%d RTT=%.0fms delay=%d frames=%d structure_errors=%d late=%d\n",now,client.nc_client.state,client.epoch,client.rep.scene.structure_revision,client.nc_client.endpoint.stats.rtt*1000,client.delay,client.stats.frames_complete,client.stats.structure_errors,client.stats.late_messages)
   next_report+=10
  }
  time.sleep(time.Millisecond)
 }
 fmt.printf("BOT done: frames=%d structures=%d errors=%d\n",client.stats.frames_complete,client.stats.structure_applied,client.stats.structure_errors)
 return client.stats.frames_complete>0 && client.stats.structure_errors==0
}

net_real_cli_server :: proc(args: []string) -> bool {
 port:=NET_REAL_PORT
 layout:=""
 seconds:=f64(0)
 host_token:=""
 i:=0
 for i<len(args) {
  switch args[i] {
  case "--port":
   if i+1>=len(args) { fmt.eprintln("--port requires 1..65535");return false }
   p,ok:=net_real_cli_port(args[i+1]);if !ok { fmt.eprintln("Invalid port");return false };port=p;i+=2
  case "--layout":
   if i+1>=len(args) { fmt.eprintln("--layout needs a path");return false };layout=args[i+1];i+=2
  case "--seconds":
   if i+1>=len(args) { return false }
   n,ok:=strconv.parse_int(args[i+1]);if !ok || n<1 { return false };seconds=f64(n);i+=2
  case "--host-token":
   if i+1>=len(args) || len(args[i+1])<16 || len(args[i+1])>NET_APP_MAX_TOKEN {
    fmt.eprintln("--host-token requires a random secret of 16..128 characters");return false
   }
   host_token=args[i+1];i+=2
  case: fmt.eprintln("Unknown --server option:",args[i]);return false
  }
 }
 return net_real_run_server(port,layout,seconds,host_token)
}

net_real_cli_bot :: proc(args: []string,hidden_window: bool = false) -> bool {
 if len(args)<1 { fmt.eprintln("Usage: --bot-client 127.0.0.1:47380 [--seconds 60]");return false }
 target,ok:=net_real_parse_target(args[0]);if !ok { fmt.eprintln("Expected numeric IPv4:port");return false }
 seconds:=f64(60)
 host_token:=""
 protocol_version:=GAME_PROTOCOL_VERSION
 upload_path:=""
 request_reset:=false
 i:=1
 for i<len(args) {
  switch args[i] {
  case "--seconds":
   if i+1>=len(args) { return false }
   n,parsed:=strconv.parse_int(args[i+1]);if !parsed || n<1 { return false };seconds=f64(n);i+=2
  case "--host-token":
   if i+1>=len(args) || len(args[i+1])>NET_APP_MAX_TOKEN { return false }
   host_token=args[i+1];i+=2
  case "--bad-version":
   protocol_version=GAME_PROTOCOL_VERSION+1;i+=1
  case "--upload-layout":
   if i+1>=len(args) { return false };upload_path=args[i+1];i+=2
  case "--host-reset":
   request_reset=true;i+=1
  case: fmt.eprintln("Unknown bot option:",args[i]);return false
  }
 }
 return net_real_run_bot(target,seconds,hidden_window,host_token,protocol_version,upload_path,request_reset)
}
