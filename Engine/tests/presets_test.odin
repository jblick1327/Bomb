package main

import "core:testing"
import "core:sync"
import "core:fmt"
import "core:math"

// Rigid pieces have one body angle. A flexible piece has many bodies, so measure
// its overall rotation by the area-weighted best fit of rest and posed centres.
// Local rubber bending is recorded separately from rotation of the whole piece.
preset_piece_angle :: proc(s: ^Scene,piece: Piece) -> f32 {
	if s.materials[piece.material].flexibility==0 { return s.subdivisions[s.sub_rows[piece.subdivisions[0]]].pose.angle }
	rest,posed:=Vec2{},Vec2{}; mass:=f32(0)
	for id in piece.subdivisions {
		sub:=s.subdivisions[s.sub_rows[id]]; weight:=polygon_area(sub.outline)
		rest=vadd(rest,vmul(sub.rest_center,weight)); posed=vadd(posed,vmul(sub.pose.position,weight)); mass+=weight
	}
	rest=vmul(rest,1/mass); posed=vmul(posed,1/mass)
	cross,dot:=f32(0),f32(0)
	for id in piece.subdivisions {
		sub:=s.subdivisions[s.sub_rows[id]]; weight:=polygon_area(sub.outline)
		a,b:=vsub(sub.rest_center,rest),vsub(sub.pose.position,posed)
		cross+=weight*vcross(a,b); dot+=weight*vdot(a,b)
	}
	if cross==0 && dot==0 { return s.subdivisions[s.sub_rows[piece.subdivisions[0]]].pose.angle }
	return math.atan2(cross,dot)
}

// Fresh layout build, identical to the soak's create -> place -> Test path.

@(test)
presets_decode_and_materials_matches_soak :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	names:=PRESET_NAMES
	for data,i in PRESET_LAYOUTS {
		layout,seed,ok,problem:=decode_layout(transmute([]byte)data)
		testing.expect(t,ok,problem)
		testing.expect(t,seed==42 && layout.next_identity==u64(len(layout.objects)+1))
		for object,j in layout.objects {
			testing.expect(t,object.identity==u64(j+1))
			testing.expect(t,transmute([2]u32)object.lo==transmute([2]u32)editor_snap(object.lo) && transmute([2]u32)object.hi==transmute([2]u32)editor_snap(object.hi),"Preset must be on the decimal grid")
		}
		fmt.printf("D decode %s: valid=%v objects=%d\n",names[i],ok,len(layout.objects))
		destroy_layout(&layout)
	}
	a,b:=preset_test_yard(0),soak_yard(); defer sandbox_destroy(&a); defer sandbox_destroy(&b)
	x,xok:=encode_world_snapshot(&a.world); y,yok:=encode_world_snapshot(&b.world); defer delete(x); defer delete(y)
	testing.expect(t,xok && yok && string(x)==string(y),"Materials preset must build byte-identical World to soak_yard")
	fmt.printf("D Materials / soak_yard: byte mismatches=%d\n",int(string(x)!=string(y)))
}
@(test)
presets_settle_600_ticks_without_breakage_or_tipping :: proc(t: ^testing.T) {
	sync.mutex_lock(&physics_test_mutex); defer sync.mutex_unlock(&physics_test_mutex)
	for name,i in PRESET_NAMES {
		g:=preset_test_yard(i)
		initial_regions,initial_links,_:=counts_runtime(&g.world.scene)
		angles:=make(map[u64]f32)
		for piece in g.world.scene.pieces { if piece.live { angles[piece.id]=preset_piece_angle(&g.world.scene,piece) } }
		max_angle,max_cell_angle:=f32(0),f32(0); bad_ticks:=0; first_bad:=0
		for tick in 1..=600 {
			sandbox_tick(&g,0,false)
			regions,links,_:=counts_runtime(&g.world.scene)
			if regions!=initial_regions || links!=initial_links { bad_ticks+=1; if first_bad==0 { first_bad=tick } }
			for piece in g.world.scene.pieces {
				if initial,ok:=angles[piece.id]; ok { max_angle=max(max_angle,math.abs(preset_piece_angle(&g.world.scene,piece)-initial)*180/math.PI) }
			}
			for sub in g.world.scene.subdivisions { max_cell_angle=max(max_cell_angle,math.abs(sub.pose.angle)*180/math.PI) }
		}
		regions,links,_:=counts_runtime(&g.world.scene)
		rubber_deviation:=f32(0); rubber_cells:=0
		for piece in g.world.scene.pieces {
			if g.world.scene.materials[piece.material].flexibility<=0 { continue }
			fit:=preset_piece_angle(&g.world.scene,piece)
			for id in piece.subdivisions {
				angle:=g.world.scene.subdivisions[g.world.scene.sub_rows[id]].pose.angle-fit
				angle=math.atan2(math.sin(angle),math.cos(angle))
				rubber_deviation=max(rubber_deviation,math.abs(angle)*180/math.PI); rubber_cells+=1
			}
		}
		fmt.printf("D settle %s: regions=%d->%d links=%d->%d max_piece_angle_deg=%.6f max_local_cell_angle_deg=%.6f bad_count_ticks=%d first_bad_tick=%d\n",name,initial_regions,regions,initial_links,links,max_angle,max_cell_angle,bad_ticks,first_bad)
		fmt.printf("D tick600 %s: rubber_cells=%d max_rubber_cell_rotation_relative_to_piece_deg=%.6f (informational)\n",name,rubber_cells,rubber_deviation)
		testing.expect(t,bad_ticks==0,"Settling broke a region or link")
		testing.expect(t,max_angle<=10,"Settling turned a piece more than 10 degrees")
		expect_valid(t,&g.world.scene)
		delete(angles); sandbox_destroy(&g)
	}
}
