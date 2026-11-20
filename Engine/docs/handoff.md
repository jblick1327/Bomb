# BOM / Blast Yard — reviewer handoff (updated 2026-11-05)

Supersedes the 2026-11-04 handoff. Read this first in any new session.

## Roles and workflow
- **Project:** a 2D destruction sandbox in Odin + Box2D 3.1.1 + raylib 5.5 on Windows. Repo: `C:\Users\jblic\Documents\BOM`. The user plays `build/BOM.exe`.
- **Implementers:**
  - Codex (best on long, evidence-heavy physics rounds; weekly limit);
  - Claude Code with Sonnet (proven on netcode, force rule, seam toughness and replication 2a/2b; runs natively on Windows and builds Odin).
- **Reviewer/planner:** Claude (Opus) in the desktop app, with the BOM folder connected. It reads the repo directly (stage files) and writes prompt files into `prompts/`. Its device shell has been unavailable (low disk space; it needs ~17 GB free), and even when available it's a Linux VM that can't run the Windows build.
- **Loop:**
  1. Reviewer writes `prompts/<task>.md` (every prompt starts "Read AGENTS.md first").
  2. User sends "Do the task in prompts/<task>.md." to Claude Code or Codex.
  3. The implementer writes `report.md` at the root plus `evidence/<task>/`, no zip, no commits.
  4. Reviewer reads them and replies with a verdict plus a follow-up prompt or "accepted".
- **User values:**
  - simplicity, and each fact has one home;
  - root-cause fixes, never band-aids;
  - no visual glitches;
  - level-design creativity.
  They're open to pushback, cost-aware, and make the gameplay calls.
- **Prompt style:** state the root cause; give exact rules; give checks (checks on existing behaviour must fail first); keep simulation byte-identity unless the user approved a rule change; include the STANDING RULE from AGENTS.md (fixture freedom, stop only on a system-rule conflict).
- **Python prototyping** (shapely/matplotlib/numpy in the reviewer's cloud workspace) before a prompt has worked well: textures, glue seams.

## Architecture (as built, beyond the 2026-11-04 handoff)
**Materials and look**
- Material library: 4 built-ins plus up to 4 layout customs (toughness, blast resistance, colour, strip thickness ≥ 0.2 (= 2 × minimum width), shock loss, flexibility). `Recipe` enum (family) vs `Slot` (palette index).
- Procedural textures: one RGBA tile with a channel per family, rest-frame UVs, tinted 2×; Inter fonts; readable menus.

**Shapes and joints**
- Rotation (any angle, 15° editor steps; Q/E) and wedges (T).
- Each cell stores its frame angle; generation runs in that frame, and frame 0 skips the transform for byte identity.
- Contact snap for off-grid shapes.
- Glue (G tool): links between touching objects (≤ 1 mm). Samples fill crevices up to 0.2 m. It's mortar with stored samples; the seam accessor is shared with mortar.
- Mortar/glue force failure (accepted 2026-11-04): per-seam damage, where r ≥ 1 adds (r − 1)·dt and r < 1 resets it; the seam breaks at SEAM_TOUGHNESS = 0.4 s. It was chosen from the sweep's feasible range 0.2–0.8. Brief blast transients survive, impacts (r = 77) and sustained overloads break, and the snapshot field is `damage`.

**Multiplayer**
- Netcode library `src/netcode/`: UDP, acks with a 32-bit mask, reliable-ordered fragments (≤ 255 KB), unreliable messages, connection handshake with salts, link simulator. Built by Sonnet and accepted. Don't edit without a reason.
- Replication 2a (accepted):
  - World.players[4] (players don't collide with each other; per-player radius; world-level bomb_radius);
  - snapshot v4;
  - drawing is Box2D-free (piece_anchored rule, structural neighbour query);
  - canonical structure plus Baseline/Delta (tick-stamped, epoch, parts ≤ 200 KB);
  - physics-free replica, verified byte-equal every tick over a 72,000-tick 4-bot soak.
- Replication 2b + follow-up (accepted):
  - pose frames per client against the client's acked base table, a 2×1150 B budget with a priority accumulator, gone ids;
  - inputs with jump counter and numbered blasts (rate limit 4/s);
  - adaptive delay (local 2 ticks, remote about 4);
  - tick-stamped structure with no global freeze;
  - each piece replicates its own immutable `ref_rest` reference pose (the old origin-frame interpolation caused metre errors);
  - pose grid 1/256 m with 4096 angle steps (≤ 0.45 px at 2560×1440).
  - Soak at 2% loss: visible error p99 2.6 mm, max 0.39 m; remote upload about 285 kbit/s average, 640 kbit/s peak; final poses converge within 6 ticks.
- Everything runs in-process so far. **Step 3 (sockets, server process, UI) is next: `prompts/step3-server.md`.**

**Decisions**
- Solo play draws its own World directly; multiplayer clients draw the replica (shared Box2D-free draw code).
- Dedicated headless server process; the host's game is a client of it.
- Host port-forwards UDP. No prediction for now (add it if movement feels slow; the replica has the geometry it needs).

## Measurements to remember
- After blasts: about 230–360 awake bodies; changed poses per tick p99 about 230 (soak) / 116 (rubble walk).
- **Rubble never sleeps while players walk on it:** the player body has sleep disabled, so it keeps its whole contact island awake. That costs server CPU. The deeper fix is a kinematic player using Box2D's character-mover API (gameplay change; research task in prompts/chatgpt-tasks.md).
- Server tick with 4 clients: p50 4.75 ms (world_tick 2.5), max about 79 ms on blast plus refill.

## Next steps (agreed order)
1. **Step 3:** server process, sockets, Host/Join UI, layout upload, roles, aim against drawn poses (`prompts/step3-server.md`).
2. **Playtest with friends.** Decide on prediction and the kinematic player.
3. **Demo pass:** Bunker preset, mortared/glued structures, mortar readability, an aim-ring cover note. Wait until the features it shows off are settled.
4. **Parked:**
   - steel (fixed, indestructible) blocks;
   - editor undo/move (the user said not needed now);
   - multicore;
   - security for public servers (connect tokens, reassembly memory cap — Sonnet flagged it);
   - possibly folding mortar into automatic glue.

## Housekeeping
- **Commit the work.** Nothing has been committed since the material library: material follow-up, textures/UI, rotation/glue, force rule, seam toughness, netcode, 2a, 2b.
- Delivery zips (about 60 MB) clutter the repo root. Move them to evidence/zips/ or delete them.
