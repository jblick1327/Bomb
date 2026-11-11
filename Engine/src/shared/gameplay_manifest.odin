package shared
import nc "../netcode"

gameplay_config_write :: proc(w:^nc.Writer,c:Gameplay_Config) {
 nc.write_u32(w,c.version);nc.write_f32(w,c.gravity.x);nc.write_f32(w,c.gravity.y)
 nc.write_f32(w,c.player.speed);nc.write_f32(w,c.player.acceleration);nc.write_f32(w,c.player.jump_speed);nc.write_f32(w,c.player.coyote_time);nc.write_f32(w,c.player.jump_buffer)
 nc.write_f32(w,c.player.gravity_scale)
 nc.write_f32(w,c.bomb_fuse);nc.write_f32(w,c.bomb_drop_min);nc.write_f32(w,c.bomb_drop_max)
 nc.write_f32(w,c.bomb_radius)
 nc.write_f32(w,c.elimination_start_interval.x);nc.write_f32(w,c.elimination_start_interval.y)
 nc.write_f32(w,c.elimination_end_interval.x);nc.write_f32(w,c.elimination_end_interval.y);nc.write_f32(w,c.elimination_ramp_seconds)
 // Shape dimensions and movement/contact implementation remain native-versioned.
 nc.write_f32(w,PLAYER_RADIUS);nc.write_f32(w,PLAYER_SEGMENT);nc.write_f32(w,BOMB_RADIUS)
}
gameplay_config_hash :: proc(c:Gameplay_Config) -> [32]u8 { w:nc.Writer;nc.writer_init(&w);defer nc.writer_destroy(&w);gameplay_config_write(&w,c);return level_sha256(w.data[:]) }
level_gameplay_hash :: proc(level:^Level_Layout) -> [32]u8 {
 w:nc.Writer;nc.writer_init(&w);defer nc.writer_destroy(&w)
 nc.write_u32(&w,1);nc.write_string(&w,level.level_id);nc.write_u64(&w,level.seed);nc.write_string(&w,level.gameplay_config_id);gameplay_config_write(&w,level.gameplay_config)
 for bounds in ([6]Level_Bounds{level.simulation_bounds,level.kill_bounds,level.camera_bounds,level.aim_bounds,level.fragment_cull_bounds,level.bombs.cleanup_bounds}) { nc.write_f32(&w,bounds.lo.x);nc.write_f32(&w,bounds.lo.y);nc.write_f32(&w,bounds.hi.x);nc.write_f32(&w,bounds.hi.y) }
 for spawn in level.spawns { nc.write_f32(&w,spawn.x);nc.write_f32(&w,spawn.y) }
 nc.write_f32(&w,level.bombs.spawn_x.x);nc.write_f32(&w,level.bombs.spawn_x.y);nc.write_f32(&w,level.bombs.spawn_height)
 palette:Layout;defer {for &m in palette.materials {m.name=""};destroy_layout(&palette)}
 for m in level.materials { base,_:=material_base_name(m.base);custom:=custom_from_wire(m,base);custom.name=m.name;append(&palette.materials,custom) }
 nc.write_u32(&w,u32(palette_count(&palette)))
 for i in 0..<palette_count(&palette) { material:=layout_material(&palette,Slot(i));material.color={};repl_write_material(&w,material) }
 nc.write_u32(&w,u32(len(level.sources)))
 for source in level.sources {
  nc.write_u64(&w,source.identity);nc.write_string(&w,source.motion);nc.write_string(&w,source.damage);nc.write_u32(&w,u32(len(source.parts)))
  for part in source.parts {
   nc.write_u64(&w,part.part_id);nc.write_string(&w,part.material);nc.write_u32(&w,u32(len(part.outline)))
   for p in part.outline {nc.write_f32(&w,p.x);nc.write_f32(&w,p.y)}
   nc.write_u32(&w,u32(len(part.anchors)));for segment in part.anchors {nc.write_f32(&w,segment.a.x);nc.write_f32(&w,segment.a.y);nc.write_f32(&w,segment.b.x);nc.write_f32(&w,segment.b.y)}
  }
 }
 nc.write_u32(&w,u32(len(level.glue)));for link in level.glue {nc.write_u64(&w,link.a.source_identity);nc.write_u64(&w,link.a.part_id);nc.write_u64(&w,link.b.source_identity);nc.write_u64(&w,link.b.part_id)}
 return level_sha256(w.data[:])
}
