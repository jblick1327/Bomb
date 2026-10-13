# Checks performed on this candidate

Artifact checks passed for all 7 message examples: required fields, closed variants, types/ranges, definition-reference types, unsigned 64-bit bounds and JSON roundtrip. The checker covers the keyword subset used by this generated schema; it is not a general-purpose JSON Schema implementation.

All four current-world scenes passed checks for identity uniqueness, allocator high-water mark versus live IDs, endpoint/control references, polygon winding and self-intersection, paired connector correspondence, held surface points, limb reach and one hold per slot. Definition dependencies resolve without retired bodies or preceding scenes. The examples contain no holes; this check does not demonstrate general hole support.

The split preserves the held material world point and both connector material regions; the connector keeps its lifetime reference. Death keeps body ID/shape/revision, clears control/outgoing holds and retains the incoming hold despite the corpse's different eligibility. Reordered delivery applies 13 then 14. The separate COM-change case preserves a surviving material point's velocity. A maximum-u64 request ID survives JSON roundtrip as a decimal string.

13 deliberately invalid cases were rejected: dangling hold, duplicate entity ID, duplicate limb slot, corpse control, missing definition, wrong definition type, u64 overflow, self-intersecting shape, mismatched connector correspondence, invalid held material point, incompatible version, wrong match, conflicting definition revision.

Not performed: Unity reconstruction, a real Odin codec, physical contact/damping mapping, blast evaluation, packet loss/delivery tests or representative arena payload measurement. The named physics/blast/response profiles and wider selected gameplay state still require review. These checks establish internal consistency of a candidate artifact, not executable game conformance.
