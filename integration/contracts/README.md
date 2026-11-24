# Contracts

`BomNative.cs`, `bom-abi.json` and `bom_client.h` are copies of the live Odin SDK bindings (`Documents\BOM\bindings`) for the current native checkpoint (ABI 1.7).
`integration/tools/Build-OwnerNative.py` refreshes them on every native checkpoint; never edit them by hand. `Assets/BOMIntegration/Runtime/BomNative.cs` is the same file as `BomNative.cs` here.

The other files are the written contracts: `round-rules.md` (gameplay), `level-layout-v4.md`, `scheduled-input-v4.md`, `native-polling.md`, `headless-architecture.md`, `source-mesh-rendering.md` and `yard-classification.md`.
