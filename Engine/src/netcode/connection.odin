package netcode

import "core:math/rand"
import "core:strings"

// Server and client state machines over Endpoints. No sockets: the caller
// feeds received datagrams in and sends whatever the *_take_outgoing procs
// return. Addresses are opaque comparable values chosen by the caller.

MAX_CLIENTS :: 4
CONNECT_INTERVAL :: 0.1
CONNECTION_TIMEOUT :: 5.0
REASON_SERVER_FULL :: "server full"

Address :: distinct u64

Outgoing :: struct {
	to:   Address, // ignored by clients (they only talk to the server)
	data: []u8, // owned by the caller
}

outgoing_free :: proc(list: ^[dynamic]Outgoing) {
	for o in list {
		delete(o.data)
	}
	delete(list^)
	list^ = nil
}

random_salt :: proc() -> u32 {
	for {
		s := rand.uint32()
		if s != 0 {
			return s
		}
	}
}

@(private)
push_outgoing :: proc(list: ^[dynamic]Outgoing, to: Address, data: []u8) {
	append(list, Outgoing{to = to, data = data})
}

@(private)
drain_outgoing :: proc(list: ^[dynamic]Outgoing) -> [dynamic]Outgoing {
	out := list^
	list^ = make([dynamic]Outgoing)
	return out
}

// ---------------------------------------------------------------------------
// Server

Disconnect_Reason :: enum {
	Timeout,
	Client_Disconnect,
	Replaced, // same address reconnected with a new salt
	Kicked,
}

Server_Event_Kind :: enum {
	Connected,
	Disconnected,
	Message,
}

Server_Event :: struct {
	kind:    Server_Event_Kind,
	client:  int,
	reason:  Disconnect_Reason, // Disconnected
	channel: u8, // Message
	data:    []u8, // Message; owned by the caller
}

server_events_free :: proc(events: ^[dynamic]Server_Event) {
	for ev in events {
		delete(ev.data)
	}
	delete(events^)
	events^ = nil
}

Server_Client :: struct {
	active:    bool,
	address:   Address,
	salt:      u32,
	last_recv: f64,
	endpoint:  Endpoint,
}

Server :: struct {
	clients: [MAX_CLIENTS]Server_Client,
	events:  [dynamic]Server_Event,
	outbox:  [dynamic]Outgoing,
}

server_init :: proc(s: ^Server) {
	s^ = {}
	s.events = make([dynamic]Server_Event)
	s.outbox = make([dynamic]Outgoing)
}

server_destroy :: proc(s: ^Server) {
	for &c in s.clients {
		if c.active {
			endpoint_destroy(&c.endpoint)
		}
	}
	server_events_free(&s.events)
	outgoing_free(&s.outbox)
	s^ = {}
}

server_client_count :: proc(s: ^Server) -> int {
	n := 0
	for c in s.clients {
		if c.active {
			n += 1
		}
	}
	return n
}

@(private)
server_find :: proc(s: ^Server, address: Address, salt: u32) -> int {
	for &c, i in s.clients {
		if c.active && c.address == address && c.salt == salt {
			return i
		}
	}
	return -1
}

@(private)
server_remove :: proc(s: ^Server, index: int, reason: Disconnect_Reason) {
	c := &s.clients[index]
	if !c.active {
		return
	}
	endpoint_destroy(&c.endpoint)
	c^ = {}
	append(&s.events, Server_Event{kind = .Disconnected, client = index, reason = reason})
}

