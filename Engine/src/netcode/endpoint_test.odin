package netcode

import "core:log"
import "core:math/rand"
import "core:slice"
import "core:testing"

// Shared helpers ------------------------------------------------------------

// Deterministic pseudo-random bytes so receivers can verify content from
// (size, tag) alone.
make_payload :: proc(size: int, tag: u32) -> []u8 {
	buf := make([]u8, size)
	x := tag * 2654435761 + 12345
	for i in 0 ..< size {
		x = x * 1664525 + 1013904223
		buf[i] = u8(x >> 24)
	}
	return buf
}

payload_matches :: proc(data: []u8, tag: u32) -> bool {
	want := make_payload(len(data), tag)
	defer delete(want)
	return slice.equal(data, want)
}

// Two endpoints joined by two simulated links.
Duo :: struct {
	a, b:   Endpoint,
	ab, ba: Link, // a -> b, b -> a
	now:    f64,
	// Largest packet seen on either link.
	max_packet_seen: int,
	packets_checked: int,
}

duo_init :: proc(d: ^Duo, cfg: Link_Config, seed: u64, salt: u32 = 0xB0B) {
	d^ = {}
	endpoint_init(&d.a, salt)
	endpoint_init(&d.b, salt)
	link_init(&d.ab, cfg, seed * 2 + 1)
	link_init(&d.ba, cfg, seed * 2 + 2)
}

duo_destroy :: proc(d: ^Duo) {
	endpoint_destroy(&d.a)
	endpoint_destroy(&d.b)
	link_destroy(&d.ab)
	link_destroy(&d.ba)
}

// Advances simulated time by dt: delivers due packets, then lets both sides
// write. Returns what each side received this step (caller frees).
duo_step :: proc(d: ^Duo, dt: f64) -> (a_msgs, b_msgs: [dynamic]Message) {
	d.now += dt
	{
		pkts := link_receive(&d.ba, d.now)
		for p in pkts {
			endpoint_receive(&d.a, p, d.now)
		}
		packets_free(&pkts)
	}
	{
		pkts := link_receive(&d.ab, d.now)
		for p in pkts {
			endpoint_receive(&d.b, p, d.now)
		}
		packets_free(&pkts)
	}
	a_msgs = endpoint_take_messages(&d.a)
	b_msgs = endpoint_take_messages(&d.b)
	{
		pkts := endpoint_write_packets(&d.a, d.now)
		for p in pkts {
			duo_check_packet(d, p)
			link_send(&d.ab, p, d.now)
		}
		packets_free(&pkts)
	}
	{
		pkts := endpoint_write_packets(&d.b, d.now)
		for p in pkts {
			duo_check_packet(d, p)
			link_send(&d.ba, p, d.now)
		}
		packets_free(&pkts)
	}
	return
}

duo_check_packet :: proc(d: ^Duo, p: []u8) {
	assert(len(p) <= MAX_PACKET, "packet exceeds MAX_PACKET")
	d.max_packet_seen = max(d.max_packet_seen, len(p))
	d.packets_checked += 1
}

// Packet format ---------------------------------------------------------------

@(test)
test_seq_greater_wraps :: proc(t: ^testing.T) {
	testing.expect(t, seq_greater(1, 0))
	testing.expect(t, !seq_greater(0, 1))
	testing.expect(t, !seq_greater(5, 5))
	// Across 65535 -> 0.
	testing.expect(t, seq_greater(0, 65535))
	testing.expect(t, !seq_greater(65535, 0))
	testing.expect(t, seq_greater(3, 65530))
	testing.expect(t, !seq_greater(65530, 3))
	testing.expect(t, seq_greater(100, 65500))
	// Half-range boundary: exactly half ahead still counts as greater, one
	// past it does not.
	testing.expect(t, seq_greater(32768, 0))
	testing.expect(t, !seq_greater(32769, 0))
	testing.expect(t, seq_greater(0, 32769))
	// Exhaustive consistency around the wrap.
	for base in ([?]u16{0, 1, 32767, 32768, 65000, 65535}) {
		for k in 1 ..< 32768 {
			a := base + u16(k)
			testing.expectf(t, seq_greater(a, base) && !seq_greater(base, a), "base %d + %d", base, k)
		}
	}
}

