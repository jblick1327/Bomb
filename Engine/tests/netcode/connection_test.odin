package netcode

import "core:log"
import "core:testing"

// (f) Server/client state machines with fake addresses and instant delivery.

NET_CLIENTS :: 6

Net :: struct {
	server:  Server,
	clients: [NET_CLIENTS]Client,
	addrs:   [NET_CLIENTS]Address,
	muted:   [NET_CLIENTS]bool, // true = this client's traffic is lost in both directions
	events:  [dynamic]Server_Event,
	// Times at which the server reported disconnects, per client index.
	disconnect_time: [MAX_CLIENTS]f64,
	disconnect_why:  [MAX_CLIENTS]Disconnect_Reason,
	now:     f64,
}

net_init :: proc(n: ^Net) {
	n^ = {}
	server_init(&n.server)
	n.events = make([dynamic]Server_Event)
	for i in 0 ..< NET_CLIENTS {
		client_init(&n.clients[i])
		n.addrs[i] = Address(1000 + i)
	}
	for i in 0 ..< MAX_CLIENTS {
		n.disconnect_time[i] = -1
	}
}

net_destroy :: proc(n: ^Net) {
	for i in 0 ..< NET_CLIENTS {
		client_destroy(&n.clients[i])
	}
	server_destroy(&n.server)
	server_events_free(&n.events)
}

net_step :: proc(n: ^Net, dt: f64) {
	n.now += dt
	for i in 0 ..< NET_CLIENTS {
		c := &n.clients[i]
		client_update(c, n.now)
		out := client_take_outgoing(c)
		if !n.muted[i] {
			for o in out {
				server_receive(&n.server, n.addrs[i], o.data, n.now)
			}
		}
		outgoing_free(&out)
	}
	server_update(&n.server, n.now)
	out := server_take_outgoing(&n.server)
	for o in out {
		for i in 0 ..< NET_CLIENTS {
			if n.addrs[i] == o.to && !n.muted[i] {
				client_receive(&n.clients[i], o.data, n.now)
			}
		}
	}
	outgoing_free(&out)
	evs := server_take_events(&n.server)
	for ev in evs {
		if ev.kind == .Disconnected {
			n.disconnect_time[ev.client] = n.now
			n.disconnect_why[ev.client] = ev.reason
		}
		append(&n.events, ev)
	}
	delete(evs)
}

net_run :: proc(n: ^Net, seconds: f64) {
	steps := int(seconds / 0.02 + 0.5)
	for _ in 0 ..< steps {
		net_step(n, 0.02)
	}
}

net_connect :: proc(n: ^Net, i: int, salt: u32) {
	client_connect(&n.clients[i], salt, n.now)
}

@(test)
test_four_clients_and_server_full :: proc(t: ^testing.T) {
	n: Net
	net_init(&n)
	defer net_destroy(&n)

	for i in 0 ..< 4 {
		net_connect(&n, i, u32(0x1000 + i))
	}
	net_run(&n, 0.5)
	seen := [MAX_CLIENTS]bool{}
	for i in 0 ..< 4 {
		c := &n.clients[i]
		testing.expectf(t, c.state == .Connected, "client %d state %v", i, c.state)
		if c.client_index >= 0 && c.client_index < MAX_CLIENTS {
			testing.expectf(t, !seen[c.client_index], "client index %d assigned twice", c.client_index)
			seen[c.client_index] = true
		}
	}
	testing.expect_value(t, server_client_count(&n.server), 4)

	// The fifth is refused with a reason.
	net_connect(&n, 4, 0x2000)
	net_run(&n, 0.5)
	testing.expect_value(t, n.clients[4].state, Client_State.Failed)
	testing.expect_value(t, n.clients[4].reject_reason, "server full")
	testing.expect_value(t, server_client_count(&n.server), 4)

	// Messages flow both ways on an accepted connection.
	testing.expect(t, client_send_reliable(&n.clients[0], []u8{1, 2, 3}))
	testing.expect(t, server_send_reliable(&n.server, n.clients[2].client_index, []u8{9, 9}))
	net_run(&n, 0.3)
	reliable_to_server := 0
	for ev in n.events {
		if ev.kind == .Message && ev.channel == CHANNEL_RELIABLE && ev.client == n.clients[0].client_index {
			reliable_to_server += 1
			testing.expect_value(t, len(ev.data), 3)
		}
	}
	testing.expect_value(t, reliable_to_server, 1)
	msgs := client_take_messages(&n.clients[2])
	defer messages_free(&msgs)
	testing.expect_value(t, len(msgs), 1)
	log.infof("connections: 4 clients accepted (indices distinct), 5th rejected with %q", n.clients[4].reject_reason)
}

@(test)
test_duplicate_connect_is_idempotent :: proc(t: ^testing.T) {
	s: Server
	server_init(&s)
	defer server_destroy(&s)
	pkt := build_control_packet(.Connect, 0xABC)
	defer delete(pkt)
	for k in 0 ..< 5 {
		server_receive(&s, Address(7), pkt, f64(k) * 0.1)
	}
	testing.expect_value(t, server_client_count(&s), 1)
	out := server_take_outgoing(&s)
	defer outgoing_free(&out)
	testing.expect_value(t, len(out), 5) // every duplicate is re-accepted
	for o in out {
		r: Reader
		reader_init(&r, o.data)
		h, ok := read_header(&r)
		testing.expect(t, ok && h.kind == .Accept && h.client_salt == 0xABC)
		testing.expect_value(t, read_u8(&r), 0)
	}
	ev := server_take_events(&s)
	defer server_events_free(&ev)
	testing.expect_value(t, len(ev), 1) // a single Connected event
}

