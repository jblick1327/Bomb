package netcode

import "core:log"
import "core:math/rand"
import "core:testing"
import "core:time"

// (g) Real UDP sockets on 127.0.0.1: a server and a client connect, then each
// sends 200 reliable messages (1..20,000 bytes) and 1,000 unreliable ones.

SOCK_RELIABLE :: 200
SOCK_UNRELIABLE :: 1000
SOCK_MAX_SIZE :: 20_000
SOCK_UNRELIABLE_PER_TICK :: 10

Peer_Stream :: struct {
	sizes:        [SOCK_RELIABLE]int,
	tag_base:     u32,
	queued:       bool,
	unreliable_sent: int,
	reliable_got: int, // reliable messages received from the other side, all verified
	reliable_bad: int,
	unreliable_seen: [SOCK_UNRELIABLE]u8,
	unreliable_dups: int,
	unreliable_got:  int,
}

@(private)
peer_accept :: proc(p: ^Peer_Stream, peer_sizes: ^[SOCK_RELIABLE]int, peer_tag: u32, msgs: []Message) {
	for m in msgs {
		switch m.channel {
		case CHANNEL_RELIABLE:
			i := p.reliable_got
			if i >= SOCK_RELIABLE || len(m.data) != peer_sizes[i] || !payload_matches(m.data, peer_tag + u32(i)) {
				p.reliable_bad += 1
			}
			p.reliable_got += 1
		case CHANNEL_UNRELIABLE:
			r: Reader
			reader_init(&r, m.data)
			id := int(read_u32(&r))
			if r.ok && id < SOCK_UNRELIABLE {
				if p.unreliable_seen[id] != 0 {
					p.unreliable_dups += 1
				} else {
					p.unreliable_got += 1
				}
				p.unreliable_seen[id] += 1
			}
		}
	}
}

@(private)
peer_queue_reliable :: proc(t: ^testing.T, p: ^Peer_Stream, send: proc(ctx: rawptr, data: []u8) -> bool, ctx: rawptr) {
	for i in 0 ..< SOCK_RELIABLE {
		payload := make_payload(p.sizes[i], p.tag_base + u32(i))
		testing.expect(t, send(ctx, payload))
		delete(payload)
	}
	p.queued = true
}

@(private)
peer_queue_unreliable :: proc(t: ^testing.T, p: ^Peer_Stream, send: proc(ctx: rawptr, data: []u8) -> bool, ctx: rawptr) {
	for _ in 0 ..< SOCK_UNRELIABLE_PER_TICK {
		if p.unreliable_sent >= SOCK_UNRELIABLE {
			return
		}
		w: Writer
		writer_init(&w)
		write_u32(&w, u32(p.unreliable_sent))
		write_raw(&w, []u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16})
		testing.expect(t, send(ctx, w.data[:]))
		writer_destroy(&w)
		p.unreliable_sent += 1
	}
}

