package netcode

import "core:log"
import "core:math"
import "core:math/rand"
import "core:testing"

// (a) codec ---------------------------------------------------------------

// The compiler folds constant NaN/Inf/-0 values, so build them from bits at
// runtime to test the real encoder.
@(private)
f32_from_bits :: proc(bits: u32) -> f32 {
	b := bits
	return transmute(f32)b
}

@(private)
f32_bits :: proc(v: f32) -> u32 {
	x := v
	return transmute(u32)x
}

@(private)
float_bit_patterns := [?]u32 {
	0x00000000, // +0
	0x80000000, // -0
	0x7FC12345, // quiet NaN with payload
	0xFFC00001, // negative NaN with payload
	0x7FA00001, // signalling NaN
	0x7F800000, // +Inf
	0xFF800000, // -Inf
	0x00000001, // smallest denormal
	0x3FC00000, // 1.5
	0x7F7FFFFF, // max finite
}

@(test)
test_codec_round_trip :: proc(t: ^testing.T) {
	w: Writer
	writer_init(&w)
	defer writer_destroy(&w)

	// 1 KB string and empty ones.
	big := make([]u8, 1024)
	defer delete(big)
	for i in 0 ..< len(big) {
		big[i] = u8('a' + i % 26)
	}
	big_str := string(big)


	write_u8(&w, 0)
	write_u8(&w, 255)
	write_u16(&w, 0)
	write_u16(&w, max(u16))
	write_u32(&w, 0)
	write_u32(&w, max(u32))
	write_u64(&w, 0)
	write_u64(&w, max(u64))
	write_u64(&w, 0x0123456789ABCDEF)
	write_i32(&w, 0)
	write_i32(&w, max(i32))
	write_i32(&w, min(i32))
	write_i32(&w, -1)
	for bits in float_bit_patterns {
		write_f32(&w, f32_from_bits(bits))
	}
	write_bool(&w, true)
	write_bool(&w, false)
	for v in ([?]u64{0, 1, 127, 128, 255, 16383, 16384, 1 << 32, 1 << 63, max(u64)}) {
		write_varint(&w, v)
	}
	for v in ([?]i64{0, -1, 1, min(i64), max(i64), -64, 64}) {
		write_zigzag(&w, v)
	}
	write_bytes(&w, nil)
	write_bytes(&w, []u8{1, 2, 3, 0, 255})
	write_string(&w, "")
	write_string(&w, "héllo ✓ 世界")
	write_string(&w, big_str)

	r: Reader
	reader_init(&r, w.data[:])
	expect_eq :: proc(t: ^testing.T, got, want: $T, loc := #caller_location) {
		testing.expectf(t, got == want, "got %v, want %v", got, want, loc = loc)
	}
	expect_eq(t, read_u8(&r), 0)
	expect_eq(t, read_u8(&r), 255)
	expect_eq(t, read_u16(&r), 0)
	expect_eq(t, read_u16(&r), max(u16))
	expect_eq(t, read_u32(&r), 0)
	expect_eq(t, read_u32(&r), max(u32))
	expect_eq(t, read_u64(&r), 0)
	expect_eq(t, read_u64(&r), max(u64))
	expect_eq(t, read_u64(&r), 0x0123456789ABCDEF)
	expect_eq(t, read_i32(&r), 0)
	expect_eq(t, read_i32(&r), max(i32))
	expect_eq(t, read_i32(&r), min(i32))
	expect_eq(t, read_i32(&r), -1)
	for bits in float_bit_patterns {
		expect_eq(t, f32_bits(read_f32(&r)), bits)
	}
	expect_eq(t, read_bool(&r), true)
	expect_eq(t, read_bool(&r), false)
	for v in ([?]u64{0, 1, 127, 128, 255, 16383, 16384, 1 << 32, 1 << 63, max(u64)}) {
		expect_eq(t, read_varint(&r), v)
	}
	for v in ([?]i64{0, -1, 1, min(i64), max(i64), -64, 64}) {
		expect_eq(t, read_zigzag(&r), v)
	}
	expect_eq(t, len(read_bytes(&r)), 0)
	b := read_bytes(&r)
	expect_eq(t, len(b), 5)
	if len(b) == 5 {
		expect_eq(t, b[4], 255)
	}
	expect_eq(t, read_string(&r), "")
	expect_eq(t, read_string(&r), "héllo ✓ 世界")
	expect_eq(t, read_string(&r), big_str)
	testing.expect(t, r.ok, "reader should still be ok")
	expect_eq(t, reader_remaining(&r), 0)

	// Reading past the end is an error and sticks.
	expect_eq(t, read_u8(&r), 0)
	testing.expect(t, !r.ok, "read past end must set ok=false")
}