@(test)
test_silent_client_times_out :: proc(t: ^testing.T) {
	n: Net
	net_init(&n)
	defer net_destroy(&n)
	for i in 0 ..< 4 {
		net_connect(&n, i, u32(0x3000 + i))
	}
	net_run(&n, 1.0)
	testing.expect_value(t, server_client_count(&n.server), 4)

	idx := n.clients[1].client_index
	n.muted[1] = true
	last_heard := n.server.clients[idx].last_recv
	net_run(&n, 6.0)

	testing.expect_value(t, server_client_count(&n.server), 3)
	elapsed := n.disconnect_time[idx] - last_heard
	testing.expectf(t, n.disconnect_time[idx] > 0, "no disconnect event for client %d", idx)
	testing.expectf(t, abs(elapsed - CONNECTION_TIMEOUT) <= 0.1, "timed out after %.3f s of silence, want 5.0 +/- 0.1", elapsed)
	testing.expect_value(t, n.disconnect_why[idx], Disconnect_Reason.Timeout)
	// The silent client times out on its side too; the others are untouched.
	testing.expect_value(t, n.clients[1].state, Client_State.Timed_Out)
	for i in ([?]int{0, 2, 3}) {
		testing.expectf(t, n.clients[i].state == .Connected, "client %d state %v", i, n.clients[i].state)
	}
	log.infof("timeout: silent client removed %.3f s after the last packet (limit 5.0 +/- 0.1)", elapsed)
}

@(test)
test_client_connect_timeout :: proc(t: ^testing.T) {
	n: Net
	net_init(&n)
	defer net_destroy(&n)
	n.muted[0] = true // nobody ever answers
	net_connect(&n, 0, 0x4000)
	start := n.now
	timed_out_at := -1.0
	for _ in 0 ..< 400 {
		net_step(&n, 0.02)
		if n.clients[0].state == .Timed_Out && timed_out_at < 0 {
			timed_out_at = n.now - start
		}
	}
	testing.expectf(t, abs(timed_out_at - CONNECTION_TIMEOUT) <= 0.1, "connect timed out after %.3f s, want 5.0 +/- 0.1", timed_out_at)

	// While trying, it sends a connect every 100 ms.
	c: Client
	client_init(&c)
	defer client_destroy(&c)
	client_connect(&c, 0x4001, 0)
	sent := 0
	for k in 0 ..< 100 { 	// 2 s at 50 Hz
		client_update(&c, f64(k) * 0.02)
		out := client_take_outgoing(&c)
		sent += len(out)
		outgoing_free(&out)
	}
	testing.expectf(t, sent >= 19 && sent <= 21, "%d connect packets in 2 s, want about 20", sent)
}

@(test)
test_reconnect_with_new_salt :: proc(t: ^testing.T) {
	n: Net
	net_init(&n)
	defer net_destroy(&n)
	for i in 0 ..< 4 {
		net_connect(&n, i, u32(0x5000 + i))
	}
	net_run(&n, 0.5)
	testing.expect_value(t, server_client_count(&n.server), 4)

	// Client 2 loses its state and comes back from the same address with a
	// new salt while the server is full. It must get in, replacing the stale
	// entry, and the old salt's packets must no longer be accepted.
	old_index := n.clients[2].client_index
	old_salt := n.clients[2].salt
	net_connect(&n, 2, 0x5ABC)
	net_run(&n, 0.5)
	testing.expect_value(t, n.clients[2].state, Client_State.Connected)
	testing.expect_value(t, server_client_count(&n.server), 4)
	testing.expect_value(t, n.disconnect_why[old_index], Disconnect_Reason.Replaced)

	stale := build_control_packet(.Disconnect, old_salt)
	defer delete(stale)
	server_receive(&n.server, n.addrs[2], stale, n.now)
	testing.expect_value(t, server_client_count(&n.server), 4) // stale salt ignored

	// The new connection carries data.
	testing.expect(t, client_send_reliable(&n.clients[2], []u8{4, 5, 6}))
	net_run(&n, 0.3)
	got := false
	for ev in n.events {
		if ev.kind == .Message && ev.client == n.clients[2].client_index {
			got = true
		}
	}
	testing.expect(t, got, "data over the reconnected session")
}

@(test)
test_disconnect_packet_frees_slot_immediately :: proc(t: ^testing.T) {
	n: Net
	net_init(&n)
	defer net_destroy(&n)
	for i in 0 ..< 4 {
		net_connect(&n, i, u32(0x6000 + i))
	}
	net_run(&n, 0.5)
	testing.expect_value(t, server_client_count(&n.server), 4)

	// Fifth is refused while full.
	net_connect(&n, 4, 0x6100)
	net_run(&n, 0.3)
	testing.expect_value(t, n.clients[4].state, Client_State.Failed)

	// A disconnect packet frees the slot in the same call, not after a timeout.
	client_disconnect(&n.clients[3])
	out := client_take_outgoing(&n.clients[3])
	testing.expect_value(t, len(out), 1)
	for o in out {
		server_receive(&n.server, n.addrs[3], o.data, n.now)
	}
	outgoing_free(&out)
	testing.expect_value(t, server_client_count(&n.server), 3)
	evs := server_take_events(&n.server)
	freed := false
	for ev in evs {
		if ev.kind == .Disconnected && ev.reason == .Client_Disconnect {
			freed = true
		}
	}
	server_events_free(&evs)
	testing.expect(t, freed, "disconnect event with reason Client_Disconnect")

	// The freed slot is usable right away.
	net_connect(&n, 4, 0x6200)
	net_run(&n, 0.3)
	testing.expect_value(t, n.clients[4].state, Client_State.Connected)

	// Kicking tells the client.
	server_kick(&n.server, n.clients[0].client_index)
	net_run(&n, 0.1)
	testing.expect_value(t, n.clients[0].state, Client_State.Disconnected)
}
