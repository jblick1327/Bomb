# Current native polling bridge

ABI 1.1, naturally aligned Windows x64. The canonical definition is Odin `bindings/bom-abi.json`; generated C/Odin/C# files are committed. The current interface has 13 structures and 21 exports. The additive 1.1 query exposes native actor dimensions for cosmetic fallback alignment. `bom_build_info` identifies protocol 3, canonical version 2, actual compiler, and a source-content tag. See source-lock.json for commits and DLL hashes.

All calls use the creating OS thread. Each handle has its own tracked allocator and generation. `get_stats` exposes owned/peak bytes and live allocations; destruction checks that owned bytes return to zero. Native temporary scratch and allocator bookkeeping are outside those owned-byte figures. Transport, input, event and geometry queues have explicit limits.

Result codes: 0 OK, 1 invalid handle, 2 bad argument, 3 busy, 4 wrong thread, 5 handle capacity, 6 not connected, 7 I/O or validation error, 8 queue overflow. Never continue interpreting an output after a nonzero result.

`update` uses a monotonic elapsed clock and runs at most four 60 Hz steps. Acquisition interpolates at a fractional presentation tick without advancing fixed input generation. Timestamped held-input changes and jump/action edges are queued; identical held state should not be submitted on every rendering frame. A large stall/backward clock clears queued intent and resynchronizes.

Acquired pointers last until release. Mutation, disconnect and destruction return BUSY during acquisition. Read-only layout, stats and error queries preserve the sample. The Unity wrapper copies all arrays, removes pointer fields from its managed snapshot, releases, atomically accepts geometry, then acknowledges events. An exception before acceptance leaves the batch unacknowledged.

Topology delivery is a coherent complete snapshot with a transaction ID, effective tick and accepted from/to revision. Flags identify pending full replacement and epoch reset. Its ID/data remain available until acknowledgement; release does not consume topology or events. Received epoch/revision come from a separate validated data replica and cannot make future topology visible early. Catalog fields report unavailable until M6, prediction status is disabled until M5, and round state is unavailable until M8.

Cells contain immutable outlines in native rest coordinates. Piece poses use piece reference pivots; rubber poses use cell rest centers. Native sample flags: 1 accepted compatibility handshake, 2 baseline, 4 valid presentation clock. Stats flags: 1 live socket, 2 acquired sample, 4 authenticated host, 8 at least one server blast rejection observed. The shape query returns the authoritative capsule radius/segment and bomb radius; it does not create Unity collision geometry.

Host request operations: 1 reset, 2 blast mode, 3 radius, 4 native layout bytes. Requests pass through the unchanged Odin codec and server authorization. Only one request may be outstanding. A local request ID correlates the ordered reliable response; statuses are 0 none, 1 pending, 2 accepted, 3 rejected. Copy the borrowed reason before mutation. Disconnect invalidates its result, and IDs remain increasing across reconnects of one live handle. The older `host_command` export uses this same path.

No C# networking, collision solver, movement prediction or authority is implemented. The separate Unity scene uses procedural extrusion and native entity poses. Original Unity gameplay scripts and scenes remain reference content.
