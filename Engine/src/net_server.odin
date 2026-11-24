package main

import nc "netcode"
import b2 "vendor:box2d"
import "core:math"
import "core:fmt"
import "core:slice"
import "core:time"

// In-process server for step 2b. It owns the World (inside a Sandbox, so layouts and
// refills keep working), the shared structure index, one netcode server connection and
// one Net_Server_Client per player slot. Per tick:
//   receive -> apply inputs -> world_tick -> structure Delta + events (reliable)
//   -> pose frame per client (unreliable) -> write packets.








// Applies one blast request: exactly once per sequence number, in order.

// Entities of this tick: dynamic rigid piece frames, rubber cells, players, bombs.




// One server tick at simulated time `now`. Received datagrams must already have been
// fed to nc.server_receive.