@(test)
test_real_sockets_smoke :: proc(t: ^testing.T) {
	server_sock, client_sock: Socket
	if !socket_open(&server_sock, 0, {127, 0, 0, 1}) {
		testing.expect(t, false, "could not open server socket")
		return
	}
	defer socket_close(&server_sock)
	if !socket_open(&client_sock, 0, {127, 0, 0, 1}) {
		testing.expect(t, false, "could not open client socket")
		return
	}
	defer socket_close(&client_sock)
	server_addr := address_loopback(socket_port(&server_sock))
	testing.expect(t, address_port(server_addr) != 0, "ephemeral port")

	server: Server
	server_init(&server)
	defer server_destroy(&server)
	client: Client
	client_init(&client)
	defer client_destroy(&client)

	state := rand.create(0x50C4E7)
	rng := rand.default_random_generator(&state)
	server_side := new(Peer_Stream) // Peer_Stream is large (the seen tables), keep it off the stack
	client_side := new(Peer_Stream)
	defer free(server_side)
	defer free(client_side)
	server_side.tag_base = 0x20000
	client_side.tag_base = 0x10000
	for i in 0 ..< SOCK_RELIABLE {
		client_side.sizes[i] = 1 + rand.int_max(SOCK_MAX_SIZE, rng)
		server_side.sizes[i] = 1 + rand.int_max(SOCK_MAX_SIZE, rng)
	}

	start := time.tick_now()
	buf: [MAX_PACKET + 64]u8
	server_client := -1
	finished := false
	finish_at := 0.0
	elapsed := 0.0

	server_send_reliable_cb :: proc(ctx: rawptr, data: []u8) -> bool {
		pair := cast(^struct {
			s: ^Server,
			i: int,
		})ctx
		return server_send_reliable(pair.s, pair.i, data)
	}
	server_send_unreliable_cb :: proc(ctx: rawptr, data: []u8) -> bool {
		pair := cast(^struct {
			s: ^Server,
			i: int,
		})ctx
		return server_send_unreliable(pair.s, pair.i, data)
	}
	client_send_reliable_cb :: proc(ctx: rawptr, data: []u8) -> bool {
		return client_send_reliable(cast(^Client)ctx, data)
	}
	client_send_unreliable_cb :: proc(ctx: rawptr, data: []u8) -> bool {
		return client_send_unreliable(cast(^Client)ctx, data)
	}

	client_connect(&client, random_salt(), 0)
	for {
		elapsed = time.duration_seconds(time.tick_since(start))
		if elapsed > 10 {
			break
		}

		// Client out.
		client_update(&client, elapsed)
		out := client_take_outgoing(&client)
		for o in out {
			testing.expect(t, len(o.data) <= MAX_PACKET)
			socket_send(&client_sock, server_addr, o.data)
		}
		outgoing_free(&out)

		// Server in.
		for {
			data, from, ok := socket_receive(&server_sock, buf[:])
			if !ok {
				break
			}
			server_receive(&server, from, data, elapsed)
		}
		evs := server_take_events(&server)
		for ev in evs {
			switch ev.kind {
			case .Connected:
				server_client = ev.client
			case .Message:
				one := [1]Message{Message{channel = ev.channel, data = ev.data}}
				peer_accept(server_side, &client_side.sizes, client_side.tag_base, one[:])
			case .Disconnected:
			}
		}
		server_events_free(&evs)

		// Server logic and out.
		sctx := struct {
			s: ^Server,
			i: int,
		}{&server, server_client}
		if server_client >= 0 {
			if !server_side.queued {
				peer_queue_reliable(t, server_side, server_send_reliable_cb, &sctx)
			}
			peer_queue_unreliable(t, server_side, server_send_unreliable_cb, &sctx)
		}
		server_update(&server, elapsed)
		sout := server_take_outgoing(&server)
		for o in sout {
			testing.expect(t, len(o.data) <= MAX_PACKET)
			socket_send(&server_sock, o.to, o.data)
		}
		outgoing_free(&sout)

		// Client in.
		for {
			data, _, ok := socket_receive(&client_sock, buf[:])
			if !ok {
				break
			}
			client_receive(&client, data, elapsed)
		}
		cmsgs := client_take_messages(&client)
		peer_accept(client_side, &server_side.sizes, server_side.tag_base, cmsgs[:])
		messages_free(&cmsgs)
		if client.state == .Connected {
			if !client_side.queued {
				peer_queue_reliable(t, client_side, client_send_reliable_cb, &client)
			}
			peer_queue_unreliable(t, client_side, client_send_unreliable_cb, &client)
		}

		reliable_done := server_side.reliable_got == SOCK_RELIABLE && client_side.reliable_got == SOCK_RELIABLE
		unreliable_sent := server_side.unreliable_sent == SOCK_UNRELIABLE && client_side.unreliable_sent == SOCK_UNRELIABLE
		if reliable_done && unreliable_sent {
			if finish_at == 0 {
				finish_at = elapsed
			}
			if elapsed - finish_at > 0.25 { 	// let the last unreliable datagrams land
				finished = true
				break
			}
		}
		time.sleep(time.Millisecond)
	}

	testing.expectf(t, client.state == .Connected, "client state %v", client.state)
	testing.expectf(t, finished, "not finished within 10 s (client got %d/%d reliable, server got %d/%d)", client_side.reliable_got, SOCK_RELIABLE, server_side.reliable_got, SOCK_RELIABLE)
	testing.expect_value(t, client_side.reliable_got, SOCK_RELIABLE)
	testing.expect_value(t, server_side.reliable_got, SOCK_RELIABLE)
	testing.expect_value(t, client_side.reliable_bad, 0)
	testing.expect_value(t, server_side.reliable_bad, 0)
	testing.expect_value(t, client_side.unreliable_dups, 0)
	testing.expect_value(t, server_side.unreliable_dups, 0)
	// Loopback UDP is nearly lossless but not guaranteed; require 95%.
	testing.expectf(t, client_side.unreliable_got >= SOCK_UNRELIABLE * 95 / 100, "client got %d/%d unreliable", client_side.unreliable_got, SOCK_UNRELIABLE)
	testing.expectf(t, server_side.unreliable_got >= SOCK_UNRELIABLE * 95 / 100, "server got %d/%d unreliable", server_side.unreliable_got, SOCK_UNRELIABLE)
	log.infof("sockets: both directions complete in %.2f s wall time (limit 10): reliable %d+%d delivered in order and byte-identical, unreliable %d/%d to client and %d/%d to server, 0 duplicates", finish_at, client_side.reliable_got, server_side.reliable_got, client_side.unreliable_got, SOCK_UNRELIABLE, server_side.unreliable_got, SOCK_UNRELIABLE)
	log.infof("  client endpoint: packets sent %d, resends %d, rtt %.1f ms", client.endpoint.stats.packets_sent, client.endpoint.stats.resends, client.endpoint.stats.rtt * 1000)
}
