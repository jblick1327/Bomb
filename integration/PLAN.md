# BOM: Autonomous Odin–Unity Integration Plan

**Final handoff · 2026-11-05 · Revision 3.0**  
**Purpose:** give an implementation agent enough decisions, contracts, tests, and recovery instructions to work for extended sessions without routine owner intervention.  
**Authority:** this document replaces `BOM_ODIN_UNITY_INTEGRATION_SPEC.md`, `BOM Hybrid Spec v2 Odin Core + Unity Client.md`, and their review comments where they conflict. Earlier documents are background, not additional acceptance gates.  
**Verification of this plan:** the two named source archives and v2 were inspected. The projects were **not compiled or run** while preparing this document. Baseline behavior, build availability, timings, and compatibility remain to be demonstrated by the implementing agent.

## 0. Start here

Give the agent this file and access to the Odin and Unity projects. Run it in a **Windows x64 development environment** with Unity **6000.2.14f1**, the project's Odin compiler and native dependencies, and a compatible .NET SDK. Repository history is preferable; the source archives are acceptable if history is unavailable. Do not change the architecture simply because the execution environment lacks one of these tools.

### Copyable agent instruction

> Read `BOM_AUTONOMOUS_INTEGRATION_PLAN.md` in full and execute it. Locate the two project roots, read applicable repository instructions, create an isolated integration branch or worktree, and begin M0. Continue automatically through each passing milestone; do not stop for phase approval or return only a plan. Odin owns all gameplay. Both clients use one headless Odin client implementation; Unity accesses it through a versioned C ABI and never implements the wire protocol. Preserve the existing Unity assets, GUIDs, prefabs, scenes, and placeholder source as reference material. Make the first live Unity slice work before implementing prediction. Use the defaults and fallback policies in this document, keep evidence and resumable progress in `integration/`, and fix failures within scope. Do not mark unrun tests as passing or substitute mocked networking for a real integration gate. Continue until the full definition of done is met, or an external blocker prevents all remaining useful work. If blocked, leave a buildable checkpoint where possible and report the exact missing prerequisite, attempted remedies, evidence, and next command.

### What successful execution produces

One integrated development workflow with:

1. An Odin dedicated server running the authoritative 60 Hz world, Box2D, destruction, bombs, players, and selectable game rules.
2. A Windows Unity client that uses the shared native Odin client core for connection, replication, clocks, interpolation, and local movement prediction.
3. A preserved Odin development client using that same client package as a reference frontend.
4. Unity-authored level export, stable source identity on every destruction cell, a runtime visual registry, and 2.5D fragment rendering.
5. Existing Unity art, camera, animation, menus, HUD, effects, and sound connected to read-only network state and input requests.
6. Reproducible scripts, tests, evidence, and packaged local builds that someone else can launch without reconstructing the agent's session.

A DLL that loads, an extrusion demo, or a structural hash match alone is **not completion**. They are intermediate gates. This is a substantial integration project; there is no promise it fits in one agent context or a particular number of hours.

## 1. Decisions the agent must use

### 1.1 Settled decisions carried forward from v2

| Topic | Decision |
| --- | --- |
| Gameplay authority | Odin alone: physics, topology, damage, players, bombs, identities, rules, deaths, and resets |
| Client architecture | Native headless Odin client core with a narrow C ABI; shared by Unity and the Odin development frontend |
| Network | Existing custom UDP transport and reliability; one source implementation of wire encoding/decoding in Odin |
| Initial platform | Windows x64 server, Unity Editor, and Windows standalone client |
| Unity version | 6000.2.14f1; retain the supplied URP and UI Toolkit setup |
| Physics plane | XY translation; physical rigid rotation about Z only; visual depth is preserved |
| Prediction | Local-player movement in scope; server always wins; no whole-world prediction |
| Existing Unity destruction | Retired from networked gameplay; no crater/mesh-carving/Unity-collider authority |
| Asset protection | Keep existing asset bytes, GUIDs, prefabs, and scenes; add network variants |
| WebGL | Out of scope; leave existing WebGL artifacts alone |

### 1.2 Defaults resolved by this plan

These are deliberate implementation defaults, not claims that the owner previously specified every detail. Use them without pausing. A later explicit owner instruction can change them.

| Choice | Required default |
| --- | --- |
| Shipped level authoring | Unity exports `bom-layout`; Odin editor remains an experimental/diagnostic authoring tool |
| Tuning | Versioned Odin server configuration, loaded at startup and identified by a gameplay-config hash |
| Native loading | Ordinary C ABI imports first; restart Unity after replacing a loaded DLL. Custom hot reload is deferred |
| Runtime asset lookup | Bundled ScriptableObject registry with direct mesh/material references; no Addressables dependency |
| Geometry pipeline | Extrusion always available; purpose-built prism clipping for supported static triangle meshes, with explicit validation and bounded fallback |
| Mesh acceleration | Use existing packages and Unity mesh APIs. Add no new package merely to obtain Burst or a boolean library |
| Footprints | Author explicit validated 2D proxies first. Add simple concave polygons by deterministic decomposition; holes/islands use explicit compound proxy parts |
| Intact 3D art | Use the original visual group only while its whole live source region follows one compatible rigid transform |
| Match modes | Preserve Odin sandbox; add two-player elimination with the exact policies in section 10 |
| Default integration launch | Sandbox for diagnostics; elimination selectable from the network menu/launch configuration |
| Local co-op | One controlled player per connection; two local standalone processes are valid tests |
| Late join in elimination | Spectator until the next round; ordinary late join remains available in sandbox |
| Old scripts/scenes | Keep them indefinitely as references. Their deletion is not required for completion |
| Delivery | Local developer builds and tests. No public hosting, matchmaking, account system, or production deployment |

### 1.3 Out of scope

Do not add Unity Netcode for GameObjects, a managed protocol port, a sidecar as the shipped client, 3D gameplay physics, client-authored destruction, full rollback of the destruction world, arbitrary runtime CSG for every possible asset type, skinned-mesh fracture, console/mobile/macOS/Linux packaging, account persistence, or gameplay redesign. Do not upgrade Unity, Odin, Box2D, or packages to make the integration easier without a demonstrated compatibility requirement and a recorded decision.

## 2. Source baseline and actual code findings

### 2.1 Inputs inspected for this plan

| Input | Identifying information |
| --- | --- |
| Current Odin source | `src(3).zip`; root `src/`; 57 Odin files |
| Odin archive SHA-256 | `42e6a5d750f868f4e36162d9c9abccdb6652296aa5067c4d6c7fdf6bb9b84fc1` |
| Unity source | `Bomb-PrototypeV0.4.zip`; root `Bomb-PrototypeV0.4/` |
| Unity archive SHA-256 | `838d890b1034bb096e248db3f459565d1f88b5c3cf908c3e713fc01f2de73dda` |
| Unity Editor | `6000.2.14f1 (589824c1fc31)` in `ProjectSettings/ProjectVersion.txt` |
| Unity art baseline | 329 `.meta` files under `Assets/` in the supplied archive |
| Existing package examples | URP 17.2.0, Input System 1.16.0, Test Framework 1.6.0 |
| Previous plan | `BOM Hybrid Spec v2 Odin Core + Unity Client.md`, 38,495 bytes |

`BOM (3).zip` is an older, different archive. Do not silently use it as the November 5 networking baseline. If the live repositories are newer than these archives, use the live repositories, record their commits and a concise difference report, and re-resolve changed symbols during M0. These fingerprints identify the audit, not a requirement to downgrade current work.

### 2.2 Facts that affect implementation

| Source | Observed behavior | Required consequence |
| --- | --- | --- |
| `net_client.odin` | `Net_Client` contains `Render_Cache_State`, `Bomb_Burst`, `Bot`, and `Sandbox_Settings` references | Map dependencies and split domain/presentation responsibilities; removing raylib imports is insufficient |
| `net_client_step` / clock code | Each invocation advances the clock approximately one tick and produces one input | Preserve that fixed-step behavior during mechanical extraction, then introduce a separately tested elapsed-time adapter |
| `physics.odin` | Legacy anchoring is inferred from a live edge on `anchor_y` | New authored fixed/anchored policies must be real physics data, not an exporter label |
| `Subdivision` / `Repl_Cell` | No durable source-asset identity in the inspected baseline | Add cell-level provenance throughout constructors, refinement, persistence, canonical replication, and hashes |
| `player.odin` | Movement reads contact support; mutable state includes velocity, grounded, coyote, buffered jump, and support velocity | Reconciliation must restore all behavior-relevant state; position-only correction is insufficient |
| `player_after_step` | Out-of-bounds automatically respawns using fixed arena constants | Factor detection from the sandbox/round policy before adding elimination |
| `net_frame.odin` | Entity keys distinguish rigid piece, rubber cell, player, and bomb | Preserve entity kind; a rubber cell does not use its rigid owner's pose |
| `net_real.odin` | Server binds to `127.0.0.1`; host-left shutdown is a deliberate session behavior | Keep loopback default; add explicit bind configuration for LAN tests; retain host authorization |
| `layout_state.odin` | Layout versions 1–3, exact integer identities, rect/wedge authored shapes, seed range 0–255 | Extend the existing contract; keep old loaders and exact integers working |
| Unity `ArenaSession` | Local two-player round, first detected death wins, local restart | Replace with server rules; resolve simultaneous deaths as a draw rather than array iteration order |
| Unity `ArenaHudDocument` | Directly depends on `ArenaSession` and computes result XP | Create a network presenter reusing UXML/USS; server supplies authoritative results |
| Unity `BombBlastVisual` | Presentation-only ring animation | Reuse the visual independently of `BombDropper` |

Baseline version values are transport `BOM1`, game protocol 3, build ID `BOM-menus-2026-11-05`, canonical structure version 2, 1/256 position grid, 4096 angle steps, 1200-byte transport packets, 1000-byte reliability fragments, and at most 255 fragments per reliable message. The pose-frame budget is presently 2 × 1150 bytes per tick. These are source observations, not permission to change limits without tests.

## 3. Autonomous execution rules

### 3.1 Scope of work and boundaries

The owner is asking for implementation of this plan. The implementation agent should create integration code, build scripts, test fixtures, new scenes/prefabs/registries, local test processes, and local builds without seeking routine approval. It may make reversible code changes and local commits on its integration branch. It must not overwrite unrelated work, force-push, merge into protected branches, publish externally, delete original content, buy/install paid dependencies, or request credentials as a substitute for a missing environment.

