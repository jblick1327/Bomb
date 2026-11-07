# M6 layout, provenance and catalog contract

Implemented development contract for ABI 1.3 / protocol 5 / canonical 3. M5 passed on its separately preserved protocol-4 build. M6 acceptance status and executed evidence are recorded in evidence/M6; this document alone is not a passing test.

## Compatibility and authority

Retain the exact v1–3 layout semantics, including implicit yard ground, `anchor_y`, spawn/kill/bomb defaults and recipe behavior. New v4 levels explicitly describe their gameplay geometry; do not add the legacy yard under an exported level. Keep the old editor's authoring formats readable. An experimental editor that cannot round-trip v4 metadata must identify that level as Unity-authored/read-only rather than discard it on save.

The coordinated format change requires game protocol 5 and canonical structure format 3. Snapshot persistence needs an explicit migration version too. Cell ABI layout changes require an ABI major change or a separate versioned sample type; do not silently extend the stride of the existing `BomCell` array. Preserve the passing protocol-4 binaries and launch configuration while developing this change.

## Level records

Layout v4 retains `kind: bom-layout`, seed, custom materials and deliberate glue. Add a nonempty stable `level_id`, separate simulation/kill/camera/aim/fragment-cull bounds, four explicit spawn points, bomb spawn/cleanup settings, and gameplay-config/catalog identifiers. Bounds are finite validated XY data; no invisible wall collider is inferred from a bounding rectangle. A foundation must be an explicit opted-in part. Legacy defaults remain a separate resolved legacy policy.

Sources are distinct from physical parts. A source has nonzero u64 identity, asset key, visual content hash, the 16-float group-to-world-rest matrix, depth interval, cap-material key, motion and damage policies, and parts. Each source's part IDs are stable nonzero u64 values within that source. A part supplies a recipe/material and explicit world-rest outline or deliberate compound outlines, anchor segments and glue references. Cross-source glue identifies both source and part. Keep the source key on every generated cell even when pieces regroup across sources.

All integer identities serialize directly as invariant decimal integers. Unity authoring stores their decimal strings and a serialized allocator ceiling so Inspector/prefab handling never converts an identity through a float or `GetInstanceID()`. Templates have no live identity. Editor duplication preserves the original and allocates a new identity for the duplicate; reopening/prefab apply preserves valid existing IDs. A copied whole level gets a new level ID. Reserve a documented high source-ID range for built-in diagnostics/ground, independently from runtime entity IDs; user allocations cannot enter that range. Legacy unknown binding is explicit zero, with extrusion.

Keep the current 200,000-byte layout-upload cap. Check byte/count limits before constructing geometry. Validate finite nonsingular transforms, CCW simple outlines, minimum area/edge, nonoverlapping compound parts, materials, IDs, anchor segments and glue endpoints. Concave decomposition preserves coverage and source/part identity; a hole remains empty. Unsupported automatic silhouettes require authored proxies and an approximation report, never an implicit bounding box.

## Coordinates and preprocessing

One Unity unit equals one Odin unit. Physics is XY/Z rotation; depth is visual only. Outlines and anchor segments are world-rest XY. The source matrix is column-major in the named order `m00,m10,m20,m30,m01,m11,m21,m31,m02,m12,m22,m32,m03,m13,m23,m33`. Bake mesh-child transforms exactly once. Validate a numerical case containing translation, arbitrary authored 3D rotation, nonuniform scale and negative scale; transform normals by inverse transpose and correct winding. Reject singular/sheared unsupported data with the full object path and a bake remedy.

Preprocessing writes derived mesh/material/registry assets only under the new integration namespace. Original model/material/importer metadata stays unchanged. Runtime registry entries hold direct mesh/material references and a builder version; they cannot depend on AssetDatabase. Native geometry remains authoritative. Every decorative/physics classification and selected approximation is recorded by original scene path.

