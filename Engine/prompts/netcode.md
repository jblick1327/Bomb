Read AGENTS.md first; its rules apply.

BOM — netcode library (standalone; 2026-11-04)

Context: BOM is an Odin + Box2D + raylib game (see AGENTS.md). Multiplayer will be a dedicated authoritative server streaming state to up to 4 clients over UDP. This task builds ONLY the reusable transport library. It must not import or modify any game code.

SCOPE
- Add files only under src/netcode/ (package netcode) and one helper entry in scripts/bom.ps1 ("NetTest" -> odin test src/netcode with memory tracking).
- Do not edit anything else. Other work is in progress on the game code.
- Use only Odin core packages (core:net for sockets). No third-party code.

STANDING RULE: You may choose test parameters (seeds, sizes, timings) when a specified one doesn't exercise what its check means to test. Record what you chose and why in the report, and continue without stopping. Stop and ask only if a rule below cannot be implemented as written.

1. Byte codec (codec.odin)
- Writer: append to a [dynamic]u8. Reader: a slice plus offset, with a sticky `ok` flag.
- Types: u8, u16, u32, u64, i32, f32 (bit-exact via transmute), bool, varint (unsigned LEB128, up to u64), zigzag i64, bytes (varint length + data), string (varint length + UTF-8).
- All little-endian.
- A truncated or oversized read sets ok=false and returns zero. It never panics or reads out of bounds. Lengths over the remaining bytes are errors.
- Quantization helpers:
  - quantize_pos(f32) -> i32 at 1/1024 m, with dequantize;
  - quantize_angle(f32 radians) -> u16 over [0, 2π), with dequantize.

2. Packets (packet.odin)
- MAX_PACKET = 1200 bytes. Header:
  - protocol_id u32 = 0x314D4F42 ("BOM1");
  - kind u8 (0 = connect, 1 = accept, 2 = reject, 3 = data, 4 = disconnect);
  - client_salt u32 (random per connection attempt);
  - for data packets: seq u16, ack u16, ack_bits u32 (bit i set = seq ack-1-i received).
- Data packet body: zero or more messages, each [channel u8][size varint][payload].
  - Channel 0 is unreliable.
  - Channel 1 is reliable-ordered, and its payload starts with msg_id u16, frag_index u8, frag_count u8.
- Sequence comparison: seq_greater(a,b) handles wrap-around (half-range rule). Test it across 65535 -> 0.

3. Endpoint (endpoint.odin): one side of one connection, with no sockets. Pure functions of the bytes in, the bytes out and the time.
- endpoint_init(&e), endpoint_destroy(&e).
- endpoint_send_unreliable(&e, payload) -> bool. False if payload + headers > MAX_PACKET.
- endpoint_send_reliable(&e, payload). Payloads up to 255 fragments × FRAGMENT_SIZE (1000 bytes). Larger is an error (false).
- endpoint_receive(&e, packet []byte, now: f64): parses the packet, updates acks and RTT, and queues delivered messages.
- endpoint_take_messages(&e) -> [dynamic]Message{channel, data}. The caller owns the result (free helper provided).
- endpoint_write_packets(&e, now) -> [dynamic][]byte. Fills packets of at most MAX_PACKET:
  - every pending unreliable message once (dropped if it doesn't fit this round);
  - reliable fragments not yet acked, resent when unacked for max(2×RTT, 50 ms) (initial RTT 100 ms), oldest first;
  - always at least one packet per call if anything is pending, or if 100 ms have passed since the last send (keep-alive, which carries acks).
- Reliable delivery is exactly once, in msg_id order, with fragments reassembled before delivery. Receive window: 1024 messages; anything beyond it is dropped (it will be resent).
- A fragment counts as acked when any packet that carried it is acked. Track which fragments each sent seq carried (ring of 1024 entries).
- RTT: exponential smoothing (0.125) of now − send time of each newly acked seq.
- Stats: packets sent/received, bytes sent, resends, RTT.

4. Connection layer (connection.odin): server and client state machines over endpoints, still without sockets.
- Client: in state connecting, sends connect(salt) every 100 ms; on accept it becomes connected (gets client_index 0..3); on reject it fails with the reason; with no reply for 5 s it times out.
- Server: up to MAX_CLIENTS = 4, keyed by (address, salt). A new connect gets accept or reject("server full"). A duplicate connect is re-accepted idempotently. A client silent for 5 s is removed, emitting a disconnect event. A disconnect packet removes it immediately.
- Address is an opaque comparable value supplied by the caller (so tests can use fake addresses).

5. Sockets (socket.odin)
- A thin non-blocking UDP wrapper using core:net: open/bind(port), send(address, bytes), receive -> (bytes, address, ok) until empty, close.
- No game logic.

6. Link simulator (link_sim.odin, used by tests): a seeded in-memory link with latency, jitter, loss, duplication and reordering, delivering packets at simulated times.

CHECKS (odin test src/netcode, with the tracking allocator: 0 leaks, no bad frees)
a) Codec round-trips edge values (0, max, negative, NaN bits, empty and 1 KB strings). Fuzz 10,000 random byte buffers through every read: no panic or out-of-bounds read.
b) Quantization: position error ≤ 0.5/1024 m over ±1000 m; angle error ≤ π/65536.
c) Reliable: 1,000 messages of random size 1..20,000 bytes, from both sides at once, over the simulator at 20% loss, 50 ms ± 30 ms latency, 5% duplicates and 10% reordering. All are delivered exactly once, in order, byte-identical, within 60 simulated seconds. Report the overhead ratio and the resend count.
d) Unreliable: no message is delivered twice; the delivered fraction is within ±3% of 1 − loss.
e) No packet ever exceeds MAX_PACKET (asserted on every write).
f) Connections: 4 clients connect and a 5th is rejected "server full". A silent client times out at 5 s ± 0.1. Reconnecting with a new salt works. A disconnect packet frees the slot immediately.
g) Real sockets smoke: server on 127.0.0.1 (ephemeral port) and a client exchange 200 reliable messages (up to 20 KB) plus 1,000 unreliable ones within 10 s of wall time.

Deliver: write report.md into src/netcode/ (API summary, check numbers, any choices made) and save the full test output to src/netcode/test-output.txt. No zip needed — the reviewer reads the repo directly. Do not commit to git.
