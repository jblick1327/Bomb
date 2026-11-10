package main

import nc "netcode"
import rl "vendor:raylib"
import "core:os"
import "core:fmt"
import "core:time"
import "core:crypto"

// A live human client and editor UI, independent from the solo World.
// The server remains on loopback for this integration increment.
Net_Game_UI :: struct {
 open: bool,
 target_text: [65]u8,
 target_edit: bool,
 active: bool,
 hosting: bool,
 socket: nc.Socket,
 client: Net_Client,
 target: nc.Address,
 start: time.Tick,
 last_step: f64,
 server_process: os.Process,
 server_started: bool,
 token: string,
}

net_gui_init :: proc(ui: ^Net_Game_UI) {
 ui^={}
 copy(ui.target_text[:], "127.0.0.1:47380")
}

net_gui_flush :: proc(ui: ^Net_Game_UI) {
 outgoing:=nc.client_take_outgoing(&ui.client.nc_client)
 for p in outgoing { _=nc.socket_send(&ui.socket,ui.target,p.data) }
 nc.outgoing_free(&outgoing)
}

net_gui_reap_server :: proc(ui:^Net_Game_UI)->bool {
 if !ui.server_started { return false }
 _,err:=os.process_wait(ui.server_process,timeout=0)
 if err==os.General_Error.Timeout { return false }
 ui.server_started=false;ui.server_process={}
 return true
}

net_gui_leave :: proc(ui: ^Net_Game_UI,game: ^Sandbox) {
 if ui.hosting && ui.server_started && ui.active && !ui.client.real_hello_ok {
  // If the host leaves before Hello finishes, the server never saw a HOST
  // and therefore cannot trigger its normal five-second shutdown.
  _=os.process_kill(ui.server_process)
 }
 if ui.active {
  nc.client_disconnect(&ui.client.nc_client)
  net_gui_flush(ui)
  net_client_destroy(&ui.client)
  nc.socket_close(&ui.socket)
  ui.active=false
 }
 sandbox_set_panel(game,false)
 if !game.editor.editing {
  sandbox_toggle_editor(game)
 }
 ui.open=false
 ui.hosting=false
 delete(ui.token);ui.token=""
 sandbox_clear_input(game)
}

net_gui_destroy :: proc(ui: ^Net_Game_UI) {
 if ui.hosting && ui.server_started && ui.active && !ui.client.real_hello_ok {
  _=os.process_kill(ui.server_process)
 }
 if ui.active {
  nc.client_disconnect(&ui.client.nc_client)
  net_gui_flush(ui)
  net_client_destroy(&ui.client)
  nc.socket_close(&ui.socket)
 }
 delete(ui.token)
 ui^={}
}

// Uses OS cryptographic entropy; no editable or guessable host token.
net_gui_make_token :: proc() -> string {
 bytes:[16]u8
 crypto.rand_bytes(bytes[:])
 return fmt.aprintf("%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
  bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
  bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15])
}

net_gui_connect :: proc(ui: ^Net_Game_UI, game: ^Sandbox, address: nc.Address, token: string="") -> bool {
 if ui.active { return false }
 if !nc.socket_open(&ui.socket) { sandbox_notice(game,"Could not open UDP socket");return false }
 net_client_init(&ui.client,nc.random_salt(),0)
 ui.client.real_gate=true
 ui.client.verify=true
 ui.client.real_host_token=token
 ui.client.bot_enabled=false
 ui.start=time.tick_now()
 ui.last_step=0
 ui.target=address
 ui.active=true
 ui.open=false
 return true
}

net_gui_join :: proc(ui: ^Net_Game_UI,game: ^Sandbox) -> bool {
 target,ok:=net_real_parse_target(string(cstring(raw_data(ui.target_text[:]))) )
 if !ok { sandbox_notice(game,"Use numeric IPv4:port, e.g. 127.0.0.1:47380");return false }
 if !net_gui_connect(ui,game,target) { return false }
 // A guest never edits the server's scene; keep the local authored layout intact.
 game.editor.editing=false
 sandbox_set_panel(game,false)
 return true
}

net_gui_host :: proc(ui: ^Net_Game_UI,game: ^Sandbox) -> bool {
 if ui.active { return false }
 _=net_gui_reap_server(ui)
 if ui.server_started { sandbox_notice(game,"The previous session is closing. Try again in a moment.");return false }
 // Server reads exactly the current editor layout, not a stale autosave.
 if !sandbox_save_layout_file(game,"output/step3-host-layout.json") {
  sandbox_notice(game,"Could not save host layout");return false
 }
 token:=net_gui_make_token()
 executable:=os.args[0]
 args:=[]string{executable,"--server","--port","47380","--host-token",token,"--layout","output/step3-host-layout.json"}
 process,err:=os.process_start(os.Process_Desc{command=args,stdout=os.stdout,stderr=os.stderr})
 if err!=nil {
  delete(token)
  sandbox_notice(game,"Could not start local server (port in use?)")
  return false
 }
 ui.server_process=process
 ui.server_started=true
 ui.token=token
 ui.hosting=true
 if !net_gui_connect(ui,game,nc.address_loopback(NET_REAL_PORT),token) {
  _=os.process_kill(ui.server_process)
  ui.hosting=false
  delete(ui.token);ui.token=""
  return false
 }
 // Don't rebuild the local scene just to enter multiplayer Test.
 game.editor.editing=false
 sandbox_set_panel(game,false)
 return true
}