Read applicable `AGENTS.md` and repository instructions first. If they impose an actual conflicting approval or execution requirement, report the conflict accurately; this file cannot override a higher-priority execution policy. Ordinary design choices already resolved here are not reasons to ask again.

If there are two repositories, retain them and put orchestration beside them or in the designated integration repository. Record coordinated commits in both. A monorepo conversion is not part of this job. If only archives are available, initialize an isolated local repository from the supplied files and record that no upstream history was supplied.

### 3.2 Files to maintain throughout execution

Create these under an `integration/` directory in the integration checkout. Paths below are **deliverables to implement**, not scripts already present in the source.

| Path | Contents |
| --- | --- |
| `integration/README.md` | Prerequisites, exact build/launch/test commands, network controls, known limits |
| `integration/source-lock.json` | Repository roots/commits or archive hashes; compiler/dependency versions; Unity version; DLL build hash |
| `integration/STATUS.md` | Current milestone, last good commits, actual passing commands, outstanding failures, immediate next task |
| `integration/tasks.json` | Ordered task IDs, dependencies, status, required evidence, and blocking reasons |
| `integration/DECISIONS.md` | Deviations, evidence, chosen remedy, compatibility impact; no silent architecture changes |
| `integration/contracts/` | C header, ABI ownership rules, protocol extensions, coordinate/level schemas, test vectors |
| `integration/baselines/` | Original semantic outputs, GUID/content manifests, deterministic fixtures |
| `integration/evidence/M*/` | Command logs, structured results, timings, captures, and per-milestone summary |
| `integration/tools/` | PowerShell build/test/orchestration scripts and fixture helpers |

`tasks.json` must distinguish `pending`, `in_progress`, `passed`, `failed`, `blocked_external`, and `deferred_optional`. Never turn an unexecuted test into a pass. List the command and exit code with each evidence entry. Use repository-relative paths in generated documentation; keep machine-specific executable paths in a local ignored configuration.

### 3.3 Work loop and recovery

1. Read `STATUS.md`, the current diff, and the next task before resuming after a context reset. Do not redo completed milestones solely because the conversation was compacted.
2. Work on the earliest unpassed required gate. Break it into small compiling changes and focused tests.
3. On failure, reproduce it, narrow it, fix it, and rerun the affected gate. Do not weaken an acceptance test to match a broken implementation.
4. After a gate passes, checkpoint the code and evidence, update status, and **start the next milestone automatically**. A checkpoint is not a request for review.
5. Give periodic concise progress updates during a live session, without stopping useful work.
6. If an approach stops producing evidence, change approach. After roughly 45 minutes on the same external blocker without new information, record attempts and continue independent, authorized work that does not require pretending the gate passed.
7. Stop only when the definition of done is satisfied, the execution budget genuinely ends, a controlling instruction requires it, or an external prerequisite blocks all remaining safe work. Leave exact next steps.

Examples of real external blockers: missing project files, no working/licensed Unity installation, unavailable native dependencies that cannot be obtained in the approved environment, a locked file owned by another user process that cannot be safely restarted, or a repository policy that expressly requires unavailable approval. A difficult refactor, failed test, unspecified cosmetic color, or missing optional Burst package is not an external blocker.

Run long tests as monitored background processes where possible. Set timeouts and reap child processes started by the test runner. Never kill an unrelated Unity Editor or server process to free a port or replace a DLL. Use a dedicated project worktree and a fresh port instead.

## 4. Runtime architecture and ownership

### 4.1 Ownership table

| Concern | Odin server | Shared Odin client | Unity |
| --- | --- | --- | --- |
| Damage, fracture, bonds, glue, cell membership | Computes truth | Replicates immutable topology | Builds visual geometry |
| Gameplay collision, mass, motion policy | Computes truth | Builds limited prediction proxies | Never uses Unity collision to decide outcomes |
| Local player | Simulates and finalizes input | Predicts/reconciles | Samples input; renders predicted pose |
| Remote players, bombs, fragments | Simulates | Interpolates at presentation time | Applies transforms and animation |
| Blast requests | Validates and executes | Numbers/sends/retries requests | Aim feedback and presentation only |
| Round/death/XP/host restart | Computes and authorizes | Replicates state/events | Displays state and sends intent |
| Asset geometry/materials | Knows identity/config, no render triangles | Exposes binding catalog | Owns asset registry, meshes, lighting, effects |
| Network bytes | Odin transport/application codec | Same Odin transport/application codec | No encoding/decoding of UDP messages |

The server and both frontends must depend on the same shared gameplay definitions and native client source. A passing implementation must not hide a second codec inside a C# helper, a Unity RPC layer, or a diagnostic sidecar.

### 4.2 Extraction boundaries

M0 must produce a file/symbol dependency map. Organize the smallest acyclic package structure that enforces these conceptual layers:

- **Domain:** IDs, vector/polygon data, material definitions, configuration, structural and pose records. No rendering.
- **Simulation:** Box2D, destruction, shape construction, player movement, bomb behavior, world tick. Imports domain, never Unity/raylib.
- **Transport/application replication:** sockets, reliability, codecs, handshake, snapshots/deltas, frame assembly. No renderer or editor state.
- **Client:** received world state, clocks, interpolation, input scheduling, reconciliation, journals. Uses simulation helpers only for the limited prediction world.
- **Frontends:** raylib rendering/editor/UI and Unity C# presentation/input. They consume shared state and cannot become dependencies of the core.
- **C export adapter:** small library entry package wrapping the client package.

The directory names and number of packages are implementation choices. One initial headless package is acceptable if it enforces the dependency direction and avoids duplicate logic. Do not overengineer package granularity or move the whole project in one untestable edit. Odin `package main` cannot be the imported shared core.

Extract `Sandbox_Settings` into shared configuration, split `Bomb_Burst` events from their visual aging/drawing, move render caches into frontend state, and make bots a caller/input source. Keep the Odin editor frontend working. The dedicated server eventually builds without raylib/window initialization; the shared DLL must have no raylib imports or linked dependency.

### 4.3 Prevent Unity authority from reappearing

Network scene validation recursively examines active/inactive objects, nested prefabs, runtime spawns, and startup callbacks. Reject `ArenaPlayerController`, `ArenaSession`, `BombDropper`, `FallingBomb`, `GroundRubble`, `DestructibleObject`, `DestructibleGround`, `DestructibleMultiMesh`, and `ArenaGameplayGround` in network gameplay hierarchies. These scripts remain in legacy scenes only. New input/view code may reproduce their presentation behavior without calling their gameplay paths.

No Unity `CharacterController`, 2D/3D `Rigidbody`, or collider participates in gameplay. Pure camera/picking colliders, if needed, use a dedicated visual-query layer and an explicit mask; audit references so they cannot drive damage or movement. Prefer mesh-free plane intersection for aim. New animators must not apply root motion to authoritative pose transforms; animate a visual child. Visual debris is cosmetic and cannot send gameplay events.

## 5. C ABI contract

### 5.1 First prove the boundary, then expose the client

Before the large extraction, compile a tiny Odin DLL with version, create, destroy, and layout-query exports. Load it from a .NET console test on Windows. This proves export names, calling convention, context initialization, architecture, and native dependency resolution. Then replace its dummy handle internals with the actual shared client. A dummy-library smoke test never counts as the real network gate.

### 5.2 Required interface responsibilities

Commit a C header and C# bindings from one canonical definition. Exact names may follow repository convention, but the following operations and semantics are mandatory:

| Operation | Contract |
| --- | --- |
| `bom_abi_version`, `bom_build_info` | ABI major/minor, native source/build hash, compiler identifier, protocol/build/config compatibility identifiers |
| `bom_client_create`, `destroy` | Opaque generation-checked handle; per-handle allocator/context and bounded owned memory |
| `connect`, `disconnect` | Explicit numeric endpoint/port and optional host token; no blocking DNS or socket waits on Unity main thread |
| `set_held_input` | Timestamped clamped movement samples; repeated calls do not advance the simulation |
| `enqueue_jump`, `enqueue_action` | Timestamped numbered edge/action requests with queue-overflow result; never overwrite a press before consumption |
| `update(now_monotonic_seconds)` | Nonblocking pump and bounded fixed-tick work; independent of renderer FPS |
| `acquire_sample`, `release_sample` | One immutable coherent presentation sample; borrowed views are valid only during this acquisition |
| `ack_sample` | Acknowledge the copied/accepted journal batch; unacknowledged structural transactions are not silently lost |
| `request_host_command` | Host-only requests through the existing Odin authorization path, with result ID/status |
| `get_stats`, `last_error`, `debug_struct_layout` | Readable diagnostics, all ABI sizes/offsets, queue/memory/clock counters |

`BomSample` contains session status, local identity, connection generation, epoch, received revision, presented revision, sample sequence, fractional presentation tick, catalog revision/hash, due structural transactions, entity poses, tick-gated events, owner prediction status, and round state. Include canonical material parameters needed for a fallback appearance. Do not expose a mutable `Scene` or require C# to interpret private Odin data structures.

Structural transactions carry `effective_tick`, `epoch`, `from_revision`, `to_revision`, added/replaced/removed cells, membership/reference changes, and resolved motion flags. Cells expose full IDs, source identity, source part, material key, immutable rest outline, rest center, and the pose mode. Include a reset/full-state transaction on initial connection, epoch change, journal overflow, or explicit resynchronization. Transactions must be atomic from the presenter's point of view.

### 5.3 Layout, memory, and lifecycle rules

