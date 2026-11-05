package main
import rl "vendor:raylib"
import "core:math"

MATERIAL_SWATCHES :: [12][3]u8{
 {180,136,82},{86,153,174},{162,112,184},{131,145,152},
 {231,104,91},{244,177,79},{236,215,119},{111,220,190},
 {102,160,231},{218,137,190},{225,230,222},{66,77,104},
}
materials_sync_name :: proc(game:^Sandbox) {
 game.material_name_buffer={}; game.material_name_edit=false
 if game.material_selected>=4 {
  name:=game.layout.materials[game.material_selected-4].name
  copy(game.material_name_buffer[:80],transmute([]u8)name)
 }
}
materials_commit_name :: proc(game:^Sandbox) {
 if game.material_selected<4 { return }
 name:=string(cstring(raw_data(game.material_name_buffer[:])))
 if name!=game.layout.materials[game.material_selected-4].name { materials_rename(game,game.material_selected-4,name) }
 materials_sync_name(game)
}
sandbox_set_materials_panel :: proc(game:^Sandbox) {
 sandbox_set_panel(game,true); game.materials_open=true
 game.material_selected=clamp(game.material_selected,0,palette_count(&game.layout)-1)
 materials_sync_name(game)
}
material_slider :: proc(x,y,width:f32,label,help:cstring,value:^f32,low,high,step:f32) {
 ui_label(.Heading,label,{x,y,width-80,24},YARD_INK)
 ui_label(.Body,rl.TextFormat("%.2f",value^),{x+width-75,y,75,24},YARD_ACCENT)
 disabled:=rl.GuiGetState()==i32(rl.GuiState.STATE_DISABLED)
 old:=value^
 _=rl.GuiSliderBar({x,y+31,width,14},nil,nil,value,low,high)
 fill:=YARD_ACCENT
 if disabled { fill={65,122,116,255} } // 45% accent over disabled track (28,42,56).
 rl.DrawRectangleRec({x+1,y+32,(width-2)*clamp((value^-low)/(high-low),0,1),12},fill)
 if value^!=old { units:=f32(math.round(1/step)); value^=clamp(f32(math.round(value^*units))/units,low,high) }
 ui_label(.Small,rl.TextFormat("%.2f",low),{x,y+46,80,20},YARD_MUTED)
 ui_label(.Small,rl.TextFormat("%.2f",high),{x+width-70,y+46,70,20},YARD_MUTED)
 ui_label(.Small,help,{x,y+68,width,22},YARD_MUTED)
}
sandbox_draw_materials_panel :: proc(game:^Sandbox,width,height:f32)->Sandbox_UI_Action {
 rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,205})
 w,h:=min(f32(1000),width-48),min(f32(720),height-56); x,y:=(width-w)/2,(height-h)/2
 rl.DrawRectangleRounded({x,y,w,h},0.025,8,{23,35,49,255})
 ui_panel_title("Materials",x+24,y+17)
 if ui_button({x+w-124,y+18,100,36},"Close") { materials_commit_name(game); return .Resume }
 ui_label(.Heading,"Built-in",{x+24,y+76,240,26},YARD_MUTED)
 ui_label(.Heading,rl.TextFormat("Custom (%d/4)",len(game.layout.materials)),{x+24,y+294,240,26},YARD_MUTED)
 for i in 0..<palette_count(&game.layout) {
  row:=y+110+f32(i)*43; if i>=4 { row=y+329+f32(i-4)*43 }
  box:=rl.Rectangle{x+24,row,240,36}; clicked:=rl.GuiButton(box,nil)
  if game.material_selected==i { rl.DrawRectangleRec(box,{48,78,88,255}) }
  m:=layout_material(&game.layout,Slot(i)); rl.DrawRectangle(i32(box.x+10),i32(box.y+12),12,12,material_color(m))
  ui_label(.Body,rl.TextFormat("%s",m.name),{box.x+34,box.y,box.width-42,box.height},YARD_INK,true)
  if clicked { materials_commit_name(game); game.material_selected=i; materials_sync_name(game) }
 }
 selected:=game.material_selected; builtin:=selected<4; m:=custom_defaults(layout_base(&game.layout,Slot(selected)))
 if !builtin { m=game.layout.materials[selected-4] }
 px,py,rw:=x+296,y,w-320
 if builtin {
  ui_label(.Heading,rl.TextFormat("%s",layout_material(&game.layout,Slot(selected)).name),{px,py+76,rw,38},YARD_INK)
  ui_label(.Small,"Built-in materials can't be changed.",{px,py+121,rw,21},YARD_MUTED)
  ui_label(.Small,"Duplicate to make an editable copy.",{px,py+143,rw,21},YARD_MUTED)
 } else {
  if rl.GuiTextBox({px,py+77,rw,36},cstring(raw_data(game.material_name_buffer[:])),81,game.material_name_edit) {
   if game.material_name_edit { materials_commit_name(game) } else { game.material_name_edit=true }
  }
  name:=string(cstring(raw_data(game.material_name_buffer[:])))
  if game.material_name_edit && name!=m.name && material_name_problem(&game.layout,name,selected-4)=="" { materials_rename(game,selected-4,name) }
  ui_label(.Small,rl.TextFormat("Based on %s",ui_recipe_name(m.base)),{px,py+125,rw,24},YARD_MUTED)
 }
 old:=m
 if builtin { rl.GuiDisable() }
 material_slider(px,py+176,rw,"Toughness","How hard it is to break. 2 = twice as strong.",&m.toughness,0.25,4,0.05)
 material_slider(px,py+274,rw,"Blast resistance","How much it shields things behind it from blasts.",&m.blast_resistance,0,6,0.1)
 switch m.base {
 case .Wood:material_slider(px,py+372,rw,"Strip thickness","Widest strip a plank is built from. Lower = finer planks.",&m.strip_thickness,STRIP_MIN,0.6,0.01)
 case .Glass:material_slider(px,py+372,rw,"Shock loss","How fast a crack's shock fades. Lower = shatters further.",&m.shock_loss,1,12,0.5)
 case .Rubber:material_slider(px,py+372,rw,"Flexibility","How much it bends. Lower = stiffer.",&m.flexibility,0.2,1,0.05)
 case .Stone:
 }
 ui_label(.Small,"Colour",{px,py+478,rw,21},YARD_MUTED)
 for c,i in MATERIAL_SWATCHES {
  box:=rl.Rectangle{px+f32(i)*(rw/12),py+503,min(f32(34),rw/12-5),28}
  rl.DrawRectangleRec(box,{c[0],c[1],c[2],255})
  if m.color==c { rl.DrawRectangleLinesEx({box.x-2,box.y-2,box.width+4,32},1,YARD_INK) }
  if !builtin && rl.IsMouseButtonReleased(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(),box) { m.color=c }
 }
 if builtin { rl.GuiEnable() }
 if !builtin && (old.toughness!=m.toughness || old.blast_resistance!=m.blast_resistance || old.strip_thickness!=m.strip_thickness || old.shock_loss!=m.shock_loss || old.flexibility!=m.flexibility || old.color!=m.color) {
  stored:=&game.layout.materials[selected-4]; stored.toughness=m.toughness; stored.blast_resistance=m.blast_resistance; stored.strip_thickness=m.strip_thickness; stored.shock_loss=m.shock_loss; stored.flexibility=m.flexibility; stored.color=m.color; sandbox_layout_changed(game)
 }
 full:=len(game.layout.materials)>=4
 if full { rl.GuiDisable() }
 if ui_button({px,py+555,132,38},"Duplicate") { materials_commit_name(game); materials_duplicate_slot(game,Slot(selected)) }
 rl.GuiEnable()
 if !builtin {
  used:=material_usage(&game.layout,selected-4); if used>0 { rl.GuiDisable() }
  if ui_button({px+146,py+555,90,38},"Delete") { materials_delete(game,selected-4) }
  rl.GuiEnable()
  if used>0 { ui_label(.Small,rl.TextFormat("Used by %d objects",used),{px+250,py+555,rw-250,38},YARD_MUTED) }
 }
 ui_label(.Small,"Tab / Escape closes",{x+24,y+h-30,240,22},YARD_MUTED)
 if full { ui_label(.Small,"4 customs maximum. Delete one to duplicate.",{px,y+h-30,rw,22},YARD_MUTED) }
 if game.status_time>0 { ui_label(.Small,rl.TextFormat("%s",game.status),{x+24,y+h-62,240,24},YARD_ACCENT,true) }
 return .None
}
