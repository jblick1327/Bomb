# Native elimination rules (M8 checkpoint)

Protocol 6 / ABI 1.4 / canonical topology 3. M7 remains frozen separately at
protocol 5 / ABI 1.3. These clients and servers must not be mixed.

Odin owns a two-participant elimination controller, separate from sandbox.
Two matching, natively validated baselines start a 180-server-tick countdown.
An interrupted countdown returns to Waiting. Gameplay runs only in Playing;
Waiting, Countdown and Finished retain network/server ticks while freezing the
physics world. A host restart publishes a fully rebuilt world before advancing
the round ID. The existing five-second host-left shutdown stays in place.

Each native detonation tests the player capsule at its current server pose,
using the independent 2.2-unit lethal radius. Deaths from every explosion and
bounds check on the tick are accumulated before combining disconnect forfeits
and choosing a winner or draw. Sandbox retains its original respawn and tools.
Manual blast and layout-upload requests are rejected in elimination.

Round state, participant session IDs/generations, survival ticks, bombs faced,
result XP, winner/draw/reason, session totals, wins, level progress and restart
permission are persistent snapshot data. XP is `10 * bombs_faced + alive_ticks/60`
using integer division and saturating counters. A round/session award is applied
once. The first level requires 100 XP; each subsequent level adds 50 to the cost.

Session identities are server-local. A 128-bit random secret, scoped to a random
server instance, permits a native handle to resume its in-memory totals. It does
not preserve its connection generation or resurrect a participant. Midround
joins/resumes spectate until a later round. One session cannot use two active
connections. The bounded 128-session table rejects further new admissions when
full; a local server restart starts a new session. Credentials are not logged or
passed to Unity. There is no account persistence or authentication service.

Only Odin implements the application codec. Welcome/Hello exchange native resume
credentials and explicit spectator intent. Native Ready confirms a validated
canonical baseline. The reliable round snapshot is sent on state changes and
once per second. Duplicate or older snapshots do not award XP in the frontend.

ABI additions are separate structs/getters, preserving existing struct strides.
`bom_client_get_round` requires an acquired sample and matching sample sequence;
its two participant rows and four connection rows are borrowed until release.
`BomSession` copies them before releasing and clears all pointers. Join flags
are set before connecting. C ABI host operation 5 selects game mode; operation 4
continues to upload layouts. The native wire host operation for game mode is 4.

Executed evidence: 220 original game tests, 74 shared tests, 19 ABI tests, C/.NET
23-layout lifecycle checks, and a real UDP diagnostic with four native handles,
two rounds, interrupted countdown, late spectator, forfeit, rejected commands,
and reconnecting to results. See M8 evidence for exact build identities. A first
failed diagnostic sent an action before input-schedule readiness; the corrected
driver waits for a fresh native owner/schedule and verifies the server's durable
rejection result.

The standalone menu derives a scene from the network yard and uses the original
HUD UXML/USS and a derived Claymate/animation prefab. Original assets are not
edited. Final two-Unity yard and simultaneous-draw runs, Odin observer agreement, repeated event presentation, native movement/jump animation and rendered menu/game/disconnect captures passed. See evidence/M8/summary.json. M9 hardening/performance/IL2CPP/soak remains required.

Player admission reserves the first two eligible connected player slots, then waits for both validated baselines. Extra ready connections cannot replace an occupied slot while it loads. Real-network sandbox manual blasts are host diagnostics; offline sandbox physics/input fixtures retain their original behavior.
