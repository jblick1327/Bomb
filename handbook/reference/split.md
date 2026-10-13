Suppose piece P is joined to fixed foundation F by connector C, and a character holds P through limb attachment L. An explosion splits P into two valid pieces. For this example, C's attachment survives only on P1, and the held location survives on P2.

| Concern | Result |
|---|---|
| Material identity and mass | Retire P; assign new IDs to P1 and P2. Derive each result's mass from its resolved density and resulting area. |
| Material/response/appearance settings | P1 and P2 inherit P's definitions/settings by default, with changes only where the response explicitly specifies them. Each result reconstructs without consulting retired P. |
| Motion | Local-frame pose and COM velocity follow `WORLD-006`; changes intended to preserve motion preserve surviving material movement. Other impulse/inheritance policies remain open. |
| Structural connection | First evaluate any attachment-loss test against C's existing reference. If it passes and one relationship survives, keep C's ID/reference; remap its endpoint to P1 while preserving the intended fit. Otherwise retire it. |
| Character's hold | Keep L's ID; remap its target and held-location coordinates to P2. The held point follows P2; the character body may move/rotate within reach. The hold does not branch. |
| Publication and runtime objects | Commit these outcomes together. Affected bodies/joints/visuals and replicated state reflect that complete outcome. Exact scheduling remains open. |

If a held location is lost, retire that hold instead. If no valid structural attachment survives, retire the connector. If several relationships survive and the old connector passes its attachment-loss test, retire it and create a new connector per relationship, each with its own initial reference. This example illustrates accepted outcomes without choosing a geometry format or fragmentation algorithm.
