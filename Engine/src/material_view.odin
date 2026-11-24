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
sandbox_draw_materials_panel :: proc(game:^Sandbox,width,height:f32)->Sandbox_UI_Action {
 rl.DrawRectangle(0,0,i32(width),i32(height),{8,14,23,205})
 selected:=game.material_selected;builtin:=selected<4
 w:=min(f32(800),width-48)
 h:=f32(600);if builtin { h=max(f32(420),130+f32(palette_count(&game.layout))*38) }
 box:=menu_box(width,height,w,h);x,y:=box.x,box.y
 rl.DrawRectangleRounded(box,0.025,8,{23,35,49,255})
 ui_text(.Title,"Materials",i32(x+24),i32(y+22),YARD_INK)
 if ui_button({x+w-112,y+20,88,36},"Done") { materials_commit_name(game);game.editor.palette=Slot(game.material_selected);return .Resume }
 for i in 0..<palette_count(&game.layout) {
  row:=rl.Rectangle{x+24,y+82+f32(i)*38,184,32}
  m:=layout_material(&game.layout,Slot(i))
  if ui_button(row,rl.TextFormat("   %s",m.name)) { materials_commit_name(game);game.material_selected=i;materials_sync_name(game) }
  if game.material_selected==i { rl.DrawRectangleLinesEx(row,1,YARD_ACCENT) }
  rl.DrawRectangle(i32(row.x+9),i32(row.y+10),10,12,material_color(m))
 }
 // Selection can change this frame; use the same geometry until the next frame.
 if selected!=game.material_selected { return .None }
 px,rw:=x+232,w-256
 base:=layout_base(&game.layout,Slot(selected))
 if builtin {
  ui_label(.Heading,ui_recipe_name(base),{px,y+86,rw,30},YARD_INK)
  description:cstring="Breaks into heavy chunks."
  switch base { case .Wood:description="Splits into long strips.";case .Glass:description="Shatters into sharp fragments.";case .Rubber:description="Bends and stretches.";case .Stone: }
  ui_label(.Body,description,{px,y+132,rw,30},YARD_MUTED)
  full:=len(game.layout.materials)>=4
  if full { rl.GuiDisable() }
  if ui_button({px,y+204,min(rw,260),42},"Create custom copy") {
   materials_commit_name(game)
   if materials_duplicate_slot(game,Slot(selected)) { game.editor.palette=Slot(game.material_selected) }
  }
  if full { rl.GuiEnable();ui_label(.Small,"Four custom materials maximum.",{px,y+260,rw,24},YARD_MUTED) }
 } else {
  m:=game.layout.materials[selected-4]
  if rl.GuiTextBox({px,y+82,rw,36},cstring(raw_data(game.material_name_buffer[:])),81,game.material_name_edit) {
   if game.material_name_edit { materials_commit_name(game) } else { game.material_name_edit=true }
  }
  name:=string(cstring(raw_data(game.material_name_buffer[:])))
  if game.material_name_edit && name!=m.name && material_name_problem(&game.layout,name,selected-4)=="" { materials_rename(game,selected-4,name) }
  ui_label(.Small,rl.TextFormat("Based on %s",ui_recipe_name(base)),{px,y+125,rw,22},YARD_MUTED)
  old:=m
  material_compact_slider(px,y+160,rw,"Toughness","How hard it is to break.",&m.toughness,0.25,4,0.05)
  material_compact_slider(px,y+242,rw,"Blast resistance","How much it shields objects behind it.",&m.blast_resistance,0,6,0.1)
  switch base {
  case .Wood:material_compact_slider(px,y+324,rw,"Strip thickness","Lower values make finer strips.",&m.strip_thickness,STRIP_MIN,0.6,0.01)
  case .Glass:material_compact_slider(px,y+324,rw,"Shock loss","Lower values let cracks travel further.",&m.shock_loss,1,12,0.5)
  case .Rubber:material_compact_slider(px,y+324,rw,"Flexibility","Lower values make it stiffer.",&m.flexibility,0.2,1,0.05)
  case .Stone:
  }
  ui_label(.Small,"Colour",{px,y+412,rw,22},YARD_MUTED)
  for c,i in MATERIAL_SWATCHES {
   swatch:=rl.Rectangle{px+f32(i)*(rw/12),y+442,min(f32(34),rw/12-5),28}
   rl.DrawRectangleRec(swatch,{c[0],c[1],c[2],255})
   if m.color==c { rl.DrawRectangleLinesEx({swatch.x-2,swatch.y-2,swatch.width+4,32},1,YARD_INK) }
   if rl.IsMouseButtonReleased(.LEFT) && rl.CheckCollisionPointRec(rl.GetMousePosition(),swatch) { m.color=c }
  }
  if old.toughness!=m.toughness || old.blast_resistance!=m.blast_resistance || old.strip_thickness!=m.strip_thickness || old.shock_loss!=m.shock_loss || old.flexibility!=m.flexibility || old.color!=m.color {
   stored:=&game.layout.materials[selected-4];stored.toughness=m.toughness;stored.blast_resistance=m.blast_resistance;stored.strip_thickness=m.strip_thickness;stored.shock_loss=m.shock_loss;stored.flexibility=m.flexibility;stored.color=m.color;sandbox_layout_changed(game)
  }
  if len(game.layout.materials)>=4 { rl.GuiDisable() }
  if ui_button({px,y+500,132,38},"Duplicate") { materials_commit_name(game);materials_duplicate_slot(game,Slot(selected)) }
  rl.GuiEnable()
  used:=material_usage(&game.layout,selected-4)
  if used>0 { rl.GuiDisable() }
  if ui_button({px+146,y+500,90,38},"Delete") { materials_delete(game,selected-4) }
  rl.GuiEnable()
  if used>0 { ui_label(.Small,rl.TextFormat("Used by %d objects",used),{px,y+548,rw,22},YARD_MUTED) }
 }
 if game.status_time>0 { ui_label(.Small,rl.TextFormat("%s",game.status),{x+24,y+h-33,w-48,22},YARD_ACCENT,true) }
 return .None
}

material_compact_slider :: proc(x,y,width:f32,label,help:cstring,value:^f32,low,high,step:f32) {
 ui_label(.Heading,label,{x,y,width-80,24},YARD_INK)
 ui_label(.Body,rl.TextFormat("%.2f",value^),{x+width-75,y,75,24},YARD_ACCENT)
 old:=value^
 _=rl.GuiSlider({x,y+30,width,14},nil,nil,value,low,high)
 if value^!=old { units:=f32(math.round(1/step));value^=clamp(f32(math.round(value^*units))/units,low,high) }
 ui_label(.Small,help,{x,y+50,width,22},YARD_MUTED)
}