// Real socket receive + the exact 2b client path, paced at the server's 60 Hz.
net_gui_step :: proc(ui: ^Net_Game_UI,game: ^Sandbox) {
 if net_gui_reap_server(ui) && ui.hosting && ui.active {
  net_gui_leave(ui,game);sandbox_notice(game,"The local server stopped. Check that its port is available.");return
 }
 if !ui.active { return }
 now:=time.duration_seconds(time.tick_since(ui.start))
 buf:[nc.MAX_PACKET+64]u8
 for {
  packet,from,ok:=nc.socket_receive(&ui.socket,buf[:])
  if !ok { break }
  if from==ui.target { nc.client_receive(&ui.client.nc_client,packet,now) }
 }
 steps:=0
 for now-ui.last_step>=NET_STEP_DT && steps<5 {
  ui.last_step+=NET_STEP_DT
  net_client_step(&ui.client,now)
  // The same canonical-hash feedback used by the headless smoke client.
  for applied in ui.client.applied {
   w:nc.Writer;nc.writer_init(&w,32)
   nc.write_u8(&w,NET_REAL_HASH_REPORT)
   nc.write_u32(&w,applied.epoch)
   nc.write_u64(&w,applied.revision)
   nc.write_u64(&w,applied.hash)
   _=nc.client_send_reliable(&ui.client.nc_client,w.data[:])
   nc.writer_destroy(&w)
  }
  clear(&ui.client.applied)
  steps+=1
 }
 if steps==5 && now-ui.last_step>=NET_STEP_DT { ui.last_step=now }
 net_gui_flush(ui)
 c:=&ui.client
 if ui.hosting && c.real_hello_ok && !c.real_is_host {
  net_gui_leave(ui,game);sandbox_notice(game,"Could not host: another session is using that port.");return
 }
 if c.real_host_left || c.real_reason!="" || c.nc_client.state==.Timed_Out || c.nc_client.state==.Failed || c.nc_client.state==.Disconnected {
  reason:="Disconnected from server"
  if c.real_reason!="" { reason=c.real_reason }
  else if c.nc_client.reject_reason!="" { reason=c.nc_client.reject_reason }
  message:=fmt.aprintf("Multiplayer: %s",reason)
  net_gui_leave(ui,game)
  sandbox_notice(game,message)
  delete(message)
 }
}

// Raylib's query needs a posed outline. Check a local copy of the logical
// cells with the interpolated draw poses, never the static/rest-frame scene.
net_gui_aim_valid :: proc(c: ^Net_Client,point: Vec2) -> bool {
 if !c.has_epoch || !c.has_complete { return false }
 poses,frames:=net_client_draw_inputs(c)
 defer { delete(poses);delete(frames) }
 for sub in c.rep.scene.subdivisions {
  if !sub.live { continue }
  pose,ok:=poses[sub.id]
  if !ok { continue }
  posed:=sub;posed.pose=pose
  if point_in_subdivision(posed,point) { return false }
 }
 return true
}

net_gui_blast :: proc(c: ^Net_Client,point: Vec2) {
 c.blast_seq+=1
 if len(c.blasts)>=NET_MAX_BLASTS { ordered_remove(&c.blasts,0);c.stats.blasts_dropped+=1 }
 append(&c.blasts,Net_Blast{seq=c.blast_seq,x=nc.quantize_pos(point.x),y=nc.quantize_pos(point.y),radius_q=c.radius_q})
 c.stats.blasts_issued+=1
}

net_gui_human_input :: proc(ui: ^Net_Game_UI,game: ^Sandbox,view: View,over_ui: bool) {
 if !ui.active { return }
 c:=&ui.client
 c.human_move=0
 if ui.open || game.panel_open || game.editor.editing || !c.real_hello_ok { return }
 if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) { c.human_move-=1 }
 if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { c.human_move+=1 }
 if rl.IsKeyPressed(.SPACE) && !game.block_jump { c.human_jump_pending=true }
 if rl.IsMouseButtonPressed(.LEFT) && !game.block_blast && !over_ui && c.real_settings.blast_mode==.Manual {
  point:=world_point(view,rl.GetMousePosition())
  if net_gui_aim_valid(c,point) { net_gui_blast(c,point) }
 }
 if c.real_is_host && rl.IsKeyPressed(.R) { _=net_host_client_send_command(c,NET_HOST_RESET) }
 if c.real_is_host && c.real_has_settings && !over_ui && rl.GetMouseWheelMove()!=0 {
  radius:=clamp(c.real_settings.blast_radius+rl.GetMouseWheelMove()*0.2,f32(0.5),f32(6))
  _=net_host_client_send_command(c,NET_HOST_BOMB_RADIUS,radius=radius)
 }
 if c.real_is_host && rl.IsKeyPressed(.ENTER) {
  sandbox_set_panel(game,false)
  sandbox_dispatch_ui(game,.Toggle_Editor,ui)
 }
}

