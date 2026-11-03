# Destruction model implementation plan

> **Historical / superseded:** This plan records an earlier implementation stage. [README.md](../../README.md) is authoritative for current behavior and defaults; original instructions below do not override later decisions, including same-blast recursion, birth contexts and the current breakup styles and jitter policy.

Build one small wall that behaves correctly, then expand its generation and presentation. Keep components as plain state and put the rules in a handful of functions. Use the existing language, entity system and physics engine; this plan does not require a new framework.

This plan follows the uploaded handoff and the decisions agreed in this conversation: replacement children inherit surviving boundary attachments; load calculation is replaceable; and destruction advances at most one generation per explosion evaluation or physics tick. Sustained physical loads may cause further generations on later ticks.

**Starting storage**

| Data | Simple first implementation |
| --- | --- |
| Material | Shared records containing the two strengths, flexibility and the three generation settings. |
| Subdivision | Stable ID, range into a global outline vertex pool, and owning piece ID. |
| Connection | Stable ID and two subdivision IDs. |
| Piece | Stable ID, material reference, byte seed, and retained lists of subdivision and connection IDs. |
| Physics state | Existing components or engine storage for bodies, poses and velocities. |
| Derived connection data | Local anchor/sample offsets and engine joint handles, rebuilt when their source geometry or endpoints change. |
| Per-pass scratch | Loads, failed IDs, affected pieces, replacement mappings and graph traversal buffers. |

Keep entity identity independent of array position. If the current entity system already solves this, use it. Otherwise, monotonically assigned IDs and an ID-to-row lookup are sufficient initially. Store stable IDs in connections and membership lists; update row lookups when dense arrays move. Keep outlines in a common undeformed reference frame for related geometry so shared boundaries remain identifiable after bodies move.

**1. Build the graph and a debug view**

Create one hand-authored wall with a few polygon subdivisions, one material and explicit connections. Draw subdivision outlines, connection lines and piece colors. Add debug controls to remove a chosen subdivision or connection.

Implement one structural update function. It removes failed links and subdivisions, discovers connected components in each affected piece, assigns ownership and retains the resulting membership lists. Start with a straightforward graph traversal and temporary adjacency built from the affected piece's connections. Rebuild that piece's lists completely after changes.

Each resulting piece inherits the material. Derive its future-generation seed from the old seed and stable group identity/order. Preserve zero when the old seed is zero; derived nonterminal seeds use 1..255. Geometry already present is independent of this seed.

**Done when:** removing a bridge connection produces two pieces; removing a subdivision also removes its incident links; every live subdivision belongs to exactly one connected piece.

**2. Add the first blast destruction loop**

Use a blast containing only position and radius. Keep the agreed fixed distance falloff and outward impulses proportional to local load and mass. Start with a simple candidate scan of this small scene. Use the physics engine's existing spatial query when scene size makes selection necessary.

For an initial subdivision sampling default, use its posed polygon centroid and keep that choice in one function. For a connection, use the length-weighted shared-boundary rest point, transformed through both endpoints and averaged, as specified in the handoff. Derive the two local offsets when creating the connection and transform them at query time.

Evaluate all candidates that exist at the start of this explosion evaluation. Compare positive loads with their material's appropriate shared threshold and collect failed IDs. Finite loads leave infinite-strength entities intact. Discard the loads after the pass.

Initially exercise this using terminal pieces with seed zero: failed subdivisions disappear and connections can fail independently. Zero-seed geometry remains live until a failure actually occurs. Apply the structural update between physics steps.

**Done when:** the wall loses the expected geometry and links, surviving groups separate, and repeated subthreshold blasts do not weaken anything.

**3. Add procedural replacement and inherited connections**

Create one generation function taking a parent outline, material recipe and seed. It returns child outlines, internal connections and stable child ordering. Start with one reproducible rectangular example. Extend the same pipeline to the supported concave outlines and the chunk, splinter and shatter presets using subdivision count, aspect ratio and triangulation.

Generate each shared displaced boundary once and reuse it in both neighboring outlines. Preserve the parent's outside boundary during replacement. Produce any convex collision decomposition as derived fixtures of the same logical subdivision.

Extend the structural update to replace eligible failed subdivisions with children. Seed zero produces no children. Preserve the direct-removal path for results already selected for discard.

Before removing old endpoints, retain their original neighbor relationships and which connections independently failed. Across an old connection that survived its own failure test, connect replacement descendants sharing a nonzero length of its original boundary. If both endpoints were replaced, compare descendants on both sides. Connections that failed remain broken. Consider only old neighbor relationships, so earlier breaks cannot be healed by geometric proximity.

Stage all replacements before reconnecting and regrouping. Generated children are absent from the current pass's evaluation set. Derive their future piece seeds using stable ordering and identity, independently of physical array order.

**Done when:** a failed subdivision can become smaller geometry while keeping surviving attachments; a simultaneously broken boundary stays disconnected; changing failure-processing order gives the same result.

