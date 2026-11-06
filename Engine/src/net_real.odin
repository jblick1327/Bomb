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

// Strict dotted-decimal IPv4 parser; optional :port. DNS is intentionally not
// supported in this staging CLI. Every component must be decimal, 0..255.


// The in-process net server owns its Sandbox. Start with the actual Materials
// preset rather than the editor's empty yard; force Test so authored shapes exist.

// Fixed 60 Hz accumulator with a bounded catch-up. Call on a dedicated headless
// process. No raylib window or render initialization occurs in this path.

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
 client_view:Net_Client_View
 defer net_client_view_destroy(&client_view)
 net_client_init(&client,nc.random_salt(),0)
 bot:Bot; bot_init(&bot,42,true)
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
   net_client_step(&client,now,net_bot_client_input,&bot)
   if hidden_window { net_client_view_step(&client,&client_view) }
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
   net_client_draw(&client,&client_view,sandbox_view(1280,800))
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
