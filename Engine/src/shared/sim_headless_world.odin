#+feature dynamic-literals
package shared

import math "core:math"
import strings "core:strings"

Headless_Game :: struct { world: World, layout: Layout }

headless_game_destroy :: proc(game: ^Headless_Game) {
 scene_destroy(&game.world.scene)
 delete(game.world.bombs)
 destroy_layout(&game.layout)
 game^={}
}

headless_game_reset :: proc(game: ^Headless_Game) { world_rebuild_layout(&game.world,&game.layout,false) }

headless_game_mode :: proc(game: ^Headless_Game,mode: Blast_Mode) {
 if mode==game.world.settings.blast_mode { return }
 game.world.settings.blast_mode=mode; bomb_rain_clear(&game.world)
 game.world.rain.until_drop=bomb_drop_delay_config(&game.world.rain,scene_gameplay_config(&game.world.scene))
}

world_rebuild_layout :: proc(w: ^World,layout: ^Layout,editing: bool) {
 w.rebuild_error=""
 if layout.level!=nil && (!w.scene.level_policy.active||w.scene.config_hash!=gameplay_config_hash(layout.level.gameplay_config)) {
  w.settings.blast_radius=layout.level.gameplay_config.bomb_radius
 }
	revision:=w.scene.revision+1
	epoch:=w.scene.epoch+1
	scene_destroy(&w.scene)
	s:=&w.scene
	s^=new_scene(WOOD_MINIMUM_WIDTH)
	s.revision=revision
	s.epoch=epoch
 if layout.level!=nil { world_build_level(w,layout,editing);world_start_physics(w);return }
	material:=add_material(s,editor_material(.Stone))
	seed:=w.settings.seed
	objects: [dynamic]Built_Object; defer delete(objects)
 layout_build_objects(w,layout,editing,&objects)
 ground:=sandbox_add_ground(s,material,seed)
 build_mortar(s,objects[:],ground)
 build_glue(s,layout.glue[:],objects[:],ground)

	world_start_physics(w)
}

layout_build_objects :: proc(w: ^World,layout: ^Layout,editing: bool, objects: ^[dynamic]Built_Object = nil) {
	s:=&w.scene
	materials: [8]int
	for choice in Recipe { materials[int(choice)]=add_material(s,editor_material(choice)) }
 for i in 4..<palette_count(layout) {
  used:=false; for object in layout.objects { if int(object.material)==i { used=true; break } }
  if used {
   m:=layout_material(layout,Slot(i)); m.name=strings.clone(m.name); append(&s.owned_names,m.name)
   materials[i]=add_material(s,m)
  }
 }
	layout_build_rectangles(w,layout,editing,materials,objects)
}

layout_build_rectangles :: proc(w: ^World,layout: ^Layout,editing: bool,materials: [8]int, objects: ^[dynamic]Built_Object = nil) {
	s:=&w.scene
	if editing { return }
	for object in layout.objects {
		seed:=derive_seed(w.settings.seed,0x10000+object.identity)
		if layout_base(layout,object.material)==.Rubber { seed=0 }
		first_id:=s.next_id+1
		owner:=add_piece(s,materials[int(object.material)],seed)
  if object.angle!=0 || object.shape!=.Rect { build_shaped_object(s,object,owner); if objects!=nil { append(objects,built_object(object,first_id,s.next_id+1)) };continue }
		nx,ny:=1,1
		if layout_base(layout,object.material)==.Rubber {
			nx=int(math.ceil((object.hi.x-object.lo.x)/RUBBER_CELL_SIZE-0.00001))
			ny=int(math.ceil((object.hi.y-object.lo.y)/RUBBER_CELL_SIZE-0.00001))
		}
		// Uniform fitted cells: one target size, no tiny leftover edge strips.
		dx,dy:=(object.hi.x-object.lo.x)/f32(nx),(object.hi.y-object.lo.y)/f32(ny)
		ids:=make([]u64,nx*ny)
		for row in 0..<ny {
			for column in 0..<nx {
				x0,x1:=object.lo.x+f32(column)*dx,object.lo.x+f32(column+1)*dx
				y0,y1:=object.lo.y+f32(row)*dy,object.lo.y+f32(row+1)*dy
				points:=[4]Vec2{{x0,y0},{x1,y0},{x1,y1},{x0,y1}}
				outline:=Polygon{points=points[:]}
				id:=add_subdivision(s,owner,outline,Pose{position=centroid(outline)})

				index:=row*nx+column; ids[index]=id
				if column>0 { connection:=add_connection(s,ids[index-1],id); assert(connection!=0); }
				if row>0 { connection:=add_connection(s,ids[index-nx],id); assert(connection!=0); }
			}
		}
		delete(ids)
		if layout_base(layout,object.material)!=.Rubber { presplit_piece(s,owner) }
  if objects!=nil { append(objects,Built_Object{identity=object.identity,mortar=object.mortar,lo=object.lo,hi=object.hi,first_id=first_id,end_id=s.next_id+1}) }
	}
}
