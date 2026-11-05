Read AGENTS.md first; its rules apply.

BOM — mortar/glue failure: impulse toughness instead of a tick count (2026-11-04)

Accepted from the previous round (report.md, evidence/force-rule/): the implementation, the honest non-tuning of check (a), and its findings. They show that both counting rules are wrong in different directions:
- Old rule (r ≥ 2 breaks instantly): one-tick transients through the rigid weld chain break remote anchors.
- Current rule (3 consecutive ticks at r ≥ 1): any impact shorter than 3 ticks can never break a seam, however violent. A 1x1 Stone block dropped from 3 m peaks at r = 77 and the glue survives. Raising the count to 4 makes the demo frame stand, but widens that immunity and is a cliff edge: 3 versus 4 ticks flips the whole outcome.
The quantity that separates "a violent impact" from "a brief moderate transient" is how much load beyond capacity the seam carries over time, an impulse, not how many ticks it lasts.

SYSTEM RULE CHANGE (approved by the user):
- Each seam keeps damage: f32, in seconds of excess capacity. Every tick, with r computed exactly as today:
    if r ≥ 1 { damage += (r − 1) * dt } else { damage = 0 }
  The seam breaks (all members at once, as today) when damage ≥ SEAM_TOUGHNESS.
  dt is the fixed tick, 1/60 s, so the rule doesn't depend on tick rate.
- Remove OVERLOAD_TICKS and the counter. damage is stored on all member connections, as the counter was.
- Snapshot: the optional connection field overload_ticks is replaced by optional damage (f32, omitted when 0). Legacy overload_ticks is accepted on load and ignored (treated as 0).
- The blast rule for mortar/glue is unchanged. MORTAR_STRENGTH and the r formula are unchanged.

Choosing SEAM_TOUGHNESS (data-driven, no other tuning):
1. Sweep SEAM_TOUGHNESS ∈ {0.025, 0.05, 0.1, 0.2, 0.4, 0.8, 1.6} s. For each value, run:
   (a) the original demo blast (-3.8,0.5) r4: all 17 far seams live at ticks 20 and 120, right post moves < 0.05 m;
   (c1) the 3x tip block: breaks within 30 ticks;
   (c2) the mortar calibration: N1 holds, N2 breaks (the existing tests);
   (c3) the 600-tick glued cantilever holds;
   (f) the 1x1 Stone block dropped from 3 m onto the glued cantilever: the glue breaks.
   Report a pass/fail table, with break ticks and the peak damage of every far seam in (a).
2. Feasible range = the values passing all five. Choose the feasible value nearest the geometric mean of the smallest and largest feasible values. If no value is feasible, stop and report the table; don't adjust fixtures.

STANDING RULE: You may choose or adjust fixture details yourself: coordinates, blast positions and radii, which cells to discard or which bonds to break, seeds, tick counts. Do this whenever a specified fixture does not exercise what its check is meant to test. Record what you chose and why in the report, and continue without stopping. Stop and ask only if a SYSTEM RULE (data model, failure rules, strengths, recipes, physics, snapshot format, byte-identity requirements) conflicts with the code or cannot be implemented as written. The fixtures for (a), (c) and (f) above are fixed; don't tune them.

Checks at the chosen value:
- (a), (c1), (c2), (c3) and (f) pass; promote (f) from informational to a test.
- Demo with no blast, 600 ticks: all 23 connections live.
- The 48 accepted captures are byte-identical.
- The 10 cantilever/mortar/Bridge captures: list which change versus the original accepted bytes (evidence/glue-followup/before/), and for each the first differing tick and why.
- --mortar-seeds spread is still about 1.0005x.
- The tick log of (a) shows per-seam damage for ticks 0–30.
- The cream ROI assertion for the blast capture is restored (right floor, brace and ridge all > 0).
Update docs/technical-reference.md and the README mortar paragraph.

Scope: don't edit src/netcode/.

Deliver: report.md at the repo root (the sweep table, the chosen value, check numbers, byte manifest) and evidence under evidence/seam-toughness/. No zip; the reviewer reads the repo directly. Do not commit to git.