- Use C calling convention and fixed-width scalars. Use `uint32_t` flags/booleans, `uint64_t` IDs/ticks, `double` clocks, `float` geometry, pointer-plus-count UTF-8/array views, and explicit reserved fields. No Odin string/slice/map, C++ object, C# bool, managed reference, or platform-sized `int` crosses the ABI.
- Use documented natural x64 alignment, not blanket packing to one byte. Verify `sizeof`, alignment, and every field offset in Odin, C, .NET, Unity Mono, and an IL2CPP player.
- Struct inputs carry `struct_size` and version. Reject smaller/incompatible inputs, bad counts, nonfinite values, and invalid handles. Copy caller strings/data needed after the call.
- `create` initializes an explicit Odin runtime context before allocation. Other exports validate the handle and establish its stored allocator/context. A missing/invalid handle must not be dereferenced in order to obtain context.
- All API calls run on the designated main/owner thread, including when it services multiple handles; concurrent cross-handle calls are unsupported in the first implementation. No callbacks into managed code. No core background thread. Multiple handles have isolated state and are tested.
- `acquire_sample` freezes that sample. No update/connect/disconnect/destroy is allowed while it is acquired; return `BUSY` rather than invalidate pointers. Read-only layout/stats calls must not invalidate it. Release on every exit path.
- C# copies persistent arrays into reusable managed/native buffers before release. Mesh tasks receive only copied buffers and immutable keys. No job retains a native core pointer.
- The wrapper accepts a sample atomically and acknowledges its journal only after ownership of all required data is safely transferred to the presenter. Acquisition/release alone does not consume events. Repeated samples are idempotent by transaction/event ID.
- Journals/queues have finite caps. On structural overflow request a fresh native presentation snapshot; on reliable receive overflow fail/resync explicitly. Never silently drop a topology delta and keep rendering a plausible world.
- On disconnect/reset/destroy clear predictions, one-shot input, actions, events, poses, catalogs, and generation-scoped lookup state. Old handles return an error. Managed disposal is deterministic; a finalizer is only a backup and cannot replace main-thread cleanup.
- Validate network-driven inputs before Box2D or unsafe access. Return typed errors for malformed data and controlled failures. Do not claim C# can recover an arbitrary native access violation or panic; fix the unsafe path. Keep useful internal diagnostics rather than disabling assertions indiscriminately.

### 5.4 Packaging and Editor behavior

Use `bomcore.dll` under a new Windows x64 plugin directory with explicit Editor/standalone importer settings. Build scripts record native binary hash, source commit, ABI/protocol versions, dependent DLLs, and matching C# binding version. Display this identity in a development diagnostics panel so testing cannot accidentally use yesterday's loaded DLL.

Default workflow: stop the dedicated test Editor, rebuild/copy the DLL, and relaunch that Editor. A loaded native plugin cannot be replaced reliably through an ordinary managed domain reload. Do not spend the initial integration on `LoadLibrary` hot reload. Support play-stop-play, script reload, scene change, application quit, and disabled domain reload by disposing/resetting native sessions correctly. Do not assume managed statics are fresh when domain reload is disabled.

Both Windows Mono and IL2CPP standalone builds must load and exercise the same ABI. The .NET smoke runner and Unity use the same binding source. A minimal C caller checks the header independently of managed marshalling.

## 6. Time, replication, and presentation contract

### 6.1 Three clocks, with named meanings

| Clock | Meaning and ownership |
| --- | --- |
| Server simulation tick `T` | Integer fixed step. Define state at `T` as the state after step `T`; commands targeting `T` are applied during that step |
| Estimated server time `S(now)` | Client estimate in fractional ticks using native monotonic time and timestamp/RTT samples; not just the tick of the newest received packet |
| Presentation tick `P(now)` | `S(now) - interpolation_delay_ticks`, adjusted smoothly and bounded by available coherent state |
| Local prediction tick `L` | Discrete local simulation horizon associated with future server input slots; independent of `P` |

Initialize the time origin from the server handshake/frame and timestamp echoes. Estimate one-way transit as half smoothed RTT; document that this is an approximation under asymmetric links. Jitter is measured separately. Reuse the existing adaptive interpolation logic where possible, but convert its progress to **elapsed time**, not calls per frame. Time must come from a monotonic source unaffected by wall-clock changes or Unity `timeScale`.

`update(now)` pumps receive/ACK/reliability work every rendered frame, accumulates elapsed time, and emits input/prediction ticks at `1/60` second. Multiple input samples within one fixed interval update held state and queue edges; they never produce extra simulation ticks. At 30 FPS two fixed steps may run; at 144 FPS many calls run zero. Rendering samples fractional presentation time every frame.

Use Input System event/callback timestamps, mapped once into the native monotonic timebase, so a 30 FPS batch can carry presses/releases that occurred between frames. Queue input samples and consume them at the appropriate fixed-step boundary. A current-state poll cannot recover an already lost press. The render-rate equivalence fixture injects one identical timestamped input trace into every schedule; it must not compare differently sampled human input as though it were identical. Pin the initial tick boundary and use the same inclusive/exclusive edge rule on both sides. M0 maps the existing `world.tick`/frame convention to the end-of-step definition above to avoid an off-by-one port.

Start with a four-step catch-up limit per update and a 250 ms stale-time threshold. If a stall would require more than four steps, continue socket/control processing, record the stall, discard obsolete unsent input rather than burst-replaying it, clear stale one-shots, and resynchronize prediction/input scheduling to a fresh owner state. Do not invent an unbounded catch-up simulation. A clock moving backward or a suspended application uses the same controlled resync path. Keep the network session alive when safe; transport timeout/reconnect is a separate state.

Frame-rate gate: with identical timestamped held/edge input and network delivery, 30/60/144/uncapped render schedules generate the same 60 Hz commands and semantic world state over 10 seconds, apart from explicitly injected stalls. Include irregular frame intervals, duplicate timestamps, a backward timestamp, a 500 ms stall, focus loss, and `timeScale=0`.

### 6.2 Received truth and presented truth are different views

The core needs a newest received replica for verification/reconciliation **and** a tick-indexed presentation history. Do not advance Unity topology immediately when a reliable delta arrives if its effective tick is still in the future of `P`. Conversely, do not make prediction use an intentionally delayed presentation replica.

Every structural change and event has `(connection_generation, epoch, effective_tick, revision/event_id)`. Include a catalog revision reference where needed. Preserve existing reliable ordering, and explicitly order due transactions by effective tick and revision before presentation. Do not let an early queued event block an earlier structural transaction because it happened to enter another queue first.

For a sample at `P`:

1. Admit only a baseline/catalog pair for the same epoch, level/config identifiers, and catalog revision. A catalog may describe a missing local cosmetic asset; it still must be a valid catalog.
2. Apply complete due structural transactions in order through their effective tick. Require the expected `from_revision`; otherwise request resync.
3. Select pose samples compatible with the structure lifetime of each entity. Interpolate only between samples within that lifetime. Never interpolate a parent into its children, across a teleport, or across an epoch.
4. Expose newly created fragments only when both their structure and a compatible pose exist. Hold their predecessor or show a safe fallback at the last valid transform until then. Never place new fragments at `(0,0)` as a default.
5. Release due events exactly once, with any prerequisite transaction applied. Late events play once at the next coherent presentation sample and record lateness; they do not rewind presentation or replay old effects.

A transaction removes old views and installs the new set atomically using ready extrusion fallbacks. The renderer may then upgrade fragments independently to validated Tier 2 geometry. Do not keep the intact source over already separated fragments while waiting for cosmetic clipping.

Different clients may have different interpolation delays. The requirement is that each applies a split at the correct **simulation tick in its own timeline**, not at the same wall-clock render frame.

### 6.3 Epochs, journals, and asynchronous work

Every view/job/cache application key includes connection generation, epoch, cell ID, immutable geometry hash, source binding/version hash, and builder version. A queued result also records the expected current membership/boundary revision. Recheck those values before applying it; reuse its geometry only when immutable keys still match. A mere unrelated revision change must not discard otherwise reusable geometry.

On reset/reconnect/new level: cancel or invalidate jobs, detach old views/effects, clear presentation/prediction/action history, accept the new catalog/baseline atomically, and rebuild cheap fallback views. Reused numeric IDs cannot resurrect old visuals. A cached immutable mesh may survive an epoch only if content/geometry keys prove equivalence; its old view ownership cannot survive.

Use event IDs and action-result IDs for idempotence. A late join receives persistent state, not a replay of every historical explosion or XP animation. An already completed result screen is reconstructed from its round snapshot.

### 6.4 Compatibility and network budgets

Keep UDP packet/reliability limits and existing fragmentation/reassembly rules. Add new control/catalog/owner-state records to the Odin codec, never to C#. Allocate message kinds after inspecting the current namespace. Increment game protocol/build compatibility whenever wire semantics change; increment canonical structure version when canonical fields/order change. M0 records current values; do not hard-code a future version number that might already be used upstream.

Unknown protocol/ABI/gameplay-config/level versions fail with a useful reason. A missing or mismatched **visual-only** asset uses extrusion and reports one warning per asset binding. A mismatched authoritative level/config hash refuses play rather than letting a wrong collider world appear plausible.

Reserve owner reconciliation/control information ahead of low-priority fragment poses. Keep the current pose-frame budget initially and measure additional bytes; do not assume the native bridge makes prediction bandwidth free. Reliable catalog/structure changes are event costs; original 3D triangle buffers never travel in normal state replication. Log input, owner state, poses, structure, retransmits, and overhead separately.

Loopback remains the default. Add explicit `--bind` configuration for private LAN testing; never silently bind every interface. Preserve host-token checks for layout/settings/reset and the existing host-left lifecycle unless a test explicitly configures a different policy. Do not put host tokens into source control, client bundles, or evidence logs.

## 7. Local input and prediction contract

### 7.1 Implement prediction after the first Unity slice

M4 first proves live connection, extrusion, transforms, events, reset, and reconnect with interpolation only. M5 then adds prediction in the shared native core and exposes it to both frontends. Keep a runtime prediction-off switch for diagnosis. Unity must not contain a parallel movement implementation.

### 7.2 Tick-addressed commands and acknowledgments

Replace latest-value-only player input with an explicit schedule. Each command has:

`{input_generation, command_sequence:u64, target_server_tick:u64, held_move, jump_edge_id_or_zero}`.

The server supplies an initial schedule origin at connection/respawn/resync. The native client estimates `S(now)` and starts targeting future ticks using:

`lead_ticks = clamp(ceil((smoothed_RTT/2 + positive_jitter_p95) * 60) + 2, 2, 15)`.

The default supported test envelope is RTT up to 200 ms and one-way positive jitter up to 30 ms. This is a delivery margin, **not** “predict ahead by RTT.” Store actual measured clock error, lead, buffer depth, and starvation. Keep successive target ticks consecutive within a schedule. Correct small clock drift gradually; a large lead/schedule change uses an acknowledged new `input_generation`, not duplicate commands for the same tick. A short native protocol note must pin the timestamp estimator and reset handshake before coding the extension.