Unity exports validated authoring input; a native validation CLI loads it, constructs the authoritative deterministic level, and reports the gameplay manifest and catalog fingerprints. The build workflow then finalizes the registry's expected gameplay identity from that report. This avoids reproducing Odin construction/physics in C# just to calculate the manifest. The gameplay fingerprint covers physics/config data; a purely missing/wrong visual asset selects visible extrusion instead of pretending the local mesh is authoritative.

## Motion, damage and provenance

Keep motion and damage independent. `dynamic` supplies no permanent pin; `fixed` pins all descendants; `anchored` pins only descendants with a nonzero matching boundary interval on explicit rest-space anchor segments. Recompute geometric anchor inheritance after refinement. For new rigid pieces, any remaining pinned member makes the piece static; new flexible cells resolve their own pin. Legacy cells retain their original piece/anchor-y behavior.

`indestructible` blocks gameplay-driven cell fracture/removal and internal same-source bond failures, including blast, impact, recursive refinement and structural failure. External glue may fail normally; explicit administrative reset/delete remains available. Do not implement this by changing a single material strength to infinity. Centralize policy filtering in the actual failure/destruction paths.

Immutable source identity/part, resolved motion flags and catalog binding participate in canonical baselines, deltas, hashes, persistence, reset and late join. Constructors/refinement inherit them; regrouping cannot replace them with a piece ID. Test two identical-looking source instances glued together, repeated split/refinement, all six motion/damage combinations, and old snapshot loading with unknown visual binding.

## Reliable metadata and presentation

The catalog/config metadata is reliable, bounded, hash-checked, versioned and epoch-scoped. Stage it with the matching baseline. Expose no mixed epoch or partially assembled catalog. The application handshake rejects a known expected gameplay-manifest mismatch before adding a player. A diagnostic client that uses the complete server-supplied gameplay data can operate without bundled art; missing or mismatched local visual content uses Tier 1 and reports the fallback.

Update prediction collision construction from the same resolved cell policy, level bounds and server tuning. Historical collision versions retain the policy/config effective at their tick. The original yard, scripts and package settings remain protected; create a derived network yard and new presenters rather than editing the source scene YAML.

## Implemented limits and representation

The decoder uses bounded scratch parsing, then constructs a physics-free preview before accepting a layout. It caps uploads at 200,000 bytes, constructed cells at 100,000, sources at 512 and physical parts at 1,024. The conservative authoring work estimate is 500,000; the original 100,000 estimate rejected the inspected 40-by-30 ground even though the real export contains only 4,615 cells. This estimate adjustment changes neither the upload nor cell limits. Cross-source overlaps require explicit source/part endpoints and a reason; depth never exempts an XY overlap. Spawn validation tests the complete native player capsule.

The embedded gameplay_config record is versioned independently and loaded at startup. Its native hash covers gravity, movement/jump tuning and bomb timing; gameplay-manifest hashing includes the resolved gameplay geometry, identities, policy and bounds while excluding cosmetic meshes, material colors, depth and source visual transforms. Catalog text preserves exact f32 bits. Validation reports also preserve f64 area totals.

Scene persistence is version 3 with provenance_version 1. Old scenes and worlds resolve missing provenance as unknown/legacy. Canonical comparison for legacy captures compares every preexisting geometry/material/ownership/pose field exactly and permits only the new metadata fields; this is not a geometric tolerance. The original M2 byte-preservation evidence remains unchanged.

BomCell keeps its previous stride. Separate versioned BomCatalogInfo, BomSourceBinding, BomCellBinding and BomLevelInfo records add metadata through bom_client_acquire_catalog while a matching sample is acquired. Managed code copies arrays and UTF-8 strings before releasing the sample. The 32-byte expected gameplay fingerprint is configured before connecting. Every reliable baseline includes an atomic hash-checked catalog with source/part bindings; topology cells are validated against it before presentation.

For large scenes the prediction world retains every moving proxy and a bounded nearby window of immutable pinned collision cells. A swept capsule leaving that window falls back before an unsupported step. Unavailable moving-body history also falls back explicitly; the yard live evidence records both predicted and conservative frames. This does not expand the verified M5 static-profile latency claim to all dynamic yard frames.
