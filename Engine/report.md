# Rotation/glue follow-up

Fixed flush glue rendering. **Simulation, joint collision settings, strengths and thresholds are unchanged.** The original radius-4 blast still produces force failures under the accepted rules. The support-preserving after-blast PNG uses the fixture adjustment described below; this is not a claim of a physics fix for the original blast.

Diagnosis: [original tick log](evidence/glue-followup/original-ticks.txt) records ticks 0-30 with body pairs, live mortar/glue counts, force ratio r, overload counters, brace displacement and death paths. The no-blast demo already passes on the accepted build: all **23 connections / 7 seams** survive 600 ticks; maximum centre movement is **0.000770723 m**, and maximum vertex movement **0.000939717 m**. Thus the requested expectation that this check fail before changes was not reproduced.

With the original blast (-3.8,0.5), radius 4:

| Seam | Failure tick | Path and r |
|---|---:|---|
| Left post / floor | 1 | Force, 7.057192326 |
| Right post / floor | 1 | Force, 3.699259281 |
| Left brace / post | 1 partial, 8 remaining | Force, 2.168455601 then 8.665056229 |
| Left roof / post | 8 | Force, 3.008141041 |
| Right roof / post | 8 | Force, 3.048999786 |
| Right brace / post | 8 | Force, 10.606233597 |
| Ridge | Survives | All 12 members live at tick 20; r=0.061381884, counter 0 |

These are force failures, not direct blast/deletion failures. Every weld already has **collideConnected=false**. The blast gives the left post velocity (0.94679475,0.060626559) m/s and angular velocity 0.9695723 rad/s, loading the connected structure. In the diagnostic control with **all contacts disabled**, the right floor still immediately fails at r=**2.718913794**. Erasing blast velocities only in a separate diagnostic control reduces its first-tick r to **0.704409003**. [No-contact log](evidence/glue-followup/no-contacts-ticks.txt), [velocity control](evidence/glue-followup/no-blast-velocity-ticks.txt). Neither control affects normal simulation.

The live ridge was also visually lost: its rest endpoint gap is **0.000000119 m**, but solver drift makes its posed gap **0.000147464 m**, exceeding the old 1e-5 flush test. The renderer then stopped drawing circles and emitted subpixel quads. Flush classification now uses rest geometry. Consecutive flush samples draw continuous mortar-width lines, with weighted half-step end extensions so runs meet across cell-pair boundaries. Fillet winding is evaluated once per quad and each of its two triangles is emitted once.

Fixture choice under the standing policy: keep the demo layout and seed 42; move the capture blast to **(-4.4,1.5), radius 3**. The original blast overdrives the supports rather than isolating remote seam preservation. The selected blast releases the nearby brace by force while retaining **17/17** connections whose geometry is more than 1 m beyond its radius at **20 ticks**. [Adjusted tick log](evidence/glue-followup/fixture-ticks.txt). Later force failures remain possible under the unchanged rules; this protection check is for the specified 20 ticks.

Checks: **169 tests pass** with memory tracking. All **48 accepted captures** and **10 additional cantilever/mortar/Bridge captures** are byte-identical; [manifest](evidence/glue-followup/byte-identity-manifest.json), [baseline provenance](evidence/glue-followup/baseline-provenance.json). The ten extra baseline captures were generated from the accepted source archive with the same observation-only test harness. `--calibrate-mortar` logs match byte-for-byte: N1 **160.772048950**, N2 **487.811828613**, ratio **3.034183025**, geometric mean **280.047332764**; the accepted N2 > 2*N1 condition holds.

At both 600-tick quiet and 20-tick adjusted-blast captures, cream pixels in the fixed ROIs are: right floor **76**, right brace **135**, ridge **180**. The ridge close-up has **0 gaps / 440 interior rows**; actual **4x MSAA** has **0 gaps / 550 rows**. Rotated plank/wedge texture continuity retains **0 defects / 90,014 interior pixels**, max difference **1/255**. Three captures have zero text overflows and leave World bytes unchanged. Teardown: **Odin 0, Box2D 0**, texture/shader IDs 0, fonts unloaded.

PNGs: [Test, no blast, 600 ticks](evidence/glue-followup/demo-test-600.png), [Test, adjusted blast, 20 ticks](evidence/glue-followup/demo-test-blast-20.png), [ridge close-up](evidence/glue-followup/ridge-closeup.png). Reproduce with `scripts/bom.ps1 Test`, optimized build, `--diagnose-demo`, `--calibrate-mortar`, and `--check-glue-followup`; SEAM_DIAG_FIXTURE=true selects the adjusted diagnostic fixture. `python scripts/package-glue-followup.py` validates the frozen evidence and builds both bundles.