// Keep local editor and modal input alive while authoritative gameplay keeps
// going through the network. Mouse-up releases the editor's placement latch.
net_gui_route_input :: proc(ui:^Net_Game_UI,game:^Sandbox,raw:Sandbox_Input,view:View,over_ui:bool) {
 ui.client.human_move=0
 if raw.menu_pressed {
  if game.palette_open { game.palette_open=false;sandbox_clear_input(game) }
  else { sandbox_set_panel(game,!game.panel_open) }
  return
 }
 if game.panel_open { return }
 if !raw.blast_down { game.block_blast=false }
 if !raw.jump_down { game.block_jump=false }
 if raw.inspection_pressed && !game.editor.editing { game.inspection=!game.inspection }
 if game.editor.editing {
  if raw.edit_pressed { sandbox_dispatch_ui(game,.Toggle_Editor,ui) }
  return
 }
 net_gui_human_input(ui,game,view,over_ui)
}

net_gui_upload_and_test :: proc(ui: ^Net_Game_UI,game: ^Sandbox) {
 if !ui.active || !ui.client.real_is_host { return }
 data,ok:=encode_layout(&game.layout,game.world.settings.seed)
 if !ok { sandbox_notice(game,"Could not encode layout");return }
 defer delete(data)
 if !net_host_client_send_layout(&ui.client,data) {
  sandbox_notice(game,"Layout upload could not be queued");return
 }
 sandbox_toggle_editor(game)
 sandbox_notice(game,"Uploaded layout to server")
}

net_gui_draw_local_outline :: proc(ui: ^Net_Game_UI,view: View) {
 c:=&ui.client
 if !c.real_hello_ok { return }
 row,ok:=c.drawn[ent_key(.Player,u64(c.nc_client.client_index))]
 if !ok { return }
 pos:=screen_point(view,{row.x,row.y})
 r:=PLAYER_RADIUS*view.scale+4
 h:=PLAYER_SEGMENT*view.scale+r
 rl.DrawRectangleRoundedLinesEx({pos.x-r,pos.y-h,2*r,2*h},0.4,8,2,YARD_INK)
}

net_gui_aim_draw :: proc(ui: ^Net_Game_UI,view: View,mouse: rl.Vector2) {
 if !ui.active || !ui.client.real_hello_ok || ui.client.real_settings.blast_mode!=.Manual { return }
 point:=world_point(view,mouse)
 good:=net_gui_aim_valid(&ui.client,point)
 color:=rl.Color{245,206,133,200}
 if !good { color={244,132,131,230} }
 radius:=ui.client.real_settings.blast_radius
 sandbox_aim_ring(mouse,radius*view.scale,color)
 rl.DrawCircleV(mouse,3,color)
}

net_gui_draw_panel :: proc(ui: ^Net_Game_UI,game: ^Sandbox,width,height: f32) -> Sandbox_UI_Action {
 if !ui.open { return .None }
 rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,210})
 box:=menu_box(width,height,540,350);x,y:=box.x,box.y
 rl.DrawRectangleRounded(box,0.025,8,{23,35,49,255})
 ui_text(.Title,"Multiplayer",i32(x+28),i32(y+24),YARD_INK)
 if ui_button({x+430,y+22,82,36},"Back") { ui.open=false;ui.target_edit=false;return .Open }
 if ui.active {
  c:=&ui.client
  line:cstring="Connecting..."
  if c.real_hello_ok { line=rl.TextFormat("Connected as player %d",c.nc_client.client_index+1) }
  ui_label(.Body,line,{x+28,y+98,484,34},YARD_ACCENT)
  if c.real_is_host { ui_label(.Small,"You are hosting this session.",{x+28,y+145,484,26},YARD_MUTED) }
  if ui_button({x+28,y+238,484,44},"Leave session") { net_gui_leave(ui,game) }
 } else {
  ui_label(.Small,"Server address",{x+28,y+84,484,26},YARD_MUTED)
  if rl.GuiTextBox({x+28,y+118,484,40},cstring(raw_data(ui.target_text[:])),65,ui.target_edit) { ui.target_edit=!ui.target_edit }
  if ui_button({x+28,y+188,234,44},"Host") { _=net_gui_host(ui,game) }
  if ui_button({x+278,y+188,234,44},"Join") { _=net_gui_join(ui,game) }
  ui_label(.Small,"Hosting currently supports this computer only.",{x+28,y+255,484,26},YARD_MUTED)
 }
 if game.status_time>0 { ui_label(.Small,rl.TextFormat("%s",game.status),{x+28,y+310,484,22},YARD_ACCENT,true) }
 return .None
}
