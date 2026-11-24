**Physics response tuning plan**



> **Historical / superseded:** This plan records an earlier tuning pass. [README.md](../../README.md) is authoritative for current behavior and defaults; original instructions below do not override later decisions, including strengths 35/20 and the current terrain and jitter behavior.



Make a small tuning pass on the current Odin build. The goal is a larger useful blast, structures that behave rigidly until they break, and a more decisive launch of surviving rubble. Use the existing sandbox and test suite.



| Setting | Current | New starting default | Purpose |

| --- | ---: | ---: | --- |

| Blast radius | 4.2 | **5.0** | Increase actual reach and destructive power. |

| Flexibility | 0.15 | **0.0** | Select the existing stiff-weld path. Positive flexibility remains available in Settings. |

| `BLAST_IMPULSE_SCALE` | 0.1 | **0.2** | Double the direct velocity kick to surviving fragments. |



Keep fragment strength **30**, connection strength **24**, blast-load multiplier **10**, and the existing seed and generation settings. At these strengths, radius 5.0 gives a subdivision-failure range of about **2.0** and a connection-failure range of **2.6**, up from 1.2 and 1.8. The direct added velocity of a surviving default-material fragment remains below roughly **6 units/second**, up from 3; inherited motion and subsequent interactions can add more.



1. **Change the defaults.** Update `DEFAULT_SANDBOX_SETTINGS` in `yard.odin` to radius 5.0 and flexibility 0.0. Use exactly zero, which already has defined stiff-joint behavior. Keep the existing radius/flexibility controls and ranges. Apply & Reset and ordinary reset must continue to reproduce the applied setup.



2. **Strengthen the existing blast impulse.** Change `BLAST_IMPULSE_SCALE` in `destruction.odin` to 0.2. Preserve the mass-scaled impulse, its application through each survivor's center, and its once-only application after same-blast destruction has finished. This leaves that event's initial fracture selection unchanged; stronger subsequent collisions may produce additional breakage.



3. **Do one short controlled comparison.** With radius 5.0, flexibility 0 and the same reset/seed, compare impulse scales 0.1 and 0.2 using the same blast position and simulation timing. Inspect the initial launch, separation of detached pieces, secondary impacts and settling. Also try a support hit and a bomb landing near the tower through the existing fixtures. Keep 0.2 as the starting setting for the hands-on feel pass; report excessive motion if observed. Use the existing tools rather than building a benchmark or tuning framework.



4. **Verify stability and existing behavior.** Run the existing tests and native input smoke playthrough. Check that the untouched tower remains standing under gravity with rigid joints, the player can still stand on/push debris, and the scene settles after impacts. Preserve checks for deterministic resets, all three breakup patterns, same-blast recursion and one final impulse per survivor. Update default-specific expectations in `sandbox_test.odin` and `sandbox_smoke.odin`; retain deliberately chosen fixture values, including explicit nondefault radii. Update the README's defaults and impulse formula. Report any failures with the concrete scenario rather than weakening assertions merely to pass.



Keep this pass focused on physical response. Retain the current mass behavior, damping, load policy, generator, center sampling, and one-generation-per-physics-step reaction rule. Evaluate the rotation produced by the stronger impulses and existing collisions/joints before considering an off-center impulse as a separate experiment. Player blast knockback, sound, fuse effects, preview changes, new data structures and storage optimization are separate work.



Finish with the three final values, a brief description of the observed physical difference, and the checks actually run. These are proposed starting values, not a claim that the new settings have already been playtested.

