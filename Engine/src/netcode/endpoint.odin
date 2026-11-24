package netcode

import "core:slice"

// One side of one connection. No sockets, no clocks: packets and the current
// time go in, packets and messages come out.

TIME_EPSILON :: 1e-9 // absorbs float rounding in accumulated simulated/wall time
KEEPALIVE_INTERVAL :: 0.1 // seconds between sends when idle
INITIAL_RTT :: 0.1
MIN_RESEND_TIMEOUT :: 0.05
RTT_SMOOTHING :: 0.125
SENT_RING :: 1024
MAX_QUEUED_UNRELIABLE :: 1024
DEFAULT_PACKETS_PER_WRITE :: 8 // keeps a sender inside the 32-packet ack_bits window; 16 doubled the resends in testing

Message :: struct {
	channel: u8,
	data:    []u8, // owned by whoever took it; release with messages_free
}

Stats :: struct {
	packets_sent:       u64,
	packets_received:   u64,
	bytes_sent:         u64,
	bytes_received:     u64,
	resends:            u64, // reliable fragments sent more than once
	rtt:                f64, // seconds, smoothed
	// Diagnostics.
	duplicates_dropped: u64,
	malformed:          u64,
	window_drops:       u64,
	unreliable_dropped: u64,
}

@(private)
Frag_Ref :: struct {
	msg_id: u16,
	index:  u8,
}

@(private)
Sent_Packet :: struct {
	valid:     bool,
	acked:     bool,
	seq:       u16,
	send_time: f64,
	frags:     [dynamic]Frag_Ref,
}

@(private)
Send_Msg :: struct {
	msg_id:      u16,
	data:        []u8,
	frag_count:  int,
	acked:       []bool,
	last_sent:   []f64, // -1 = never sent
	acked_count: int,
}

@(private)
Recv_Slot :: struct {
	active:     bool,
	msg_id:     u16,
	frag_count: int,
	got:        int,
	frags:      [][]u8,
	have:       []bool,
}

Endpoint :: struct {
	salt:                  u32, // must match on both sides; packets with another salt are ignored
	stats:                 Stats,
	max_packets_per_write: int,
	next_seq:              u16, // starts at 1 so a fresh peer's "ack 0" cannot acknowledge anything
	last_send_time:        f64,
	ack_dirty:             bool,

	// Sending.
	sent:                  []Sent_Packet,
	unreliable_out:        [dynamic][]u8,
	reliable_out:          [dynamic]^Send_Msg,
	next_msg_id:           u16,

	// Receiving.
	got_any:               bool,
	remote_seq:            u16,
	recv_bits:             u32,
	recv_seen:             []i32,
	recv_expected:         u16,
	recv_slots:            []Recv_Slot,
	inbox:                 [dynamic]Message,
}

endpoint_init :: proc(e: ^Endpoint, salt: u32 = 0) {
	e^ = {}
	e.salt = salt
	e.max_packets_per_write = DEFAULT_PACKETS_PER_WRITE
	e.next_seq = 1
	e.last_send_time = -1e18
	e.stats.rtt = INITIAL_RTT
	e.sent = make([]Sent_Packet, SENT_RING)
	e.recv_seen = make([]i32, SENT_RING)
	for &s in e.recv_seen {
		s = -1
	}
	e.recv_slots = make([]Recv_Slot, RELIABLE_WINDOW)
	e.unreliable_out = make([dynamic][]u8)
	e.reliable_out = make([dynamic]^Send_Msg)
	e.inbox = make([dynamic]Message)
}

@(private)
send_msg_destroy :: proc(m: ^Send_Msg) {
	delete(m.data)
	delete(m.acked)
	delete(m.last_sent)
	free(m)
}

@(private)
recv_slot_clear :: proc(s: ^Recv_Slot) {
	for f in s.frags {
		delete(f)
	}
	delete(s.frags)
	delete(s.have)
	s^ = {}
}

endpoint_destroy :: proc(e: ^Endpoint) {
	for &p in e.sent {
		delete(p.frags)
	}
	delete(e.sent)
	for m in e.unreliable_out {
		delete(m)
	}
	delete(e.unreliable_out)
	for m in e.reliable_out {
		send_msg_destroy(m)
	}
	delete(e.reliable_out)
	delete(e.recv_seen)
	for &s in e.recv_slots {
		recv_slot_clear(&s)
	}
	delete(e.recv_slots)
	for m in e.inbox {
		delete(m.data)
	}
	delete(e.inbox)
	e^ = {}
}

