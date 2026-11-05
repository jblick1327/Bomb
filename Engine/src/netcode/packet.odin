package netcode

// Wire format.
//
//   every packet: protocol_id u32 | kind u8 | client_salt u32            (9 bytes)
//   data packets: ... | seq u16 | ack u16 | ack_bits u32                 (17 bytes)
//   accept body:  client_index u8
//   reject body:  reason (varint length + UTF-8)
//   data body:    zero or more [channel u8][size varint][payload]
//     channel 0: unreliable, payload is the application message
//     channel 1: reliable-ordered, payload = msg_id u16 | frag_index u8 |
//                frag_count u8 | fragment bytes

MAX_PACKET :: 1200
PROTOCOL_ID :: u32(0x314D4F42) // "BOM1" read as little-endian bytes: 42 4F 4D 31
FRAGMENT_SIZE :: 1000
MAX_FRAGMENTS :: 255
MAX_RELIABLE_SIZE :: MAX_FRAGMENTS * FRAGMENT_SIZE
RELIABLE_WINDOW :: 1024

BASE_HEADER_SIZE :: 9
DATA_HEADER_SIZE :: 17
RELIABLE_HEADER_SIZE :: 4

CHANNEL_UNRELIABLE :: u8(0)
CHANNEL_RELIABLE :: u8(1)

Packet_Kind :: enum u8 {
	Connect    = 0,
	Accept     = 1,
	Reject     = 2,
	Data       = 3,
	Disconnect = 4,
}

Header :: struct {
	kind:        Packet_Kind,
	client_salt: u32,
	// Data packets only.
	seq:         u16,
	ack:         u16,
	ack_bits:    u32,
}

write_header :: proc(w: ^Writer, h: Header) {
	write_u32(w, PROTOCOL_ID)
	write_u8(w, u8(h.kind))
	write_u32(w, h.client_salt)
	if h.kind == .Data {
		write_u16(w, h.seq)
		write_u16(w, h.ack)
		write_u32(w, h.ack_bits)
	}
}

// Parses the header and leaves the reader at the start of the body. Wrong
// protocol id, unknown kind or truncation returns ok=false.
read_header :: proc(r: ^Reader) -> (h: Header, ok: bool) {
	if read_u32(r) != PROTOCOL_ID {
		r.ok = false
		return {}, false
	}
	kind := read_u8(r)
	if kind > u8(Packet_Kind.Disconnect) {
		r.ok = false
		return {}, false
	}
	h.kind = Packet_Kind(kind)
	h.client_salt = read_u32(r)
	if h.kind == .Data {
		h.seq = read_u16(r)
		h.ack = read_u16(r)
		h.ack_bits = read_u32(r)
	}
	return h, r.ok
}

// Wire size of one message record for a payload of n bytes.
message_record_size :: proc(n: int) -> int {
	return 1 + varint_size(u64(n)) + n
}

// Largest unreliable payload that still fits one packet.
max_unreliable_payload :: proc() -> int {
	n := MAX_PACKET - DATA_HEADER_SIZE - 2 // channel byte + at least one size byte
	for message_record_size(n) + DATA_HEADER_SIZE > MAX_PACKET {
		n -= 1
	}
	return n
}

// Half-range rule: a is "greater" than b if it is ahead of b by less than
// half the sequence space, so 0 is greater than 65535.
seq_greater :: proc(a, b: u16) -> bool {
	return (a > b && a - b <= 32768) || (a < b && b - a > 32768)
}

seq_less :: proc(a, b: u16) -> bool {
	return seq_greater(b, a)
}

// Builds a control packet (connect / accept / reject / disconnect).
// The caller owns the result.
build_control_packet :: proc(kind: Packet_Kind, salt: u32, client_index: u8 = 0, reason: string = "") -> []u8 {
	w: Writer
	writer_init(&w, BASE_HEADER_SIZE + 2 + len(reason))
	write_header(&w, Header{kind = kind, client_salt = salt})
	#partial switch kind {
	case .Accept:
		write_u8(&w, client_index)
	case .Reject:
		write_string(&w, reason)
	}
	return w.data[:]
}
