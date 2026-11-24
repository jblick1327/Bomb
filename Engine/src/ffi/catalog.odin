package ffi
import core "../shared"
@(export)
bom_client_expect_gameplay_manifest :: proc "c" (handle:u64,hash:[^]u8,length:u32) -> u32 {
 s,status,held:=enter(handle);if status!=OK {return status};defer leave(s,held)
 if s.acquired||s.live {return BUSY}
 if length!=0&&(length!=32||hash==nil) {return BAD_ARGUMENT}
 s.has_expected_manifest=length==32;s.expected_manifest={}
 if length==32 {copy(s.expected_manifest[:],hash[:32])};return OK
}

// Generated catalog mapping below. All pointers share the acquired sample lifetime.
@(export)
bom_client_acquire_catalog :: proc "c" (handle,sample_sequence:u64,catalog:^BomCatalogInfo) -> u32 {
 s,status,held:=enter(handle);if status!=OK {return status};defer leave(s,held);context=s.ctx
 if catalog==nil||catalog.struct_size<u32(size_of(BomCatalogInfo))||catalog.version!=1||!s.acquired||sample_sequence!=s.sample_sequence {return BAD_ARGUMENT}
 catalog^={struct_size=u32(size_of(BomCatalogInfo)),version=1};scene:=&s.client.rep.scene
 catalog.epoch=scene.epoch;catalog.revision=u64(scene.epoch);if scene.catalog!=nil {catalog.flags=1}
 catalog_hash:=transmute([4]u64)core.level_sha256(transmute([]u8)scene.level_json)
 gameplay_hash:=transmute([4]u64)scene.gameplay_manifest;config_hash:=transmute([4]u64)scene.config_hash
 catalog.catalog_hash0=catalog_hash[0]
 catalog.catalog_hash1=catalog_hash[1]
 catalog.catalog_hash2=catalog_hash[2]
 catalog.catalog_hash3=catalog_hash[3]
 catalog.gameplay_hash0=gameplay_hash[0]
 catalog.gameplay_hash1=gameplay_hash[1]
 catalog.gameplay_hash2=gameplay_hash[2]
 catalog.gameplay_hash3=gameplay_hash[3]
 catalog.config_hash0=config_hash[0]
 catalog.config_hash1=config_hash[1]
 catalog.config_hash2=config_hash[2]
 catalog.config_hash3=config_hash[3]
 clear(&s.bindings);for cell in s.cells {
  row,ok:=scene.sub_rows[cell.id];if !ok {return IO_ERROR};p:=scene.subdivisions[row].provenance
  append(&s.bindings,BomCellBinding{cell.id,p.source_identity,p.source_part_id,core.cell_policy_flags(p),0})
 }
 clear(&s.sources);if scene.catalog!=nil {for source in scene.catalog.sources {
  entry:=BomSourceBinding{source_identity=source.identity,depth_lo=source.depth.x,depth_hi=source.depth.y,asset_key=raw_data(source.asset_key),asset_key_length=u32(len(source.asset_key)),cap_key=raw_data(source.cap_key),cap_key_length=u32(len(source.cap_key))}
  motion:=core.Motion_Policy.Dynamic;if source.motion=="fixed" {motion=.Fixed};if source.motion=="anchored" {motion=.Anchored}
  damage:=core.Damage_Policy.Destructible;if source.damage=="indestructible" {damage=.Indestructible};entry.flags=u32(motion)|(u32(damage)<<2)
  visual:[32]u8;for i in 0..<32 {a,b:=source.visual_hash[i*2],source.visual_hash[i*2+1];hi:=a>='a'?a-'a'+10:a-'0';lo:=b>='a'?b-'a'+10:b-'0';visual[i]=(hi<<4)|lo}
  hash:=transmute([4]u64)visual
  entry.visual_hash0=hash[0]
  entry.visual_hash1=hash[1]
  entry.visual_hash2=hash[2]
  entry.visual_hash3=hash[3]
  entry.m00=source.group_to_rest[0]
  entry.m10=source.group_to_rest[1]
  entry.m20=source.group_to_rest[2]
  entry.m30=source.group_to_rest[3]
  entry.m01=source.group_to_rest[4]
  entry.m11=source.group_to_rest[5]
  entry.m21=source.group_to_rest[6]
  entry.m31=source.group_to_rest[7]
  entry.m02=source.group_to_rest[8]
  entry.m12=source.group_to_rest[9]
  entry.m22=source.group_to_rest[10]
  entry.m32=source.group_to_rest[11]
  entry.m03=source.group_to_rest[12]
  entry.m13=source.group_to_rest[13]
  entry.m23=source.group_to_rest[14]
  entry.m33=source.group_to_rest[15]
  append(&s.sources,entry)
 }}
 catalog.source_count=u32(len(s.sources));catalog.binding_count=u32(len(s.bindings));catalog.sources=raw_data(s.sources);catalog.bindings=raw_data(s.bindings)
 policy:=scene.level_policy;if policy.active {catalog.level.flags=1;catalog.level.config_version=policy.config.version
 catalog.level.simulation_lo_x=policy.simulation.lo.x
 catalog.level.simulation_lo_y=policy.simulation.lo.y
 catalog.level.simulation_hi_x=policy.simulation.hi.x
 catalog.level.simulation_hi_y=policy.simulation.hi.y
 catalog.level.kill_lo_x=policy.kill.lo.x
 catalog.level.kill_lo_y=policy.kill.lo.y
 catalog.level.kill_hi_x=policy.kill.hi.x
 catalog.level.kill_hi_y=policy.kill.hi.y
 catalog.level.camera_lo_x=policy.camera.lo.x
 catalog.level.camera_lo_y=policy.camera.lo.y
 catalog.level.camera_hi_x=policy.camera.hi.x
 catalog.level.camera_hi_y=policy.camera.hi.y
 catalog.level.aim_lo_x=policy.aim.lo.x
 catalog.level.aim_lo_y=policy.aim.lo.y
 catalog.level.aim_hi_x=policy.aim.hi.x
 catalog.level.aim_hi_y=policy.aim.hi.y
 catalog.level.fragment_cull_lo_x=policy.fragment_cull.lo.x
 catalog.level.fragment_cull_lo_y=policy.fragment_cull.lo.y
 catalog.level.fragment_cull_hi_x=policy.fragment_cull.hi.x
 catalog.level.fragment_cull_hi_y=policy.fragment_cull.hi.y
 catalog.level.bomb_cleanup_lo_x=policy.bombs.cleanup_bounds.lo.x
 catalog.level.bomb_cleanup_lo_y=policy.bombs.cleanup_bounds.lo.y
 catalog.level.bomb_cleanup_hi_x=policy.bombs.cleanup_bounds.hi.x
 catalog.level.bomb_cleanup_hi_y=policy.bombs.cleanup_bounds.hi.y
 catalog.level.spawn0_x=policy.spawns[0].x
 catalog.level.spawn0_y=policy.spawns[0].y
 catalog.level.spawn1_x=policy.spawns[1].x
 catalog.level.spawn1_y=policy.spawns[1].y
 catalog.level.spawn2_x=policy.spawns[2].x
 catalog.level.spawn2_y=policy.spawns[2].y
 catalog.level.spawn3_x=policy.spawns[3].x
 catalog.level.spawn3_y=policy.spawns[3].y
 catalog.level.bomb_spawn_lo=policy.bombs.spawn_x.x
 catalog.level.bomb_spawn_hi=policy.bombs.spawn_x.y
 catalog.level.bomb_spawn_height=policy.bombs.spawn_height
 catalog.level.gravity_x=policy.config.gravity.x
 catalog.level.gravity_y=policy.config.gravity.y
 catalog.level.move_speed=policy.config.player.speed
 catalog.level.move_acceleration=policy.config.player.acceleration
 catalog.level.jump_speed=policy.config.player.jump_speed
 catalog.level.coyote_time=policy.config.player.coyote_time
 catalog.level.jump_buffer=policy.config.player.jump_buffer
 catalog.level.bomb_fuse=policy.config.bomb_fuse
 catalog.level.bomb_drop_min=policy.config.bomb_drop_min
 catalog.level.bomb_drop_max=policy.config.bomb_drop_max
 }
 return OK
}