A reset request proposes a new generation, first target tick, and sequence origin. The server validates a future origin within its scheduling window, flushes the previous schedule at an identified boundary, and returns the accepted origin/generation. If delivery made the proposal obsolete, reject/retry against fresh server time; do not silently map queued commands onto different ticks. The estimator's timestamp echo reports the server tick and a sub-tick phase at the echo's send time; keep a bounded sample window and exclude retransmission outliers from clock/RTT estimation.

Rules the server and client must share:

- Native input transmission runs at 60 Hz. Each packet carries the newest command and the previous three commands, within the 1200-byte packet constraint. Retain the full bounded local command ring for reconciliation.
- Accept commands only for the authenticated player, current connection/epoch/input generation, and a bounded future window (initially 32 ticks). Validate finite/clamped movement and a unique target slot.
- Duplicates with identical contents are ignored. Conflicting payloads for the same generation/sequence/target slot are rejected and counted. Out-of-order arrival cannot change an already finalized tick.
- At simulation step `T`, consume the command for `T` if present. If absent, carry forward the last **held movement** for at most six ticks, then use neutral movement. Never carry forward a jump edge or action.
- A command arriving for an already finalized tick is `too_late` and never applied later. Do not build an ever-growing queue whose oldest input drives the player seconds behind reality.
- Owner state reports the exact state tick, `finalized_through_tick`, last actually applied command sequence, input generation, and held-state fallback status. `finalized_through_tick` retires missing/rejected slots too; “last received sequence” is not a reconciliation ACK.
- After a schedule reset, old-generation commands are terminal and cannot execute. New-generation traffic cannot execute before the server accepts its schedule. Send neutral held input while synchronization is incomplete.
- Focus loss, menu capture, disconnect, death, teleport, reset, and stale-time resync clear held input and unconsumed edges. Presses cannot fire on the next round because they remained queued.

Use 64-bit command/action identifiers. Test identities above `2^32` and `2^53`; no float/double or signed truncation in C# may carry them. Transport's existing compact sequence numbers retain their documented wrap-safe comparisons.

### 7.3 One-shot actions are not held state

A jump edge belongs to one target tick. Redundant packets may repeat its ID, but it can trigger at most once. If its target tick is finalized missing, the late edge is dropped; client jump buffering does not authorize the server to execute an old press at an unrelated tick.

Blast/host requests use a separate bounded request stream with `(connection_generation, epoch, request_id)`, terminal acceptance/rejection, and a deduplication cache. Use the transport's reliable channel for these low-frequency requests, or retain the existing native retry/ACK mechanism if it provides the same terminal semantics. Record which is chosen and test it. Never send the same request through both paths. Keep a bounded result window (initially 1,024 request IDs) with a rejection low-water mark: an older ID cannot execute again after its cached result was evicted. Never evict an unresolved request silently.

Blasts are validated and executed at the server's processing tick, not a client-requested historical time; no lag-compensated destruction is added. Include the actual effect tick and event ID in the result. Rate, bounds, solid-aim, and host checks stay authoritative. Clear expired/old-epoch requests; a delayed packet after a reset must not explode the new world. A 500 ms application-level age limit is the default for unexecuted blast intent, with an explicit expiry result. Include its estimated creation server tick and a deadline no more than 30 ticks later, reject implausible future timestamps, and enforce the deadline on the server; also expire local queued intent. The timestamp is only a stale-intent filter and never grants rewind or damage authority. Host administrative commands use their own explicit epoch precondition rather than this blast deadline.

### 7.4 Owner state and replay

Owner snapshots include at least position, linear velocity, grounded, coyote timer, buffered-jump timer, support velocity, input-generation/finalization fields, state tick, topology revision, and a teleport/respawn serial. Audit the shared player code for additional mutable dependencies before calling this complete. Support identity uses stable entity/cell keys, never a process-local Box2D ID. Owner state uses sufficient precision for reconciliation; do not reconstruct velocity from quantized render poses.

Reconciliation procedure:

1. Discard stale/out-of-order owner records. Teleport, death, generation, or epoch changes clear the prediction ring and visual correction offset.
2. Restore the authoritative player state at its state tick in the prediction world, including velocity/timers and valid contact-world state.
3. Replay only commands targeting later ticks, in target order, using the collision history and the same `player_before_step`/`player_after_step` movement helpers as the server. Disable sandbox respawn or gameplay-side mutation inside the prediction helper; the server supplies those outcomes.
4. Rebuild/sample the corrected predicted state. Retire all command slots finalized by the owner snapshot, including commands the server dropped.
5. Keep correction smoothing on a **visual child** only. The prediction body immediately uses corrected state. Decay small offsets over about 100 ms. Teleports, invalid history, gross error, or a penetration that cannot be resolved safely snap/rebase and record a reason.

Sharing Box2D and movement code is not a guarantee of bit-identical contacts or solver warm starts. Use bounded-error acceptance tests and explicit history validity, not an unproven deterministic-lockstep claim.

### 7.5 Collision history and moving supports

Start with a controlled static-terrain fixture. Then add nearby kinematic proxies for dynamic rigid pieces and appropriate rubber cell bodies. Reuse the actual server collision shape construction and filtering. A render mesh is never a collision proxy.

Maintain tick-indexed versions of topology and received/extrapolated poses for the prediction neighborhood; initially retain 256 ticks. Include shapes that enter the player's swept region during replay, not only shapes near its final position. Expand by the maximum possible travel over the prediction horizon plus capsule radius and a margin. Unknown entering objects/history invalidate replay rather than permitting tunneling through them.

For historical ticks, use the topology effective at that tick and compatible poses. For future ticks, moving proxies use bounded extrapolation from the newest state (initial limit 100 ms); track that this is estimated. Never replay past input against today's shattered geometry without acknowledging the mismatch. Do not rewind the authoritative server or re-simulate fragment dynamics.

When required history is missing, topology has changed beyond the available ring, a support is too uncertain, or extrapolation exceeds its bound, switch the local player to a labeled conservative mode: rebase to owner state and use authoritative interpolation until a valid prediction window is available. Smooth presentation where possible; do not feed smoothing back into collision. Log transitions. A supported future improvement is better support extrapolation, not silently predicting the whole world.

Dynamic fragments are kinematic obstacles in the prediction world; local player impulses do not determine their authoritative motion. Players already pass through one another in the inspected code. Do not add player/bomb proxy interactions unless the server collision filter requires them; document any authoritative interaction the local predictor omits and test its correction behavior.

### 7.6 Prediction acceptance defaults

| Scenario | Passing condition |
| --- | --- |
| Render-rate independence | Same fixed command count and target slots for identical timed input at 30/60/144 FPS |
| Local responsiveness on validated static terrain | p95 input-to-visible-motion ≤ one 60 Hz step + one render interval + 2 ms; no added RTT-sized delay |
| Static run/jump, 100 ms RTT, no loss, 10 minutes | Zero non-teleport snaps; p95 correction ≤ 0.03 world units; p99 ≤ 0.10 |
| Static run/jump, 200 ms RTT, 5% loss, 30 ms jitter, 10 minutes | No duplicate actions/unbounded backlog; p99 correction ≤ 0.20; any conservative-mode interval and snap reason reported |
| Moving/rotating supports, fracture below feet | No NaN, runaway velocity, duplicate jump, or replay using invalid history; recovery to coherent owner state within 1 second after fresh history is available |
| Teleport/death/epoch reset | Immediate generation-aware reset; no old input or correction offset survives |
| Prediction disabled | Same authoritative outcomes; ordinary interpolation path works |

The numeric bounds above are implementation targets selected by this plan, not measured results. If a bound fails, fix or honestly report it; do not silently relax it. Dynamic-support conservative fallback is an accepted limitation, but it must not activate continually on the static fixture to evade the static prediction gate.

## 8. Level authoring, motion policy, and provenance

### 8.1 A single level contract

Extend `bom-layout` to version 4 while retaining versions 1–3 and their current semantics. Unity is the authoring source for shipped scenes. The server loads validated exported geometry and is the runtime source of truth. A Unity client cannot modify gameplay geometry by inspecting a renderer or collider at runtime.

Retain existing seed/material/glue fields and exact `u64` identities. New records require:

| Scope | Required fields |
| --- | --- |
| Level | `level_id`, schema version, simulation bounds, separate kill bounds, per-slot spawn points, gameplay-config identifier/hash, visual catalog identifier/hash |
| Authored source instance | Stable `identity`, named asset key, visual content hash, canonical group-to-rest matrix, fallback depth interval, cap-material key, motion/damage policy |
| Physics part | Stable `part_id` within the instance, material, rect/wedge or explicit outline/compound parts, anchoring specification, and explicit glue relationships |
| Replicated cell | Immutable `source_identity`, `source_part_id`, rest geometry, material and resolved motion flags |
| Runtime visual entry | Asset key/version, preprocessed mesh-group references, surface slots, cap materials, visual depth, geometry-builder version |

Keep source identity and physics part distinct: a multi-mesh authored object may use several physical proxy parts but one original visual group. A piece can contain cells from several source instances. Never bind art solely to a piece ID.

IDs remain unsigned 64-bit integers. Export directly using invariant decimal integer formatting; never route them through a double, JavaScript number, or Unity `GetInstanceID()`. Ensure the existing exact JSON path and the new parser preserve values above `2^53`. Avoid the maximum value so `next_identity` remains representable. Validate all counts, lengths, indices, and geometry before allocation/physics creation. Keep the existing layout-upload cap initially; fail oversized uploads clearly rather than increasing caps silently.

### 8.2 Stable authoring identity

Add new `BomAssetInstance` authoring components only in network scene variants or new authored prefabs. Store nonzero identity as an instance override; prefab templates store no live instance identity. Export-time validation catches duplicates. The Editor assignment tool preserves a valid identity on reopen and prefab apply; duplication allocates a fresh identity for the duplicate, not the original. Use a per-level allocator/registry or collision-checked random IDs with an exactly serialized allocator ceiling.

Across levels, the key is `(level_id, identity)`; duplicating a whole level assigns a new `level_id`. Copying individual objects between levels is validated in the destination. Play mode/runtime never allocates authoritative world entity IDs. Every exported physics object is explicitly opted in. Unmarked objects are decorative, including distant art that overlaps another object's XY silhouette.

