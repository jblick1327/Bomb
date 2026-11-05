package netcode

import "core:net"

// Thin non-blocking UDP wrapper over core:net (IPv4 only). No game logic.
// An Address packs IPv4 (high 32 bits of the low 48) and port (low 16 bits).

address_make :: proc(ip: [4]u8, port: u16) -> Address {
	return Address(u64(ip[0]) << 40 | u64(ip[1]) << 32 | u64(ip[2]) << 24 | u64(ip[3]) << 16 | u64(port))
}

address_loopback :: proc(port: u16) -> Address {
	return address_make({127, 0, 0, 1}, port)
}

address_port :: proc(a: Address) -> u16 {
	return u16(u64(a) & 0xffff)
}

address_ip :: proc(a: Address) -> [4]u8 {
	v := u64(a)
	return {u8(v >> 40), u8(v >> 32), u8(v >> 24), u8(v >> 16)}
}

@(private)
address_to_endpoint :: proc(a: Address) -> net.Endpoint {
	return net.Endpoint{address = net.IP4_Address(address_ip(a)), port = int(address_port(a))}
}

@(private)
address_from_endpoint :: proc(ep: net.Endpoint) -> (Address, bool) {
	ip4, is_ip4 := ep.address.(net.IP4_Address)
	if !is_ip4 {
		return 0, false
	}
	return address_make(cast([4]u8)ip4, u16(ep.port)), true
}

Socket :: struct {
	handle:  net.UDP_Socket,
	is_open: bool,
}

// Opens a non-blocking UDP socket bound to ip:port. Port 0 picks an ephemeral
// port; read it back with socket_port.
socket_open :: proc(s: ^Socket, port: u16 = 0, ip: [4]u8 = {0, 0, 0, 0}) -> bool {
	sock, err := net.make_bound_udp_socket(net.IP4_Address(ip), int(port))
	if err != nil {
		return false
	}
	if net.set_blocking(sock, false) != nil {
		net.close(sock)
		return false
	}
	s.handle = sock
	s.is_open = true
	return true
}

socket_port :: proc(s: ^Socket) -> u16 {
	if !s.is_open {
		return 0
	}
	ep, err := net.bound_endpoint(s.handle)
	if err != nil {
		return 0
	}
	return u16(ep.port)
}

socket_send :: proc(s: ^Socket, to: Address, data: []u8) -> bool {
	if !s.is_open {
		return false
	}
	n, err := net.send_udp(s.handle, data, address_to_endpoint(to))
	return err == nil && n == len(data)
}

// Returns the next waiting datagram, written into buf (use MAX_PACKET bytes or
// more), or ok=false when nothing is waiting. Call in a loop until it returns
// false. Datagrams from non-IPv4 senders and Windows' "port unreachable"
// notifications are skipped.
socket_receive :: proc(s: ^Socket, buf: []u8) -> (data: []u8, from: Address, ok: bool) {
	if !s.is_open {
		return nil, 0, false
	}
	for _ in 0 ..< 64 {
		n, ep, err := net.recv_udp(s.handle, buf)
		if err == .Connection_Refused {
			continue
		}
		if err != nil {
			return nil, 0, false
		}
		addr, is_ip4 := address_from_endpoint(ep)
		if n <= 0 || !is_ip4 {
			continue
		}
		return buf[:n], addr, true
	}
	return nil, 0, false
}

socket_close :: proc(s: ^Socket) {
	if s.is_open {
		net.close(s.handle)
	}
	s^ = {}
}
