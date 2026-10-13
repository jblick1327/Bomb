# BOM exchange candidate bundle

Read `BOM-Shared-Exchange-Contract-v0.1-DRAFT.md` first. Every representation choice is proposed; this bundle does not replace Handbook 1.7.0.

`BOM-Exchange-v0.1-DRAFT.schema.json` describes decoded message fields, not packets or binary layout. IDs and sequence/revision numbers are decimal strings in JSON. `examples/00-definitions.json` supplies every reference used by the scene snapshots. Open profile meanings identified in the contract must be resolved before executable compatibility is claimed.

The four scene files are full current worlds, not incremental edits. Scene 13 and scene 14 each reconstruct without scene 10 or 11. `expectations.json` gives labels and application results. The motion fixture separately demonstrates COM velocity handling. The request files are independent examples.

The schema's local `SceneInput` type pairs the definitions bundle with an initial world; it is not a fifth wire-message kind. Host import establishes actual match identities and remaps all affected references together.

All numerical values are synthetic fixture choices. Two participants in this example do not select multiplayer capacity. No current Unity/Odin code has been modified or validated. See `CHECKS.md` for the checks actually performed.
