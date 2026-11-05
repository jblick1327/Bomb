Read AGENTS.md first; its rules apply. Also read docs/handoff.md and the latest report.md (step 2b follow-up).

BOM — multiplayer step 3: server process, real sockets, Host/Join (2026-11-05)

Context. Steps 2a/2b built and verified the whole protocol IN-PROCESS: Net_Server, Net_Client, pose frames, inputs, clock and replicas over the netcode endpoints and link simulator. This step puts it on real UDP and real processes and adds the UI. Protocol rules from 2a/2b are unchanged. Solo play stays exactly as it is (it draws its own World).

Don't edit src/netcode/ except to fix a bug you can reproduce with a test (report it).

STANDING RULE: You may choose or adjust fixture details yourself: coordinates, blast positions and radii, which cells to discard or which bonds to break, seeds, tick counts. Do this whenever a specified fixture does not exercise what its check is meant to test. Record what you chose and why in the report, and continue without stopping. Stop and ask only if a SYSTEM RULE (data model, failure rules, strengths, recipes, physics, snapshot format, byte-identity requirements) conflicts with the code or cannot be implemented as written.

A. Server process
- `BOM.exe --server [--port 47380] [--layout path] [--host-token T]` runs headless: no window, no raylib init. Fixed 60 Hz ticks with an accumulator (catch up at most 5 ticks, then drop time and log it). Sockets through netcode/socket.odin, Net_Server unchanged.
- On connect, Hello{GAME_PROTOCOL_VERSION, build id, host_token?}. A mismatched version or build is refused with the reason "version mismatch (server X, you Y)". The client holding the host token gets the HOST role.
- With no layout, start from the Materials preset. Logs: connects and disconnects, tick overruns, and per-client bytes/s every 10 s.
- The server exits 5 s after the host disconnects (after telling the other clients "host left").
- A disconnected player's body is removed (world_remove_player). A rejoin gets a fresh player slot and a Baseline.

B. Game client
- A Multiplayer panel (Settings or the top bar) with:
  - Host [port]: spawn the same exe with --server --port --host-token <random> and the current layout file, then connect to 127.0.0.1;
  - Join [ip:port];
  - Leave.
  It shows status (connecting / connected as player N / reason for a failure), the RTT, and the host's LAN IPv4 plus a "forward UDP <port>" hint.
- In multiplayer the game draws from Net_Client (replica plus interpolated poses), using the existing draw path, Test mode only. Each player index has a distinct capsule colour; player 0 keeps today's colour. The local player is outlined.
- Aim validity and the aim ring use the DRAWN poses (copy the interpolated poses into the replica cells each frame before testing aim). The server re-validates.
- HOST role:
  - Edit stays local. Pressing Test uploads the layout (v3 JSON, reliable). The server validates it with decode_layout, rebuilds, and starts a new epoch;
  - R/Reset, blast mode, the bomb radius and the F3 edit commands are sent as host commands. F3 S/L saves and loads a snapshot on the server.
  Non-host clients can't edit, reset, change mode or use F3 edits; those controls are hidden or disabled with a tooltip "host only".
- Leaving, or losing the connection, returns to solo Edit with the local layout intact, and shows the reason.

C. Checks
a) Two-process loopback: launch the server process and two clients. One is the GUI in a hidden-window smoke mode; one is a headless `--bot-client ip:port`, which uses the 2b bot through a real socket. Run 60 s with blasts and falling bombs. Each client periodically reports its replica's canonical hash at a revision, and the server compares: 0 mismatches. Report RTT, delay, bandwidth and late messages.
b) Version mismatch is refused with the reason. A 5th client is refused ("server full").
c) The host uploads a layout and every client gets the new epoch. A non-host's host command is rejected and logged.
d) Kill the bot client: the server removes its player within 5 s. Kill the server: the GUI returns to solo with the reason.
e) Solo: the 2a/2b capture criteria and PNGs unchanged; all tests pass.
f) A manual checklist in report.md for the user to try with a friend (port forward, firewall prompt, join by public IP), including what to report back.

Deliver: report.md at the repo root plus evidence/step3/ (no interim files). No zip. Do not commit to git.
