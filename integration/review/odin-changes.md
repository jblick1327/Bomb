# Odin change review - historical Task 2 package

Task 2 review date: 2026-11-10. The owner subsequently selected option **(b)** and authorized transfer, the five authoritative gameplay changes, a full-folder backup and baseline commit, a local Odin merge after Task 3 passes, and a Unity integration branch. Pushes, PRs and a Unity default-branch merge still require approval. The before/after tables below describe the supplied M0-to-M9 integration, not the later follow-up. See [decisions-needed.md](decisions-needed.md) for current decisions and verification. Historical failed attempts remain evidence.

## Physics, destruction, material and gameplay behavior changes — read first

This integration is not exclusively a file extraction. The following are functional changes relative to the actual M0 working snapshot. The legacy material recipes, subdivision-generation algorithms, blast load/impulse formulas, seam toughness and normal Box2D stepping were not numerically retuned in the reviewed diff. That is a static source finding, not a fresh runtime equivalence result.

| Area | Before | After / scope | Source and reason |
| --- | --- | --- | --- |
| Runtime damage policy | Cells/bonds fail through the existing damage paths. | Explicit indestructible cells skip runtime failure/refinement; bonds internal to the same nonzero indestructible source are protected, including the glass shock path. Creation refinement and explicit administrative removal can bypass the guard. This does not make every connection between different sources unbreakable. | `shared/cell_policy.odin`, `shared/sim_destruction.odin:189`, `shared/sim_glass_shock.odin:162`; implement authored damage policy. |
| Small fragments and cleanup | Minimum-width regrouping can prune small pieces; out-of-bounds cells are discarded. | An indestructible member prevents the minimum-width pruning branch. Ordinary out-of-bounds discard enters the guarded failure path too, so an indestructible dynamic source can survive that discard. Administrative deletion explicitly bypasses protection. | `shared/sim_model.odin:163`, `shared/sim_yard.odin:156`; policy affects more than blast damage and deserves owner attention. |
| Motion and anchoring | Legacy horizontal anchor-line detection determines static bodies. | Dynamic, Fixed and Anchored source policies are explicit. Fixed cells pin; Dynamic cells do not; Anchored cells pin where their rest edges overlap authored anchor segments. Child refinement inherits provenance and recomputes pins. A rigid connected piece is anchored if a member pins; flexible cells use individual pins. Legacy sources retain the original line test. | `shared/cell_policy.odin`, `shared/physics.odin:15`, `shared/sim_physics.odin:179`; support authored immovable/anchored geometry. |
| v4 world construction | Native legacy yard builds its floor/base and uses fixed gravity and spawn positions. | Authored v4 builds proxy parts and explicit glue, uses configured gravity/spawns/bounds, and omits the implicit legacy floor/base. Legacy layout construction remains a separate path. Rubber proxies are fitted/clipped into native cells. | `shared/level_build.odin`, `shared/sim_headless_world.odin`, `shared/sim_yard.odin:170`; use the exported level as authority. |
| Bomb configuration | Fuse 1 s, drop delay 1–2.5 s, fixed sky/spawn/cleanup constants. | Defaults retain those values; a validated v4 gameplay config/level can override fuse, drop timing, spawn interval/height and cleanup bounds. | `shared/gameplay_config.odin`, `shared/sim_bombs.odin`; tuning is data-driven on the Odin side. |
| Player movement and respawn | Global tuning, global spawn and fixed kill bounds. | Same movement formula is shared with prediction; v4 tuning/spawns/kill bounds are authoritative. Legacy defaults remain speed 4, acceleration 32, jump 6.3, coyote/buffer 0.1 s. Support cell/type and teleport serial are additional reconciliation state. Sandbox still respawns; elimination records deaths instead. | `shared/sim_player.odin`, `shared/player.odin`, `shared/sim_yard.odin`; consistent replay and authored levels. |
| Elimination | Sandbox only; no winner/XP controller. | Two participants, 180-tick countdown, interrupted-countdown cancellation, physics frozen outside Playing, bomb/bounds/disconnect deaths resolved together, simultaneous draw, host restart after Finished. Blast lethality uses an independent 2.2-unit radius expanded by the native player capsule, rather than material damage/occlusion. | `shared/round_rules.odin`, `shared/round_server.odin`, `shared/sim_yard.odin:81`; new authoritative game mode. |
| Results and rejoin | No native session XP/resume state. | XP is `10*bombs_faced + alive_ticks/60` with integer division and saturation, awarded once; wins and increasing level costs persist in a bounded 128-session in-memory table. Resume restores totals, not a live round body; midround joins spectate. Server exit loses these totals. | `shared/round_rules.odin`, `shared/round_server.odin`, `shared/round_wire.odin`; native session progression and reconnect. |
| Manual network blasts | Any active authorized sandbox player could request a blast. | Real-network sandbox blasts are host diagnostics only; elimination rejects manual blasts and layout uploads. Offline fixtures retain their original sandbox path. This is an existing-network behavior change even without a v4 layout. | `shared/input_request_network.odin`, `shared/sim_net_server.odin:197`, commit `abce348`; restrict diagnostic tools. |
| Input timing | Real sessions consume legacy input/edges and sequence queues. | Real sessions negotiate scheduled input, fenced by connection incarnation, epoch and schedule generation; late/missing input and repeated actions have explicit handling. Requests have durable terminal results and blast-intent age/deadline handling. | `shared/input_*.odin`, `shared/net_client.odin`, `shared/sim_net_server.odin`; prediction and exactly-once authoritative requests. |
| Reset timing | Synchronous reset blocks the dedicated loop. | Real dedicated server builds a replacement on one worker while old physics/networking continue; publishes the complete epoch, then cleans up the detached world. Other host mutations are rejected while a rebuild/cleanup is pending. Reset request completion is tied to publication. | `shared/net_rebuild.odin`, `shared/sim_net_host.odin`; avoid connection timeouts during large rebuilds. |
| Materials | Built-in recipes determine fracture/strength/damping/appearance. | The built-in `editor_material` function is token-identical after extraction. v4 source parts select validated palette material names; explicit motion/damage policy is separate from material strength. No global recipe retune was found. | `shared/sim_editor.odin:34`, `shared/level_build.odin`; preserve material behavior while authoring assignments. |

