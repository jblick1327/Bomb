package main

import "core:testing"
import "core:sync"
import "core:fmt"

@(test)
layout_drop_chooses_first_json :: proc(t: ^testing.T) {
	paths:=[4]cstring{"notes.txt","first.JSON","second.json","ignored.png"}
	testing.expect(t,sandbox_dropped_layout_index(paths[:])==1)
	testing.expect(t,sandbox_dropped_layout_index(paths[:1])== -1)
	testing.expect(t,sandbox_dropped_layout_index(nil)== -1)
}

@(test)
layout_exact_round_trip_and_world_build :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	original:=Layout{next_identity=102}; defer destroy_layout(&original)
	append(&original.objects,Authored_Shape{identity=23,material=recipe_slot(.Glass),lo={0.03,0.02},hi={1.02,1.01}})
	append(&original.objects,Authored_Shape{identity=91,material=recipe_slot(.Wood),lo={2,0},hi={3.1234567,1.0000001}})
	data,ok:=encode_layout(&original,233); defer delete(data); testing.expect(t,ok)
	decoded,seed,valid,problem:=decode_layout(data); defer destroy_layout(&decoded)
	testing.expect(t,valid,problem)
	testing.expect(t,seed==233 && decoded.next_identity==102 && len(decoded.objects)==2)
	for r,i in decoded.objects {
		a:=original.objects[i]
		testing.expect(t,r.identity==a.identity && r.material==a.material)
		testing.expect(t,transmute([2]u32)r.lo==transmute([2]u32)a.lo && transmute([2]u32)r.hi==transmute([2]u32)a.hi)
	}
	again,ok2:=encode_layout(&decoded,seed); defer delete(again)
	testing.expect(t,ok2 && string(data)==string(again))
	a,b:=sandbox_editor_create(),sandbox_editor_create(); defer sandbox_destroy(&a); defer sandbox_destroy(&b)
	for r in original.objects { append(&a.layout.objects,r) }
	a.layout.next_identity=original.next_identity; a.world.settings.seed=233
	testing.expect(t,sandbox_load_layout_data(&b,data))
	// Both build from a fresh Edit world; its UI revision is not simulation data.
	sandbox_toggle_editor(&a); sandbox_toggle_editor(&b)
	// Load rebuilt b's Edit floor once. Match that normal reset revision in a.
	sandbox_reset(&a)
	x,xok:=encode_world_snapshot(&a.world); y,yok:=encode_world_snapshot(&b.world)
	defer delete(x); defer delete(y)
	testing.expect(t,xok && yok && string(x)==string(y),"Decoded layout must build identical v3 World bytes")
	fmt.println("C layout round trip: float/identity/seed mismatches=0; World bytes identical=",string(x)==string(y))
}

@(test)
layout_rejections_are_atomic_and_report_first_problem :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	g:=sandbox_editor_create(); defer sandbox_destroy(&g)
	testing.expect(t,editor_place(&g,{4,0},{5,1}))
	sandbox_toggle_editor(&g)
	layout_before,ok:=encode_layout(&g.layout,g.world.settings.seed); defer delete(layout_before); testing.expect(t,ok)
	world_before,ok2:=encode_world_snapshot(&g.world); defer delete(world_before); testing.expect(t,ok2)
	cases:=[12]string{
		`{"kind":"wrong","version":1,"next_identity":1}`,
		`{"kind":"bom-layout","version":5,"next_identity":1}`,
		`{"kind":"bom-layout","version":1,"next_identity":2,"objects":[{"identity":1,"material":"iron"}]}`,
		`{"kind":"bom-layout","version":1,"next_identity":2,"objects":[{"identity":0,"material":"wood"}]}`,
		`{"kind":"bom-layout","version":1,"next_identity":3,"objects":[{"identity":1,"material":"wood","lo":{"x":0,"y":0},"hi":{"x":1,"y":1}},{"identity":1,"material":"glass"}]}`,
		`{"kind":"bom-layout","version":1,"next_identity":1,"objects":[{"identity":1,"material":"wood","lo":{"x":0,"y":0},"hi":{"x":1,"y":1}}]}`,
		`{"kind":"bom-layout","version":1,"next_identity":2,"objects":[{"identity":1,"material":"wood","lo":{"x":0,"y":0},"hi":{"x":0.1,"y":1}}]}`,
		`{"kind":"bom-layout","version":1,"next_identity":2,"objects":[{"identity":1,"material":"wood","lo":{"x":0,"y":-1},"hi":{"x":1,"y":1}}]}`,
		`{"kind":"bom-layout","version":1,"next_identity":2,"objects":[{"identity":1,"material":"wood","lo":{"x":-5,"y":0},"hi":{"x":-4,"y":1}}]}`,
		`{"kind":"bom-layout","version":1,"next_identity":3,"objects":[{"identity":1,"material":"wood","lo":{"x":0,"y":0},"hi":{"x":1,"y":1}},{"identity":2,"material":"glass","lo":{"x":0.5,"y":0.5},"hi":{"x":2,"y":2}}]}`,
		`{broken`,
		`{"kind":"bom-layout","version":1,"seed":256,"next_identity":1}`,
	}
	expected:=[12]string{"Not a bom-layout file","Unsupported layout version","Unknown material","Object identity must be nonzero","Duplicate object identity","next_identity must exceed every object identity","Too small (min 0.2)","Outside the build area","Overlaps the spawn","Overlaps an object","Invalid layout JSON","Seed must be between 0 and 255"}
	rejected,unchanged:=0,0
	for data,i in cases {
		result:=sandbox_load_layout_data(&g,transmute([]byte)data)
		if !result { rejected+=1 }
		testing.expect(t,!result)
		testing.expect_value(t,g.status,expected[i])
		a,aok:=encode_layout(&g.layout,g.world.settings.seed); b,bok:=encode_world_snapshot(&g.world)
		same:=aok && bok && string(a)==string(layout_before) && string(b)==string(world_before) && !g.editor.editing
		if same { unchanged+=1 }
		testing.expect(t,same,"Rejected load changed the layout or World")
		delete(a); delete(b)
	}
	fmt.printf("C rejection checks: rejected=%d/12 unchanged=%d/12\n",rejected,unchanged)
}