@(test)
test_header_round_trip :: proc(t: ^testing.T) {
	for kind in Packet_Kind {
		w: Writer
		writer_init(&w)
		defer writer_destroy(&w)
		h := Header {
			kind        = kind,
			client_salt = 0xCAFEF00D,
		}
		if kind == .Data {
			h.seq = 65535
			h.ack = 7
			h.ack_bits = 0x80000001
		}
		write_header(&w, h)
		want := DATA_HEADER_SIZE if kind == .Data else BASE_HEADER_SIZE
		testing.expect_value(t, len(w.data), want)

		r: Reader
		reader_init(&r, w.data[:])
		got, ok := read_header(&r)
		testing.expect(t, ok)
		testing.expect(t, got == h)
		testing.expect_value(t, reader_remaining(&r), 0)
	}
	// The magic number is "BOM1" on the wire.
	w: Writer
	writer_init(&w)
	defer writer_destroy(&w)
	write_header(&w, Header{kind = .Connect, client_salt = 1})
	testing.expect_value(t, string(w.data[:4]), "BOM1")

	// Wrong protocol id and unknown kind are rejected.
	bad := [?]u8{'X', 'O', 'M', '1', 0, 0, 0, 0, 0}
	r: Reader
	reader_init(&r, bad[:])
	_, ok := read_header(&r)
	testing.expect(t, !ok)
	copy(bad[:], "BOM1")
	bad[4] = 9
	reader_init(&r, bad[:])
	_, ok = read_header(&r)
	testing.expect(t, !ok)
}

// Endpoint --------------------------------------------------------------------

@(test)
test_endpoint_send_limits :: proc(t: ^testing.T) {
	e: Endpoint
	endpoint_init(&e, 1)
	defer endpoint_destroy(&e)

	limit := max_unreliable_payload()
	testing.expect_value(t, limit, 1180)
	big := make([]u8, limit + 1)
	defer delete(big)
	testing.expect(t, endpoint_send_unreliable(&e, big[:limit]), "limit-sized unreliable must fit")
	testing.expect(t, !endpoint_send_unreliable(&e, big[:limit + 1]), "one byte over must be refused")

	// The accepted one really does fit in a single MAX_PACKET datagram.
	pkts := endpoint_write_packets(&e, 0)
	defer packets_free(&pkts)
	testing.expect_value(t, len(pkts), 1)
	if len(pkts) == 1 {
		testing.expect_value(t, len(pkts[0]), MAX_PACKET)
	}

	huge := make([]u8, MAX_RELIABLE_SIZE + 1)
	defer delete(huge)
	testing.expect(t, endpoint_send_reliable(&e, huge[:MAX_RELIABLE_SIZE]), "255 fragments allowed")
	testing.expect(t, !endpoint_send_reliable(&e, huge), "larger than 255 fragments refused")
	testing.expect(t, endpoint_send_reliable(&e, nil), "empty reliable message allowed")
}

@(test)
test_reliable_boundaries_lossless :: proc(t: ^testing.T) {
	d: Duo
	duo_init(&d, Link_Config{latency = 0.02}, 11)
	defer duo_destroy(&d)

	sizes := [?]int{0, 1, 999, 1000, 1001, 1007, 1993, 2000, 2001, 5000, MAX_RELIABLE_SIZE}
	for s, i in sizes {
		p := make_payload(s, u32(i))
		defer delete(p)
		testing.expect(t, endpoint_send_reliable(&d.a, p))
	}
	got := 0
	for _ in 0 ..< 2000 {
		am, bm := duo_step(&d, 0.01)
		messages_free(&am)
		for m in bm {
			testing.expectf(t, m.channel == CHANNEL_RELIABLE, "channel %d", m.channel)
			if got < len(sizes) {
				testing.expectf(t, len(m.data) == sizes[got], "message %d: %d bytes, want %d", got, len(m.data), sizes[got])
				testing.expectf(t, payload_matches(m.data, u32(got)), "message %d content differs", got)
			}
			got += 1
		}
		messages_free(&bm)
		if got >= len(sizes) {
			break
		}
	}
	testing.expect_value(t, got, len(sizes))
	testing.expect(t, d.max_packet_seen <= MAX_PACKET)
}

