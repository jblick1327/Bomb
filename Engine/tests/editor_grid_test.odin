package main

import "core:testing"
import "core:sync"
import "core:fmt"
import "core:math"

@(test)
editor_grid_decimal_bits_and_shared_edges :: proc(t: ^testing.T) {
	p:=editor_snap({7.23,-5.649})
	testing.expect(t,transmute([2]u32)p==transmute([2]u32)Vec2{7.2,-5.6})
	// Approved correction: 1.04 and 1.06 straddle the rounding midpoint.
	// 1.02 and 1.04 retain a 0.02 gap and belong to the same grid point.
	a:=editor_rectangle({0.03,0.02},{1.02,1.01},recipe_slot(.Wood))
	b:=editor_rectangle({1.04,0},{2,0.98},recipe_slot(.Glass))
	gap:=b.lo.x-a.hi.x
	testing.expect(t,gap>0 && math.abs(gap-0.02)<0.000001)
	a=editor_rectangle(editor_snap(a.lo),editor_snap(a.hi),recipe_slot(.Wood))
	b=editor_rectangle(editor_snap(b.lo),editor_snap(b.hi),recipe_slot(.Glass))
	layout:=Layout{}; defer destroy_layout(&layout)
	testing.expect(t,editor_valid_rectangle(&layout,a)); append(&layout.objects,a)
	testing.expect(t,editor_valid_rectangle(&layout,b))
	testing.expect(t,transmute(u32)a.hi.x==transmute(u32)b.lo.x)
	fmt.printf("B snapped shared edge: before gap=%.9f after=%.1f; snap bits=0x%x,0x%x\n",gap,b.lo.x-a.hi.x,transmute(u32)p.x,transmute(u32)p.y)
}

@(test)
editor_rectangle_reports_first_problem :: proc(t: ^testing.T) {
	layout:=Layout{}; defer destroy_layout(&layout)
	append(&layout.objects,editor_rectangle({0,0},{1,1},recipe_slot(.Wood)))
	cases:=[5]Authored_Shape{
		editor_rectangle({2,0},{2.1,1},recipe_slot(.Glass)),
		editor_rectangle({2,-1},{3,1},recipe_slot(.Glass)),
		editor_rectangle({-5,0},{-4,1},recipe_slot(.Glass)),
		editor_rectangle({0.5,0.5},{2,2},recipe_slot(.Glass)),
		editor_rectangle({1,0},{2,1},recipe_slot(.Glass)),
	}
	expected:=[5]string{"Too small (min 0.2)","Outside the build area","Overlaps the spawn","Overlaps an object",""}
	for r,i in cases {
		testing.expect_value(t,editor_rectangle_problem(&layout,r),expected[i])
		testing.expect(t,editor_valid_rectangle(&layout,r)==(expected[i]==""))
	}
}

@(test)
editor_place_keeps_exact_fixture_coordinates :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	g:=sandbox_editor_create(); defer sandbox_destroy(&g)
	a,b:=Vec2{0.03,0.02},Vec2{1.02,1.01}
	testing.expect(t,editor_place(&g,a,b))
	r:=g.layout.objects[0]
	bad:=0
	if transmute([2]u32)r.lo!=transmute([2]u32)a { bad+=1 }
	if transmute([2]u32)r.hi!=transmute([2]u32)b { bad+=1 }
	fmt.printf("B exact editor_place: mismatching endpoints=%d\n",bad)
	testing.expect(t,bad==0)
}
