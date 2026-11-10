#+feature dynamic-literals
package shared

import math "core:math"

Segment :: struct { a,b: Vec2 }

segment_overlap :: proc(a,b: Segment) -> (Segment,bool) {
	d := vsub(a.b,a.a)
	length := vlen(d)
	if length < 0.00001 { return {},false }
	if math.abs(vcross(d,vsub(b.a,a.a))) > 0.0001*length || math.abs(vcross(d,vsub(b.b,a.a))) > 0.0001*length { return {},false }
	unit := vmul(d,1/length)
	t0,t1 := vdot(vsub(b.a,a.a),unit),vdot(vsub(b.b,a.a),unit)
	lo,hi := max(f32(0),min(t0,t1)),min(length,max(t0,t1))
	if hi-lo <= 0.0001 { return {},false }
	return Segment{vadd(a.a,vmul(unit,lo)),vadd(a.a,vmul(unit,hi))},true
}

shared_segments :: proc(a,b: Polygon) -> [dynamic]Segment {
	result: [dynamic]Segment
	for i in 0..<len(a.points) {
		for j in 0..<len(b.points) {
			if segment,ok := segment_overlap(Segment{a.points[i],a.points[(i+1)%len(a.points)]},Segment{b.points[j],b.points[(j+1)%len(b.points)]}); ok { append(&result,segment) }
		}
	}
	return result
}