Build an inventory in the new yard scene. By default, existing objects that the old scene treated as gameplay ground or destructible become explicit bound objects; wall/platform gameplay colliders become fixed proxies; other decoration stays decorative. Record all classifications with object paths and evidence. Do not infer solidity solely because an FBX has a collider or fills screen space.

### 8.3 Coordinates and transforms

- One Unity unit equals one Odin unit. +X is right, +Y up, Z is visual depth. Angles in native contracts are radians; convert once at Unity transform assignment.
- Export collision outlines and cell rest data in a documented shared XY **world-rest space**. Do not mix asset local coordinates with piece reference coordinates.
- The visual group contains every selected MeshFilter/renderer, material submesh, and child local transform baked into a canonical group space. The instance matrix maps that group into world-rest space.
- Store matrices as 16 named-order floats: `m00,m10,m20,m30,m01,m11,m21,m31,m02,m12,m22,m32,m03,m13,m23,m33` (column-major). Include a numerical transform fixture proving the serialization matches Unity/Odin math.
- Arbitrary authored 3D mesh orientations can be baked into rest geometry before planar motion. X/Y rotations in the art hierarchy do not create physical tilt axes. Support finite nonsingular affine transforms; handle nonuniform/negative scale with inverse-transpose normals and winding correction. Reject unsupported shear/singular transforms with the object's path and a bake remedy.
- Collision proxies are explicitly authored/projected into the shared XY plane. Z-separated objects still collide if their opted-in XY proxies overlap; report overlaps and require intended layering, not a hidden 3D collision exception.

For a rigid fragment rest point `p` and piece reference `r`:

```text
world.xy = piece_pose.xy + RotateZ(piece_pose.angle) * (p.xy - r.xy)
world.z  = p.z
```

For rubber, use the cell pose about its own `rest_center`. For a fixed body, expose a resolved rest pose rather than requiring Unity to guess anchoring. Bake the source matrix exactly once. A useful Unity implementation stores chunk vertices relative to the reference XY pivot, retains their baked depth, and sets one GPU model transform per fragment group. Do not transform every mesh vertex on the CPU every frame.

### 8.4 Motion and damage are independent

Replace the ambiguous `category: static|destructible` proposal with these explicit policies:

| Policy | Meaning |
| --- | --- |
| `motion=dynamic` | No permanent authored pin; ordinary Odin dynamics |
| `motion=fixed` | All descendants retain a permanent pin; appropriate for an immovable gameplay wall |
| `motion=anchored` | Only descendants still intersecting explicit authored anchor segments remain pinned; detached unpinned fragments become dynamic |
| `damage=destructible` | Normal Odin material/blast/contact/bond failure rules |
| `damage=indestructible` | Ignore gameplay-driven cell fracture/removal and internal source bonds that would split this instance; explicit administrative reset/delete still works |

For new rigid bodies, any live pinned member makes that rigid body static; after a split recompute from the remaining live cells. For new flexible/cell-body representations, resolve the pin per simulated cell body. Anchor segments are in rest XY and pin only a nonzero matching boundary interval within the documented geometry epsilon. Refinement recomputes anchor inheritance geometrically; blindly copying `anchored=true` to every child would keep detached rubble floating.

An indestructible dynamic prop may move; it is not automatically anchored. External glue joining it to another source may fail according to normal rules without cutting its own protected cells. Centralize damage filtering so blast, impact, structural failure, and recursive refinement all honor it; setting one material strength to infinity is not a complete implementation.

Legacy v1–3 levels retain their `anchor_y`-based behavior through an explicit legacy policy. Do not change old preset physics during extraction or as a side effect of new fields. New policies and their resolved flags participate in persistence, replication, structure hashes, and prediction shape creation.

### 8.5 Footprint support and bounds migration

Implement in this order:

1. Existing rect/wedge proxy authoring and gizmos, with strict validation and visible approximation reports.
2. Convex explicit polygons.
3. Simple concave polygons via deterministic validated triangulation/decomposition, retaining the original source/part and creating the correct shared-edge bonds. Internal decomposition is not an automatic gameplay crack.
4. Holes/disconnected silhouettes represented by explicit nonoverlapping compound proxy parts and deliberate glue. A hole must remain empty; do not fill it with a convex hull.

Validate CCW winding, finite coordinates, minimum area/edge, self-intersection, overlap, and Box2D shape limits. Subdivision/refinement uses Odin's existing material logic after deterministic construction. Area/coverage tests must show no filled holes, duplicate fixtures, or gaps introduced by decomposition. General automatic mesh-silhouette extraction is optional; authored compound proxies satisfy the required support.

No shipped level may silently replace an unsupported shape with a bounding box. A designer may deliberately choose a simplified proxy if the approximation is visible in gizmos and recorded in export metadata. Cosmetic geometry fallback does not authorize physics approximation.

Move all applicable hard-coded bounds into level data: yard extents, player respawn/kill box and spawns, blast acceptance, bomb spawn/cleanup limits, world fragment culling, camera bounds, and aim limits. Search for constants and inline numeric equivalents, including in `bombs.odin`, not just the three constants listed in v2. Old levels retain their original defaults. Physics bounds, kill bounds, render bounds, and bomb spawn margin are separate concepts with explicit config fields.

### 8.6 Provenance through the entire lifecycle

Every cell constructor sets source identity/part; every refinement child inherits them; regrouping cannot change them. Reserved identities for built-in ground/debug sources are allocated deterministically without colliding with exported objects. An old snapshot without provenance loads with an explicit legacy/unknown binding and extrusion; do not invent an arbitrary imported asset.

Update canonical encode/decode/hash, deltas, baseline indexes, snapshot persistence, layout reload, source registry, late join, and resets together. Version canonical/snapshot formats as appropriate. Hash source identity, physics policy, and catalog binding identity; do not hash nondeterministic client mesh triangles. Add tests with two same-looking source instances glued together, splitting and refining repeatedly.

The visual catalog is reliable, versioned, and epoch-scoped. It maps source identity to asset key/content hash, source matrix, depth/cap policy, and part metadata. Stage incomplete catalogs/baselines and expose no mixed epoch. Hash-check catalog bytes separately from structure. Clients with missing art can join using extrusion; clients with the wrong gameplay level/config cannot.

## 9. Unity 2.5D visual reconstruction

### 9.1 Required new presentation pieces

| Component/system | Responsibility |
| --- | --- |
| `BomCoreHost` | Own handle, sample input, pump native client before visual work, copy/ack samples, expose diagnostics |
| `StructurePresenter` | Atomic topology transactions, generation/epoch handling, fragment lifetime and ownership |
| `FragmentView` | Pose/reference application; no gameplay collider; supports rigid-group and rubber-cell modes |
| `FragmentMeshBuilder/Cache` | Immutable geometry builds, cap visibility data, bounded jobs/uploads/eviction |
| `BomVisualRegistry` | Runtime-safe mesh groups and hashes; no `UnityEditor.AssetDatabase` calls in player builds |
| `BomMaterialMap` | Odin material keys to surface/interior materials and fallback appearance |
| `NetworkPlayerView` | Existing character mesh/animator; root-motion-free visual child |
| `NetworkBombView/Effects` | Existing art, fuse/landing cues, event-ID-deduplicated effects/audio |
| `NetworkArenaViewModel/HudPresenter` | Existing UI layout/styles driven by session/round state |
| `LocalPlayerInput` | Input System sampling and explicit edges/requests; no physics |
| `NetworkMenu/LaunchConfig` | Endpoint/connect, errors, mode/host commands, quit/reconnect |

Use new folders, assembly definitions, prefab variants, and scenes. Reuse the art team's mesh/material/animation references and UXML/USS. Do not edit the legacy HUD controller to require a new network session in original scenes; add a presenter that targets the same visual tree. Scheduled result animations cancel/rebind on round/generation changes so stale callbacks cannot update a new round.

### 9.2 Tier 1: extrusion, the dependable baseline

For each valid cell polygon, triangulate faces and extrude along its configured depth interval. Use the surface material on front/back and interior material on exposed sides. Handle nonconvex cells through validated triangulation. Generate normals, UVs, bounds, winding, and index format correctly. Render using the cell/piece reference, not the source prefab pivot.

Tier 1 is required for unbound art, mismatched cosmetics, unsupported/open meshes, failed Tier 2 builds, and asynchronous readiness. Make it readable and correctly material-mapped; a fallback should not be an invisible or misleading outline. Build or pool enough fallback data before committing a visible topology transaction; frame pacing can briefly hold presentation while preserving coherent state.

### 9.3 Runtime visual registry and preprocessing

A registry entry is an authored mesh **group**, not necessarily one MeshFilter. Bake each selected child transform into canonical group geometry; preserve per-triangle material slot, interpolable vertex channels, normals/tangents/UVs, and original depth. Combine turf/dirt or separate shells as authored visual layers of one source when they share a gameplay proxy; this preserves the team's look without reusing crater gameplay.

Create new derived mesh assets if CPU-readable data or normalized geometry is needed. Do not change original FBX importer settings, reimport models, or alter their GUIDs just to enable runtime reads. Store runtime-ready arrays/meshes in the new registry and include them in the build through direct references. Hash the normalized geometry and relevant visual/material parameters together with a builder version; GUID alone is not a content version.

Preflight classifies static triangle meshes as supported closed solid, supported collection of solids, open/thin surface, nonmanifold, degenerate, or unsupported/skinned. Report material slots, triangle count, bounds, transform issues, expected fallback, and a proxy/geometry remedy. Open decorative layers may be treated as clipped surface overlays; they are not closed solids with invented volume. If a robust capped solid cannot be produced, the affected physics region uses Tier 1 and an explicit cosmetic fallback reason.

### 9.4 Tier 2: prism clipping and caps

Implement a focused triangle-mesh/vertical-prism clipper, not a general-purpose CSG engine. Start with convex cells: clip candidate triangles against each XY edge's vertical plane, carrying interpolated UV/normal/tangent/material data. Cull candidates with a baked spatial index. For nonconvex cell regions, decompose the prism, combine without overlapping duplicate surfaces, and suppress decomposition-plane interiors.

Generate cut contours on each plane in that plane's own coordinates (distance along the edge and Z). Weld with a scale-aware epsilon, classify nested loops/holes, triangulate the cap region with correct winding, and use the interior material. Handle disconnected cap loops and multiple solids. Preserve exterior submeshes and normal seams. Plane-coincident triangles need an explicit half-open ownership rule to avoid double walls. Test tangent/normal orientation under mirrored scale.