// Queues one unreliable message for the next write. False if it cannot fit in
// a single packet (or 1024 messages are already waiting).
endpoint_send_unreliable :: proc(e: ^Endpoint, payload: []u8) -> bool {
	if DATA_HEADER_SIZE + message_record_size(len(payload)) > MAX_PACKET {
		return false
	}
	if len(e.unreliable_out) >= MAX_QUEUED_UNRELIABLE {
		return false
	}
	append(&e.unreliable_out, slice.clone(payload))
	return true
}

// Queues one reliable-ordered message of up to 255 * FRAGMENT_SIZE bytes.
endpoint_send_reliable :: proc(e: ^Endpoint, payload: []u8) -> bool {
	if len(payload) > MAX_RELIABLE_SIZE {
		return false
	}
	frag_count := max(1, (len(payload) + FRAGMENT_SIZE - 1) / FRAGMENT_SIZE)
	m := new(Send_Msg)
	m.msg_id = e.next_msg_id
	e.next_msg_id += 1
	m.data = slice.clone(payload)
	m.frag_count = frag_count
	m.acked = make([]bool, frag_count)
	m.last_sent = make([]f64, frag_count)
	for &t in m.last_sent {
		t = -1
	}
	append(&e.reliable_out, m)
	return true
}

// ---------------------------------------------------------------------------
// Receiving

@(private)
process_ack :: proc(e: ^Endpoint, seq: u16, now: f64) {
	rec := &e.sent[int(seq) % SENT_RING]
	if !rec.valid || rec.acked || rec.seq != seq {
		return
	}
	rec.acked = true
	sample := max(now - rec.send_time, 0)
	e.stats.rtt += RTT_SMOOTHING * (sample - e.stats.rtt)
	if len(e.reliable_out) > 0 {
		front := e.reliable_out[0].msg_id
		for f in rec.frags {
			d := int(f.msg_id - front)
			if d >= len(e.reliable_out) {
				continue
			}
			m := e.reliable_out[d]
			if m.msg_id != f.msg_id || int(f.index) >= m.frag_count || m.acked[f.index] {
				continue
			}
			m.acked[f.index] = true
			m.acked_count += 1
		}
	}
	clear(&rec.frags)
}

@(private)
pop_acked :: proc(e: ^Endpoint) {
	for len(e.reliable_out) > 0 {
		m := e.reliable_out[0]
		if m.acked_count != m.frag_count {
			break
		}
		send_msg_destroy(m)
		ordered_remove(&e.reliable_out, 0)
	}
}

@(private)
handle_fragment :: proc(e: ^Endpoint, payload: []u8) {
	r: Reader
	reader_init(&r, payload)
	msg_id := read_u16(&r)
	index := int(read_u8(&r))
	count := int(read_u8(&r))
	if !r.ok || count == 0 || index >= count {
		e.stats.malformed += 1
		return
	}
	data := payload[RELIABLE_HEADER_SIZE:]
	if len(data) > FRAGMENT_SIZE {
		e.stats.malformed += 1
		return
	}
	delta := msg_id - e.recv_expected
	if delta >= 32768 {
		return // already delivered: a duplicate or late resend
	}
	if int(delta) >= RELIABLE_WINDOW {
		e.stats.window_drops += 1
		return
	}
	slot := &e.recv_slots[int(msg_id) % RELIABLE_WINDOW]
	if !slot.active {
		slot.active = true
		slot.msg_id = msg_id
		slot.frag_count = count
		slot.frags = make([][]u8, count)
		slot.have = make([]bool, count)
	} else if slot.msg_id != msg_id || slot.frag_count != count {
		e.stats.malformed += 1
		return
	}
	if slot.have[index] {
		return
	}
	slot.frags[index] = slice.clone(data)
	slot.have[index] = true
	slot.got += 1

	// Deliver every complete message at the head of the window, in order.
	for {
		s := &e.recv_slots[int(e.recv_expected) % RELIABLE_WINDOW]
		if !s.active || s.msg_id != e.recv_expected || s.got != s.frag_count {
			break
		}
		total := 0
		for f in s.frags {
			total += len(f)
		}
		out := make([]u8, total)
		at := 0
		for f in s.frags {
			copy(out[at:], f)
			at += len(f)
		}
		append(&e.inbox, Message{channel = CHANNEL_RELIABLE, data = out})
		recv_slot_clear(s)
		e.recv_expected += 1
	}
}

