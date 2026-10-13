The accepted blast contract is independently authored resistance through `MaterialProperties` (`MAT-010`), ordinary distance plus extra resistance × thickness (`WORLD-008`), original material cost even when removed (`WORLD-007`), a breach before carving behind a layer (`WORLD-009`), straight outward paths (`WORLD-010`), and complete blocking by indestructible cover (`WORLD-011`). Destruction response and density remain independent inputs.

### One illustrative path

These values explain the rule; they are not game defaults or a full 2D geometry algorithm.

| Segment on one straight path | Thickness / distance | Blast resistance | Ordinary distance cost | Extra material cost | Total reach cost |
|---|---:|---:|---:|---:|---:|
| Air before the cover | 1 m | 0 | 1 m | 0 m | 1 m |
| Strong cover | 1 m | 4 | 1 m | 4 m | 5 m |
| Weak core | 2 m | 1 | 2 m | 2 m | 4 m |

The cost to reach the core is **6 m** and the cost through both original layers is **10 m**. With a reach budget of 5 and sufficient geometric radius, the path penetrates 0.8 m of cover, leaves 0.2 m unbreached, and does not carve the core. With a reach budget of 8 and sufficient geometric radius, it breaches the cover and penetrates 1 m of core. Removing the cover does not refund its 4 m extra cost. If the cover is indestructible, the path ends at its first surface even with reach left. Other exposed paths are evaluated separately.

### Complete lasting result

Evaluate the full 2D cut and character exposure from the original world. Assemble final geometry before deciding consequences. Zero connected results retire a body; one keeps its ID; multiple retire it and receive new IDs (`IDENTITY-001`). A wide rectangular cover with a through-opening can split into two new bodies while an indented connected core keeps its ID. Each result carries its inherited selections and recoverable current shape without a retired parent (`MAT-008`).

Test old connector failure policies before creating surviving replacements (`CON-014`). Remap each surviving held material location once; a destroyed held location retires its hold (`LIMB-008`). Resolve mass from density × final area and preserve surviving material motion when the operation's motion policy requires it (`MAT-005`, `MAT-009`, `WORLD-006`). The killing explosion keeps the new corpse's shape/ID, installs its authored configuration, clears control/outgoing holds and retains valid incoming holds (`CHAR-006`, `CHAR-004`, `PLAYER-002`, `LIMB-009`).

Publish the complete valid structural outcome together (`COMMIT-002`). Unity derives bodies, colliders, joints and presentation; Odin receives committed semantic results/current recovery state. Reconstruction needs current bodies, relationships, control, countdowns, allocator state and selected validated definitions, not the original shape, retired parents or blast replay (`STATE-001`, `REBUILD-001`).

Numerical geometry, authored values, encoding, character boundary lethality and general explosion scheduling remain open. Implementation evidence and its limits are recorded separately.