**Geometry and visibility are separate:** cache the complete clipped cell shell and potential cap patches. Whether a particular cap interval is visible depends on current live neighbors and pose ownership. Do not bake “this cap is hidden forever” into immutable cached geometry.

Split boundary intervals at all overlapping neighbor endpoints, including nonconforming refinement edges. Hide a cap interval only when the other occupied interval belongs to the same source solid and follows the same rigid transform, leaving no exposed cut there. Reveal it when a neighbor disappears or separates. Flexible cells can move relative to one another even with one owner ID, so use their actual pose mode; do not suppress all caps merely because `piece_id` matches. Distinct source assets retain their own surfaces unless an explicit union preprocessing operation was authored.

The closed-cell validation runs before optional internal-cap hiding; a rendered rigid union may omit interior faces but must have no visible external holes. A regroup may update cap visibility/group draw data without recutting exterior triangles. A removed cell exposes neighboring caps even if their piece ID did not change.

### 9.5 Intact-to-fractured switching and failure behavior

Show the original source group only if every expected source region is present and all its cells can be represented by one rigid source transform. Initial flexible sources, pre-damaged late joins, grouped sources with differing transforms, and missing cells must start with fragment rendering. A source's first visible fracture replaces its original renderers atomically with current fragments/fallbacks. Never show both the intact source and its debris, and never hide all of them waiting for a job.

Keep source identity, source matrix hash, part geometry, material mapping, and builder version in the geometry cache key. Membership/cap visibility is a separate changing key. Cache negative results to avoid retrying an unsupported asset every frame. Report one clear warning per cause and keep bounded stats, not an unbounded warning log.

Known invalid meshes may use Tier 1. **Valid required fixtures may not all “pass” by falling back.** Tier 2 must actually succeed for the closed box, closed concave solid, disconnected multi-mesh solid group, and multi-material closed fixture. Thin/open/nonmanifold fixtures pass by the declared overlay/fallback policy with a reason. Record which renderer was used in test evidence.

### 9.6 Scheduling, memory, and budgets

Pump the native core before mesh work. Workers operate only on copied immutable data and do no Unity object creation. Apply meshes/materials on the main thread using the pinned version's supported APIs, with explicit disposal on completion/cancel/error. Use Jobs/MeshData where available; a bounded task/worker implementation is acceptable initially. Do not block on all outstanding jobs after every explosion.

Initial configurable budgets: two active clipping jobs; 128 pending requests; 2 ms mesh-application scheduling budget per frame; 256 MiB mesh-cache target; 64 MiB pending geometry buffers. Account for temporary allocations as well as cache entries. Prioritize visible cells, drop obsolete jobs, evict least-recently-used unreferenced geometry, and retain or rebuild a cheap fallback. One oversized upload may exceed the scheduling budget; measure its indivisible cost and split large meshes ahead of time instead of claiming a strict time cutoff can interrupt a Unity API call.

A network backlog is never fixed by dropping structural deltas for the sake of prettier meshes. If the presenter cannot stay within its bounded queues, request a coherent fresh snapshot and show a resync state. Repeated reset/blast tests must settle back to a bounded live cache and no leaked jobs/handles/Mesh objects.

## 10. Server rules and Unity infrastructure integration

### 10.1 Preserve sandbox; add a separate elimination mode

Do not change the original sandbox's death/respawn rules while extracting the core. Add an explicit mode adapter after the shared client and authoring contracts work. Sandbox retains respawn, manual blast tooling, and Odin bomb behavior. Elimination adds rules without importing Unity's physics or crater implementation.

Elimination defaults:

| Rule | Required behavior |
| --- | --- |
| Participants | Two player connections; additional permitted connections are spectators, within the existing transport capacity |
| State machine | `Waiting -> Countdown -> Playing -> Finished`; disconnect below two ready participants during countdown returns to Waiting |
| Start | Once two players have loaded the right baseline/config and are ready, 180 server ticks of countdown, then start |
| Movement | Existing Odin movement/tuning; no Unity gravity/jump rewrite |
| Bomb behavior | Odin falling bombs: current default radius/body/fuse/drop distribution initially; configurable server settings, not Unity collision explosions |
| Lethal area | A separate server `lethal_radius`, default 2.2 units, measured against the player's 2D capsule, not just its center |
| Other deaths | Leaving explicit kill bounds; no automatic respawn during Playing |
| Manual blasts | Diagnostic sandbox only by default; nonhost/playing-elimination requests are rejected |
| Simultaneous death | Accumulate all deaths caused in the same tick, then decide result: zero alive is a draw, one alive is winner |
| Finished world | Freeze gameplay simulation/bomb spawning and retain result scene; server session/tick/networking continue |
| Restart | Authorized host request only; rebuild world and increment epoch/round identity, reset transient state, then wait/count down with current participants |
| Midround join/rejoin | Spectator until next round. Reconnect is a new connection generation, not an undocumented resurrection |
| Midround disconnect | Participant forfeits on the next server tick; resolve with any other same-tick deaths |
| Host leaves | Preserve existing notification/shutdown policy; show a useful client message |

Do not port Unity's ramping spawn intervals, fall acceleration, crater radius, shatter impulse, or additional rubble physics. Keep the winning Odin behavior. The existing Unity art and effects express that behavior. If designers later request another bomb mode, that is a versioned server feature after this integration.

Factor out-of-bounds detection from respawn. In elimination, collect deaths before applying the mode's terminal outcome. For each detonation, test the capsule pose at that detonation's server moment and accumulate dead players; never let a loop's first `KillPlayer` call select the winner. Structural updates and simultaneous blast ordering remain deterministic under Odin's existing rules.

### 10.2 Replicated round state and results

Replicate a persistent round snapshot with mode, round ID, state, start/countdown/end ticks, participant IDs, alive/spectator flags, winner or draw, terminal reason, bombs spawned, per-player survival ticks, per-player result values, and restart permission. Events trigger presentation; the snapshot is sufficient for late join or dropped/repeated events.

Server result formula, preserving the existing HUD's broad meaning:

- Per-round `xp_gained = 10 * bombs_spawned_while_player_alive + floor(player_alive_ticks / 60)`.
- At round end award it exactly once, keyed by round/player; maintain session totals and win counts on the server. No account persistence.
- Level thresholds start at 100 XP and increase by 50 per subsequent level. The server supplies result/total/progression fields; Unity animates them.
- Label the network HUD statistic “Bombs faced” or “Bombs dropped,” because counting spawned bombs is not proof of a dodge. Do not claim a new dodge detector exists.

Owner snapshots and results include the actual authoritative state. UI may animate a countdown or a timer from server tick values, but cannot decide a winner, award XP, resume physics, or restart the server by itself. Result animations are idempotent and use the round ID to avoid duplicated awards/old callbacks.

### 10.3 Preserve the useful Unity infrastructure

Duplicate `YardLevel.unity` to a new network scene and build a new network menu/bootstrap scene. Keep `YardLevel.unity`, `Arena.unity`, `MainMenuScene.unity`, `menu.unity`, and old prefabs unchanged. The new menu covers endpoint, connecting/loading, rejection, disconnect, reconnect, mode, host-only restart, and quit. It must work in a standalone player without Editor-only APIs.

Reuse existing geometry/materials, Claymate/player animations, bomb visuals, `BombBlastVisual`, audio assets, camera framing, and HUD UXML/USS. Where a legacy camera/layout component references `ArenaSession` or authoritative colliders, write a read-only network adapter; do not re-enable legacy session logic just to satisfy a reference. Apply camera/player visual smoothing without modifying the native simulation pose.

Capture before/after screenshots at the same camera for art composition, player/bomb appearance, material layering, lighting, and HUD layout. The old crater topology is not an appearance requirement: Odin fragments replace it. The underlying art/materials should remain recognizable. Preserve original scene functionality as a regression reference; retirement requires a separate owner request and is not part of this run.

## 11. Milestones, tasks, and hard acceptance gates

Each milestone ends with evidence and a checkpoint, then execution continues. “Gate passed” means the named scenario actually ran. A mocked test can assist development but cannot replace the real executable gate.

### M0 — Environment, source lock, baselines, and dependency map

**Tasks:**

1. Resolve project roots/version provenance and applicable instructions. Record original git status without staging unrelated work. Create an isolated branch/worktree and source lock. Inventory missing files/dependencies rather than guessing a compiler version.
2. Discover and pin the existing Odin compiler, vendored Box2D/raylib setup, Windows linker prerequisites, Unity 6000.2.14f1, installed modules, .NET SDK, and relevant package lock. Verify Unity licensing and standalone Mono/IL2CPP build support.
3. Establish the originals' build commands. If only source archives were provided, reconstruct the smallest documented wrapper using existing repository instructions; do not replace vendor bindings or change gameplay to get a build.
4. Record GUID **and content** manifests for every original asset and `.meta`, plus package/settings baselines. GUID stability alone does not protect asset bytes. Inventory original scenes/prefabs and missing references.
5. Run existing fast correctness checks and short transport/replication soaks; record clean runs and genuine baseline failures separately. Capture an original Odin session and the Unity yard/HUD.
6. Produce a dependency map with entry points, renderer-owned types, server/domain types, initialization order, and candidate extraction cuts. Inventory all entity construction/refinement/persistence paths and bounds constants.
7. Create `STATUS`, tasks, evidence layout, and initial build/test orchestration. Record the proposed yard classification; implementation defaults in this document settle routine choices.

**Gate M0:** originals build/run; source/toolchain lock and manifests exist; known baseline failures are reproducible; the extraction boundary is mapped. If one toolchain is externally unavailable, mark that portion blocked rather than passing M0. Native-only M1/M2 work may proceed after the Odin/native baseline and preservation manifest are confirmed; M4 cannot pass until the full Unity baseline is verified. A newly introduced failure cannot be called pre-existing without baseline evidence. No simulation changes occur in M0.

### M1 — Tiny native-library proof

**Tasks:** compile a minimal Odin DLL, C header, C caller, and .NET caller; export ABI/build identity, layout descriptors, create/destroy, and a harmless status query. Check explicit runtime context and x64 architecture. Exercise 100 create/destroy cycles, two independent handles, invalid/stale handle rejection, and header/.NET layout agreement.

**Gate M1:** the real Windows DLL loads in C and .NET and all lifecycle/layout tests pass. No raylib/window opens. Commit the proof and build command, then continue immediately to extraction.