@(test)
test_sequence_wraparound_in_flight :: proc(t: ^testing.T) {
	d: Duo
	duo_init(&d, Link_Config{latency = 0.01}, 12)
	defer duo_destroy(&d)
	// Start both packet counters just below the wrap and run through it.
	d.a.next_seq = 65500
	d.b.next_seq = 65510
	d.a.next_msg_id = 65520 // reliable message ids wrap too
	d.b.recv_expected = 65520
	count := 200
	for i in 0 ..< count {
		p := make_payload(1 + i * 37 % 4000, u32(i))
		defer delete(p)
		testing.expect(t, endpoint_send_reliable(&d.a, p))
	}
	got := 0
	for _ in 0 ..< 3000 {
		am, bm := duo_step(&d, 0.01)
		messages_free(&am)
		for m in bm {
			testing.expectf(t, payload_matches(m.data, u32(got)), "message %d wrong across wrap", got)
			got += 1
		}
		messages_free(&bm)
		if got == count && len(d.a.reliable_out) == 0 {
			break
		}
	}
	testing.expect_value(t, got, count)
	testing.expect_value(t, len(d.a.reliable_out), 0) // everything acked across the wrap
	testing.expect(t, d.a.next_seq < 60000, "a's packet sequence should have wrapped past 65535")
}

@(test)
test_duplicate_packets_ignored :: proc(t: ^testing.T) {
	a, b: Endpoint
	endpoint_init(&a, 5)
	endpoint_init(&b, 5)
	defer endpoint_destroy(&a)
	defer endpoint_destroy(&b)

	testing.expect(t, endpoint_send_unreliable(&a, []u8{1, 2, 3}))
	p := make_payload(3500, 3)
	defer delete(p)
	testing.expect(t, endpoint_send_reliable(&a, p))
	pkts := endpoint_write_packets(&a, 0)
	defer packets_free(&pkts)
	for pk in pkts {
		testing.expect(t, endpoint_receive(&b, pk, 0.05))
	}
	// Replaying every packet, several times, in reverse, must change nothing.
	for _ in 0 ..< 3 {
		#reverse for pk in pkts {
			testing.expect(t, !endpoint_receive(&b, pk, 0.06), "duplicate packet must be rejected")
		}
	}
	msgs := endpoint_take_messages(&b)
	defer messages_free(&msgs)
	testing.expect_value(t, len(msgs), 2)
	unreliable, reliable := 0, 0
	for m in msgs {
		if m.channel == CHANNEL_UNRELIABLE {
			unreliable += 1
		} else {
			reliable += 1
			testing.expect(t, payload_matches(m.data, 3))
		}
	}
	testing.expect_value(t, unreliable, 1)
	testing.expect_value(t, reliable, 1)
	testing.expect_value(t, b.stats.duplicates_dropped, u64(3 * len(pkts)))
}

