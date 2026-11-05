package netcode

import "core:log"
import "core:math/rand"
import "core:testing"

// (c) reliable stress, (d) unreliable delivery, (e) packet size limit.
// All run over the seeded link simulator in simulated time.

HARSH_LINK :: Link_Config {
	latency       = 0.050,
	jitter        = 0.030,
	loss          = 0.20,
	duplicate     = 0.05,
	reorder       = 0.10,
	reorder_delay = 0.100,
}

SIM_DT :: 0.02 // 50 Hz send/receive tick

@(test)
test_reliable_stress_both_directions :: proc(t: ^testing.T) {
	N :: 1000
	state := rand.create(0x5EED)
	rng := rand.default_random_generator(&state)

	sizes: [2][N]int // [side][index]; side 0 = a->b, side 1 = b->a
	total_payload := 0
	for side in 0 ..< 2 {
		for i in 0 ..< N {
			sizes[side][i] = 1 + rand.int_max(20000, rng)
			total_payload += sizes[side][i]
		}
	}

	d: Duo
	duo_init(&d, HARSH_LINK, 20261104)
	defer duo_destroy(&d)

	for i in 0 ..< N {
		pa := make_payload(sizes[0][i], u32(i))
		pb := make_payload(sizes[1][i], 0x10000 | u32(i))
		testing.expect(t, endpoint_send_reliable(&d.a, pa))
		testing.expect(t, endpoint_send_reliable(&d.b, pb))
		delete(pa)
		delete(pb)
	}

	got_a, got_b := 0, 0 // messages received at a (sent by b) and at b (sent by a)
	finished_at := -1.0
	for d.now < 60 {
		am, bm := duo_step(&d, SIM_DT)
		for m in bm {
			ok := got_b < N && m.channel == CHANNEL_RELIABLE && len(m.data) == sizes[0][got_b] && payload_matches(m.data, u32(got_b))
			testing.expectf(t, ok, "b: message %d wrong (len %d)", got_b, len(m.data))
			got_b += 1
		}
		for m in am {
			ok := got_a < N && m.channel == CHANNEL_RELIABLE && len(m.data) == sizes[1][got_a] && payload_matches(m.data, 0x10000 | u32(got_a))
			testing.expectf(t, ok, "a: message %d wrong (len %d)", got_a, len(m.data))
			got_a += 1
		}
		messages_free(&am)
		messages_free(&bm)
		if got_a == N && got_b == N && finished_at < 0 {
			finished_at = d.now
			break
		}
	}
	testing.expectf(t, finished_at >= 0, "not finished in 60 s: a got %d, b got %d of %d", got_a, got_b, N)

	// Keep running: nothing may be delivered a second time.
	extra := 0
	for _ in 0 ..< 250 {
		am, bm := duo_step(&d, SIM_DT)
		extra += len(am) + len(bm)
		messages_free(&am)
		messages_free(&bm)
	}
	testing.expect_value(t, extra, 0)
	testing.expect(t, d.max_packet_seen <= MAX_PACKET)

	wire := d.a.stats.bytes_sent + d.b.stats.bytes_sent
	resends := d.a.stats.resends + d.b.stats.resends
	packets := d.a.stats.packets_sent + d.b.stats.packets_sent
	log.infof("reliable stress: 2 x %d messages, %d payload bytes total (%.1f KB avg per message)", N, total_payload, f64(total_payload) / f64(2 * N) / 1024)
	log.infof("  completed in %.2f simulated s (a<-b %d, b<-a %d delivered, 0 duplicates, 0 reordered)", finished_at, got_a, got_b)
	log.infof("  overhead ratio (wire bytes sent / payload bytes): %.3f   [%d wire bytes in %d packets]", f64(wire) / f64(total_payload), wire, packets)
	log.infof("  fragment resends: %d (a %d, b %d)   final RTT estimate a %.0f ms, b %.0f ms", resends, d.a.stats.resends, d.b.stats.resends, d.a.stats.rtt * 1000, d.b.stats.rtt * 1000)
	log.infof("  link a->b: sent %d dropped %d duplicated %d reordered %d | b->a: sent %d dropped %d duplicated %d reordered %d", d.ab.stats.sent, d.ab.stats.dropped, d.ab.stats.duplicated, d.ab.stats.reordered, d.ba.stats.sent, d.ba.stats.dropped, d.ba.stats.duplicated, d.ba.stats.reordered)
	log.infof("  largest packet %d bytes (limit %d); receiver rejected duplicates a %d, b %d", d.max_packet_seen, MAX_PACKET, d.a.stats.duplicates_dropped, d.b.stats.duplicates_dropped)
}

// The sender window must hold more messages than the receiver window (1024)
// without ever exceeding it.
@(test)
test_reliable_more_than_window :: proc(t: ^testing.T) {
	N :: 3000
	d: Duo
	duo_init(&d, HARSH_LINK, 77)
	defer duo_destroy(&d)
	for i in 0 ..< N {
		p := make_payload(1 + i % 150, u32(i))
		testing.expect(t, endpoint_send_reliable(&d.a, p))
		delete(p)
	}
	got := 0
	for d.now < 120 && got < N {
		am, bm := duo_step(&d, SIM_DT)
		messages_free(&am)
		for m in bm {
			testing.expectf(t, got < N && len(m.data) == 1 + got % 150 && payload_matches(m.data, u32(got)), "message %d wrong", got)
			got += 1
		}
		messages_free(&bm)
	}
	testing.expect_value(t, got, N)
	testing.expect_value(t, d.b.stats.window_drops, u64(0))
	log.infof("window test: %d messages (> %d window) delivered in %.2f simulated s, window drops %d", N, RELIABLE_WINDOW, d.now, d.b.stats.window_drops)
}