### M2 — Mechanical headless extraction

**Tasks:** move shared types/logic in small steps; keep behavior identical; replace presentation-owned fields with frontend adapters or generic events; keep bot input outside the native client; retain the fixed-step client entry semantics temporarily. Build dedicated server and both reference entry points. Do not mix prediction, wire changes, or new motion policies into this refactor.

**Gate M2:** original deterministic fixtures produce equivalent semantic output and structure hashes; relevant soaks pass; real Odin dev/bot client connects to the dedicated server; menus/editor smoke works; shared core and dedicated server dependency inspection show no raylib/window dependency. The development frontend still renders/edits normally. Timing/path/log-order noise may be normalized by an explicit comparison script; structural state differences may not.

### M3 — Real client ABI, frame-independent pumping, and headless interoperability

**Tasks:** implement the complete polling ABI and native .NET runner; introduce the elapsed-time pump as a distinct tested change; expose coherent topology/poses/events/host controls; add sample acknowledgment, reset, native diagnostics, and safe error handling. Confirm protocol remains unchanged except any separately versioned extension truly necessary for the boundary.

**Gate M3:**

- .NET client and Odin reference client connect through real UDP to one real server for 10 minutes.
- Both report matching structure hashes at each compared `(epoch, revision)`; missing reports are reported as missing, not treated as matching.
- Move, jump, valid/invalid blast, layout/reset authorization, epoch reset, disconnect/reconnect, and late join run end to end.
- ABI layout/lifecycle and render-rate tests pass, including a stall and two handles.
- Malformed/truncated/oversized native decoder inputs fail safely; no raylib or Unity is involved in the smoke runner.

### M4 — First Unity vertical slice, interpolation and extrusion

**Tasks:** create network scenes/prefabs, native host, input adapter, transaction presenter, Tier 1 meshes, player/bomb views, effects, read-only session HUD, and launch tooling. Initially use a known Odin preset; do not try to align the imported yard until M6. Bring up diagnostic visuals and original art references as appropriate. Prediction remains off for this gate.

**Gate M4:** two real Unity processes plus an Odin dev client join the server, move/jump, produce the same destruction/hash history, display correctly timed explosions, survive reset and reconnect, and late join an already fractured world. Validate reference pivots, rubber poses, radians conversion, depth preservation, and zero legacy authority in the loaded/spawned network scene. Original content manifests pass. Save an actual capture and the full launch command. Do not accept an offline Unity animation as this gate.

### M5 — Scheduled input, owner state, and local prediction

**Tasks:** write the short native protocol/clock extension note; add schedule generations, tick-addressed redundant input, terminal action semantics, owner snapshots, prediction state rings and collision history. Bump compatibility versions. Implement static prediction first, then kinematic/moving support handling and conservative fallback. Enable prediction in both clients through the same package. Add input-generation/focus/menu/teleport handling and correction telemetry.

**Gate M5:** all section 7.6 tests pass; loss/reordering does not duplicate jumps/blasts or replay stale intent; owner ACK/finalized-slot tests pass; static prediction uses genuine local stepping; dynamic contact tests demonstrate valid replay or explicit conservative fallback. Re-run the M4 real-client scenario after the wire change. Mono client build works with prediction on/off.

### M6 — Authoritative level export, policies, and runtime visual registry

**Tasks:** implement layout v4 and compatibility tests; authoring identities and gizmos; simple then compound proxy support; motion/damage policy in actual physics/damage paths; bounds/spawns/config migration; durable cell provenance; reliable catalog; Unity runtime registry and preprocessing report. Export the new yard variant, preserving original assets. Integrate deterministic fixtures for all constructors and legacy presets.

**Gate M6:**

- Exported yard loads identically as gameplay geometry in Odin and Unity; server is the geometry authority.
- Known transforms/footprints/spawns agree within 0.01 world units or one pose position step, whichever is larger. Explicit proxy approximations are listed separately and cannot hide a transform bug.
- IDs survive reopen/prefab apply and regenerate on duplicate; values above `2^53` round-trip exactly.
- New fixed/anchored/dynamic × destructible/indestructible fixtures behave as specified, including detached anchored children and mixed-source glue.
- Every cell retains source identity/part through refinement, regroup, save/load, reset, and late join. Old snapshots/presets still load under their legacy behavior.
- Wrong gameplay manifest refuses play; missing visual assets use visible Tier 1 with correct cells/poses.
- Registry works in a standalone player, not just through AssetDatabase in the Editor.

### M7 — Source-mesh fracture rendering

**Tasks:** implement preprocessed group geometry, prism clipping, contour/cap triangulation, shared-boundary visibility, caching, fallback, job invalidation, and upload budgets. Keep original intact appearance only when valid. Implement supported closed-solid fixtures before attempting every imported rock. Use the real `Rock.fbx` and multi-layer yard art as additional audit cases.

**Gate M7:** required supported fixtures actually use Tier 2; exterior materials/UVs remain mapped; cap normals/topology are valid; missing cells reveal caps; multi-source regrouping has correct pivots; thin/open/bad assets follow declared fallback. Depth never changes from gameplay. A reset/disconnect during outstanding jobs applies zero stale results. Capture intact/fractured/moving views from two camera angles. No network change or gameplay collision difference is introduced by changing visual tier.

### M8 — Full menus, camera, HUD, and elimination mode

**Tasks:** add the section 10 server state machine, participant/spectator roles, deaths/results/XP, server-authorized restarts, network menu, camera/animator adapters, and UI bindings. Do not restore legacy session scripts. Keep sandbox selectable and passing its original behavior checks.

**Gate M8:** two Unity players complete/restart multiple rounds; same-tick deaths draw; disconnect forfeit, countdown interruption, spectator late join, host rejection, reconnect to result, and duplicate result event all behave as specified. Odin observer sees the same state. Server owns every outcome/award. Existing presentation assets are recognizably reused, result animations cancel correctly, and standalone menu-to-game-to-disconnect works.

### M9 — Hardening, performance, packaging, and final evidence

**Tasks:** run full mixed-client/loss/reset/geometry suite; profile reference loads; fix leaks/backlogs; finalize pooled views/cache eviction; produce Windows server, Mono client, IL2CPP client, symbols/build manifests, and developer README. Keep debug effects optional. Complete an independent code review pass for accidental authority, stale lifetimes, unsafe ABI inputs, hidden fallback, and asset changes; fix findings and rerun affected tests.

**Gate M9:** all required gates and the final definition of done pass, including a 30-minute real-process soak and Mono/IL2CPP verification. Package scripts reproduce artifacts and embed the correct native DLL identity. Original assets/scenes remain preserved. Report any limits honestly; do not label required failing work “optional” to declare completion.

## 12. Verification and reproducibility

### 12.1 Existing entry points to discover and reuse

In the inspected source, `main.odin` exposes `--server`, `--bot-client`, `--hidden-client`, `--check-shapes`, `--check-glue-followup`, `--probe-demo-blasts`, `--diagnose-demo`, `--net-soak`, `--replication-soak`, `--pose-resolution`, `--check-textures`, and `--smoke-menus`, among other diagnostics. Reuse them rather than building an entirely separate oracle. Inspect current argument parsing; not every flag has identical duration/output semantics.

M0 runs the fast correctness checks, a 2-minute replication soak, a 2-minute network soak, and a short pose-resolution run as supported. Run longer source-recommended checks before final completion. Do not repeatedly run expensive unrelated visual studies after every small ABI change. Rerun the tests whose paths changed, then the milestone gate. Final hardening runs the comprehensive suite once the implementation has stabilized.

Baseline comparisons preserve deterministic cell IDs, outlines, membership, material behavior, pose semantics, hashes, and event order. Wall-clock timings, machine paths, and incidental log ordering may be normalized. A normalized failure must still retain the raw log for inspection.

### 12.2 Test matrix

| Area | Required cases and evidence |
| --- | --- |
| Native API | C/.NET/Mono/IL2CPP layout; invalid/stale handle; null/count/version errors; multiple clients; teardown; no use-after-release |
| Timing | 30/60/144/uncapped, irregular intervals, focus loss, suspended frame, clock reset, timeScale zero; command counts and timeline trace |
| Transport | Baseline + deltas, reliable fragmentation, missing pose base, duplicates/reorder, burst loss, compatibility rejection, packet/queue bounds |
| Input | Redundant edges once, lost jump, late command terminal, starvation neutralization, conflicting duplicate, future-window reject, generation reset |
| Prediction | Static runs/jumps, moving/rotating support, world split during replay, missing history, teleport, death, disabled prediction comparison |
| Identity | Multiple source instances with same asset; mixed-source piece; repeated refinement; rubber; high IDs; same numeric ID after new epoch |
| Level export | v1–3 compatibility, v4 round-trip, convex/concave/compound with empty hole, mirrored/scaled/rotated mesh, invalid geometry, bounds/spawns |
| Mesh | Actual Tier 2 closed fixtures, contour holes/multiple solids, UV/material preservation, cap visibility changes, open-mesh fallback, reset mid-job |
| Unity authority | Recursively no legacy scripts or gameplay physics, including inactive/nested/runtime objects; no animator root-motion authority |
| Content | Original GUID and byte manifests, no removed assets, no package upgrades/importer rewrites; legacy scenes still run |
| Rules/UI | Waiting/countdown/play/result, simultaneous death, forfeit, spectator, duplicate awards, host authorization, menu/disconnect/reconnect |

Use native codec tests and malformed-input tests for the sole Odin codec; **do not** reintroduce a C# golden-packet parity program or implement a second decoder for testing. Hash reports validate authoritative topology; independent transform/mesh/material tests validate its presentation.

### 12.3 Link profiles and multi-process runs

Pin seeds (initial set: 42, 137, 2026) and record each run's actual packet impairment trace or deterministic simulator configuration. Latency values below are round trip; jitter is bounded positive variation on each one-way path.

| Profile | RTT | One-way jitter | Random loss | Extra behavior |
| --- | --- | --- | --- | --- |
| Clean | 0 ms | 0 | 0 | Local oracle and geometry regression |
| Typical | 100 ms | 10 ms | 0 | Static prediction acceptance |
| Adverse | 200 ms | 30 ms | 5% | Reordering/duplication in a separate pass |
| Interrupted | 100 ms | 20 ms | 0 | One 500 ms loss burst, reset and reconnect |