// Parses one datagram. Returns false if it was rejected (wrong protocol, kind,
// salt, malformed header, or a duplicate / too-old packet).
endpoint_receive :: proc(e: ^Endpoint, packet: []u8, now: f64) -> bool {
	if len(packet) > MAX_PACKET {
		e.stats.malformed += 1
		return false
	}
	r: Reader
	reader_init(&r, packet)
	h, ok := read_header(&r)
	if !ok || h.kind != .Data || h.client_salt != e.salt {
		e.stats.malformed += 1
		return false
	}

	seq := h.seq
	ring := int(seq) % SENT_RING
	newest := !e.got_any || seq_greater(seq, e.remote_seq)
	if !newest {
		diff := int(e.remote_seq - seq)
		if diff >= SENT_RING || e.recv_seen[ring] == i32(seq) {
			e.stats.duplicates_dropped += 1
			return false
		}
	}
	e.recv_seen[ring] = i32(seq)
	if !e.got_any {
		e.got_any = true
		e.remote_seq = seq
		e.recv_bits = 0
	} else if newest {
		shift := int(seq - e.remote_seq)
		if shift > 32 {
			e.recv_bits = 0
		} else {
			old := u32(0) if shift == 32 else e.recv_bits << uint(shift)
			e.recv_bits = old | (u32(1) << uint(shift - 1))
		}
		e.remote_seq = seq
	} else {
		diff := int(e.remote_seq - seq)
		if diff <= 32 {
			e.recv_bits |= u32(1) << uint(diff - 1)
		}
	}

	e.stats.packets_received += 1
	e.stats.bytes_received += u64(len(packet))

	// Acknowledgements for our own packets.
	process_ack(e, h.ack, now)
	for i in 0 ..< 32 {
		if h.ack_bits & (u32(1) << uint(i)) != 0 {
			process_ack(e, h.ack - 1 - u16(i), now)
		}
	}
	pop_acked(e)

	// Messages.
	had_messages := false
	for reader_remaining(&r) > 0 {
		channel := read_u8(&r)
		size := read_varint(&r)
		if !r.ok || size > u64(reader_remaining(&r)) {
			e.stats.malformed += 1
			break
		}
		payload := reader_take(&r, int(size))
		switch channel {
		case CHANNEL_UNRELIABLE:
			append(&e.inbox, Message{channel = CHANNEL_UNRELIABLE, data = slice.clone(payload)})
		case CHANNEL_RELIABLE:
			if len(payload) < RELIABLE_HEADER_SIZE {
				e.stats.malformed += 1
			} else {
				handle_fragment(e, payload)
			}
		case:
			e.stats.malformed += 1
			r.ok = false
		}
		if !r.ok {
			break
		}
		had_messages = true
	}
	if had_messages {
		e.ack_dirty = true
	}
	return true
}

// Hands the delivered messages to the caller, who owns them (messages_free).
endpoint_take_messages :: proc(e: ^Endpoint) -> [dynamic]Message {
	msgs := e.inbox
	e.inbox = make([dynamic]Message)
	return msgs
}

messages_free :: proc(msgs: ^[dynamic]Message) {
	for m in msgs {
		delete(m.data)
	}
	delete(msgs^)
	msgs^ = nil
}

// ---------------------------------------------------------------------------
// Sending

@(private)
Builder :: struct {
	w:      Writer,
	frags:  [dynamic]Frag_Ref,
	active: bool,
}

@(private)
begin_packet :: proc(e: ^Endpoint, b: ^Builder) {
	writer_init(&b.w, MAX_PACKET)
	ack := e.remote_seq if e.got_any else 0
	bits := e.recv_bits if e.got_any else 0
	write_header(&b.w, Header{kind = .Data, client_salt = e.salt, seq = e.next_seq, ack = ack, ack_bits = bits})
	b.frags = make([dynamic]Frag_Ref)
	b.active = true
}