@(private)
server_handle_connect :: proc(s: ^Server, from: Address, salt: u32, now: f64) {
	if i := server_find(s, from, salt); i >= 0 {
		// Duplicate connect: the accept was probably lost. Answer again.
		s.clients[i].last_recv = now
		push_outgoing(&s.outbox, from, build_control_packet(.Accept, salt, u8(i)))
		return
	}
	// The same address with a different salt is a reconnect: the old
	// connection is dead, so replace it instead of filling slots with ghosts.
	for &c, i in s.clients {
		if c.active && c.address == from {
			server_remove(s, i, .Replaced)
		}
	}
	for &c, i in s.clients {
		if !c.active {
			c.active = true
			c.address = from
			c.salt = salt
			c.last_recv = now
			endpoint_init(&c.endpoint, salt)
			append(&s.events, Server_Event{kind = .Connected, client = i})
			push_outgoing(&s.outbox, from, build_control_packet(.Accept, salt, u8(i)))
			return
		}
	}
	push_outgoing(&s.outbox, from, build_control_packet(.Reject, salt, 0, REASON_SERVER_FULL))
}

// Feed every received datagram here.
server_receive :: proc(s: ^Server, from: Address, packet: []u8, now: f64) {
	if len(packet) > MAX_PACKET {
		return
	}
	r: Reader
	reader_init(&r, packet)
	h, ok := read_header(&r)
	if !ok {
		return
	}
	switch h.kind {
	case .Connect:
		server_handle_connect(s, from, h.client_salt, now)
	case .Disconnect:
		if i := server_find(s, from, h.client_salt); i >= 0 {
			server_remove(s, i, .Client_Disconnect)
		}
	case .Data:
		i := server_find(s, from, h.client_salt)
		if i < 0 {
			return
		}
		c := &s.clients[i]
		c.last_recv = now
		if endpoint_receive(&c.endpoint, packet, now) {
			msgs := endpoint_take_messages(&c.endpoint)
			defer delete(msgs)
			for m in msgs {
				append(&s.events, Server_Event{kind = .Message, client = i, channel = m.channel, data = m.data})
			}
		}
	case .Accept, .Reject:
	// Not meaningful to a server.
	}
}

// Call regularly (e.g. every tick): drops silent clients and produces each
// client's outgoing data packets.
server_update :: proc(s: ^Server, now: f64) {
	for &c, i in s.clients {
		if !c.active {
			continue
		}
		if now - c.last_recv >= CONNECTION_TIMEOUT - TIME_EPSILON {
			server_remove(s, i, .Timeout)
			continue
		}
		packets := endpoint_write_packets(&c.endpoint, now)
		for p in packets {
			push_outgoing(&s.outbox, c.address, p)
		}
		delete(packets)
	}
}

server_send_unreliable :: proc(s: ^Server, client: int, payload: []u8) -> bool {
	if client < 0 || client >= MAX_CLIENTS || !s.clients[client].active {
		return false
	}
	return endpoint_send_unreliable(&s.clients[client].endpoint, payload)
}

server_send_reliable :: proc(s: ^Server, client: int, payload: []u8) -> bool {
	if client < 0 || client >= MAX_CLIENTS || !s.clients[client].active {
		return false
	}
	return endpoint_send_reliable(&s.clients[client].endpoint, payload)
}

// Removes the client and tells it so.
server_kick :: proc(s: ^Server, client: int) {
	if client < 0 || client >= MAX_CLIENTS || !s.clients[client].active {
		return
	}
	c := &s.clients[client]
	push_outgoing(&s.outbox, c.address, build_control_packet(.Disconnect, c.salt))
	server_remove(s, client, .Kicked)
}

server_take_outgoing :: proc(s: ^Server) -> [dynamic]Outgoing {
	return drain_outgoing(&s.outbox)
}

server_take_events :: proc(s: ^Server) -> [dynamic]Server_Event {
	out := s.events
	s.events = make([dynamic]Server_Event)
	return out
}

// ---------------------------------------------------------------------------
// Client

Client_State :: enum {
	Disconnected,
	Connecting,
	Connected,
	Failed, // rejected; see reject_reason
	Timed_Out,
}

Client :: struct {
	state:             Client_State,
	salt:              u32,
	client_index:      int,
	reject_reason:     string, // owned; valid when state == .Failed
	endpoint:          Endpoint,
	last_connect_send: f64,
	last_recv:         f64, // time of the last reply (or of the connect attempt)
	outbox:            [dynamic]Outgoing,
}