@(test)
test_receive_window_and_garbage :: proc(t: ^testing.T) {
	// Hand-build a data packet carrying a reliable fragment with a chosen id.
	build :: proc(salt: u32, seq: u16, msg_id: u16, frag_index, frag_count: u8, data: []u8) -> []u8 {
		w: Writer
		writer_init(&w)
		write_header(&w, Header{kind = .Data, client_salt = salt, seq = seq})
		write_u8(&w, CHANNEL_RELIABLE)
		write_varint(&w, u64(RELIABLE_HEADER_SIZE + len(data)))
		write_u16(&w, msg_id)
		write_u8(&w, frag_index)
		write_u8(&w, frag_count)
		write_raw(&w, data)
		return w.data[:]
	}
	e: Endpoint
	endpoint_init(&e, 9)
	defer endpoint_destroy(&e)

	payload := []u8{1, 2, 3}
	// id 1023 is the last one inside the window; 1024 is outside.
	p1 := build(9, 1, 1023, 0, 1, payload)
	defer delete(p1)
	p2 := build(9, 2, 1024, 0, 1, payload)
	defer delete(p2)
	// Zero fragment count, index >= count, oversize fragment, wrong salt.
	p3 := build(9, 3, 0, 0, 0, payload)
	defer delete(p3)
	p4 := build(9, 4, 0, 2, 2, payload)
	defer delete(p4)
	big := make([]u8, FRAGMENT_SIZE + 1)
	defer delete(big)
	p5 := build(9, 5, 0, 0, 1, big)
	defer delete(p5)
	p6 := build(77, 6, 0, 0, 1, payload)
	defer delete(p6)

	testing.expect(t, endpoint_receive(&e, p1, 0))
	testing.expect(t, endpoint_receive(&e, p2, 0))
	testing.expect(t, endpoint_receive(&e, p3, 0))
	testing.expect(t, endpoint_receive(&e, p4, 0))
	testing.expect(t, endpoint_receive(&e, p5, 0))
	testing.expect(t, !endpoint_receive(&e, p6, 0), "wrong salt rejected")
	testing.expect_value(t, e.stats.window_drops, u64(1))
	testing.expect(t, e.stats.malformed >= 4)
	msgs := endpoint_take_messages(&e)
	defer messages_free(&msgs)
	testing.expect_value(t, len(msgs), 0) // 1023 is buffered, waiting for 0..1022

	// Oversized datagram and short garbage.
	too_big := make([]u8, MAX_PACKET + 1)
	defer delete(too_big)
	testing.expect(t, !endpoint_receive(&e, too_big, 0))
	testing.expect(t, !endpoint_receive(&e, nil, 0))
	testing.expect(t, !endpoint_receive(&e, []u8{1, 2, 3}, 0))
}

@(test)
test_receive_fuzz_no_panic :: proc(t: ^testing.T) {
	state := rand.create(0xF022)
	rng := rand.default_random_generator(&state)

	// A realistic packet to mutate.
	src: Endpoint
	endpoint_init(&src, 42)
	defer endpoint_destroy(&src)
	pl := make_payload(2500, 1)
	defer delete(pl)
	endpoint_send_reliable(&src, pl)
	endpoint_send_unreliable(&src, []u8{9, 9, 9, 9})
	seed_pkts := endpoint_write_packets(&src, 0)
	defer packets_free(&seed_pkts)

	e: Endpoint
	endpoint_init(&e, 42)
	defer endpoint_destroy(&e)
	s: Server
	server_init(&s)
	defer server_destroy(&s)
	c: Client
	client_init(&c)
	defer client_destroy(&c)
	client_connect(&c, 42, 0)

	buf: [MAX_PACKET]u8
	for iter in 0 ..< 10_000 {
		n: int
		if iter % 2 == 0 {
			n = rand.int_max(80, rng)
			for i in 0 ..< n {
				buf[i] = u8(rand.uint32(rng))
			}
			if iter % 4 == 0 && n >= 9 {
				copy(buf[:], "BOM1")
				buf[4] = u8(rand.int_max(5, rng))
			}
		} else {
			pk := seed_pkts[iter % len(seed_pkts)]
			n = len(pk)
			copy(buf[:], pk)
			for _ in 0 ..< 1 + rand.int_max(4, rng) {
				buf[rand.int_max(n, rng)] = u8(rand.uint32(rng))
			}
			if iter % 5 == 1 {
				n = rand.int_max(n + 1, rng) // truncate too
			}
		}
		now := f64(iter) * 0.001
		endpoint_receive(&e, buf[:n], now)
		server_receive(&s, Address(iter % 7), buf[:n], now)
		client_receive(&c, buf[:n], now)
		if iter % 100 == 0 {
			msgs := endpoint_take_messages(&e)
			messages_free(&msgs)
			ev := server_take_events(&s)
			server_events_free(&ev)
		}
	}
	log.infof("receive fuzz: 10000 random/mutated datagrams into endpoint, server and client without a panic")
}