The settings above are reviewed here, not silently approved. Task 4's detailed keep/change decisions remain outstanding and have not been implemented.

## Baseline and owner's development state

Task 1 finding: the real owner repository is `C:\Users\jblic\Documents\BOM`, its only branch is `master` at `482fa59a62ee641816023cec869f019cdcc218a2`, and its existing uncommitted files are part of the development state.

The new handoff resolves the previous missing-source problem:

- Unity archive: `BOM-Unity-Repository.zip`, branch `integration/odin-unity-20261105`, HEAD `d686962d049bec1c602467de1cacd480b2d7453e`.
- Native archive: `BOM-Odin-Repository.zip`, same branch, HEAD `dc22bcb6f925d773b2735278d0165c19c06f35db`.
- M0 raw import: `f3ca3aa3d18a4fdc33c9b716f2f39e030a9eae89`, directly descended from the owner's `482fa59`. Its commit message records the supplied dirty working-tree import.
- Actual M0 archive hash in `source-lock.json`: `809fec8d14a1b978290502f203ff2964f17c8daccf0a3d82a42d1efae533adee`, exactly matching the owner's local `Documents\BOM (4).zip`.

All **171** rows in `baselines/odin-content.json` match the owner's present raw bytes: 65 src files, 33 diagnostics, 52 tests, 20 scripts and one layout. Of those, 169 match the Git import after CRLF/LF normalization; the other two are ignored Python bytecode caches, absent from Git rather than conflicting source. The earlier full archive comparison also found all 5,373 live non-Git files unchanged relative to the archive, with only the archive's extra root `src.zip` absent locally.

**No later owner source divergence or content conflicts were found.** There is still an operational integration issue: the owner's Git HEAD alone omits the dirty baseline. A normal patch against clean `482fa59` would misattribute or omit existing work. Preserve/checkpoint the full current source state on an isolated branch/copy before integrating; do not reset, clean, blanket-stage generated evidence, or apply the overlay over the live owner folder.

The supplied native working tree has historical evidence modifications/untracked captures, as listed in `HANDOFF.md`; its reviewed source matches the committed source. The Unity copy retains precisely the four pre-existing metadata deletions. None was restored or deleted during review.

After adding these review documents, the integration's actual protected-content command was run once: `integration/tools/Invoke-BomIntegration.ps1 -Task Test -Suite Content`. It exited 0 and verified all 605 protected files with no errors. Raw record: [Test-Content-20261110T153219926Z.json](../evidence/M0/Test-Content-20261110T153219926Z.json). This is a fresh content check, not a game-test or scene-play check. The extracted native source/ABI/scripts/tests remained clean against `dc22bcb6` after review.

## Patch, overlay and source-identity reproduction

| Check | Observed result |
| --- | --- |
| M9 patch SHA-256 | `4d4bfce12269e1f9953c739a9a6aefafb65ce2524304b9b267ccfdcc3a7ba15d`, matches source lock. |
| Patch application | `git apply --check --cached` and `git apply --cached --whitespace=nowarn` against a separate index initialized at `f3ca3aa`: both exit 0, empty stdout/stderr. |
| Patch alone vs final tree | **Incomplete for the whole commit**: `M\t.gitignore\n` is the only residual tree difference. All source/test/binding/script changes reproduce. |
| Exact omitted edit | Add `/tests/interop/obj/` and `/tests/interop/bin/` to `.gitignore`. Retained separately as `odin-gitignore-completion.patch`; original distribution patch remains untouched. |
| Supplemented tree reproduction | Apply that two-line supplement to the same auxiliary index; `git diff --cached --exit-code dc22bcb6f925d773b2735278d0165c19c06f35db` exits 0 with no output. This reproduces the commit's complete Git tree, not its author/date/commit metadata from a patch alone. |
| Overlay SHA-256 | `2ec920cac8a1b80e43fbf9229e8ff7fb8dd692ea15b350f96d02e8587d69b966`, matches both source lock and embedded M9 overlay. |
| All 297 overlay entries | Size and SHA-256 match the overlay manifest; raw bytes match the supplied native working files; normalized bytes match `dc22bcb6`. No overlay source mismatch. |
| Supplied Unity source plugin DLL | `Assets/BOMIntegration/Plugins/x86_64/bomcore.dll` independently hashes to `4f8cd3852c9eaa40cb3b2cccbf6cfe097b99c013ae8563954773a5ca294407a7`, matching both previously checked packaged player DLLs. |
| Native source fingerprint | 110 files in `src/shared`, `src/netcode`, `src/ffi`, `bindings`, using relative path + NUL + raw bytes and `en-CA` cultural ordering under .NET 10: **`88769f2b478f4e87ff98d0f0ffae60ffedca150cc99169a7c226374230976856`**, tag **`614576365290190056`**, exactly as shipped. |

Raw records: [source-verification.json](source-verification.json), [patch-completion-verification.json](patch-completion-verification.json), [source-fingerprint-review.json](source-fingerprint-review.json). [odin-complete.patch](odin-complete.patch) is an additional complete diff produced from the supplied Git history; the original evidence/patches were not rewritten.