@(test)
test_codec_known_bytes :: proc(t: ^testing.T) {
	w: Writer
	writer_init(&w)
	defer writer_destroy(&w)
	write_u32(&w, 0x01020304)
	write_u16(&w, 0xA0B0)
	write_varint(&w, 300)
	write_zigzag(&w, -1)
	got := w.data[:]
	want := [?]u8{0x04, 0x03, 0x02, 0x01, 0xB0, 0xA0, 0xAC, 0x02, 0x01}
	testing.expect_value(t, len(got), len(want))
	for i in 0 ..< min(len(got), len(want)) {
		testing.expectf(t, got[i] == want[i], "byte %d: got %02x want %02x", i, got[i], want[i])
	}
}

@(test)
test_codec_truncated_and_oversized :: proc(t: ^testing.T) {
	w: Writer
	writer_init(&w)
	defer writer_destroy(&w)
	write_u64(&w, 0xDEADBEEF)
	write_varint(&w, 1 << 40)
	write_string(&w, "truncate me")
	full := w.data[:]

	// Every strict prefix must fail somewhere without panicking.
	for n in 0 ..< len(full) {
		r: Reader
		reader_init(&r, full[:n])
		_ = read_u64(&r)
		_ = read_varint(&r)
		_ = read_string(&r)
		testing.expectf(t, !r.ok, "prefix of %d/%d bytes parsed as ok", n, len(full))
	}

	// A length larger than the remaining bytes is an error, not a short read.
	{
		bad: Writer
		writer_init(&bad)
		defer writer_destroy(&bad)
		write_varint(&bad, 100)
		write_raw(&bad, []u8{1, 2, 3})
		r: Reader
		reader_init(&r, bad.data[:])
		b := read_bytes(&r)
		testing.expect(t, !r.ok && b == nil, "oversized length must fail")
	}
	// Absurd 64-bit length.
	{
		bad: Writer
		writer_init(&bad)
		defer writer_destroy(&bad)
		write_varint(&bad, max(u64))
		r: Reader
		reader_init(&r, bad.data[:])
		_ = read_string(&r)
		testing.expect(t, !r.ok, "u64-max length must fail")
	}
	// Overlong / overflowing varints.
	{
		ten_continue := [?]u8{0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x00}
		r: Reader
		reader_init(&r, ten_continue[:])
		_ = read_varint(&r)
		testing.expect(t, !r.ok, "11-byte varint must fail")

		overflow := [?]u8{0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x02}
		reader_init(&r, overflow[:])
		_ = read_varint(&r)
		testing.expect(t, !r.ok, "varint above 64 bits must fail")

		max_ok := [?]u8{0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01}
		reader_init(&r, max_ok[:])
		v := read_varint(&r)
		testing.expect(t, r.ok && v == max(u64), "u64 max varint must parse")
	}
	// Strict bool.
	{
		two := [?]u8{2}
		r: Reader
		reader_init(&r, two[:])
		_ = read_bool(&r)
		testing.expect(t, !r.ok, "bool byte 2 must fail")
	}
	// A failed reader returns zero from everything afterwards.
	{
		r: Reader
		reader_init(&r, nil)
		_ = read_u8(&r)
		testing.expect(t, !r.ok, "empty read fails")
		testing.expect_value(t, read_u32(&r), 0)
		testing.expect_value(t, read_varint(&r), 0)
		testing.expect_value(t, len(read_bytes(&r)), 0)
		testing.expect_value(t, read_string(&r), "")
		testing.expect(t, !r.ok, "ok stays false")
	}
}

@(private)
fuzz_all_reads :: proc(data: []u8, rng: rand.Generator) {
	check :: proc(r: ^Reader, data: []u8) {
		assert(r.pos >= 0 && r.pos <= len(data), "reader position out of bounds")
	}
	for kind in 0 ..< 13 {
		r: Reader
		reader_init(&r, data)
		switch kind {
		case 0:
			_ = read_u8(&r)
		case 1:
			_ = read_u16(&r)
		case 2:
			_ = read_u32(&r)
		case 3:
			_ = read_u64(&r)
		case 4:
			_ = read_i32(&r)
		case 5:
			_ = read_f32(&r)
		case 6:
			_ = read_bool(&r)
		case 7:
			_ = read_varint(&r)
		case 8:
			_ = read_zigzag(&r)
		case 9:
			b := read_bytes(&r)
			assert(len(b) <= len(data), "read_bytes longer than the buffer")
		case 10:
			s := read_string(&r)
			assert(len(s) <= len(data), "read_string longer than the buffer")
		case 11:
			_, _ = read_header(&r)
		case 12:
			_ = read_u16(&r)
			_ = read_varint(&r)
		}
		check(&r, data)
	}
	// A random run of reads on one reader; once it fails it must stay failed.
	r: Reader
	reader_init(&r, data)
	failed := false
	for _ in 0 ..< 24 {
		switch rand.int_max(10, rng) {
		case 0:
			_ = read_u8(&r)
		case 1:
			_ = read_u16(&r)
		case 2:
			_ = read_u32(&r)
		case 3:
			_ = read_u64(&r)
		case 4:
			_ = read_i32(&r)
		case 5:
			_ = read_f32(&r)
		case 6:
			_ = read_varint(&r)
		case 7:
			_ = read_zigzag(&r)
		case 8:
			_ = read_bytes(&r)
		case 9:
			_ = read_string(&r)
		}
		check(&r, data)
		if failed {
			assert(!r.ok, "ok flag recovered after a failure")
		}
		failed = !r.ok
	}
}

