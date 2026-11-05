package main

import rl "vendor:raylib"
import "core:math"

View :: struct { offset: Vec2, scale: f32 }
screen_point :: proc(view: View,point: Vec2) -> rl.Vector2 { return {view.offset.x+point.x*view.scale,view.offset.y-point.y*view.scale} }
world_point :: proc(view: View,point: rl.Vector2) -> Vec2 { return {(point.x-view.offset.x)/view.scale,(view.offset.y-point.y)/view.scale} }
piece_color :: proc(id: u64,alpha: u8 = 255) -> rl.Color {
	colors := [6]rl.Color{{64,173,165,255},{97,142,206,255},{194,134,204,255},{212,161,88,255},{139,178,113,255},{211,116,125,255}}
	c:=colors[id%6]; c.a=alpha; return c
}
// One interpolated body-origin frame per rigid piece, shared by every vertex.
rigid_render_frame :: proc(s: ^Scene,sub: Subdivision,poses: map[u64]Pose,frames: map[u64]Pose = nil) -> Pose {
	if frame,ok:=frames[sub.owner]; ok { return frame }
	piece:=s.pieces[s.piece_rows[sub.owner]]
	anchor:=s.subdivisions[s.sub_rows[piece.subdivisions[0]]]
	frame:=anchor.pose
	if pose,ok:=poses[anchor.id]; ok { frame=pose }
	frame.position=vsub(frame.position,vrotate(anchor.rest_center,frame.angle))
	return frame
}
render_piece_frames :: proc(s: ^Scene,poses: map[u64]Pose,previous: map[u64]Pose = nil,alpha: f32 = 1) -> map[u64]Pose {
	frames:=make(map[u64]Pose)
	for piece in s.pieces {
		if !piece.live || s.materials[piece.material].flexibility>0 || len(piece.subdivisions)==0 { continue }
		sub:=s.subdivisions[s.sub_rows[piece.subdivisions[0]]]
		frames[piece.id]=rigid_render_frame(s,sub,poses)
		if old,ok:=previous[sub.id]; ok {
			// Keep the origin interpolation before adding any region centre back.
			a,b:=old,sub.pose
			a.position=vsub(a.position,vrotate(sub.rest_center,a.angle))
			b.position=vsub(b.position,vrotate(sub.rest_center,b.angle))
			frames[piece.id]=interpolate_pose(a,b,alpha)
		}
	}
	return frames
}
rigid_render_point :: proc(frame: Pose,rest: Vec2) -> Vec2 { return vadd(frame.position,vrotate(rest,frame.angle)) }
render_subdivision :: proc(s: ^Scene,sub: Subdivision,poses: map[u64]Pose,frames: map[u64]Pose = nil) -> Subdivision {
	result:=sub
	if pose,ok:=poses[sub.id]; ok { result.pose=pose }
	if s.materials[sub.material].flexibility==0 {
		frame:=rigid_render_frame(s,sub,poses,frames)
		result.pose.angle=frame.angle
		result.pose.position=rigid_render_point(frame,sub.rest_center)
	}
	return result
}
point_on_boundary :: proc(point: Vec2,a,b: Polygon) -> bool {
	for i in 0..<len(a.points) {
		for j in 0..<len(b.points) {
			if segment,ok:=segment_overlap(Segment{a.points[i],a.points[(i+1)%len(a.points)]},Segment{b.points[j],b.points[(j+1)%len(b.points)]}); ok {
				d:=vsub(segment.b,segment.a); length:=vlen(d)
				projection:=vdot(vsub(point,segment.a),d)/(length*length)
				if projection >= -0.0001 && projection <= 1.0001 && math.abs(vcross(d,vsub(point,segment.a))) < 0.0001*length { return true }
			}
		}
	}
	return false
}
draw_polygon :: proc(view: View,outline: Polygon,color: rl.Color,stroke: rl.Color,outlines: bool = true) {
	triangles:=triangulate_polygon(outline)
	for triangle in triangles {
		a,b,c:=screen_point(view,triangle.points[0]),screen_point(view,triangle.points[1]),screen_point(view,triangle.points[2])
		// Raylib's triangle winding uses the screen's downward Y axis.
		cross:=vcross(vsub(triangle.points[1],triangle.points[0]),vsub(triangle.points[2],triangle.points[0]))
		if cross > 0 { rl.DrawTriangle(a,b,c,color) } else { rl.DrawTriangle(c,b,a,color) }
		delete(triangle.points)
	}
	delete(triangles)
	if outlines {
		for i in 0..<len(outline.points) { rl.DrawLineEx(screen_point(view,outline.points[i]),screen_point(view,outline.points[(i+1)%len(outline.points)]),2,stroke) }
	}
}
pick_subdivision :: proc(s: ^Scene,point: Vec2) -> u64 {
	best:=u64(0)
	for sub in s.subdivisions {
		if !sub.live { continue }
		points: [dynamic]rl.Vector2
		for rest in sub.outline.points { p:=posed_point(sub,rest); append(&points,rl.Vector2{p.x,p.y}) }
		hit:=rl.CheckCollisionPointPoly({point.x,point.y},raw_data(points),i32(len(points)))
		delete(points)
		if hit && (best==0 || sub.id<best) { best=sub.id }
	}
	return best
}
pick_connection :: proc(s: ^Scene,point: Vec2,max_distance: f32) -> u64 {
	best:=u64(0); distance:=max_distance
	for c in s.connections { if c.live { d:=vlen(vsub(point,connection_sample(s,c))); if d<distance || (best!=0 && d==distance && c.id<best) { distance=d; best=c.id } } }
	return best
}
draw_scene :: proc(s: ^Scene,caches: ^Render_Cache_State,view: View,poses: map[u64]Pose,selected: u64,surface,joints: bool,ids: bool = true,material_colors: bool = false,outline_width: f32 = 2,piece_frames: map[u64]Pose = nil) {
	render_cache_prepass(s,caches)
	frames:=piece_frames
	if frames==nil { frames=render_piece_frames(s,poses) }
	defer { if piece_frames==nil { delete(frames) } }
	ids_order: [dynamic]u64
	defer delete(ids_order)
	for sub in s.subdivisions { if sub.live { append(&ids_order,sub.id) } }
	sort_ids(ids_order[:])
 // Fill and seal every region before any outline can be painted over.
 outlines:=make([]Polygon,len(ids_order))
 defer { for outline in outlines { delete(outline.points) }; delete(outlines) }
 hubs:=make([]Vec2,len(ids_order)); defer delete(hubs)
 for id,i in ids_order {
  sub:=s.subdivisions[s.sub_rows[id]]
  outlines[i]=render_outline(s,caches,sub,poses,surface,frames,&hubs[i])
 }
 // Paint the supporting floor before objects: its 1px boundary seal must not
 // paint over the bottom of a darker object resting on that boundary.
 textured:=material_colors && !ids && material_texture.id!=0
 for pass in 0..<2 {
  if textured { texture_begin() }
  for id,i in ids_order {
   sub:=s.subdivisions[s.sub_rows[id]]; if render_static(sub)!=(pass==0) { continue }
   fill:=piece_color(sub.owner,210)
   if textured {
    m:=s.materials[sub.material]; vertical:=false
    if m.aspect_ratio<1 { _,_,axis,_,_:=frame_grain(sub.outline,sub.frame); vertical=axis==1 }
    texture_cached_fill(view,outlines[i],hubs[i],&caches.cells[id],m,vertical,sub.frame)
   } else { draw_cached_fill(view,outlines[i],fill,&caches.cells[id],hubs[i]) }
  }
  if textured {
   texture_end()
   for id,i in ids_order { sub:=s.subdivisions[s.sub_rows[id]]; if render_static(sub)==(pass==0) { draw_cached_strokes(view,outlines[i],material_color(s.materials[sub.material]),1,&caches.cells[id],false) } }
  }
 }
 if material_colors && surface { draw_rubber_bands(s,caches,view,outlines,ids_order[:],selected,outline_width) }
 if material_colors && !surface { for id,i in ids_order {
  sub:=s.subdivisions[s.sub_rows[id]]
  if s.materials[sub.material].flexibility<=0 { continue }
  film:=FILM_COLOR; if id==selected { film={255,255,255,255} }
  draw_cached_film(view,outlines[i],film,outline_width,&caches.cells[id])
 } }
 // All inspection outlines sit above the film, including adjacent cells'.
 for id,i in ids_order {
  sub:=s.subdivisions[s.sub_rows[id]]
  if material_colors && s.materials[sub.material].flexibility>0 && !ids { continue }
  stroke:=rl.Color{202,220,231,255}; if id==selected { stroke={255,255,255,255} }
  draw_cached_strokes(view,outlines[i],stroke,outline_width,&caches.cells[id],ids)
 }
 draw_mortar(s,view,poses,frames,outline_width)
 if ids { for id in ids_order {
  sub:=render_subdivision(s,s.subdivisions[s.sub_rows[id]],poses,frames)
  center:=screen_point(view,sub.pose.position)
  ui_text(.Body,rl.TextFormat("%d",id),i32(center.x)-5,i32(center.y)-23,rl.Color{16,29,40,255})
 } }
	if joints {
		clear(&ids_order)
		for c in s.connections { if c.live { append(&ids_order,c.id) } }
		sort_ids(ids_order[:])
		for id in ids_order {
			c:=s.connections[s.conn_rows[id]]
			a,b:=render_subdivision(s,s.subdivisions[s.sub_rows[c.a]],poses,frames),render_subdivision(s,s.subdivisions[s.sub_rows[c.b]],poses,frames)
			anchor:=vmul(vadd(posed_point(a,c.rest_point),posed_point(b,c.rest_point)),0.5)
			color:=rl.Color{248,205,109,255}
			rl.DrawLineEx(screen_point(view,a.pose.position),screen_point(view,b.pose.position),2,color)
			rl.DrawCircleV(screen_point(view,anchor),5,color)
			p:=screen_point(view,anchor)
			ui_text(.Small,rl.TextFormat("c%d",c.id),i32(p.x)+7,i32(p.y)+7,color)
		}
	}
}
counts_runtime :: proc(s: ^Scene) -> (int,int,int) {
	a,b,c:=0,0,0
	for sub in s.subdivisions { if sub.live { a+=1 } }
	for conn in s.connections { if conn.live { b+=1 } }
	for piece in s.pieces { if piece.live { c+=1 } }
	return a,b,c
}