The first fingerprint reproduction attempt did **not** match. Its raw result was:

```text
files: 110
culture: en-CA
source_sha256: 84411f478b95adf08611d764ea29f400dd5a67c04542ae87a959e2ccecb32b43
build_tag: 595620792414853855
```

That attempt used the available Windows PowerShell/.NET Framework cultural sorting. The independent .NET 10 implementation produced the locked hash with both case-sensitive and case-insensitive `en-CA` comparers. The source bytes were unchanged between checks. Reproduction must use the recorded modern tool environment; specifying the culture name alone did not reproduce the fingerprint across these runtimes.

The .NET helper's first launch also failed before hashing because its first-use state path was outside the writable workspace:

```text
System.UnauthorizedAccessException: Access to the path 'C:\Users\jblic\.dotnet\10.0.401.toolpath.sentinel' is denied.
   at Microsoft.Win32.SafeHandles.SafeFileHandle.CreateFile(String fullPath, FileMode mode, FileAccess access, FileShare share, FileOptions options)
   at Microsoft.Win32.SafeHandles.SafeFileHandle.Open(String fullPath, FileMode mode, FileAccess access, FileShare share, FileOptions options, Int64 preallocationSize, Nullable`1 unixCreateMode)
   at System.IO.Strategies.OSFileStreamStrategy..ctor(String path, FileMode mode, FileAccess access, FileShare share, FileOptions options, Int64 preallocationSize, Nullable`1 unixCreateMode)
   at System.IO.Strategies.FileStreamHelpers.ChooseStrategyCore(String path, FileMode mode, FileAccess access, FileShare share, FileOptions options, Int64 preallocationSize, Nullable`1 unixCreateMode)
   at System.IO.File.Create(String path)
   at Microsoft.Extensions.EnvironmentAbstractions.FileWrapper.CreateEmptyFile(String path)
   at Microsoft.DotNet.Cli.Utils.FileAccessRetrier.RetryOnIOException(Action action)
   at Microsoft.DotNet.Configurer.DotnetFirstTimeUseConfigurer.Configure()
   at Microsoft.DotNet.Cli.Program.ConfigureDotNetForFirstTimeUse(IFirstTimeUseNoticeSentinel firstTimeUseNoticeSentinel, IAspNetCertificateSentinel aspNetCertificateSentinel, IFileSentinel toolPathSentinel, Boolean isDotnetBeingInvokedFromNativeInstaller, DotnetFirstRunConfiguration dotnetFirstRunConfiguration, IEnvironmentProvider environmentProvider, Dictionary`2 performanceMeasurements, Boolean skipFirstTimeUseCheck)
   at Microsoft.DotNet.Cli.Program.ProcessArgs(String[] args, TimeSpan startupTime)
   at Microsoft.DotNet.Cli.Program.Main(String[] args)
```

After directing `DOTNET_CLI_HOME` and `NUGET_PACKAGES` to local `review/dotnet-state`, the helper ran under .NET 10.0.12 and returned the matching result. These are review-tool results, not native/game-test passes. No DLL was rebuilt; binary reproducibility and M0-runtime comparisons remain Task 3 work.

## Protocol history 3 → 6

All application codecs remain native Odin. The game protocol, canonical topology version, layout JSON version, scene/world snapshot versions and C ABI minor version are distinct version spaces.

| Version / commit | Wire changes |
| --- | --- |
| 3 — owner's M0 snapshot and early extracted core | Hello is `0xC2` + u32 game version + build string + host token; Welcome supplies slot/host flag. Movement uses the legacy input/ack/jump/blast format. Canonical topology is 2. The shared-core/ABI extraction itself did not require a game-protocol bump. |
| 3 → 4 — `9b9da61` | Build ID becomes `BOM-scheduled-input-2026-11-06`. Introduces `0xD0` scheduled input, `0xD1/0xD2` clock probe/echo, `0xD3` schedule negotiation, `0xD4` owner state, `0xD5` reliable request envelope and `0xD6` terminal request result. Input identity is u64 incarnation + u32 epoch + u64 schedule generation; up to four commands include sequence, target tick, signed movement and jump-edge ID. Owner state carries finalized/applied input, position/velocity/support, coyote/buffer and teleport state. Requests carry connection/epoch/request identity and creation/deadline ticks; results carry status/effect tick/event ID/reason. Existing explosion/rejected-event messages gain a u64 event ID between tick and payload. Canonical topology remains 2. |
| 4 → 5 — `e698289` | Build ID becomes `BOM-level-catalog-2026-11-07`; canonical topology becomes 3. Hello gains a flag and optional 32-byte expected gameplay manifest. Canonical baseline/hash data gains a 32-byte catalog hash, catalog JSON, source-part anchor records; every cell gains u64 source identity, u64 part ID and u32 motion/damage/pin flags. Thus cell provenance also participates in deltas/hashes. Catalog/part bindings validate together with native topology. v4 level JSON upload is now understood. |
| 5 → 6 — `571cba5`, subsequently hardened through `57c05fd` | Build ID becomes `BOM-rounds-2026-11-09`. Hello appends spectator intent and resume credential (16-byte server identity, u64 session ID, 16-byte secret); Welcome returns credentials. New `0xCA` reliable round snapshot carries rules version, epoch/tick/round timing, mode/state/result, two participant records and four connection/progression records. New `0xCB` Ready confirms a validated baseline. Adds host game-mode operation 4 on the native wire (C ABI operation 5; ABI operation 4 remains upload). Canonical topology remains 3. |

ABI additions progress from 1.0 through 1.4 and include actors, prediction, catalog/provenance and round queries in additive structs/getters. These are in-process layouts, not an alternate managed wire protocol. Final protocol/build checks reject the owner's old protocol-3 frontend against the new server: rebuild server, Odin frontend and Unity native plugin as one compatible checkpoint in Task 3. Do not mix frozen M5/M6/M7 artifacts with final protocol 6.

## Original tests: 215 retained, five added

M0 `evidence/M0/summary.json` and `original-tests.log` record **215** original game tests, not 220. The final top-level test inventory contains **220**, preserving every original name and adding exactly:

- `test_client_due_event_not_blocked_by_future_event`
- `test_client_presentation_overflow_is_explicit_and_owned`
- `authored_level_snapshot_preserves_catalog_bounds_high_ids_and_pins`
- `source_keys_survive_repeated_refinement_regroup_and_scene_snapshot`
- `odin_editor_preserves_unity_authored_metadata_and_stays_read_only`

Transport remains 27 original tests. The original test bodies were adapted in eight files: shared instrumentation references, headless helpers, bounded pose-clock/event expectations, unsupported layout version 5, and field-level JSON assertions replacing formatting-specific searches. Their exact before/after diff is in `odin-complete.patch` and their reasons are listed per file in the inventory below. The historical baseline compatibility helper now allows only the Scene v2→v3 provenance migration, while comparing the pre-existing physics fields exactly. That is a changed assertion contract and is not raw snapshot byte identity.

The completion report/contracts' phrase “220 original game tests” should be corrected to “215 original game tests plus five integration regression tests.” No test was rerun in this review. Historical successes and failures remain in the delivered evidence, including the restricted-socket and overlapping-Unity-process failures noted in the M0 summary; this review does not relabel those attempts.

## Subsystems added and extraction scope

- **ABI:** `bindings/bom-abi.json` generates native/C/C# layouts and imports; `src/ffi/` supplies opaque handles, explicit sample acquisition/release/acknowledgment, coherent copied snapshots, catalog/prediction/round queries and error/capacity handling. C and .NET callers exercise the real ABI. Borrowed native pointers are scoped to a sample.
- **Prediction and input:** native schedule/clock/request kernels, shared movement replay, topology/pose collision history, dynamic proxies, bounded command history, owner reconciliation and explicit fallback reasons; Unity does not own these decisions.
- **Rounds:** pure native rules plus server admission, lifecycle, serialization, resume and progression. They are new behavior, not extraction-only code.
- **v4 authoring/provenance:** bounded validated proxies/material names/anchor segments/glue/transforms/bounds/config, separate gameplay/catalog hashes, canonical source IDs and persistent scene metadata. Legacy loader defaults remain separate.
- **Extraction:** physics/destruction helpers move from `package main` to `package shared`; source files and generated aliases preserve the graphical Odin frontend. `Headless_Game` owns World/Layout without raylib. Bots, view bursts/rendering and GUI intent remain frontend adapters. Instrumentation state moves with the core.
- **Hardening:** replica validation, bounded telemetry, async reset/publication, reconnect endpoint preservation, explicit server binding and teardown ownership.

Across 347 matched original procedures extracted into shared, 277 have identical non-comment/non-whitespace tokens and 70 differ. This is a review aid, not an equivalence proof. All changed matched procedures have explicit before/after fragments in [mapped-procedure-diffs.patch](mapped-procedure-diffs.patch); changed procedures remaining in the frontend are in [frontend-procedure-diffs.patch](frontend-procedure-diffs.patch). The complete patch also captures changed data definitions, new helpers and code that was renamed or split.

## Recommendation and ASK

Task 2 source review is complete with the reproduction qualifications above. Recommendation: **(b)** prepare the integration on a new review branch while retaining the full dirty baseline, include the existing `.gitignore` change in any patch-based transfer, and correct the baseline-test wording in the review/handoff documentation. Do not change gameplay rules as part of those corrections. Preserve frozen evidence and supply supplemental correction records rather than rewriting old results.

Owner must choose:

- **(a) Merge as is:** accept the reviewed native source behavior; prepare a separate branch and perform Task 3's builds/runtime verification.
- **(b) Merge with the listed changes:** the same source plus the transfer/documentation corrections above, or other explicitly specified changes; then perform Task 3 on a separate branch.
- **(c) Hold:** leave both live repositories unchanged.

No option has been chosen. This document is not authorization to merge into `master`, push, delete files, open a PR, or make owner-rule decisions. Task 3 and all later tasks remain pending. Game feel, physical LAN testing and the real artist workflow still require human evaluation later in the ordered task list.

## Exhaustive grouped file inventory

The appendix below lists each of the 183 changed/new paths once, grouped into pure moves, new code and edits. Mixed extraction/behavior units are conservatively classified as edits. All source paths in the tables are relative to the native repository root; baseline-to-final differences start at `f3ca3aa`, not at clean `482fa59`.

### 1. Pure moves / extraction without gameplay behavior change

40 paths.

| Status | File | Before | After | Reason |
| --- | --- | --- | --- | --- |
| M | `src/blast_profile.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/blast_query.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/blast_shape_cache.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/cover.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/diagnostic_hooks.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/failures.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/geometry.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/glue.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/inheritance_bounds.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/material_wire.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/mortar.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/presets.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/settings.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/shape_build.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/shape_geometry.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/blast_profile.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/bombs.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/geometry.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/glue.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/net_host.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/settings.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_blast_query.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_blast_shape_cache.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_cover.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_diagnostic_hooks.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_editor.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_failures.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_geometry.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_glue.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_inheritance_bounds.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_material_wire.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_mortar.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_presets.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_shape_build.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_shape_geometry.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_wood_generation.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/sim_world_state.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared/state.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| A | `src/shared_aliases.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |
| M | `src/wood_generation.odin` | Previously in the original main package. | Relocated into shared and/or forwarded by aliases; package/import/#load paths adjusted. | Headless extraction; no gameplay behavior change identified in this unit. |

### 2. New code: ABI, prediction, rounds, v4 levels, provenance and verification

78 paths.

| Status | File | Before | After | Reason |
| --- | --- | --- | --- | --- |
| A | `bindings/BomNative.cs` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `bindings/bom-abi.json` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `bindings/bom_client.h` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `diagnostics/headless_fixture.odin` | No corresponding unit in the M0 import. | Headless fixture helper replacing Sandbox-only diagnostic calls. | New integration support; see the subsystem review. |
| A | `scripts/build-client.ps1` | No corresponding unit in the M0 import. | Build/generate/test the native core and ABI. | New integration support; see the subsystem review. |
| A | `scripts/generate-client-abi.py` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `scripts/generate-interop-caller.py` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `scripts/test-client-core.ps1` | No corresponding unit in the M0 import. | Build/generate/test the native core and ABI. | New integration support; see the subsystem review. |
| A | `src/ffi/abi.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/catalog.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/catalog_test.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/client.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/decoder_test.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/physics_resource_test.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/prediction.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/prediction_test.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/reconnect_test.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/round.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/round_test.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/ffi/timing_test.odin` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `src/headless_world.odin` | No corresponding unit in the M0 import. | Headless server entry point or Odin frontend/client adapter for the shared core. | New integration support; see the subsystem review. |
| A | `src/net_client_bot.odin` | No corresponding unit in the M0 import. | Headless server entry point or Odin frontend/client adapter for the shared core. | New integration support; see the subsystem review. |
| A | `src/net_client_view.odin` | No corresponding unit in the M0 import. | Headless server entry point or Odin frontend/client adapter for the shared core. | New integration support; see the subsystem review. |
| A | `src/net_server_frontend.odin` | No corresponding unit in the M0 import. | Headless server entry point or Odin frontend/client adapter for the shared core. | New integration support; see the subsystem review. |
| A | `src/presets/unity-policy-v4.json` | No corresponding unit in the M0 import. | Explicit v4 policy/provenance fixture; not a replacement for the original presets. | New integration support; see the subsystem review. |
| A | `src/server/main.odin` | No corresponding unit in the M0 import. | Headless server entry point or Odin frontend/client adapter for the shared core. | New integration support; see the subsystem review. |
| A | `src/shared/cell_policy.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/cell_policy_test.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/gameplay_config.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/gameplay_config_test.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/gameplay_manifest.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_clock.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_clock_test.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_link.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_link_test.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_network.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_owner.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_request_network.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_request_network_test.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_requests.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_requests_test.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_schedule.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_schedule_test.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_wire.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/input_wire_test.odin` | No corresponding unit in the M0 import. | Scheduled input, clock synchronization, replay ownership, durable request processing or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/level_build.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/level_build_test.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/level_catalog.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/level_layout.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/level_layout_test.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/level_validate_cli.odin` | No corresponding unit in the M0 import. | Validated v4 authoring, provenance, motion/damage policy, gameplay/catalog identities or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/net_rebuild.odin` | No corresponding unit in the M0 import. | Async native reset/publication or bounded telemetry validation. | New integration support; see the subsystem review. |
| A | `src/shared/net_rebuild_test.odin` | No corresponding unit in the M0 import. | Async native reset/publication or bounded telemetry validation. | New integration support; see the subsystem review. |
| A | `src/shared/net_server_timing_test.odin` | No corresponding unit in the M0 import. | Async native reset/publication or bounded telemetry validation. | New integration support; see the subsystem review. |
| A | `src/shared/prediction_client.odin` | No corresponding unit in the M0 import. | Native prediction history, collision proxies, replay, safe fallback or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/prediction_client_test.odin` | No corresponding unit in the M0 import. | Native prediction history, collision proxies, replay, safe fallback or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/prediction_contact_test.odin` | No corresponding unit in the M0 import. | Native prediction history, collision proxies, replay, safe fallback or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/prediction_history.odin` | No corresponding unit in the M0 import. | Native prediction history, collision proxies, replay, safe fallback or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/prediction_history_test.odin` | No corresponding unit in the M0 import. | Native prediction history, collision proxies, replay, safe fallback or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/prediction_proxy_test.odin` | No corresponding unit in the M0 import. | Native prediction history, collision proxies, replay, safe fallback or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/prediction_region_test.odin` | No corresponding unit in the M0 import. | Native prediction history, collision proxies, replay, safe fallback or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/prediction_static.odin` | No corresponding unit in the M0 import. | Native prediction history, collision proxies, replay, safe fallback or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/prediction_static_test.odin` | No corresponding unit in the M0 import. | Native prediction history, collision proxies, replay, safe fallback or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/replication_validation.odin` | No corresponding unit in the M0 import. | Validate bounds, memberships and references before applying replica changes. | New integration support; see the subsystem review. |
| A | `src/shared/round_network_test.odin` | No corresponding unit in the M0 import. | Server-owned rounds, same-tick death resolution, XP/session resume, wire state or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/round_rules.odin` | No corresponding unit in the M0 import. | Server-owned rounds, same-tick death resolution, XP/session resume, wire state or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/round_rules_test.odin` | No corresponding unit in the M0 import. | Server-owned rounds, same-tick death resolution, XP/session resume, wire state or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/round_server.odin` | No corresponding unit in the M0 import. | Server-owned rounds, same-tick death resolution, XP/session resume, wire state or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/round_wire.odin` | No corresponding unit in the M0 import. | Server-owned rounds, same-tick death resolution, XP/session resume, wire state or its tests. | New integration support; see the subsystem review. |
| A | `src/shared/round_world_test.odin` | No corresponding unit in the M0 import. | Server-owned rounds, same-tick death resolution, XP/session resume, wire state or its tests. | New integration support; see the subsystem review. |
| A | `tests/client_timeline_test.odin` | No corresponding unit in the M0 import. | Five additional timeline/provenance/persistence/read-only-editor tests, separate from the 215 originals. | New integration support; see the subsystem review. |
| A | `tests/interop/Interop.csproj` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `tests/interop/LevelProfile.cs` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `tests/interop/PredictionProfile.cs` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `tests/interop/Program.cs` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `tests/interop/RoundProfile.cs` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `tests/interop/RoundUnityHost.cs` | No corresponding unit in the M0 import. | Versioned C ABI, generated bindings or independent interop/diagnostic callers. | New integration support; see the subsystem review. |
| A | `tests/level_v4_persistence_test.odin` | No corresponding unit in the M0 import. | Five additional timeline/provenance/persistence/read-only-editor tests, separate from the 215 originals. | New integration support; see the subsystem review. |

### 3. Edits to existing code, including gameplay/destruction and necessary frontend/tool/test adaptations

65 paths.

| Status | File | Before | After | Reason |
| --- | --- | --- | --- | --- |
| M | `.gitignore` | Interop bin/obj directories are not specifically ignored. | Ignore /tests/interop/bin/ and /tests/interop/obj/. | Keep generated interop output out of source history; omitted by the distribution patch. |
| M | `diagnostics/cover_capture.odin` | Uses package-global cover counters. | Qualifies shared.cover_wood_failures. | Read instrumentation from its new owner; fixture semantics retained. |
| M | `diagnostics/frame_bench.odin` | Defines/read frame profiling globals in the frontend package. | Globals are shared; report reads/writes are qualified. | Measure the extracted physics/cache core. |
| M | `diagnostics/menu_smoke.odin` | Calls the old client draw signature. | Passes Net_Client_View. | Adapt the real UI smoke to the extracted presentation owner. |
| M | `diagnostics/mortar_measurements.odin` | Local measure flag/counter. | Shared flag/counter, explicitly qualified. | Keep native seam measurements connected to their instrumentation. |
| M | `diagnostics/net_soak.odin` | Client owns Bot and old Client constructor arguments. | Allocate a Bot per client and pass its callback to shared stepping. | Keep the deterministic soak frontend outside the headless client. |
| M | `diagnostics/sandbox_smoke.odin` | Old network draw call. | Passes the separate client view. | Preserve the original smoke through client extraction. |
| M | `diagnostics/seam_diagnostics.odin` | Defines and mutates diagnostic globals locally. | Shared diagnostic state/procedures; callers qualify accesses. | Instrument the shared seam path, not a duplicate. |
| M | `diagnostics/soak.odin` | Replenishes through editor_build_objects; old client draw signature. | Uses shared layout_build_objects and separate client view. | Replenish the same native world after headless extraction. |
| M | `scripts/bom.ps1` | No Server task; temporary staging cleanup trusts its path. | Add Server build and confine cleanup to the resolved build directory. | Build the new headless entry point and protect cleanup boundaries. |
| M | `src/bombs.odin` | Constant fuse/drop range, fixed sky/cleanup bounds. | Level-configured fuse/drop range and authored spawn/cleanup bounds; legacy constants retained. | Use one authoritative native bomb implementation for v4 levels. |
| M | `src/destruction.odin` | Every reported failure can refine/remove cells or break bonds. | Skip indestructible damage unless creation or administrative override; inherit source policy and recompute child pins. | Keep authored identity and explicit damage policy through fracture. |
| M | `src/editor.odin` | Editor constructs objects itself and can edit every supported layout. | Delegate construction to shared routines; refuse editing Unity v4 layouts. | Preserve unsupported source/catalog metadata instead of silently dropping it. |
| M | `src/exact_json.odin` | Exact JSON handles f32, not f64. | Add finite f64 shortest-roundtrip serialization, including negative zero. | Write validation report totals without truncating precision. |
| M | `src/glass_shock.odin` | Shock may break any qualifying non-mortar bond. | Also skip internal same-source indestructible bonds. | Enforce explicit damage policy without changing shock attenuation/strength formulas. |
| M | `src/layout_state.odin` | Versions 1–3 load/save legacy rectangles/materials/glue. | Decode version 4 into a Level_Layout; preserve v4 on save and open it read-only in Odin. | Round-trip Unity-authored levels without changing legacy recipes. |
| M | `src/material_library.odin` | Layout owns legacy materials, objects and glue. | Layout may also own a validated level; destruction frees it. Built-in material recipe functions are unchanged. | Extend layout ownership without changing default material properties. |
| M | `src/model.odin` | Subdivision/piece state has no source policy; tiny pieces may be removed. | Provenance and catalog ownership added; indestructible members prevent tiny-piece pruning; owned catalog memory freed. | Preserve authored identity, damage policy and native memory ownership. |
| M | `src/net_client.odin` | Frontend-specific client, burst objects, FIFO queue, unconstrained historical pose-clock cases. | One native client with bounded coherent queues; sort due messages; clamp pose-clock horizon; plain events; scheduled input/prediction/catalog/round state. | Share network semantics between Odin and Unity and prevent stale/future data presentation. |
| M | `src/net_frame.odin` | Explosion/rejection events contain tick and payload, no durable event ID. | Protocol 4 adds a u64 event ID before payload. Existing pose packet layout otherwise retained. | Identify request effects and present each event coherently. |
| M | `src/net_game_ui.odin` | Frontend owns client burst state and advances up to five catch-up steps. | Separate client view; four-step maximum; reset on time discontinuity; clear input on capture/focus loss. | Keep frontend intent and presentation separate from shared native scheduling. |
| M | `src/net_host.odin` | Host settings/reset/layout mutation synchronously rebuild the sandbox. | Native requests use terminal results; real resets stage/publish asynchronously; elimination restricts reset, upload, mode and tuning; game-mode command added. | Keep transport alive during rebuild and enforce server-owned round controls. |
| M | `src/net_real.odin` | Local bind and simple dedicated-loop/observer driver. | Explicit IPv4 bind and non-loopback host-key requirement; modern fixed-step/observer options, rolling metrics and teardown evidence. | Support supervised native verification and deliberate LAN hosting. |
| M | `src/net_server.odin` | Sandbox server applies legacy input immediately; every active player can request blasts. | Real sessions consume scheduled input, allow only host diagnostics in sandbox, run rounds, send owner/ready/catalog state, bound telemetry and publish reset worlds. | Keep authority and request timing in Odin while supporting the integration. |
| M | `src/net_session.odin` | Protocol 3 Hello contains version/build/token; Welcome contains slot/host flag. | Protocol 6 adds expected manifest, spectator/resume fields, admission checks, credentials and round control. | Reject incompatible gameplay data and preserve server-session results through reconnect. |
| M | `src/physics.odin` | Anchoring uses the legacy ground-line test. | Explicit pinned policy participates in rigid anchoring; flexible cells use their individual pinned state. Legacy line test remains. | Support fixed, dynamic and authored anchor segments without replacing Box2D. |
| M | `src/player.odin` | Global movement tuning, global spawn; grounded/support velocity only. | Same movement formula is shared with prediction; validated per-level tuning/spawns, support cell/type and teleport serial added. | Replay the native movement kernel and apply authoritative level configuration. |
| M | `src/render_cache.odin` | Static rendering groups follow piece anchoring. | Explicit flexible-cell pins determine static grouping; profiling globals are qualified through shared. | Render fixed/anchored rubber consistently with native physics. |
| M | `src/replication.odin` | Canonical v2 contains material/cell/connection/piece data and permissive decoding. | Canonical v3 adds catalog/anchors and per-cell source/part/policy fields; bounds, references, duplicates and assembly are validated before use. | Replicate durable provenance and reject malformed or incoherent native state. |
| M | `src/sandbox_view.odin` | Draw the network client without a separate view object. | Pass the dedicated client_view to the draw adapter. | Preserve graphical presentation after extracting the headless client. |
| A | `src/shared/exact_json.odin` | Exact JSON handles f32, not f64. | Add finite f64 shortest-roundtrip serialization, including negative zero. | Write validation report totals without truncating precision. |
| A | `src/shared/model.odin` | Subdivision/piece state has no source policy; tiny pieces may be removed. | Provenance and catalog ownership added; indestructible members prevent tiny-piece pruning; owned catalog memory freed. | Preserve authored identity, damage policy and native memory ownership. |
| A | `src/shared/net_client.odin` | Frontend-specific client, burst objects, FIFO queue, unconstrained historical pose-clock cases. | One native client with bounded coherent queues; sort due messages; clamp pose-clock horizon; plain events; scheduled input/prediction/catalog/round state. | Share network semantics between Odin and Unity and prevent stale/future data presentation. |
| A | `src/shared/net_frame.odin` | Explosion/rejection events contain tick and payload, no durable event ID. | Protocol 4 adds a u64 event ID before payload. Existing pose packet layout otherwise retained. | Identify request effects and present each event coherently. |
| A | `src/shared/net_session.odin` | Protocol 3 Hello contains version/build/token; Welcome contains slot/host flag. | Protocol 6 adds expected manifest, spectator/resume fields, admission checks, credentials and round control. | Reject incompatible gameplay data and preserve server-session results through reconnect. |
| A | `src/shared/physics.odin` | Anchoring uses the legacy ground-line test. | Explicit pinned policy participates in rigid anchoring; flexible cells use their individual pinned state. Legacy line test remains. | Support fixed, dynamic and authored anchor segments without replacing Box2D. |
| A | `src/shared/player.odin` | Global movement tuning, global spawn; grounded/support velocity only. | Same movement formula is shared with prediction; validated per-level tuning/spawns, support cell/type and teleport serial added. | Replay the native movement kernel and apply authoritative level configuration. |
| A | `src/shared/replication.odin` | Canonical v2 contains material/cell/connection/piece data and permissive decoding. | Canonical v3 adds catalog/anchors and per-cell source/part/policy fields; bounds, references, duplicates and assembly are validated before use. | Replicate durable provenance and reject malformed or incoherent native state. |
| A | `src/shared/sim_bombs.odin` | Constant fuse/drop range, fixed sky/cleanup bounds. | Level-configured fuse/drop range and authored spawn/cleanup bounds; legacy constants retained. | Use one authoritative native bomb implementation for v4 levels. |
| A | `src/shared/sim_destruction.odin` | Every reported failure can refine/remove cells or break bonds. | Skip indestructible damage unless creation or administrative override; inherit source policy and recompute child pins. | Keep authored identity and explicit damage policy through fracture. |
| A | `src/shared/sim_glass_shock.odin` | Shock may break any qualifying non-mortar bond. | Also skip internal same-source indestructible bonds. | Enforce explicit damage policy without changing shock attenuation/strength formulas. |
| A | `src/shared/sim_headless_world.odin` | Rebuild/object construction lives in Sandbox/editor-owned routines. | Headless World/Layout routines preserve the legacy construction path and dispatch authored v4 levels. | Remove raylib/editor ownership from the authoritative core. |
| A | `src/shared/sim_layout_state.odin` | Versions 1–3 load/save legacy rectangles/materials/glue. | Decode version 4 into a Level_Layout; preserve v4 on save and open it read-only in Odin. | Round-trip Unity-authored levels without changing legacy recipes. |
| A | `src/shared/sim_material_library.odin` | Layout owns legacy materials, objects and glue. | Layout may also own a validated level; destruction frees it. Built-in material recipe functions are unchanged. | Extend layout ownership without changing default material properties. |
| A | `src/shared/sim_model.odin` | Subdivision/piece state has no source policy; tiny pieces may be removed. | Provenance and catalog ownership added; indestructible members prevent tiny-piece pruning; owned catalog memory freed. | Preserve authored identity, damage policy and native memory ownership. |
| A | `src/shared/sim_net_host.odin` | Host settings/reset/layout mutation synchronously rebuild the sandbox. | Native requests use terminal results; real resets stage/publish asynchronously; elimination restricts reset, upload, mode and tuning; game-mode command added. | Keep transport alive during rebuild and enforce server-owned round controls. |
| A | `src/shared/sim_net_real.odin` | Local bind and simple dedicated-loop/observer driver. | Explicit IPv4 bind and non-loopback host-key requirement; modern fixed-step/observer options, rolling metrics and teardown evidence. | Support supervised native verification and deliberate LAN hosting. |
| A | `src/shared/sim_net_server.odin` | Sandbox server applies legacy input immediately; every active player can request blasts. | Real sessions consume scheduled input, allow only host diagnostics in sandbox, run rounds, send owner/ready/catalog state, bound telemetry and publish reset worlds. | Keep authority and request timing in Odin while supporting the integration. |
| A | `src/shared/sim_net_session.odin` | Protocol 3 Hello contains version/build/token; Welcome contains slot/host flag. | Protocol 6 adds expected manifest, spectator/resume fields, admission checks, credentials and round control. | Reject incompatible gameplay data and preserve server-session results through reconnect. |
| A | `src/shared/sim_physics.odin` | Anchoring uses the legacy ground-line test. | Explicit pinned policy participates in rigid anchoring; flexible cells use their individual pinned state. Legacy line test remains. | Support fixed, dynamic and authored anchor segments without replacing Box2D. |
| A | `src/shared/sim_player.odin` | Global movement tuning, global spawn; grounded/support velocity only. | Same movement formula is shared with prediction; validated per-level tuning/spawns, support cell/type and teleport serial added. | Replay the native movement kernel and apply authoritative level configuration. |
| A | `src/shared/sim_yard.odin` | Built-in floor/gravity/culling and automatic player respawn; no elimination death collection. | v4 policies configure floor/gravity/bounds/spawns; elimination accumulates deaths and disables manual blasts; sandbox retains respawn. | Build authored levels and run server-owned rounds. |
| M | `src/state.odin` | Scene snapshots write version 2 without provenance/catalog fields. | Scene version 3 with provenance_version 1, level JSON and anchors; old scene versions migrate to Legacy/Destructible. | Persist provenance and validate pin/catalog consistency. |
| M | `src/world_compat.odin` | Baseline comparisons require identical Scene text. | For historical Scene v2 to v3 migration only, compare exact old physics fields while allowing new metadata; maintain exact non-scene comparison. | Retain useful original fixture checks despite a deliberate snapshot-format change. |
| M | `src/world_state.odin` | Scene v1/v2 or World v3/v4 dispatch. | Recognize standalone Scene v3 by minimum_width, while retaining World v3/v4 loading. | Disambiguate scene and world formats after scene provenance versioning. |
| M | `src/yard.odin` | Built-in floor/gravity/culling and automatic player respawn; no elimination death collection. | v4 policies configure floor/gravity/bounds/spawns; elimination accumulates deaths and disables manual blasts; sandbox retains respawn. | Build authored levels and run server-owned rounds. |
| M | `tests/cover_test.odin` | Direct cover globals. | shared-qualified cover state/counters. | Test the extracted implementation with the same assertions. |
| M | `tests/force_rule_test.odin` | Direct seam diagnostics globals. | shared-qualified diagnostic state. | Keep force-rule fixtures observing the authoritative core. |
| M | `tests/glass_shock_test.odin` | Test-local glass commit counter. | Counter owned by shared and read by the original test. | Verify one actual shared structural commit. |
| A | `tests/interop/layout_test.c` | Rejects layout version 4 as unsupported. | Rejects version 5; version 4 is now supported. | Update the unsupported-version fixture without weakening other rejections. |
| M | `tests/layout_test.odin` | Rejects layout version 4 as unsupported. | Rejects version 5; version 4 is now supported. | Update the unsupported-version fixture without weakening other rejections. |
| M | `tests/mortar_seam_test.odin` | Searches all serialized JSON for the word damage. | Decode and check the optional connection.damage fields. | Provenance now also contains a damage policy; preserve the zero-seam-damage assertion. |
| M | `tests/net_test.odin` | Sandbox helpers, old clock horizon and burst checks. | Headless helpers, bounded clock expectations and plain-event count. | Test the shared client and its deliberate horizon/event changes. |
| M | `tests/response_test.odin` | Remove impact_scale through a formatting-specific string substitution. | Decode, set the optional field absent, and re-encode exactly. | Continue verifying the legacy default of 1 after writer changes. |
| M | `tests/seam_followup_test.odin` | Direct peak-damage globals. | shared-qualified peak-damage globals. | Preserve the original seam measurements. |
