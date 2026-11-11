# Original scenes: load and play check (2026-11-10)

Method: in the dedicated validation copy of the project (Unity 6000.2.14f1, protocol 7 integration present), a PlayMode test
(`evidence/original-scenes/OriginalSceneSmoke.cs`) loads each original scene from `Assets/Game/Scenes`, plays it for 8 seconds of
real time without Editor throttling (batch mode), records every log message, and fails on any exception.
Raw results: `evidence/original-scenes/playmode-report.txt`, `playmode-results.xml`; Unity log in the workspace under
`review/task3-20261110/original-scenes/playmode-unity.log`. The test passed (exit 0, 4/4).

| Scene | Played | Frames | Exceptions | Errors | Notes |
| --- | --- | --- | --- | --- | --- |
| Arena | 7.9 s | 12,090 | 0 | 2 | original falling-bomb gameplay ran (floor collisions logged) |
| MainMenuScene | 8.0 s | 17,087 | 0 | 2 | |
| YardLevel | 7.2 s | 10,200 | 0 | 0 | 2 Unity warnings: Physics.ClosestPoint on a non-convex MeshCollider (original code) |
| menu | 8.0 s | 15,658 | 0 | 0 | |

The 4 errors are the same two messages in two scenes, raised when the scene opens: "Missing Prefab Asset" for
`Rock (1)` (GUID 33021fe8..., `Assets/Game/Geometry/Rock.blend`) in Arena and `Cube` (GUID 58135906..., `Assets/Game/Player/ClayMate.blend`)
in MainMenuScene. Both are Blender `.blend` model assets; Unity imports `.blend` files only when Blender is installed, and it is not on
this machine. They are an environment limitation of this check, not a change made by the integration (the original assets and scenes are
unmodified and verified by the protected-content check); re-run with Blender installed to confirm they disappear.

An earlier attempt that played the scenes from the Editor window was invalid for play time (the Editor throttles an unfocused play loop to
about one frame); its console captures are kept in the workspace (`Arena-console.json` etc.) and show the same two messages.
