Read AGENTS.md first; its rules apply.

BOM — step 2b follow-up: replicate each piece's own reference pose, not the world-origin frame (2026-11-05)

Accepted from step 2b: everything in report.md (frames, budget, inputs, clock, tick-stamped structure, the soak and all its checks). One root cause to fix.

Root cause. A rigid piece's replicated pose is its body-origin frame, and the body origin is the shared rest origin (0,0) for every piece. For a piece 9 m from the origin, this causes three problems:
1. An angle step moves the piece by 9 m × the step. That is why the resolution choice needed 16384 steps per turn (lever arm 9.45 m).
2. While the piece spins, its origin swings around a 9 m circle, so position deltas are large.
3. Interpolating origin position and angle separately draws a fast-spinning piece along the CHORD of that 9 m circle instead of along its path. That is the source of the 6.2 m / 2.0 m / 2.4 m maximum render errors on the remote clients (a dropped frame doubles the angle gap), and of the 5.8 cm max error even on the local client.

Rules:
- Each piece gets an immutable rest reference point ref_rest: the area centroid of its cells when the piece id is created. It is part of the piece's structure record (canonical encoding and Baseline/Delta "pieces added"). It never changes for that id, even if the piece's cell list changes later.
- The replicated pose of a dynamic rigid piece is its reference pose: position = frame.position + rotate(ref_rest, frame.angle), plus angle = frame.angle. Quantize, delta-encode, budget and interpolate THAT. The client converts back with frame.position = ref_position − rotate(ref_rest, angle). Rubber cells, players and bombs are unchanged.
- Rerun section A of step 2b with the lever arm = the largest distance from a piece's ref_rest to any of its vertices (report that maximum), keeping the same 0.5 px rule. Adopt the new choice.
- The render-error measurement must compare VISIBLE positions: for pieces, the reference point plus the maximum vertex error, not the origin frame.

STANDING RULE: You may choose or adjust fixture details yourself: coordinates, blast positions and radii, which cells to discard or which bonds to break, seeds, tick counts. Do this whenever a specified fixture does not exercise what its check is meant to test. Record what you chose and why in the report, and continue without stopping. Stop and ask only if a SYSTEM RULE (data model, failure rules, strengths, recipes, physics, snapshot format, byte-identity requirements) conflicts with the code or cannot be implemented as written.

Checks (the same 10-minute soak, seeds and links as 2b):
a) The new resolution table and choice.
b) Render error per client (visible reference point, and max vertex error): p50/p99/max for all entities, players and bombs. Report both representations side by side using the old metric's samples. Expected: the remote maximum drops from meters to roughly what fast debris can travel over a lost-frame gap. Explain any maximum over 0.5 m with the entity, speed and gap involved.
c) All other 2b soak checks still pass: table agreement 0 mismatches, structure equality on every client, inputs exact, local delay 2. Report frame bytes per tick, bytes per entry and upload against the 2b numbers.
d) Solo captures and PNGs unchanged (the 2a/2b v4 criteria); the 205 tests pass, plus new tests for ref_rest immutability across cell-list changes and for the frame <-> reference-pose round trip.

Do not edit src/netcode/. Deliver: report.md at the repo root and evidence under evidence/replication-2b-followup/ (no interim or handoff files). No zip. Do not commit to git.
