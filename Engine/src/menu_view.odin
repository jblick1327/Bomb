package main

import rl "vendor:raylib"

Menu_Page :: enum { Main, Gameplay, Appearance, Help }

menu_box :: proc(width,height,w,h:f32)->rl.Rectangle { return {(width-w)*0.5,(height-h)*0.5,w,h} }
menu_button :: proc(box:rl.Rectangle,row:int)->rl.Rectangle { return {box.x+28,box.y+82+f32(row)*52,box.width-56,42} }

sandbox_draw_menu :: proc(game:^Sandbox,width,height:f32,net:^Net_Game_UI=nil)->Sandbox_UI_Action {
 rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,205})
 online:=net!=nil && net.active
 page:=game.menu_page
 w,h:=f32(480),f32(410)
 if page==.Gameplay { h=330 }
 if page==.Appearance { h=260 }
 if page==.Help { w=700;h=570 }
 box:=menu_box(width,height,w,h)
 rl.DrawRectangleRounded(box,0.025,8,{23,35,49,255})
 title:cstring="Menu"
 switch page { case .Gameplay:title="Gameplay";case .Appearance:title="Appearance";case .Help:title="Controls";case .Main: }
 ui_text(.Title,title,i32(box.x+28),i32(box.y+24),YARD_INK)
 if page==.Main {
  if ui_button(menu_button(box,0),"Gameplay") { return .Gameplay }
  if ui_button(menu_button(box,1),"Appearance") { return .Appearance }
  if ui_button(menu_button(box,2),"Multiplayer") { return .Multiplayer }
  if ui_button(menu_button(box,3),"Help") { return .Help }
  if ui_button(menu_button(box,4),"Resume") { return .Resume }
 } else {
  if ui_button({box.x+box.width-110,box.y+22,82,36},"Back") { return .Open }
  if page==.Gameplay {
   mode:=i32(sandbox_mode(game));radius:=sandbox_radius(game)
   ready:=!online || net.client.real_has_settings
   editable:=!online || net.client.real_is_host && ready
   if online { mode=i32(net.client.real_settings.blast_mode);radius=net.client.real_settings.blast_radius }
   old_mode,old_radius:=mode,radius
   if !editable { rl.GuiDisable() }
   _=rl.GuiToggleGroup({box.x+28,box.y+94,(box.width-64)*0.5,34},"Manual blasts;Falling bombs",&mode)
   sandbox_slider(box.x+28,box.y+158,box.width-56,"Blast radius",&radius,0.5,6,true)
   if !editable { rl.GuiEnable() }
   if editable {
    if online {
     if mode!=old_mode { _=net_host_client_send_command(&net.client,NET_HOST_MODE,u8(mode)) }
     if radius!=old_radius { _=net_host_client_send_command(&net.client,NET_HOST_BOMB_RADIUS,radius=radius) }
    } else { sandbox_set_blast_mode(game,Blast_Mode(mode));sandbox_set_radius(game,radius) }
   }
   if !ready { ui_label(.Small,"Waiting for server settings...",{box.x+28,box.y+235,box.width-56,24},YARD_MUTED) }
   else if !editable { ui_label(.Small,"The host controls gameplay settings.",{box.x+28,box.y+235,box.width-56,24},YARD_MUTED) }
  }
  if page==.Appearance {
   sandbox_slider(box.x+28,box.y+98,box.width-56,"Outline width",&game.outline_width,0,2,true)
  }
  if page==.Help {
   x,y:=box.x+28,box.y+88
   ui_text(.Heading,"Build",i32(x),i32(y),YARD_ACCENT)
   lines:=[5]cstring{"Drag to place / Right click to remove","1-8: material / T: rectangle or wedge","Q / E: rotate / G: glue / M: mortar","Ctrl+S: save layout / Drop a layout file to open","Enter: switch between Edit and Test"}
   for line,i in lines { ui_label(.Body,line,{x,y+34+f32(i)*30,box.width-56,26},YARD_INK) }
   y+=210
   ui_text(.Heading,"Play",i32(x),i32(y),YARD_ACCENT)
   play:=[3]cstring{"A / D or arrows: move / Space: jump","Click: blast / Mouse wheel: blast radius","R: reset / Tab or Escape: menu / F3: diagnostics"}
   for line,i in play { ui_label(.Body,line,{x,y+34+f32(i)*30,box.width-56,26},YARD_INK) }
   ui_label(.Small,"In multiplayer, the host edits layouts and changes gameplay settings.",{x,box.y+box.height-60,box.width-56,26},YARD_MUTED,true)
  }
 }
 if game.status_time>0 { ui_label(.Small,rl.TextFormat("%s",game.status),{box.x+28,box.y+box.height-35,box.width-56,22},YARD_ACCENT,true) }
 return .None
}

