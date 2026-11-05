# netcode — standalone UDP transport library

Package `netcode` in `src/netcode/`. Odin core packages only (`core:net` in `socket.odin` alone). It imports and changes no game code. The only edit outside this folder is one `NetTest` entry in `scripts/bom.ps1`. Nothing is committed.

Run it with `scripts/bom.ps1 NetTest`. That runs `odin test src/netcode` with the tracking allocator and `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true`, so a leak or a bad free fails the run. The full output is in `test-output.txt`.

**Result: 27 tests, all pass, 0 leaks and 0 bad frees on every test.** Run time was about 4.6 s, of which about 4.3 s is the real-socket test.

## Files

| File | Contents |
|---|---|
| `codec.odin` | `Writer` (appends to a `[dynamic]u8`) and `Reader` (slice, offset, sticky `ok`). u8/u16/u32/u64/i32/f32/bool, varint (LEB128), zigzag, bytes, string, all little-endian. `quantize_pos` / `dequantize_pos`, `quantize_angle` / `dequantize_angle`. |
| `packet.odin` | `MAX_PACKET` 1200, `PROTOCOL_ID` 0x314D4F42 (bytes `BOM1`), `Packet_Kind`, `Header` read/write, `seq_greater`, and the size helpers. |
| `endpoint.odin` | `Endpoint`: reliable-ordered fragments with acks, RTT and resends, plus unreliable messages and keep-alives. No sockets. |
| `connection.odin` | `Server` (4 slots) and `Client` state machines over endpoints. `Address` is an opaque `distinct u64`. |
| `socket.odin` | Non-blocking UDP over `core:net`. IPv4 only. The only place `Address` is converted to or from a `net.Endpoint`. |
| `link_sim.odin` | Seeded in-memory link: latency, jitter, loss, duplication and reordering. |
| `*_test.odin` | The checks below. |

## API summary

```odin
// codec
writer_init / writer_destroy;  write_u8 … write_f32, write_bool, write_varint, write_zigzag, write_bytes, write_string, write_raw
reader_init(&r, data);  read_u8 … read_string  // truncated or oversized reads set r.ok = false and return zero
quantize_pos(f32) -> i32 / dequantize_pos;  quantize_angle(f32) -> u16 / dequantize_angle

// endpoint
endpoint_init(&e, salt) / endpoint_destroy(&e)
endpoint_send_unreliable(&e, payload) -> bool      // false if it can't fit one packet (max payload 1180)
endpoint_send_reliable(&e, payload) -> bool        // false above 255 * 1000 bytes
endpoint_receive(&e, packet, now) -> bool
endpoint_take_messages(&e) -> [dynamic]Message     // caller owns; messages_free(&msgs)
endpoint_write_packets(&e, now) -> [dynamic][]u8   // caller owns; packets_free(&pkts)
e.stats: packets_sent, packets_received, bytes_sent, bytes_received, resends, rtt (+ duplicates_dropped, malformed, window_drops, unreliable_dropped)

// connection
server_init / server_receive(&s, from, packet, now) / server_update(&s, now) / server_take_outgoing / server_take_events
server_send_reliable / server_send_unreliable / server_kick / server_destroy
client_init / client_connect(&c, salt, now) / client_receive / client_update / client_take_outgoing
client_send_reliable / client_send_unreliable / client_take_messages / client_disconnect / client_destroy
random_salt()

// socket
socket_open(&s, port, ip) / socket_port / socket_send(&s, addr, data) / socket_receive(&s, buf) -> (data, from, ok) / socket_close
```

## Check numbers

**(a) Codec.**
- Round-trips cover 0, max, negative values, NaN with payload, signalling NaN, ±Inf, −0, denormals, empty and 1 KB strings, and every varint boundary.
- Every strict prefix of a valid buffer fails cleanly.
- Oversized lengths, 11-byte varints, 64-bit overflow and a bool byte of 2 are all errors.
- Fuzz: 10,000 random buffers through every read proc (13 kinds, plus a random 24-read run per buffer). There was no panic and no out-of-bounds read; position stays within bounds and `ok` never recovers once false.
- Extra: 10,000 random and bit-flipped datagrams into `endpoint_receive`, `server_receive` and `client_receive`: no panic.

**(b) Quantization.**
- Position, 1,000,000 samples over ±1000 m plus edge values: worst error 0.000488 m, exactly the 0.5/1024 limit, which is reached at ties.
- Angle, 1,100,000 samples including negatives and values beyond 2π: worst error 4.816e-5 rad against π/65536 = 4.794e-5. The 2e-7 overshoot is f32 rounding of the dequantized output, so the test allows 1e-6 of slack (see choices).

**(c) Reliable stress.** 1,000 messages each way, sizes 1..20,000 bytes, simultaneous.
- Link: 50 ms ± 30 ms latency, 20% loss, 5% duplicates, 10% reordering (extra delay up to 100 ms).
- All 2,000 messages were delivered exactly once, in order and byte-identical. After completion 250 more ticks delivered nothing extra.
- Completed in **33.94 simulated seconds** (limit 60).
- Payload was 19,686,209 bytes (9.6 KB average).
- Wire bytes sent were 26,290,840 in 26,582 packets, so the **overhead ratio is 1.335** (wire bytes ÷ payload bytes, counting headers, resends, acks and keep-alives, both directions).
- **Fragment resends: 6,260** (a 3,103, b 3,157).
- The links dropped about 20% of packets (2,680 and 2,712) and duplicated about 4% (558 and 538). The receivers rejected exactly those duplicates.
- Final RTT estimates were 199 ms and 171 ms, against a true round trip of about 100 ms plus the 20 ms tick on each side.
- Extra: 3,000 small messages (more than the 1,024 window) over the same link, delivered in order in 2.28 s with 0 window drops.