@(test)
test_codec_fuzz_reads :: proc(t: ^testing.T) {
	state := rand.create(0xC0DEC)
	rng := rand.default_random_generator(&state)
	buf: [96]u8
	for iter in 0 ..< 10_000 {
		n := rand.int_max(len(buf) + 1, rng)
		for i in 0 ..< n {
			buf[i] = u8(rand.uint32(rng))
		}
		// Bias some buffers toward large length prefixes / continuation bytes.
		if iter % 4 == 0 && n > 0 {
			buf[0] = 0xFF
		}
		if iter % 7 == 0 && n > 1 {
			for i in 0 ..< min(n, 10) {
				buf[i] |= 0x80
			}
		}
		fuzz_all_reads(buf[:n], rng)
	}
	log.infof("fuzz: 10000 random buffers, every read proc, no panic or out-of-bounds read")
}

// (b) quantization --------------------------------------------------------

@(test)
test_quantize_position :: proc(t: ^testing.T) {
	state := rand.create(0x9051)
	rng := rand.default_random_generator(&state)
	bound := 0.5 / 1024.0
	worst := 0.0
	check :: proc(x: f32, bound: f64, worst: ^f64) -> bool {
		back := dequantize_pos(quantize_pos(x))
		err := abs(f64(back) - f64(x))
		worst^ = max(worst^, err)
		return err <= bound
	}
	for _ in 0 ..< 1_000_000 {
		x := f32(rand.float64_range(-1000, 1000, rng))
		if !check(x, bound, &worst) {
			testing.expectf(t, false, "position %v error exceeds 0.5/1024", x)
			return
		}
	}
	for x in ([?]f32{0, 1000, -1000, 0.5 / 1024, -0.5 / 1024, 1.0 / 1024, 999.9995, -999.9995}) {
		testing.expectf(t, check(x, bound, &worst), "edge position %v", x)
	}
	testing.expect_value(t, quantize_pos(math.nan_f32()), 0)
	testing.expect_value(t, quantize_pos(1e30), max(i32))
	testing.expect_value(t, quantize_pos(-1e30), min(i32))
	log.infof("quantize_pos: 1,000,000 samples over +/-1000 m, worst error %.6f m (limit %.6f)", worst, bound)
}

@(test)
test_quantize_angle :: proc(t: ^testing.T) {
	state := rand.create(0xA17E)
	rng := rand.default_random_generator(&state)
	// Limit is pi/65536; 1e-6 extra covers the f32 rounding of the dequantized value.
	bound := math.PI / 65536.0
	slack := 1e-6
	worst := 0.0
	circular :: proc(a, b: f64) -> f64 {
		d := abs(a - b)
		d = math.mod(d, math.TAU)
		return min(d, math.TAU - d)
	}
	check :: proc(x: f32, worst: ^f64) -> f64 {
		back := dequantize_angle(quantize_angle(x))
		e := circular(f64(back), f64(x))
		worst^ = max(worst^, e)
		return e
	}
	for _ in 0 ..< 1_000_000 {
		x := f32(rand.float64_range(0, math.TAU, rng))
		e := check(x, &worst)
		if e > bound + slack {
			testing.expectf(t, false, "angle %v error %v exceeds pi/65536", x, e)
			return
		}
	}
	// Outside [0, 2pi): negatives and multiples must wrap to the same angle.
	for _ in 0 ..< 100_000 {
		x := f32(rand.float64_range(-50, 50, rng))
		e := check(x, &worst)
		// Reduce in f64 first: the f32 input is exact, only the output rounds.
		if e > bound + slack {
			testing.expectf(t, false, "wrapped angle %v error %v exceeds pi/65536", x, e)
			return
		}
	}
	for x in ([?]f32{0, math.PI, -math.PI, math.TAU, 6.2831855, 6.28318, 1e-9, -1e-9}) {
		testing.expectf(t, check(x, &worst) <= bound + slack, "edge angle %v", x)
	}
	testing.expect_value(t, quantize_angle(math.nan_f32()), 0)
	testing.expect_value(t, quantize_angle(0), 0)
	testing.expect(t, dequantize_angle(max(u16)) < math.TAU, "dequantized angle stays below 2pi")
	log.infof("quantize_angle: 1,100,000 samples, worst error %.3e rad (limit pi/65536 = %.3e)", worst, bound)
}