@(private)
finish_packet :: proc(e: ^Endpoint, b: ^Builder, out: ^[dynamic][]u8, now: f64) {
	assert(len(b.w.data) <= MAX_PACKET, "netcode: packet exceeds MAX_PACKET")
	rec := &e.sent[int(e.next_seq) % SENT_RING]
	delete(rec.frags)
	rec^ = Sent_Packet {
		valid     = true,
		seq       = e.next_seq,
		send_time = now,
		frags     = b.frags,
	}
	append(out, b.w.data[:])
	e.stats.packets_sent += 1
	e.stats.bytes_sent += u64(len(b.w.data))
	e.next_seq += 1
	e.last_send_time = now
	e.ack_dirty = false
	b^ = {}
}

@(private)
builder_room :: proc(b: ^Builder) -> int {
	return MAX_PACKET - len(b.w.data)
}

// Produces the datagrams to send this round, each at most MAX_PACKET bytes.
// Order: pending unreliable messages (each sent once; any that do not fit in
// max_packets_per_write packets are dropped), then reliable fragments that are
// unacked and due, oldest first. If nothing else is sent, an empty packet goes
// out when acks are owed or KEEPALIVE_INTERVAL has passed since the last send.
endpoint_write_packets :: proc(e: ^Endpoint, now: f64) -> [dynamic][]u8 {
	out := make([dynamic][]u8)
	b: Builder
	budget := max(e.max_packets_per_write, 1)

	// Unreliable.
	for msg, i in e.unreliable_out {
		need := message_record_size(len(msg))
		if b.active && need > builder_room(&b) {
			finish_packet(e, &b, &out, now)
		}
		if !b.active {
			if len(out) >= budget {
				e.stats.unreliable_dropped += u64(len(e.unreliable_out) - i)
				break
			}
			begin_packet(e, &b)
		}
		write_u8(&b.w, CHANNEL_UNRELIABLE)
		write_varint(&b.w, u64(len(msg)))
		write_raw(&b.w, msg)
	}
	for m in e.unreliable_out {
		delete(m)
	}
	clear(&e.unreliable_out)

	// Reliable.
	timeout := max(2 * e.stats.rtt, MIN_RESEND_TIMEOUT)
	window := min(len(e.reliable_out), RELIABLE_WINDOW)
	reliable_loop: for mi in 0 ..< window {
		m := e.reliable_out[mi]
		for fi in 0 ..< m.frag_count {
			if m.acked[fi] {
				continue
			}
			if m.last_sent[fi] >= 0 && now - m.last_sent[fi] < timeout - TIME_EPSILON {
				continue
			}
			lo := fi * FRAGMENT_SIZE
			hi := min(lo + FRAGMENT_SIZE, len(m.data))
			frag := m.data[lo:hi]
			psize := RELIABLE_HEADER_SIZE + len(frag)
			need := message_record_size(psize)
			if b.active && need > builder_room(&b) {
				finish_packet(e, &b, &out, now)
			}
			if !b.active {
				if len(out) >= budget {
					break reliable_loop
				}
				begin_packet(e, &b)
			}
			write_u8(&b.w, CHANNEL_RELIABLE)
			write_varint(&b.w, u64(psize))
			write_u16(&b.w, m.msg_id)
			write_u8(&b.w, u8(fi))
			write_u8(&b.w, u8(m.frag_count))
			write_raw(&b.w, frag)
			append(&b.frags, Frag_Ref{msg_id = m.msg_id, index = u8(fi)})
			if m.last_sent[fi] >= 0 {
				e.stats.resends += 1
			}
			m.last_sent[fi] = now
		}
	}

	if b.active {
		finish_packet(e, &b, &out, now)
	} else if len(out) == 0 && (e.ack_dirty || now - e.last_send_time >= KEEPALIVE_INTERVAL - TIME_EPSILON) {
		begin_packet(e, &b)
		finish_packet(e, &b, &out, now)
	}
	return out
}

packets_free :: proc(packets: ^[dynamic][]u8) {
	for p in packets {
		delete(p)
	}
	delete(packets^)
	packets^ = nil
}
