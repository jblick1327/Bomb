package main

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

sandbox_smoke_aim :: proc() {
 g:=sandbox_editor_create(); defer sandbox_destroy(&g)
 g.editor.palette=recipe_slot(.Glass)
 assert(editor_place(&g,{1.5,0},{4.5,2})); sandbox_toggle_editor(&g)
 for _ in 0..<120 { sandbox_tick(&g,0,false) }
 before,ok:=encode_world_snapshot(&g.world); assert(ok); defer delete(before)
 view:=View{offset={640,520},scale=60}
 aim:=screen_point(view,{-1.5,1.5})
 poses:=make(map[u64]Pose); defer delete(poses)
 for sub in g.world.scene.subdivisions { poses[sub.id]=sub.pose }
 g.accumulator=1.0/60.0
 rl.BeginDrawing()
 rl.ClearBackground({19,28,42,255})
 sandbox_draw_world(&g,view,poses)
 sandbox_draw_aim(&g,view,aim)
 ui_text(.Title,"Damage: 3.8    /    Shove: 5.0",32,28,YARD_INK)
 ui_text(.Heading,"Glass in view  /  Paused capture",32,62,YARD_MUTED)
 rlgl.DrawRenderBatchActive()
 image:=rl.LoadImageFromScreen()
 rl.EndDrawing()
 assert(rl.ExportImage(image,"evidence/world-v3/aim-glass.png")); rl.UnloadImage(image)
 after,encoded:=encode_world_snapshot(&g.world); defer delete(after)
 assert(encoded && string(before)==string(after),"Aim rendering must not change the world")
}
