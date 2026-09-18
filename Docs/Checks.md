# Arena checks

The checks live in `Assets/Game/Editor/Checks/` and run synchronously against the
open Arena scene in Play mode. They are Editor regression checks, not Unity Test
Runner tests. They assume the baseline scene tuning and temporarily change the
round, input routing, or physics; the normal suite finishes with a fresh round.

| Check | Covers |
| --- | --- |
| `VerifySideArena` | Movement, jump/landing, boundaries, fixed camera |
| `VerifyCraterMovement` | Crater escape, coyote jump, buffered landing jump |
| `VerifyArenaLayout` | Resizing ground, boundaries, spawn, bomb range, camera |
| `VerifyBombs` | Falling collision, crater collision, overlapping shapes, damage |
| `VerifyFoundation` | Exposed terrain contours, whole-body damage, blast ring, death/HUD/reset |
| `StressTerrain` | Deterministic batches of overlapping cuts and rebuild timings |

**Arena → Checks → Run All** runs the five normal checks. A failed check throws an
exception identifying the condition. The Console shows the full result.

For individual checks, the optional Unity CLI / Pipeline connection can call the
scripts from the project root:

```powershell
unity command run_script --file Assets/Game/Editor/Checks/VerifyBombs.cs --entry VerifyBombs.Main --caller plugin --skill unity-cli --format json
unity command run_script --file Assets/Game/Editor/Checks/StressTerrain.cs --entry StressTerrain.Main --args '[0,25]' --caller plugin --skill unity-cli --format json
```

Continue stress batches with `(25,25)`, `(50,25)`, etc. in the same Play session;
press R to restore terrain afterward. Timings include a full mesh and collider
rebuild. They are Editor timings, not standalone build frame times. Larger arenas
or frequent explosions may require terrain chunking.

**Arena → Preview → Craters** creates sample overlapping cuts. **Capture** writes
a 1280×720 image to `Temp/Arena-preview.png`. Previews are temporary; R restores
the round. No CLI is needed for the menu tools.
