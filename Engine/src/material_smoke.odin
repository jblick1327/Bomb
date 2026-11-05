package main
import rl "vendor:raylib"
import b2 "vendor:box2d"
import win "core:sys/windows"
import "core:mem"
import "core:os"
import "core:fmt"
import "core:time"

run_material_smoke :: proc() {
 rl.SetTraceLogLevel(.WARNING);rl.SetConfigFlags({.MSAA_4X_HINT,.WINDOW_HIDDEN,.WINDOW_RESIZABLE,.WINDOW_HIGHDPI})
 rl.InitWindow(1280,800,"Material UI verification");defer { presentation_shutdown();rl.CloseWindow() }
 sandbox_gui_style();rl.SetShapesTexture(rl.Texture2D{},rl.Rectangle{});rl.SetTargetFPS(0);rl.SetExitKey(.KEY_NULL)
 material_native_interactions()
}
material_native_interactions :: proc() {
 track:mem.Tracking_Allocator;mem.tracking_allocator_init(&track,context.allocator);defer mem.tracking_allocator_destroy(&track);context.allocator=mem.tracking_allocator(&track)
 before:=b2.GetByteCount()
 defer { fmt.printf("Materials native teardown: Odin=%d Box2D delta=%d\n",track.current_memory_allocated,b2.GetByteCount()-before);assert(track.current_memory_allocated==0 && b2.GetByteCount()==before) }
 g:=sandbox_editor_create();defer sandbox_destroy(&g)
 directory:=fmt.aprintf("output/material-ui-%d",time.to_unix_nanoseconds(time.now()));defer delete(directory);assert(os.make_directory_all(directory)==nil);g.layout_directory=directory
 target:=rl.LoadRenderTexture(1280,800);defer rl.UnloadRenderTexture(target)
 sandbox_smoke_frame(&g,target,smoke_mouse(20,40),smoke_button(false))
 // + New is the fifth slot before any custom exists.
 sandbox_smoke_click(&g,target,sandbox_smoke_palette_x(&g,4),752);assert(g.materials_open)
 sandbox_smoke_click(&g,target,500,614);assert(len(g.layout.materials)==1 && g.material_selected==4)
 // Loaded in-range values must remain exact until a UI edit occurs.
 g.layout.materials[0].toughness=1.234;g.layout.materials[0].strip_thickness=0.333;sandbox_layout_changed(&g)
 sandbox_smoke_frame(&g,target);assert(g.layout.materials[0].toughness==1.234 && g.layout.materials[0].strip_thickness==0.333)
 // The real slider snaps only this mouse edit; the duplicate must retain it.
 sandbox_smoke_click(&g,target,800,254);assert(g.layout.materials[0].toughness>1)
 sandbox_smoke_click(&g,target,678,557)
 original:=g.layout.materials[0]
 sandbox_smoke_click(&g,target,500,614);assert(len(g.layout.materials)==2 && g.layout.materials[1].toughness==original.toughness && g.layout.materials[1].color==original.color)
 sandbox_smoke_click(&g,target,624,614);assert(len(g.layout.materials)==1)
 // Edit the name through raygui's native character queue.
 sandbox_smoke_click(&g,target,700,135);assert(g.material_name_edit)
 sandbox_smoke_frame(&g,target,smoke_key(.END,true));sandbox_smoke_frame(&g,target,smoke_key(.END,false))
 for _ in 0..<6 { sandbox_smoke_frame(&g,target,smoke_key(.BACKSPACE,true));sandbox_smoke_frame(&g,target,smoke_key(.BACKSPACE,false)) }
 library:=win.LoadLibraryW("user32.dll");defer win.FreeLibrary(library)
 post:=cast(proc "system" (hwnd:rawptr,msg:u32,wparam:uintptr,lparam:int)->i32)win.GetProcAddress(library,"PostMessageW")
 for r in "Coral wood" { post(rl.GetWindowHandle(),0x0102,uintptr(r),1);sandbox_smoke_frame(&g,target);sandbox_smoke_frame(&g,target) }
 sandbox_smoke_frame(&g,target,smoke_key(.ENTER,true));sandbox_smoke_frame(&g,target,smoke_key(.ENTER,false));assert(g.layout.materials[0].name=="Coral wood")
 // Range endpoints; the value returns to the built-in target.
 sandbox_smoke_frame(&g,target,smoke_mouse(1090,450),smoke_button(true));sandbox_smoke_frame(&g,target,smoke_mouse(1150,450));sandbox_smoke_frame(&g,target,smoke_button(false));assert(g.layout.materials[0].strip_thickness==0.6)
 sandbox_smoke_frame(&g,target,smoke_mouse(440,450),smoke_button(true));sandbox_smoke_frame(&g,target,smoke_mouse(400,450));sandbox_smoke_frame(&g,target,smoke_button(false));assert(g.layout.materials[0].strip_thickness==STRIP_MIN)
 sandbox_smoke_frame(&g,target,smoke_key(.TAB,true));sandbox_smoke_frame(&g,target,smoke_key(.TAB,false));assert(!g.panel_open)
 // Keycap chips are decorative and the full underlying button remains clickable.
 sandbox_smoke_click(&g,target,1240,44);assert(g.panel_open);sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,true));sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,false))
 previous:=g.editor.mortar;sandbox_smoke_click(&g,target,1245,752);assert(g.editor.mortar!=previous);sandbox_smoke_click(&g,target,1245,752);assert(g.editor.mortar==previous)
 sandbox_smoke_frame(&g,target,smoke_key(.FIVE,true));sandbox_smoke_frame(&g,target,smoke_key(.FIVE,false));assert(g.editor.palette==Slot(4))
 editor_smoke_drag(&g,target,{0,0},{1.4,1.5});assert(len(g.layout.objects)==1)
 sandbox_smoke_click(&g,target,943,44);sandbox_smoke_click(&g,target,624,614);assert(len(g.layout.materials)==1 && material_usage(&g.layout,0)==1 && g.status!="In use by 1 objects")
 sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,true));sandbox_smoke_frame(&g,target,smoke_key(.ESCAPE,false))
 sandbox_smoke_click(&g,target,860,44);assert(!g.editor.editing)
 sandbox_smoke_click(&g,target,860,44);assert(g.editor.editing)
 sandbox_smoke_frame(&g,target,smoke_key(.LEFT_CONTROL,true),smoke_key(.S,true));sandbox_smoke_frame(&g,target,smoke_key(.LEFT_CONTROL,false),smoke_key(.S,false));assert(len(g.layout_files)==1)
 sandbox_smoke_click(&g,target,1060,44);sandbox_smoke_click(&g,target,640,353);assert(!g.panel_open && len(g.layout.materials)==1)
 assert(editor_remove(&g,{0.7,0.7}));sandbox_smoke_click(&g,target,943,44);g.material_selected=4;materials_sync_name(&g);sandbox_smoke_click(&g,target,624,614);assert(len(g.layout.materials)==0)
 fmt.println("Materials smoke passed: + New, duplicate built-in/custom with knobs, disabled Delete, name, snapping/endpoints, swatch, keycaps pass clicks, Test/Edit, save/load/autosave")
}
