# Checkpoint — 2026-11-05

M0 is not fully passed: baseline builds/tests/import are verified, but visual captures, full scene audit and standalone checks remain. M1 tiny native proof passed from the reproducible repository command (native, C and .NET). M2 has begun as a mechanical, compiling source split; full headless extraction is not done. M3–M9 remain pending.

Unity integration branch: integration/odin-unity-20261105, starting commit c3a7d53f62bc6dfe9c160726226381489feceee4. Extracted Odin branch has the same name, starting HEAD 482fa59a62ee641816023cec869f019cdcc218a2 plus substantial original archive working-tree changes. Do not reset it to HEAD.

Passed original checks: Odin build; 215 game tests; 27 network tests with actual UDP access; two-minute simulated replication and network soaks; one-minute simulated pose-resolution run; isolated Unity 6000.2.14f1 package import/compilation (exit 0); Unity original-file content manifest check. These do not constitute the later real-process integration/30-minute soak gates.

M2 first step: shared settings/Blast_Mode moved into settings.odin; rendering functions moved from net_client.odin into net_client_view.odin. No function body or gameplay constant changed. Net_Client still owns render caches/burst aging/bot state and Net_Server still owns Sandbox, so the headless boundary remains unfinished. Build and regression evidence is under evidence/M2.

Environment: exact documented Odin compiler acquired locally; installed MSVC plus portable SDK libraries allow original builds without a system SDK install. Local ignored config records paths. No Unity connector was discovered or installed. Original Unity Editor was left running and untouched; only a separate copied project was batch-imported. Installed Windows support lists Mono variations; IL2CPP remains unverified/missing.

Next command: ./integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite NativeInterop. Then finish M0 visual/standalone evidence and continue the incremental M2 ownership split. Before editing original native sources, review baselines/odin-pre-M2 and current diff. Do not present the proof DLL as a real game client.

M2 first-step validation: build and all 215 tests passed; a 14-second server with a 10-second real UDP bot passed with one checked structural hash, zero mismatches and zero unrecorded hashes. This is a smoke test, not M2 gate completion. patches/M2-initial.patch isolates this session's native changes from the archive's pre-existing uncommitted changes.
