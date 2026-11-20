package netcode

import "core:math"

// Little-endian byte codec. The Writer appends to a [dynamic]u8. The Reader
// walks a slice with a sticky `ok` flag: once any read fails, ok stays false
// and every later read returns zero without touching the data.

Writer :: struct {
	data: [dynamic]u8,
}

writer_init :: proc(w: ^Writer, capacity := 0, allocator := context.allocator) {
	w.data = make([dynamic]u8, 0, capacity, allocator)
}

writer_destroy :: proc(w: ^Writer) {
	delete(w.data)
	w.data = nil
}

writer_reset :: proc(w: ^Writer) {
	clear(&w.data)
}

writer_bytes :: proc(w: ^Writer) -> []u8 {
	return w.data[:]
}

write_u8 :: proc(w: ^Writer, v: u8) {
	append(&w.data, v)
}

write_u16 :: proc(w: ^Writer, v: u16) {
	append(&w.data, u8(v), u8(v >> 8))
}

write_u32 :: proc(w: ^Writer, v: u32) {
	append(&w.data, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24))
}

write_u64 :: proc(w: ^Writer, v: u64) {
	for i in 0 ..< 8 {
		append(&w.data, u8(v >> uint(8 * i)))
	}
}

write_i32 :: proc(w: ^Writer, v: i32) {
	write_u32(w, u32(v))
}

// Bit-exact: NaN payloads and signed zero survive a round trip.
write_f32 :: proc(w: ^Writer, v: f32) {
	write_u32(w, transmute(u32)v)
}

write_bool :: proc(w: ^Writer, v: bool) {
	append(&w.data, u8(1) if v else u8(0))
}

// Unsigned LEB128, 1..10 bytes.
write_varint :: proc(w: ^Writer, v: u64) {
	v := v
	for v >= 0x80 {
		append(&w.data, u8(v & 0x7f) | 0x80)
		v >>= 7
	}
	append(&w.data, u8(v))
}

varint_size :: proc(v: u64) -> int {
	v := v
	n := 1
	for v >= 0x80 {
		v >>= 7
		n += 1
	}
	return n
}

zigzag_encode :: proc(v: i64) -> u64 {
	return u64((v << 1) ~ (v >> 63))
}

zigzag_decode :: proc(u: u64) -> i64 {
	return i64(u >> 1) ~ -i64(u & 1)
}

write_zigzag :: proc(w: ^Writer, v: i64) {
	write_varint(w, zigzag_encode(v))
}

// varint length + data
write_bytes :: proc(w: ^Writer, b: []u8) {
	write_varint(w, u64(len(b)))
	append(&w.data, ..b)
}

// varint length + UTF-8 bytes (no validation is done on write or read).
write_string :: proc(w: ^Writer, s: string) {
	write_varint(w, u64(len(s)))
	append(&w.data, s)
}

// Raw append without a length prefix.
write_raw :: proc(w: ^Writer, b: []u8) {
	append(&w.data, ..b)
}

Reader :: struct {
	data: []u8,
	pos:  int,
	ok:   bool,
}

reader_init :: proc(r: ^Reader, data: []u8) {
	r.data = data
	r.pos = 0
	r.ok = true
}

reader_remaining :: proc(r: ^Reader) -> int {
	return len(r.data) - r.pos
}

reader_fail :: proc(r: ^Reader) {
	r.ok = false
}

// Returns the next n bytes as a view, or nil and ok=false. n < 0 is an error.
@(private)
reader_take :: proc(r: ^Reader, n: int) -> []u8 {
	if !r.ok {
		return nil
	}
	if n < 0 || n > len(r.data) - r.pos {
		r.ok = false
		return nil
	}
	s := r.data[r.pos:r.pos + n]
	r.pos += n
	return s
}

read_u8 :: proc(r: ^Reader) -> u8 {
	b := reader_take(r, 1)
	if b == nil {
		return 0
	}
	return b[0]
}

