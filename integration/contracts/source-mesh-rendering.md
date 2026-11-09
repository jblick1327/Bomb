# Source-mesh presentation contract

Odin owns cells, outlines, membership, source/part identity, motion, damage, poses and depth metadata. Unity copies the coherent sample and catalog before releasing native memory. Visual-tier selection never changes the native scene or sends a different gameplay command.

The version-2 derived visual source retains original material slots, normals, tangent handedness, color and all eight four-component UV channels. Original FBX importers and scene assets remain unchanged. Group/child transforms are baked exactly once, including mirrored and nonuniform affine transforms. Initial source membership comes from the real native validator's exact decimal cell IDs.

Workers receive copied managed values. Closed connected solids are validated independently. The clipper intersects each source solid with native XY prisms while retaining world-rest Z. Concave cells are decomposed, cut contours support holes and disconnected solids, and caps use outward normals and the interior material. Double-precision intermediate positions, explicit cut-plane membership, distance-scaled contour tolerances and removal of coincident opposing welded folds handle the captured native grain strips. No physics outline is adjusted to make a visual test pass.

Potential cap geometry is cached independently of current membership. A shared interval is hidden only for the same source solid and rigid owner. Removed/refined neighbors expose the remaining intervals. Different sources and flexible cells retain their boundaries. The production attachment adapter maps world-rest geometry through the native reference pivot; shared-owner, split-owner and flexible-cell pivot fixtures verify it.

An original intact view is eligible only when the native initial cell set is unchanged, all cells share one rigid owner, and the gameplay manifest matches. A source switches from the visible native extrusion only after its whole current source mesh is ready. Open, inward, thin, nonmanifold, missing and oversized sources have explicit negative-cache/fallback reasons; they never become invisible gameplay holes.

Geometry work has two active workers, 128 pending requests, a 64 MiB reserved-buffer limit and a bounded completion queue. Positive and negative CPU entries use a referenced LRU, capped at 112 MiB and 8,192 entries. GPU/staging records have a 128 MiB limit; the combined source/fallback cache guard is 256 MiB. GPU geometry is immutable and owner-independent, and unused records can be evicted. A reset/reconnect invalidates tickets without waiting for workers; no stale completion reaches Unity meshes. Disposal drains only managed work after canceling it.

Native polling runs first. Presentation scheduling checks a 2 ms budget between work units. Mesh uploads are split into at most 4,096-triangle chunks. Unity API calls cannot be interrupted: final yard captures measured maximum individual upload 8.81 ms and source read 5.99 ms. Further splitting, pooling and measured frame performance remain required M9 work; these values are not represented as a strict 2 ms cutoff.

The real dedicated server now stages reset worlds on one background worker and publishes only the completed epoch. The old authoritative world and networking continue during construction. Detached cleanup finishes before another build is admitted, serializing Box2D world creation/destruction. Host checks and existing protocol 5 remain unchanged; other host mutations are rejected while the rebuild is pending. This removes the observed connection timeout during large synchronous resets. The final yard rebuild took 33.45 seconds while all clients stayed connected. Startup/rebuild speed remains a measured M9 performance concern.

## Reproduction

After building the pinned native source and configuring the separate Unity validation project:

```powershell
./integration/tools/Test-SourcePresentation.ps1 -Mode All -Seconds 60
./integration/tools/Test-SourcePresentation.ps1 -Mode TierComparison -SkipBuild
./integration/tools/Test-SourcePresentation.ps1 -Mode Invalidation -SkipBuild
```

The pure managed geometry/job checks are also available in `integration/geometry-tests/BomClipTests.csproj`. They reference the pinned Unity CoreModule and the repository SDK; no native network or physics oracle is replaced by these tests. Unity Editor checks and the real executable runs remain separate required evidence.

The final real runs are listed in `evidence/M7/summary.json`. The native patch is relative to the preserved dirty-byte import, and the source overlay ZIP preserves the exact source bytes used for the build identity. Previously frozen M5/M6 builds stay separate. M8 menus/elimination and M9 final hardening are not completed by M7.