**4. Connect physics and the replaceable load calculation**

Give each retained subdivision one rigid body, with as many derived convex fixtures as needed. Represent connections with one suitable joint type and map the shared flexibility value to its softness. Keep damping a global implementation setting initially. A piece remains a graph grouping; its subdivisions retain their own motion.

After each fixed physics tick, read the reactions and collect failures through the same path used by blasts. Implement the initial policies as plain functions:

```text
equivalent_force = impulse / interval_covered_by_that_impulse
interaction_load = max(force_magnitude, abs(torque) / reference_length)
subdivision_load = largest_individual_interaction_load
connection_load = load_from_its_own_joint_reaction
fails = load > 0 and load >= relevant_material_strength
```

Choose one global reference length, initially one world unit, and calibrate the fixed blast falloff onto the same load scale. Combine contact points belonging to the same logical interaction before choosing the strongest interaction. Keep different opposing interactions separate so squeezing is not lost through cancellation. All load scratch is temporary.

Keep force/torque conversion and interaction aggregation together in a small load-calculation function. Replacing that function can change the approximation later without changing the component relationships or threshold check.

Preserve existing bodies and their motion when only piece ownership changes. For generated children, inherit the parent's angular velocity and its linear velocity evaluated at each child's center. Apply an explosion's impulse to the original motion before transferring motion to replacements; do not sample that explosion again on the children. Create and remove bodies and joints between engine steps.

**Done when:** an impact or overloaded connection uses the same structural update as a blast, flexible and stiff materials behave differently, and fragments inherit the parent's motion without receiving the same blast twice.

**5. Finish size filtering and presentation**

After regrouping, measure each resulting connected group's orientation-independent geometric width. Put the width calculation in one function. A straightforward convex-hull and edge-normal projection calculation is a reasonable initial implementation of the agreed shortest overall dimension.

Groups below the global minimum width become visual fading remnants. Apply this filter to resulting pieces; small subdivisions may still belong to a sufficiently large connected piece. Filter new results before creating their physics bodies. Existing bodies selected for fading are removed between steps.

Render the stored polygons from their body poses. Add simple interpolation across flexible connections for the rubber-like cosmetic surface once the physical motion works. Keep that surface separate from collision and failure geometry.

**Done when:** rotating a group does not change the width decision, narrow separated remnants fade, and collision triangles never appear as extra destruction entities.

**6. Add transmission after the local loop works**

Expose a simple state reader using stable IDs. Send geometry, connections, ownership and generation context on structural changes, plus the motion state needed for interpolation. Start with explicit snapshots using the project's existing transport.

Transmit existing geometry or the information actually needed to reconstruct it. The current piece seed only governs future generation and cannot by itself reconstruct the current damaged shape. Cosmetic surface interpolation may differ between clients.

**Done when:** a receiver can display a structure, apply a split and interpolate the surviving geometry using the transmitted state.

**The shared structural update**

Both explosion and physics passes use this order:

```text
evaluate loads on the entities present at pass start
collect failed subdivision and connection IDs
stage deletions and one generation of replacements
rebuild inherited links across old surviving boundaries
find connected groups and retain their memberships
filter groups by minimum width
update physics representations and presentation state
```

This is one implementation path with reusable helper functions. A temporary failure list is enough to keep children out of the current evaluation. A continuing physical overload may affect them on a later tick.

**Verification to keep throughout implementation**

Use the same small wall and a few focused behavior checks:

- Removing a bridge link and removing a central subdivision produce the expected graph partitions and membership lists.
- Replacements inherit intact boundaries and never restore independently failed connections, including simultaneous replacement of both endpoints.
- One explosion produces at most one generation; sustained overload may progress on later physics ticks.
- Seed zero stays live until failure and generates no children. The same outline, recipe, seed and stable ordering reproduce the same output after storage rows are shuffled.
- Subthreshold events leave strengths unchanged; infinite strengths survive finite loads.
- Child motion includes the parent's rotation, and an explosion is not applied twice to replacements.
- Width filtering is unchanged by rotation and runs before new physics creation; multiple collision fixtures remain one logical subdivision.

**Keep the first version small**

Use ordinary arrays, per-piece member lists and complete rebuilds of affected pieces. Reuse the benchmark fixtures as examples and the benchmark results as evidence for membership retention and local sample caching. Measure the complete working scene before adding more specialized storage.

Leave full-world repacking, incremental membership patching, eager world-space sample caches, parallel processing, custom allocators, network compression and rollback for demonstrated needs. Start implementation with phase 1's wall and debug removals.

The plan is engine-agnostic. For Box2D integration, consult the installed version's [simulation documentation](https://box2d.org/documentation/md_simulation.html) for safe update timing, joint reactions and the time interval represented by contact impulses. Global normalization choices in this plan are gameplay rules.
