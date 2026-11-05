package main
import rl "vendor:raylib"
import "core:math"

UI_Style :: enum { Title, Heading, Body, Small }
UI_SIZES := [UI_Style]int{.Title=26,.Heading=18,.Body=17,.Small=15}
ui_fonts:[UI_Style]rl.Font
ui_fonts_ready:bool
ui_dpi:f32=1
ui_overflows:int
ui_font_init :: proc() {
 if ui_fonts_ready { return }
 ui_dpi=max(f32(1),rl.GetWindowScaleDPI().x)
 codepoints:[dynamic]rune; defer delete(codepoints)
 for c in 32..=126 { append(&codepoints,rune(c)) }; for c in 160..=255 { append(&codepoints,rune(c)) }
 for c in "×–—…·" { found:=false; for existing in codepoints { if existing==c { found=true } }; if !found { append(&codepoints,c) } }
 regular:=#load("assets/fonts/Inter-Regular.ttf"); semibold:=#load("assets/fonts/Inter-SemiBold.ttf")
 for style in UI_Style {
  data:=regular; if style==.Title || style==.Heading { data=semibold }
  ui_fonts[style]=rl.LoadFontFromMemory(".ttf",raw_data(data),i32(len(data)),i32(math.round(f32(UI_SIZES[style])*ui_dpi)),raw_data(codepoints),i32(len(codepoints)))
  assert(ui_fonts[style].texture.id!=0); rl.SetTextureFilter(ui_fonts[style].texture,.BILINEAR)
 }
 ui_fonts_ready=true
}
ui_font_shutdown :: proc() { if ui_fonts_ready { for font in ui_fonts { rl.UnloadFont(font) }; ui_fonts={}; ui_fonts_ready=false } }
ui_measure :: proc(style:UI_Style,text:cstring)->f32 { return rl.MeasureTextEx(ui_fonts[style],text,f32(UI_SIZES[style]),0).x }
ui_text :: proc(style:UI_Style,text:cstring,x,y:i32,color:rl.Color,box:rl.Rectangle = {}) {
 bounds:=box; if bounds.width==0 { bounds={f32(x),f32(y),f32(rl.GetScreenWidth()-x),f32(rl.GetScreenHeight()-y)} }
 if ui_measure(style,text)>bounds.width+0.5 || f32(UI_SIZES[style])>bounds.height+0.5 { ui_overflows+=1 }
 rl.DrawTextEx(ui_fonts[style],text,{f32(x),f32(y)},f32(UI_SIZES[style]),0,color)
}
ui_fit :: proc(style:UI_Style,text:cstring,width:f32)->cstring {
 if ui_measure(style,text)<=width { return text }
 s:=string(text)
 for len(s)>0 {
  end:=len(s)-1; for end>0 && s[end]&0xc0==0x80 { end-=1 }; s=s[:end]
  result:=rl.TextFormat("%s…",s); if ui_measure(style,result)<=width { return result }
 }
 return ""
}
ui_label :: proc(style:UI_Style,text:cstring,box:rl.Rectangle,color:rl.Color,fit:bool=false) {
 shown:=text; if fit { shown=ui_fit(style,text,box.width) }
 ui_text(style,shown,i32(math.round(box.x)),i32(math.round(box.y+(box.height-f32(UI_SIZES[style]))/2)),color,box)
}
ui_keycap :: proc(box:rl.Rectangle,key:cstring,color:rl.Color=YARD_MUTED) {
 rl.DrawRectangleRoundedLinesEx(box,0.3,6,1,color)
 ui_label(.Small,key,{box.x+(box.width-ui_measure(.Small,key))/2,box.y,ui_measure(.Small,key),box.height},color)
}
ui_button :: proc(box:rl.Rectangle,label:cstring,key:cstring=nil)->bool {
 result:=rl.GuiButton(box,nil)
 color:=YARD_INK; if rl.GuiGetState()==i32(rl.GuiState.STATE_DISABLED) { color=YARD_MUTED }
 room:=box.width-20
 if key!=nil { chip_width:=ui_measure(.Small,key)+12; room-=chip_width+8; ui_keycap({box.x+box.width-chip_width-8,box.y+8,chip_width,box.height-16},key,YARD_MUTED) }
 ui_label(.Body,label,{box.x+10,box.y,room,box.height},color,true)
 return result
}
ui_toggle :: proc(box:rl.Rectangle,label:cstring,value:^bool,key:cstring=nil)->bool {
 if ui_button(box,label,key) { value^=!value^; return true }; return false
}
ui_recipe_name :: proc(recipe:Recipe)->cstring { switch recipe { case .Wood:return "Wood";case .Glass:return "Glass";case .Rubber:return "Rubber";case .Stone:return "Stone" }; return "" }

ui_panel_title :: proc(title:cstring,x,y:f32) {
 ui_text(.Title,title,i32(x),i32(y),YARD_INK)
 ui_text(.Small,"Paused",i32(x+ui_measure(.Title,title)+18),i32(y+8),YARD_MUTED)
}