client_init :: proc(c: ^Client) {
	c^ = {}
	c.client_index = -1
	c.outbox = make([dynamic]Outgoing)
}

client_destroy :: proc(c: ^Client) {
	if c.endpoint.sent != nil {
		endpoint_destroy(&c.endpoint)
	}
	delete(c.reject_reason)
	outgoing_free(&c.outbox)
	c^ = {}
}

// Starts a connection attempt with a fresh salt (pass random_salt()).
client_connect :: proc(c: ^Client, salt: u32, now: f64) {
	if c.endpoint.sent != nil {
		endpoint_destroy(&c.endpoint)
	}
	delete(c.reject_reason)
	c.reject_reason = ""
	c.salt = salt
	c.client_index = -1
	c.state = .Connecting
	c.last_connect_send = -1e18
	c.last_recv = now
	endpoint_init(&c.endpoint, salt)
}

client_receive :: proc(c: ^Client, packet: []u8, now: f64) {
	if len(packet) > MAX_PACKET {
		return
	}
	r: Reader
	reader_init(&r, packet)
	h, ok := read_header(&r)
	if !ok || h.client_salt != c.salt {
		return
	}
	switch h.kind {
	case .Accept:
		index := int(read_u8(&r))
		if !r.ok || index >= MAX_CLIENTS {
			return
		}
		if c.state == .Connecting {
			c.state = .Connected
			c.client_index = index
		}
		if c.state == .Connected {
			c.last_recv = now
		}
	case .Reject:
		reason := read_string(&r)
		if r.ok && c.state == .Connecting {
			c.state = .Failed
			c.reject_reason = strings.clone(reason)
		}
	case .Data:
		if c.state == .Connected {
			c.last_recv = now
			endpoint_receive(&c.endpoint, packet, now)
		}
	case .Disconnect:
		if c.state == .Connected {
			c.state = .Disconnected
		}
	case .Connect:
	}
}

client_update :: proc(c: ^Client, now: f64) {
	switch c.state {
	case .Connecting:
		if now - c.last_recv >= CONNECTION_TIMEOUT - TIME_EPSILON {
			c.state = .Timed_Out
		} else if now - c.last_connect_send >= CONNECT_INTERVAL - TIME_EPSILON {
			c.last_connect_send = now
			push_outgoing(&c.outbox, 0, build_control_packet(.Connect, c.salt))
		}
	case .Connected:
		if now - c.last_recv >= CONNECTION_TIMEOUT - TIME_EPSILON {
			c.state = .Timed_Out
			return
		}
		packets := endpoint_write_packets(&c.endpoint, now)
		for p in packets {
			push_outgoing(&c.outbox, 0, p)
		}
		delete(packets)
	case .Disconnected, .Failed, .Timed_Out:
	}
}

client_send_unreliable :: proc(c: ^Client, payload: []u8) -> bool {
	if c.state != .Connected {
		return false
	}
	return endpoint_send_unreliable(&c.endpoint, payload)
}

client_send_reliable :: proc(c: ^Client, payload: []u8) -> bool {
	if c.state != .Connected {
		return false
	}
	return endpoint_send_reliable(&c.endpoint, payload)
}

client_take_messages :: proc(c: ^Client) -> [dynamic]Message {
	if c.endpoint.sent == nil {
		return make([dynamic]Message)
	}
	return endpoint_take_messages(&c.endpoint)
}

// Tells the server and stops. (Sent once; a lost packet just means the server
// notices by timeout instead.)
client_disconnect :: proc(c: ^Client) {
	if c.state == .Connecting || c.state == .Connected {
		push_outgoing(&c.outbox, 0, build_control_packet(.Disconnect, c.salt))
	}
	c.state = .Disconnected
}

client_take_outgoing :: proc(c: ^Client) -> [dynamic]Outgoing {
	return drain_outgoing(&c.outbox)
}