palette_button :: proc()->rl.Rectangle { return {16,f32(rl.GetScreenHeight())-66,228,38} }
palette_popup :: proc(game:^Sandbox,height:f32)->rl.Rectangle {
 h:=f32(palette_count(&game.layout)+1)*40+16
 return {16,height-88-h,270,h}
}
sandbox_draw_editor_toolbar :: proc(game:^Sandbox,width,height:f32)->Sandbox_UI_Action {
 disabled:=game.panel_open
 if disabled { rl.GuiDisable() }
 material:=layout_material(&game.layout,game.editor.palette)
 if ui_button({16,height-66,228,38},rl.TextFormat("   %s",material.name)) { game.palette_open=!game.palette_open;game.editor.dragging=false }
 rl.DrawRectangle(22,i32(height)-53,10,12,material_color(material))
 shape:cstring="Rectangle";if game.editor.shape==.Wedge { shape="Wedge" }
 if ui_button({256,height-66,120,38},shape) { if game.editor.shape==.Rect { game.editor.shape=.Wedge } else { game.editor.shape=.Rect } }
 if ui_button({388,height-66,38,38},"-") { game.editor.angle=angle_wrap(game.editor.angle-15) }
 ui_label(.Body,rl.TextFormat("%.0f\u00b0",game.editor.angle),{432,height-66,62,38},YARD_INK)
 if ui_button({500,height-66,38,38},"+") { game.editor.angle=angle_wrap(game.editor.angle+15) }
 glue:cstring="Glue";if game.editor.glue_tool { glue="Glue: on" }
 if ui_toggle({550,height-66,112,38},glue,&game.editor.glue_tool) { game.editor.glue_first=0;game.editor.dragging=false }
 mortar:cstring="Mortar";if game.editor.mortar { mortar="Mortar: on" }
 _=ui_toggle({674,height-66,132,38},mortar,&game.editor.mortar)
 if disabled { rl.GuiEnable() }
 if !game.palette_open || disabled { return .None }
 popup:=palette_popup(game,height)
 rl.DrawRectangleRounded(popup,0.03,8,{23,35,49,255})
 for i in 0..<palette_count(&game.layout) {
  m:=layout_material(&game.layout,Slot(i));row:=rl.Rectangle{popup.x+8,popup.y+8+f32(i)*40,popup.width-16,34}
  if ui_button(row,rl.TextFormat("%d   %s",i+1,m.name)) { game.editor.palette=Slot(i);game.palette_open=false }
  if game.editor.palette==Slot(i) { rl.DrawRectangleLinesEx(row,1,YARD_ACCENT) }
 }
 if ui_button({popup.x+8,popup.y+8+f32(palette_count(&game.layout))*40,popup.width-16,34},"Manage materials") {
  game.material_selected=int(game.editor.palette);return .Materials
 }
 if rl.IsMouseButtonPressed(.LEFT) && !rl.CheckCollisionPointRec(rl.GetMousePosition(),popup) && !rl.CheckCollisionPointRec(rl.GetMousePosition(),palette_button()) {
  game.palette_open=false;game.block_blast=true
 }
 return .None
}

sandbox_dispatch_ui :: proc(game:^Sandbox,action:Sandbox_UI_Action,net:^Net_Game_UI=nil) {
 if action==.Multiplayer && net!=nil {
  sandbox_set_panel(game,false);net.open=true;net.target_edit=false;return
 }
 if net!=nil && net.active {
  if action==.Toggle_Editor {
   if !net.client.real_is_host { return }
   if game.editor.editing { net_gui_upload_and_test(net,game) }
   else { sandbox_toggle_editor(game) }
   game.block_jump=rl.IsKeyDown(.SPACE);game.block_blast=rl.IsMouseButtonDown(.LEFT)
   return
  }
  if action==.Reset { if net.client.real_is_host { _=net_host_client_send_command(&net.client,NET_HOST_RESET) };return }
 }
 sandbox_handle_ui(game,action)
}
