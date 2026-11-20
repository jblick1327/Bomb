# Task 5: Unity authority audit (2026-11-10)

Method: text search of `Assets/BOMIntegration` for `Rigidbody`, `Rigidbody2D`, `CharacterController`; component
inventory of the `NetworkMenu`, `NetworkYard` and `RoundDraw` scene files (YAML) and of every prefab they instance;
search of managed code for sockets and byte-level readers/writers; runtime log check from the shipped player.

## 1. References to Rigidbody / Rigidbody2D / CharacterController
| Location | Classification |
| --- | --- |
| `Runtime/BomAuthorityAudit.cs:13` (the only runtime code file that names them) | **Guard.** Rejects Collider, Collider2D, Rigidbody, Rigidbody2D, CharacterController, Joint, Joint2D, root-motion Animators and unaudited legacy scripts, including inactive ones. Runs before connecting (`BOM UNITY AUTHORITY PASS` appears in every player log). |
| `Runtime/BomSourcePresentation.cs:13` | Comment stating the class uses none of them. |
| `Editor/BomAuthorityValidation.cs:14,15` | **Assertion/test.** Adds a Rigidbody/Rigidbody2D to a fixture, requires the guard to reject it, destroys it. |
| `Editor/BomNetworkMenuBuilder.cs:23`, `Editor/BomYardBuilder.cs:56` | **Disabling code (editor time).** Destroy Rigidbodies/Colliders/Animators from art copied into the native presentation. |

**Actual use: none.** No runtime code adds, reads or drives a Rigidbody, Rigidbody2D or CharacterController.

## 2. Scenes
| Scene | Objects | Physics components | Scripts |
| --- | --- | --- | --- |
| NetworkMenu | 361 | none | Bom* integration scripts, Unity/URP camera and light data only |
| NetworkYard | 356 | none | same, without the menu scripts |
| RoundDraw | 29 | none | Bom* integration scripts only |

No script from `Assembly-CSharp` (the original game's legacy gameplay assembly) is attached in any of the three scenes.
Their 25 prefab instances (14 distinct art prefabs) contain no scripts. One prefab,
`Assets/Polytope Studio/Lowpoly_Village/Prefabs/Modular/Fence/PT_Modular_Fence_Wood_01.prefab`, carries a MeshCollider; all 12
instances of it (6 per scene in NetworkMenu and NetworkYard) list that component under `m_RemovedComponents`, so no collider survives.
The runtime audit would reject it anyway. The original prefab is untouched.

## 3. Wire bytes in managed code
No managed code opens a socket or encodes/decodes packets. Matches for `BitConverter`/`BinaryWriter`/`MemoryStream` are SHA-256
cache keys and hash display (`BomNativeIdentity`, `BomSourcePresentation`, `BomSourceMeshData`, editor exporter/preprocessor). `BomSession.cs:59`
copies the host-key string to native memory for an ABI call; the native library builds the packet.

## Verdict
No real use of Unity gameplay physics or managed wire handling found, so nothing needs changing and no ASK is raised.
Run-time proof: the player logs in `review/task3-20261110/release-launch-ps51/` contain `BOM UNITY AUTHORITY PASS` and
`BOM UNITY ABI PASS ... protocol 7`.
