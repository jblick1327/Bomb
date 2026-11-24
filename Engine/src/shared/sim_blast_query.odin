#+feature dynamic-literals
package shared

import runtime "base:runtime"
import b2 "vendor:box2d"

Blast_Query :: struct { ids: map[u64]bool }

blast_query_shape :: proc "c" (shape: b2.ShapeId,data: rawptr) -> bool {
	context=runtime.default_context()
	query:=cast(^Blast_Query)data
	id:=u64(uintptr(b2.Shape_GetUserData(shape)))
	if id!=0 { query.ids[id]=true }
	return true
}

blast_regions :: proc(s: ^Scene,blast: Blast) -> [dynamic]u64 {
	result: [dynamic]u64
	if !s.physics.active {
		for sub in s.subdivisions { if sub.live { append(&result,sub.id) } }
	} else {
		query:=Blast_Query{ids=make(map[u64]bool)}; defer delete(query.ids)
		extent:=max(f32(0),blast.radius)+0.05
		box:=b2.AABB{lowerBound={blast.position.x-extent,blast.position.y-extent},upperBound={blast.position.x+extent,blast.position.y+extent}}
		_ = b2.World_OverlapAABB(s.physics.world,box,STRUCTURE_QUERY_FILTER,blast_query_shape,&query) // also sees frozen debris
		for id in s.pending_regions { query.ids[id]=true }
		for id in query.ids { if is_live_subdivision(s,id) { append(&result,id) } }
	}
	sort_ids(result[:])
	return result
}

blast_connections :: proc(s: ^Scene,regions: []u64) -> [dynamic]u64 {
	set:=make(map[u64]bool); defer delete(set)
	for id in regions { for connection in s.subdivisions[s.sub_rows[id]].incident_links { set[connection]=true } }
	result: [dynamic]u64
	for id in set { if s.connections[s.conn_rows[id]].live { append(&result,id) } }
	sort_ids(result[:])
	return result
}
