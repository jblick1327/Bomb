Read AGENTS.md first; its rules apply.

BOM — mortar/glue force rule: sustained overload only (2026-11-04)

Accepted from the last round: flush-glue rendering (rest-geometry classification, continuous lines, single-wound quads) and the diagnosis in evidence/glue-followup/.

Root cause (from evidence/glue-followup/original-ticks.txt): the immediate r ≥ 2 path reacts to one-tick constraint impulses. A blast's velocity on one welded body is cancelled across the rigid weld chain in a single step. The far floor seams then read r = 7.06 / 3.70 on tick 1, while every seam is below 1 from tick 2. Those spikes are an artefact of resolving a velocity step in one solver step, not a sustained stress.

SYSTEM RULE CHANGE (approved by the user):
- Remove the immediate-break path. A mortar/glue seam breaks only after OVERLOAD_TICKS = 3 consecutive ticks with r ≥ 1. The counter semantics and the snapshot field are unchanged.
- The blast rule for mortar/glue (min connection strength, sampled at the seam midpoint) is unchanged.
- Revert the capture/check fixture to the original demo blast (-3.8,0.5), radius 4.

Scope: do not edit src/netcode/ (a separate, finished library).

Checks:
a) Original demo blast: every seam whose geometry lies more than 1 m outside the blast radius is live at ticks 20 and 120, and the right post moves < 0.05 m. Must fail on the current build.
b) Demo, no blast, 600 ticks: unchanged (all 7 seams live).
c) Sustained loads still break:
  - --calibrate-mortar: N1 holds and N2 breaks as accepted, with the same N1/N2 values;
  - the glued cantilever with a 3x mass block resting on its tip breaks within 30 ticks;
  - the existing 600-tick glued cantilever still holds.
d) Byte identity: the 48 accepted captures. List any mortar/Bridge/cantilever capture whose bytes change, with the first tick whose seam history differs and the r value that previously triggered an immediate break.
e) Rerun --mortar-seeds and report the spread (accepted: 1.0005x).
f) Informational: drop a 1x1 Stone block from 3 m onto the glued cantilever. Report whether and when the seam breaks.

Update docs/technical-reference.md and the README mortar paragraph for the new rule.

Deliver: write report.md at the repo root (tick log of check a, byte manifest, calibration/seed numbers), and save the PNG demo Test after the original blast at 20 ticks under evidence/force-rule/. No zip needed — the reviewer reads the repo directly. Do not commit to git.