@(test)
test_unreliable_delivery_fraction :: proc(t: ^testing.T) {
	TICKS :: 10_000
	PER_TICK :: 2
	TOTAL :: TICKS * PER_TICK
	d: Duo
	duo_init(&d, HARSH_LINK, 4242)
	defer duo_destroy(&d)

	seen := make([]u8, TOTAL)
	defer delete(seen)
	duplicates := 0
	delivered := 0
	next := 0
	receive :: proc(msgs: []Message, seen: []u8, duplicates, delivered: ^int, t: ^testing.T) {
		for m in msgs {
			r: Reader
			reader_init(&r, m.data)
			id := int(read_u32(&r))
			testing.expect(t, r.ok && m.channel == CHANNEL_UNRELIABLE && id < len(seen) && len(m.data) == 4 + 16)
			if r.ok && id < len(seen) {
				if seen[id] != 0 {
					duplicates^ += 1
				}
				seen[id] += 1
				delivered^ += 1
			}
		}
	}
	for tick in 0 ..< TICKS + 100 {
		if tick < TICKS {
			for _ in 0 ..< PER_TICK {
				w: Writer
				writer_init(&w)
				write_u32(&w, u32(next))
				filler := make_payload(16, u32(next))
				write_raw(&w, filler)
				delete(filler)
				testing.expect(t, endpoint_send_unreliable(&d.a, w.data[:]))
				writer_destroy(&w)
				next += 1
			}
		}
		am, bm := duo_step(&d, SIM_DT)
		messages_free(&am)
		receive(bm[:], seen, &duplicates, &delivered, t)
		messages_free(&bm)
	}
	unique := 0
	for s in seen {
		if s > 0 {
			unique += 1
		}
	}
	fraction := f64(unique) / f64(TOTAL)
	expected := 1 - HARSH_LINK.loss
	testing.expect_value(t, duplicates, 0)
	testing.expect_value(t, delivered, unique)
	testing.expectf(t, abs(fraction - expected) <= 0.03, "delivered fraction %.4f, expected %.2f +/- 0.03", fraction, expected)
	testing.expect_value(t, d.a.stats.unreliable_dropped, u64(0))
	log.infof("unreliable: sent %d, delivered %d unique (%.2f%%, expected %.0f%% +/- 3), duplicate deliveries %d, link duplicates absorbed %d", TOTAL, unique, fraction * 100, expected * 100, duplicates, d.b.stats.duplicates_dropped)
}

// Unreliable messages beyond the per-write packet budget are dropped, not queued.
@(test)
test_unreliable_budget_drops :: proc(t: ^testing.T) {
	e: Endpoint
	endpoint_init(&e, 3)
	defer endpoint_destroy(&e)
	e.max_packets_per_write = 2
	big := make([]u8, 1000)
	defer delete(big)
	for _ in 0 ..< 10 {
		testing.expect(t, endpoint_send_unreliable(&e, big))
	}
	pkts := endpoint_write_packets(&e, 0)
	defer packets_free(&pkts)
	testing.expect_value(t, len(pkts), 2)
	testing.expect_value(t, e.stats.unreliable_dropped, u64(8))
	again := endpoint_write_packets(&e, 0.01)
	defer packets_free(&again)
	testing.expect_value(t, len(again), 0) // nothing carried over, no keep-alive due yet
}

// (e) Mix everything that could overfill a packet and assert on every write.
@(test)
test_packet_size_never_exceeds_max :: proc(t: ^testing.T) {
	state := rand.create(0xE)
	rng := rand.default_random_generator(&state)
	d: Duo
	duo_init(&d, Link_Config{latency = 0.03, jitter = 0.01, loss = 0.1}, 5)
	defer duo_destroy(&d)
	for step in 0 ..< 1500 {
		// Random unreliable sizes up to and including the maximum, plus reliable
		// payloads around the fragment size, from both sides.
		for _ in 0 ..< rand.int_max(6, rng) {
			n := rand.int_max(max_unreliable_payload() + 1, rng)
			p := make_payload(n, u32(step))
			endpoint_send_unreliable(&d.a, p)
			endpoint_send_unreliable(&d.b, p)
			delete(p)
		}
		if step % 3 == 0 {
			sizes := [?]int{999, 1000, 1001, 1, 2500, 0}
			n := sizes[rand.int_max(len(sizes), rng)]
			p := make_payload(n, u32(step))
			endpoint_send_reliable(&d.a, p)
			endpoint_send_reliable(&d.b, p)
			delete(p)
		}
		am, bm := duo_step(&d, 0.01) // duo_step asserts len <= MAX_PACKET on every packet
		messages_free(&am)
		messages_free(&bm)
	}
	testing.expect(t, d.packets_checked > 1000)
	testing.expect(t, d.max_packet_seen <= MAX_PACKET)
	log.infof("packet size: %d packets written, largest %d bytes (MAX_PACKET %d), asserted on every write", d.packets_checked, d.max_packet_seen, MAX_PACKET)
}

// Idle endpoints exchange only keep-alives, and only about 10 per second.
@(test)
test_keepalive_rate :: proc(t: ^testing.T) {
	d: Duo
	duo_init(&d, Link_Config{latency = 0.01}, 8)
	defer duo_destroy(&d)
	for _ in 0 ..< 1000 { 	// 10 s at 100 Hz
		am, bm := duo_step(&d, 0.01)
		messages_free(&am)
		messages_free(&bm)
	}
	testing.expectf(t, d.a.stats.packets_sent >= 95 && d.a.stats.packets_sent <= 105, "a sent %d keep-alives in 10 s", d.a.stats.packets_sent)
	testing.expectf(t, d.b.stats.packets_received >= 95, "b received %d", d.b.stats.packets_received)
}