**(d) Unreliable.** 20,000 messages, 2 per tick, over the same link.
- 15,996 were delivered (**79.98%**; expected 80% ± 3).
- 0 duplicate deliveries, though the link duplicated about 4% of packets.

**(e) Packet size.**
- `finish_packet` asserts `len ≤ MAX_PACKET` on every write, and the test harness asserts it again on every packet.
- A randomised mix of unreliable messages from 0 to 1180 bytes and reliable messages of 0, 1, 999, 1000, 1001 and 2500 bytes produced 5,417 packets, the largest exactly 1200.
- 1180 bytes is accepted and 1181 is refused.
- 255 × 1000 bytes is accepted and one byte more is refused.

**(f) Connections.**
- 4 clients connect with distinct indices, and a 5th gets `reject("server full")`.
- A silent client was removed **5.000 s** after the server last heard from it (limit 5.0 ± 0.1), with a `Timeout` event.
- A connecting client with no reply times out at 5.00 s, and sends a connect about every 100 ms (20 in 2 s).
- A duplicate connect is re-accepted (5 duplicates produced 5 accepts, 1 slot, 1 Connected event).
- Reconnecting with a new salt from the same address while the server is full works. The old entry is replaced, and the stale salt is ignored afterwards.
- A disconnect packet frees the slot in the same call, and the slot is immediately reusable.
- Kick notifies the client.

**(g) Real sockets (127.0.0.1, ephemeral ports).**
- Each direction sent 200 reliable messages (1..20,000 bytes) and 1,000 unreliable ones.
- Everything was delivered in **4.33 s wall time** (limit 10): reliable in order and byte-identical, unreliable 1000/1000 each way, 0 duplicates, 0 resends.
- The wall time is mostly pacing, not throughput. The test sends 10 unreliable messages per loop and sleeps 1 ms, which Windows rounds up to a coarse tick.

## Choices and deviations (please read)

- **Packet budget per write is 8** (`e.max_packets_per_write`). The spec doesn't say how many packets one call may emit, and it needs a limit for "dropped if it doesn't fit this round". I first used 16, which finished faster (23 s) but ran at overhead 1.82 with 16,079 resends. At 16 packets per tick the sender outruns the 32-packet `ack_bits` window, so received packets go unacknowledged and get resent. At 8 the overhead is 1.335, near the 1.25 floor that 20% loss implies. At 5 it takes 51.9 s, too close to the 60 s limit. Unreliable messages beyond the budget are dropped, and each drop is counted in `unreliable_dropped`.
- **"Anything pending" includes owed acks.** An ack-only packet goes out whenever messages arrived since the last send, as well as the 100 ms keep-alive. Without it, a one-way flow gets acks at 10 Hz and only the last 33 packets are covered, so most data is resent. Packets carrying no messages don't trigger an ack, so two idle sides don't ping-pong.
- **Packet sequence starts at 1, not 0.** A peer that has received nothing sends `ack = 0, ack_bits = 0`, which would acknowledge our seq 0. Starting at 1 means that false ack matches no sent packet. After a 65536-packet wrap seq 0 is used normally.
- **Duplicates are dropped at packet level.** A 1024-entry ring of received sequence numbers drops duplicate or too-old packets. This is what keeps duplicates from reaching unreliable delivery.
- **Receive window and acks.** Acks are per packet, not per fragment, as specified, so a fragment outside the window that is dropped still has its packet acked and would not be resent. The sender therefore never sends a message more than 1024 places beyond its oldest unfinished one, and the receiver's window is always at or ahead of that point. The "dropped, it will be resent" case can only arise from a non-conforming peer. It is counted in `window_drops` and tested.
- **Reconnect policy.** The server is keyed by (address, salt), but a connect from an address that already holds a slot with a different salt replaces that slot (disconnect reason `Replaced`, then a new Connected event). Otherwise a client reconnecting to a full server would be refused while its own dead session still held a slot.
- **Client silence.** A client in the connected state that hears nothing from the server for 5 s moves to `Timed_Out`. The spec only gave the connecting case.
- **Timer comparisons** subtract 1e-9 (`TIME_EPSILON`) so accumulated float time doesn't make a 100 ms interval fire a tick late. Without it a connect or keep-alive interval was missed in tests.
- **Strict decoding.** A bool byte other than 0 or 1 is an error. Non-minimal varints are accepted, but not more than 10 bytes or a 10th byte above 1.
- **Quantization.** `quantize_pos` computes in f64, so the scaling is exact and the error is exactly half a step at worst. NaN maps to 0 and out-of-range values saturate. The angle test allows 1e-6 over π/65536 for the f32 rounding of the dequantized value.
- **Caps.** Up to 1024 unreliable messages can be queued between writes, and `endpoint_send_unreliable` returns false beyond that. A hostile peer could make the receiver buffer up to 1024 incomplete messages of 255 fragments each, which is a memory risk. I did not cap it.
- **Link simulator.** Loss is decided per packet. A duplicate is a second copy of a surviving packet with its own jitter. Reordering adds extra delay to a random 10% of packets, on top of jitter.
- **Test parameters I chose.** Seeds are fixed in each test. The stress test uses a 20 ms tick, and the window test uses 3,000 messages. The unreliable test uses 20,000 messages sent 2 per tick, because the tolerance of ±3% would otherwise be noisy. The socket test requires at least 95% of unreliable messages (loopback gave 100%), paces 10 per loop, and runs both directions.
- **Addresses.** `Address` is a `u64` packing IPv4 and port. IPv6 senders are ignored by `socket_receive`.
- **Bug caught by the tests.** An early `sed` edit made `write_f32` convert values instead of copying their bits. The round-trip test failed and I restored the `transmute`.
