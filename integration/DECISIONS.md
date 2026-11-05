# Integration decisions

- Use the November 5 live Bomb checkout, not the older BOM/BOM-main Unity projects.
- Retain two source roots. Extract the supplied BOM.zip into the task workspace; do not replace either older Unity repository with Odin files. The local ignored configuration identifies the extracted Odin root.
- Preserve archive working-tree changes. Its Git HEAD alone does not describe the supplied source.
- Original Unity deletions predate integration and remain untouched. Baseline manifests describe actual starting bytes.
- No Unity connector appeared in the available plugin search or project package manifest. Do not alter pinned packages merely to install an unidentified connector. Batch Editor verification remains possible.
- Installed Unity Windows support currently lists Mono variations only; IL2CPP support requires verification/remedy before M9.

- Content acceptance freezes the original Unity assets/packages/settings. The Odin manifest is provenance for semantic comparisons: native code must change during extraction, so a byte freeze on all native sources would contradict M2.
- The official May compiler reports exactly dev-2026-05-nightly:ea5175d. A portable Microsoft SDK x64 package supplies missing libraries, with MSVC and -ignore-vs-search configured locally; no global toolchain upgrade.