Apply impairments in both directions using the native link simulator/test transport hook. For real executable gates, packets must still traverse the actual socket/codec/handshake path; an impaired datagram proxy or existing native simulation hook is acceptable. An in-memory fake replica alone is not. Include at least one unmodified real UDP run and one private LAN run if a second machine is available. No second machine is a documented coverage limit, not a reason to fabricate “real network” evidence.

The final 30-minute real-process soak uses one dedicated server, two Unity standalone clients, and an Odin reference client/observer, within the four-client limit. Include seeded bursts, overlapping blasts, several late joins, repeated reconnects, at least ten resets, and resets while jobs run. A test supervisor starts/stops only its own processes and records exit codes.

### 12.4 Performance and memory acceptance

Record CPU, GPU, RAM, OS, build configuration, resolution, scripting backend, mesh counts, active simulated pieces/cells, pose updates, and profiler settings. Do not present the earlier Python/VTK timings as Odin or Unity performance.

Required reference loads:

- A playable yard with two players and up to 500 live cells, including at least 200 independently moving body/pose entities when the fixture permits.
- A stress fixture approaching 1,000 live cells, with repeated fracture/reset and both visual tiers, used to establish scaling and bounded degradation.

Initial acceptance targets on the recorded Windows development machine:

| Metric | Target |
| --- | --- |
| Server steady-state step, reference load | p95 < 16.67 ms; log fracture spike cost separately and prevent cumulative tick backlog |
| Native client update, reference load | p95 ≤ 2 ms, p99 ≤ 4 ms outside explicitly measured baseline/resync processing |
| Unity presentation | Aim for 60 FPS at 1080p; report p50/p95/p99 CPU/GPU frame times and fracture spikes, not just an average |
| Mesh main-thread work | Honor the 2 ms scheduling budget; identify/split single expensive uploads |
| Pose traffic | Existing pose budget initially retained; owner/control prioritized; reliable bursts accounted separately |
| Memory | Stay within configured cache/queue caps; no monotonic live-allocation growth across reset cycles |
| Correctness under stress | No crash, stale visual, invalid topology hash, duplicate action, or silently discarded structural transaction |

These are targets, not measurements. If the development machine cannot sustain the reference load, profile and optimize within scope; retain measured evidence and identify the failing target. Do not quietly change fixture size or lower render quality without reporting it. The 1,000-cell stress fixture may use fallback/eviction and lower cosmetic detail, provided gameplay/network state remains coherent and the actual load is reported.

Measure tracked allocations as well as process RSS: native/managed allocators can retain freed pages. After warmup, compare the last ten equivalent reset cycles; require zero lost native handles, worlds, meshes, or job buffers, and no unexplained increase in tracked live bytes. GC allocation on the stable native-pose/render path should be zero after buffers warm up; instrument unavoidable UI/effect allocations separately.

### 12.5 Build/test interface to deliver

Implement one documented PowerShell entry point, for example:

```powershell
./integration/tools/Invoke-BomIntegration.ps1 -Task VerifyEnvironment
./integration/tools/Invoke-BomIntegration.ps1 -Task Build -Configuration Development
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Fast
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite NativeInterop
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite UnitySlice
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Prediction
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content
./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Soak -Minutes 30
./integration/tools/Invoke-BomIntegration.ps1 -Task Launch -Mode Sandbox
./integration/tools/Invoke-BomIntegration.ps1 -Task Launch -Mode Elimination
./integration/tools/Invoke-BomIntegration.ps1 -Task Package
```

These are the desired **new wrapper commands**, not claims that they already exist. The agent may use an equivalent repository-standard interface if it documents a one-to-one mapping. Commands return nonzero on failure, produce machine-readable test summaries, and print evidence paths. Capture Unity EditMode/PlayMode XML and logs using the pinned version's supported batch runner. Visual gates require actual rendered captures; a graphicsless test cannot establish appearance.

The launcher exposes bind/endpoint/port/config paths without source edits, handles spaces in paths safely, records native identity, uses local secrets without logging them, and cleans up its processes. Packaging includes server/client launch examples and a clean-machine dependency list. Do not require the owner to repeat manual Inspector wiring to reproduce a network scene.

## 13. Asset protection and change control

Freeze original files under `Assets/`, including `.meta`, not just the GUID strings. Keep third-party packs (`Polytope Studio`, TextMesh Pro, Samples) read-only. New folders/scenes/variants/derived mesh assets have new GUIDs. Retain serialization mode and existing package versions. Do not move or rename originals, replace assets wholesale, or edit source scene YAML to strip their gameplay.

Some integration settings necessarily live outside `Assets/`: plugin import settings for **new** DLL assets, new assembly definitions, additive network scene build entries, and a new visual-query layer if required. These specific additive changes are authorized by this plan; record them and preserve pre-existing scene entries/layer assignments. Do not ask for approval merely to add the new network scene to the test build. Do not change `Packages/manifest.json` or the existing render pipeline as a shortcut.

If a Unity import operation wants to rewrite original material/model metadata, investigate and use derived assets or a matching Editor import state. A mass reserialization or package lock rewrite is not acceptable unexplained noise. If an original bug blocks integration, prefer a new adapter. A necessary original-code fix must preserve public behavior and existing scenes, be narrowly scoped, tested, and recorded in the decision log; this is not permission to rewrite the old project.

For baseline failures, keep a separate list with reproduction evidence. Fix in-scope blockers without hiding them in the extraction diff. The narrow original-code-fix allowance above applies outside the frozen Unity `Assets/` set; within that set, use a new adapter/derived asset and leave originals intact. Do not make an existing destructive gameplay test pass by disabling the test or omitting the asset. No protected content is deleted during this autonomous run.

## 14. Fallbacks, stop conditions, and honest reporting

| Problem | Action without routine owner intervention |
| --- | --- |
| Unknown/mismatched visual asset | Validated extrusion, correct authoritative poses/cells, one diagnostic; continue |
| Unsupported nonmanifold/skinned asset | Record classification and remedy; use Tier 1 for gameplay proxy; continue required supported fixtures |
| Unsupported automatic silhouette | Use explicitly authored validated proxy parts in the network scene; never silent bounding-box physics |
| Native DLL locked in test Editor | Shut down only the dedicated runner-owned Editor, rebuild, relaunch; do not kill owner's Editor |
| Missing optional mesh optimization package | Use existing APIs/bounded workers; continue |
| Prediction history uncertain | Conservative authoritative mode and telemetry; recover when valid; cannot evade the static gate |
| Slow Tier 2 geometry | Cache, prioritize, budget, simplify derived visual LOD, or precompute repeated known fixtures; physics remains unchanged |
| Baseline/desync error | Stop presenting incoherent state, request resync, diagnose; do not conceal by suppressing hash reporting |
| Failing required gate | Fix and rerun; do not mark it optional or proceed as if passed |
| Missing Unity/Odin/native build prerequisite | Record exact external blocker; continue independent contract/tests/documentation work if useful; no false runtime claims |
| New scope request/choice absent from plan | Prefer the smallest reversible implementation preserving the authority boundary and existing gameplay; record it. Ask only if consequences materially change scope or cannot be reversed safely |

Any genuine blocker report includes milestone/task, last good commits, exact command/output, the missing prerequisite, attempted remedies and their results, independent work completed, and one concrete next action. Do not end with a vague request to “review the architecture.”

At the end of a limited session, provide a checkpoint rather than a completion claim: passed gates, current failures, unrun gates, changed paths/commits, and next command. Never label the project complete while the real Unity/native/server run, IL2CPP check, required Tier 2 cases, or round integration remains unverified.

## 15. Final definition of done

All of the following are required:

- [ ] M0–M9 evidence exists; no required gate is pending, failed, or hidden behind a mock.
- [ ] Dedicated server and shared client library are headless; Odin dev client uses the same shared client source; Unity contains no wire codec.
- [ ] C/.NET/Mono/IL2CPP ABI, ownership, lifecycle, and loaded-binary identity checks pass.
- [ ] Unity runs two real clients against the Odin server with correct movement, bombs, destruction, structural hashes, interpolation, resets, reconnects, and late join.
- [ ] Static local-player prediction passes the timing/error gates; dynamic/topology uncertainty has bounded, reported fallback and correct reconciliation semantics.
- [ ] Layout export, exact identities, source provenance, resolved motion/damage policy, runtime visual registry, and legacy-layout compatibility pass.
- [ ] Valid supported source meshes really fracture as Tier 2; cap visibility/materials/pivots/depth are correct; invalid assets fall back explicitly.
- [ ] Network menus/camera/animation/HUD/effects use the existing Unity content; selectable elimination rules, results, XP, spectating, and host restarts are server-owned and tested.
- [ ] Original content/GUID/scene manifests pass and old scenes remain usable. No asset/script retirement was necessary.
- [ ] A 30-minute real-process soak and measured reference/stress runs meet the stated correctness/bounded-resource gates; any performance target failure remains a reported unresolved requirement.
- [ ] Build/package/launch/test scripts are reproducible and all known limitations appear in the README.
- [ ] Final report contains source/build identities, what changed, exact successful commands/evidence, measured performance, remaining limits, rollback/checkpoint information, and package locations.

## 16. Documentation references

Project-source observations in section 2 come from the named archives. The following official references support the platform-specific implementation constraints; they do not replace testing against the pinned toolchain:

- [Odin explicit context definition](https://odin-lang.org/docs/overview/#explicit-context-definition): non-Odin calling conventions must establish context when the called code requires it.
- [Odin export attributes](https://odin-lang.org/docs/attributes/): exported native procedures and linking attributes.
- [Unity 6000.2 plugin configuration](https://docs.unity3d.com/6000.2/Documentation/Manual/plug-in-inspector.html): platform import configuration and native-library session lifetime.
- [Unity 6000.2 writable mesh data](https://docs.unity3d.com/6000.2/Documentation/ScriptReference/Mesh.AllocateWritableMeshData.html): worker-accessible mesh buffers and batched allocation.
- [Unity mesh-data apply/dispose API](https://docs.unity.cn/6000.2/Documentation/ScriptReference/Mesh.ApplyAndDisposeWritableMeshData.html): application/disposal and caller responsibility for valid topology.

The required result is one authoritative Odin game with two presentation frontends. The agent should spend its time implementing and proving that boundary, then connecting the existing Unity experience to it, following the gates continuously without routine phase handoffs.
