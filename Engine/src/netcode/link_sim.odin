package netcode

import "core:math/rand"
import "core:slice"

// A seeded in-memory one-way link for tests: packets sent into it come out
// later (or never, or twice, or out of order) at simulated times. Time is
// whatever the caller passes in; nothing here reads a clock.

Link_Config :: struct {
	latency:       f64, // seconds, mean one-way delay
	jitter:        f64, // seconds, uniform +/- added to every packet
	loss:          f64, // probability a packet is dropped
	duplicate:     f64, // probability a surviving packet is delivered twice
	reorder:       f64, // probability a packet gets extra delay (so later ones overtake it)
	reorder_delay: f64, // seconds, the extra delay is uniform in (0, reorder_delay]
}

Link_Stats :: struct {
	sent:       u64,
	dropped:    u64,
	duplicated: u64,
	reordered:  u64,
	delivered:  u64,
	bytes_sent: u64,
}

@(private)
Link_Packet :: struct {
	deliver_at: f64,
	order:      u64,
	data:       []u8,
}

Link :: struct {
	cfg:     Link_Config,
	stats:   Link_Stats,
	state:   rand.Default_Random_State,
	pending: [dynamic]Link_Packet,
	counter: u64,
}

link_init :: proc(l: ^Link, cfg: Link_Config, seed: u64) {
	l^ = {}
	l.cfg = cfg
	l.state = rand.create(seed)
	l.pending = make([dynamic]Link_Packet)
}

link_destroy :: proc(l: ^Link) {
	for p in l.pending {
		delete(p.data)
	}
	delete(l.pending)
	l^ = {}
}

@(private)
link_rand :: proc(l: ^Link) -> f64 {
	return rand.float64(rand.default_random_generator(&l.state))
}

// Copies the packet into the link at time `now`.
link_send :: proc(l: ^Link, data: []u8, now: f64) {
	l.stats.sent += 1
	l.stats.bytes_sent += u64(len(data))
	if link_rand(l) < l.cfg.loss {
		l.stats.dropped += 1
		return
	}
	copies := 1
	if link_rand(l) < l.cfg.duplicate {
		copies = 2
		l.stats.duplicated += 1
	}
	for _ in 0 ..< copies {
		delay := l.cfg.latency + (link_rand(l) * 2 - 1) * l.cfg.jitter
		if link_rand(l) < l.cfg.reorder {
			delay += link_rand(l) * l.cfg.reorder_delay
			l.stats.reordered += 1
		}
		delay = max(delay, 0)
		l.counter += 1
		append(&l.pending, Link_Packet{deliver_at = now + delay, order = l.counter, data = slice.clone(data)})
	}
}

// Everything due by `now`, in delivery-time order. The caller owns the packets
// (packets_free).
link_receive :: proc(l: ^Link, now: f64) -> [dynamic][]u8 {
	out := make([dynamic][]u8)
	due := make([dynamic]Link_Packet)
	defer delete(due)
	i := 0
	for i < len(l.pending) {
		if l.pending[i].deliver_at <= now {
			append(&due, l.pending[i])
			unordered_remove(&l.pending, i)
		} else {
			i += 1
		}
	}
	slice.sort_by(due[:], proc(a, b: Link_Packet) -> bool {
		if a.deliver_at != b.deliver_at {
			return a.deliver_at < b.deliver_at
		}
		return a.order < b.order
	})
	for p in due {
		append(&out, p.data)
		l.stats.delivered += 1
	}
	return out
}

link_pending :: proc(l: ^Link) -> int {
	return len(l.pending)
}