read_u16 :: proc(r: ^Reader) -> u16 {
	b := reader_take(r, 2)
	if b == nil {
		return 0
	}
	return u16(b[0]) | u16(b[1]) << 8
}

read_u32 :: proc(r: ^Reader) -> u32 {
	b := reader_take(r, 4)
	if b == nil {
		return 0
	}
	return u32(b[0]) | u32(b[1]) << 8 | u32(b[2]) << 16 | u32(b[3]) << 24
}

read_u64 :: proc(r: ^Reader) -> u64 {
	b := reader_take(r, 8)
	if b == nil {
		return 0
	}
	v: u64
	for i in 0 ..< 8 {
		v |= u64(b[i]) << uint(8 * i)
	}
	return v
}

read_i32 :: proc(r: ^Reader) -> i32 {
	return i32(read_u32(r))
}

read_f32 :: proc(r: ^Reader) -> f32 {
	return transmute(f32)read_u32(r)
}

// Strict: any byte other than 0 or 1 is an error.
read_bool :: proc(r: ^Reader) -> bool {
	b := reader_take(r, 1)
	if b == nil {
		return false
	}
	if b[0] > 1 {
		r.ok = false
		return false
	}
	return b[0] == 1
}

// Unsigned LEB128. More than 10 bytes, or a 10th byte that would overflow
// 64 bits, is an error.
read_varint :: proc(r: ^Reader) -> u64 {
	if !r.ok {
		return 0
	}
	v: u64
	for i in 0 ..< 10 {
		if r.pos >= len(r.data) {
			r.ok = false
			return 0
		}
		b := r.data[r.pos]
		r.pos += 1
		if i == 9 && b > 1 {
			r.ok = false
			return 0
		}
		v |= u64(b & 0x7f) << uint(7 * i)
		if b & 0x80 == 0 {
			return v
		}
	}
	r.ok = false
	return 0
}

read_zigzag :: proc(r: ^Reader) -> i64 {
	return zigzag_decode(read_varint(r))
}

// The result aliases the reader's data; copy it if it must outlive the packet.
// A length larger than the remaining bytes is an error.
read_bytes :: proc(r: ^Reader) -> []u8 {
	n := read_varint(r)
	if !r.ok {
		return nil
	}
	if n > u64(len(r.data) - r.pos) {
		r.ok = false
		return nil
	}
	return reader_take(r, int(n))
}

read_string :: proc(r: ^Reader) -> string {
	b := read_bytes(r)
	if b == nil {
		return ""
	}
	return string(b)
}

// Quantization -------------------------------------------------------------

POS_SCALE :: 1024.0
TWO_PI :: 2.0 * math.PI
ANGLE_STEPS :: 65536.0

// 1/1024 m resolution. The arithmetic is done in f64 (the scaling is exact),
// so the error is at most half a step. NaN maps to 0; values outside the i32
// range saturate.
quantize_pos :: proc(x: f32) -> i32 {
	v := f64(x)
	if v != v {
		return 0
	}
	s := math.round(v * POS_SCALE)
	if s >= f64(max(i32)) {
		return max(i32)
	}
	if s <= f64(min(i32)) {
		return min(i32)
	}
	return i32(s)
}

dequantize_pos :: proc(q: i32) -> f32 {
	return f32(f64(q) / POS_SCALE)
}

// Maps radians (any finite value) onto [0, 2π) in 65536 steps. NaN maps to 0.
quantize_angle :: proc(radians: f32) -> u16 {
	v := f64(radians)
	if v != v || math.is_inf(v) {
		return 0
	}
	a := math.mod(v, TWO_PI)
	if a < 0 {
		a += TWO_PI
	}
	q := i64(math.round(a / TWO_PI * ANGLE_STEPS))
	return u16(q & 0xffff) // 65536 wraps to 0
}

dequantize_angle :: proc(q: u16) -> f32 {
	return f32(f64(q) * TWO_PI / ANGLE_STEPS)
}
